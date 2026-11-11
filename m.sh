#!/bin/bash
# Adapted from bypass-mdm-v2.sh by Assaf Dori. See SOURCE.md and LICENSE.

error_exit() {
	printf 'ERROR: %s\n' "$1" >&2
	exit 1
}

info() {
	printf '%s\n' "$1"
}

# Read a scalar from diskutil's property list output.
plist_value() {
	printf '%s' "$1" | plutil -extract "$2" raw -o - - 2>/dev/null
}

mount_recovery_volume() {
	local device="$1"
	local info_plist mount_point

	info_plist=$(diskutil info -plist "$device") || return 1
	mount_point=$(plist_value "$info_plist" MountPoint)
	if [ -z "$mount_point" ]; then
		info "Mounting $device..." >&2
		diskutil mount "$device" </dev/null >&2 || return 1
		info_plist=$(diskutil info -plist "$device") || return 1
		mount_point=$(plist_value "$info_plist" MountPoint)
	fi

	case "$mount_point" in
		/Volumes/*) [ -d "$mount_point" ] || return 1 ;;
		*) return 1 ;;
	esac
	printf '%s\n' "$mount_point"
}

discover_volumes() {
	local listing container group volume role device disk_info
	local system_id data_id
	system_device=""
	data_device=""

	listing=$(diskutil apfs listVolumeGroups -plist) ||
		error_exit "Could not read APFS volume groups. Check the internal drive in Disk Utility."
	container=0
	while plist_value "$listing" "Containers.$container.ContainerReference" >/dev/null; do
		group=0
		while plist_value "$listing" "Containers.$container.VolumeGroups.$group.APFSVolumeGroupUUID" >/dev/null; do
			volume=0
			system_id=""
			data_id=""
			while device=$(plist_value "$listing" "Containers.$container.VolumeGroups.$group.Volumes.$volume.DeviceIdentifier"); do
				[[ "$device" =~ ^disk[0-9]+s[0-9]+$ ]] ||
					error_exit "Unexpected APFS device identifier: $device"
				role=$(plist_value "$listing" "Containers.$container.VolumeGroups.$group.Volumes.$volume.Role") ||
					error_exit "Could not read the APFS role for $device."
				case "$role" in
					System) system_id="$device" ;;
					Data) data_id="$device" ;;
				esac
				volume=$((volume + 1))
			done
			if [ -n "$system_id" ] && [ -n "$data_id" ]; then
				disk_info=$(diskutil info -plist "$system_id") ||
					error_exit "Could not inspect APFS System volume $system_id."
				if [ "$(plist_value "$disk_info" Internal)" = "true" ]; then
					[ -z "$system_device" ] ||
						error_exit "Multiple internal macOS installations found. Check the intended pair in Disk Utility."
					system_device="$system_id"
					data_device="$data_id"
				fi
			fi
			group=$((group + 1))
		done
		container=$((container + 1))
	done

	[ -n "$system_device" ] ||
		error_exit "Could not find one internal APFS System/Data pair. Check the drive and macOS installation in Disk Utility."

	system_path=$(mount_recovery_volume "$system_device") ||
		error_exit "Could not mount System volume $system_device."
	data_path=$(mount_recovery_volume "$data_device") ||
		error_exit "Could not mount Data volume $data_device. This pilot requires an unlocked Data volume."

	[ -d "$system_path/System" ] ||
		error_exit "The System folder is missing from $system_path."
	[ -d "$data_path/private/var/db/dslocal/nodes/Default" ] ||
		error_exit "The local account database is missing from $data_path."
}

# Resolve the installation once and keep its device IDs and paths for this run.
for command in diskutil plutil dscl od tr grep mkdir chmod chown touch rm rmdir; do
	command -v "$command" >/dev/null 2>&1 || error_exit "Recovery command unavailable: $command"
done

info "Finding the internal macOS System and Data volumes..."
discover_volumes
readonly system_device data_device system_path data_path
printf 'System volume: %s (%s)\nData volume: %s (%s)\n' "$system_path" "$system_device" "$data_path" "$data_device"

# APFS stores the installed OS's writable configuration on its paired Data volume.
db_path="$data_path/private/var/db"
dscl_path="$db_path/dslocal/nodes/Default"
hosts_file="$data_path/private/etc/hosts"
config_path="$db_path/ConfigurationProfiles/Settings"

[ -d "$data_path/Users" ] || error_exit "Missing Users directory on $data_path."
[ -f "$hosts_file" ] && [ -w "$hosts_file" ] ||
	error_exit "The installed macOS hosts file is missing or unwritable: $hosts_file."
[ -w "$db_path" ] && [ -w "$dscl_path" ] ||
	error_exit "The installed macOS account database is unwritable."

# List existing users before choosing credentials or an account ID.
accounts=$(dscl -f "$dscl_path" localhost -list /Local/Default/Users UniqueID) ||
	error_exit "Could not read the local account database."

uid=501
while grep -Eq "[[:space:]]$uid[[:space:]]*$" <<< "$accounts"; do
	uid=$((uid + 1))
	[ "$uid" -lt 600 ] || error_exit "No available local user ID from 501 through 599."
done

random_hex=$(od -An -N 24 -tx1 /dev/urandom | tr -d '[:space:]')
[[ "$random_hex" =~ ^[0-9a-f]{48}$ ]] || error_exit "Could not generate secure administrator credentials."
username="pilot_${random_hex:0:12}"
password="${random_hex:12}"
unset random_hex
if grep -Eiq "^$username[[:space:]]" <<< "$accounts" || [ -e "$data_path/Users/$username" ] || [ -L "$data_path/Users/$username" ]; then
	error_exit "Generated administrator name is already in use. Run again to generate a new name."
fi

account_path="/Local/Default/Users/$username"
user_home="$data_path/Users/$username"
directory_service=(dscl -f "$dscl_path" localhost)
home_created=false

cleanup_account() {
	"${directory_service[@]}" -delete "$account_path" >/dev/null 2>&1 ||
		printf 'Could not remove incomplete account %s.\n' "$username" >&2
	if [ "$home_created" = true ]; then
		rmdir "$user_home" || printf 'Could not remove incomplete home directory %s.\n' "$user_home" >&2
	fi
}

info "Creating a temporary local administrator..."
"${directory_service[@]}" -create "$account_path" || error_exit "Could not create $username."
if ! "${directory_service[@]}" -create "$account_path" UserShell /bin/zsh ||
	! "${directory_service[@]}" -create "$account_path" RealName "Pilot Administrator" ||
	! "${directory_service[@]}" -create "$account_path" UniqueID "$uid" ||
	! "${directory_service[@]}" -create "$account_path" PrimaryGroupID 20 ||
	! "${directory_service[@]}" -create "$account_path" NFSHomeDirectory "/Users/$username" ||
	! "${directory_service[@]}" -passwd "$account_path" "$password" ||
	! mkdir "$user_home"; then
	cleanup_account
	error_exit "Could not initialise the temporary administrator."
fi
home_created=true
if ! chmod 700 "$user_home" || ! chown "$uid:20" "$user_home" ||
	! "${directory_service[@]}" -append /Local/Default/Groups/admin GroupMembership "$username"; then
	cleanup_account
	error_exit "Could not finish creating the temporary administrator."
fi

printf '\nSave these temporary login details before restarting.\nUsername: %s\nPassword: %s\n\n' "$username" "$password"
unset password

info "Applying local enrolment settings..."
mkdir -p "$config_path" || error_exit "Could not create the local enrolment settings directory."
for domain in deviceenrollment.apple.com mdmenrollment.apple.com iprofiles.apple.com; do
	if ! grep -Fqx "0.0.0.0 $domain" "$hosts_file"; then
		printf '\n0.0.0.0 %s\n' "$domain" >> "$hosts_file" ||
			error_exit "Could not write the hosts entry for $domain."
	fi
done

rm -f "$config_path/.cloudConfigHasActivationRecord" "$config_path/.cloudConfigRecordFound" ||
	error_exit "Could not remove the previous local enrolment markers."
touch "$config_path/.cloudConfigProfileInstalled" "$config_path/.cloudConfigRecordNotFound" ||
	error_exit "Could not create the local enrolment markers."
touch "$db_path/.AppleSetupDone" || error_exit "Could not mark macOS setup complete."

info "Local changes completed. Restart when you have saved the login details."
