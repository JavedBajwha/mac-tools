#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Error handling function
error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

# Warning function
warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

# Success function
success() {
	echo -e "${GRN}✓ $1${NC}"
}

# Info function
info() {
	echo -e "${BLU}ℹ $1${NC}"
}

# Validation function for username
validate_username() {
	local username="$1"

	# Check if username is empty
	if [ -z "$username" ]; then
		echo "Username cannot be empty"
		return 1
	fi

	# Check length (1-31 characters for macOS)
	if [ ${#username} -gt 31 ]; then
		echo "Username too long (max 31 characters)"
		return 1
	fi

	# Check for valid characters (alphanumeric, underscore, hyphen)
	if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		echo "Username can only contain letters, numbers, underscore, and hyphen"
		return 1
	fi

	# Check if starts with letter or underscore
	if ! [[ "$username" =~ ^[a-zA-Z_] ]]; then
		echo "Username must start with a letter or underscore"
		return 1
	fi

	return 0
}

# Validation function for password
validate_password() {
	local password="$1"

	# Check if password is empty
	if [ -z "$password" ]; then
		echo "Password cannot be empty"
		return 1
	fi

	# Check minimum length (macOS allows any length, but recommend 4+)
	if [ ${#password} -lt 4 ]; then
		echo "Password too short (minimum 4 characters recommended)"
		return 1
	fi

	return 0
}

# Check if user already exists
check_user_exists() {
	local dscl_path="$1"
	local username="$2"

	if dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" 2>/dev/null; then
		return 0 # User exists
	else
		return 1 # User doesn't exist
	fi
}

# Find available UID
find_available_uid() {
	local dscl_path="$1"
	local uid=501

	# Check UIDs from 501-599
	while [ $uid -lt 600 ]; do
		if ! dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID $uid 2>/dev/null | grep -q "UniqueID"; then
			echo $uid
			return 0
		fi
		uid=$((uid + 1))
	done

	echo "501" # Default fallback
	return 1
}

# Function to detect system volumes with multiple fallback strategies
detect_volumes() {
	local system_vol=""
	local data_vol=""

	info "Detecting system volumes..." >&2

	# Strategy 1: Look for common macOS APFS volume patterns
	# List all volumes and look for system volume (ends with or contains common names)
	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			vol_name=${vol##*/}

			# Check if this looks like a system volume (not Data, not recovery)
			if [[ ! "$vol_name" =~ "Data"$ ]] && [[ ! "$vol_name" =~ "Recovery" ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"
				info "Found system volume: $system_vol" >&2
				break
			fi
		fi
	done

	# Strategy 2: If no system volume found, try looking for any volume with /System directory
	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ]; then
				system_vol=${vol##*/}
				warn "Using volume with /System directory: $system_vol" >&2
				break
			fi
		done
	fi

	# Strategy 3: Check for Data volume
	if [ -d "/Volumes/Data" ]; then
		data_vol="Data"
		info "Found data volume: $data_vol" >&2
	elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data" ]; then
		data_vol="$system_vol - Data"
		info "Found data volume: $data_vol" >&2
	else
		# Look for any volume ending with "Data"
		for vol in /Volumes/*Data; do
			if [ -d "$vol" ]; then
				data_vol=${vol##*/}
				warn "Found data volume: $data_vol" >&2
				break
			fi
		done
	fi

	# Validate findings
	if [ -z "$system_vol" ]; then
		error_exit "Could not detect system volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	if [ -z "$data_vol" ]; then
		error_exit "Could not detect data volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	echo "$system_vol|$data_vol"
}

# Read a scalar from diskutil's property list output.
plist_value() {
	printf '%s' "$1" | plutil -extract "$2" raw -o - - 2>/dev/null
}

mount_recovery_volume() {
	local device="$1"
	local role="$2"
	local info_plist mount_point

	info_plist=$(diskutil info -plist "$device") || return 1
	mount_point=$(plist_value "$info_plist" MountPoint)
	if [ -z "$mount_point" ]; then
		info "Mounting $device..." >&2
		if ! diskutil mount "$device" >&2; then
			[ "$role" = "Data" ] || return 1
			info "If the Data volume is locked, enter its FileVault password when prompted." >&2
			diskutil apfs unlockVolume "$device" </dev/tty >&2 || return 1
		fi
		info_plist=$(diskutil info -plist "$device") || return 1
		mount_point=$(plist_value "$info_plist" MountPoint)
	fi

	case "$mount_point" in
		/Volumes/*) [ -d "$mount_point" ] || return 1 ;;
		*) return 1 ;;
	esac
	printf '%s\n' "$mount_point"
}

recover_unmounted_volumes() {
	local listing container group volume role device disk_info
	local system_id data_id target_system="" target_data="" system_mount data_mount

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
					[ -z "$target_system" ] ||
						error_exit "Multiple internal macOS installations found. Check the intended pair in Disk Utility."
					target_system="$system_id"
					target_data="$data_id"
				fi
			fi
			group=$((group + 1))
		done
		container=$((container + 1))
	done

	[ -n "$target_system" ] ||
		error_exit "Could not find one internal APFS System/Data pair. Check the drive and macOS installation in Disk Utility."

	system_mount=$(mount_recovery_volume "$target_system" System) ||
		error_exit "Could not mount System volume $target_system."
	data_mount=$(mount_recovery_volume "$target_data" Data) ||
		error_exit "Could not mount or unlock Data volume $target_data."

	[ -d "$system_mount/System" ] ||
		error_exit "The System folder is missing from $system_mount."
	[ -d "$data_mount/private/var/db/dslocal/nodes/Default" ] ||
		error_exit "The local account database is missing from $data_mount."

	printf '%s|%s\n' "$system_mount" "$data_mount"
}

# Try the mounted volumes first, then use APFS metadata to recover missing mounts.
system_path=""
data_path=""
if volume_info=$(detect_volumes 2>/dev/null); then
	system_path="/Volumes/${volume_info%%|*}"
	data_path="/Volumes/${volume_info#*|}"
fi
if [ -z "$system_path" ] || [ ! -d "$system_path/System" ] ||
	[ ! -d "$data_path/private/var/db/dslocal/nodes/Default" ]; then
	info "Checking APFS volume groups for missing mounts..."
	volume_info=$(recover_unmounted_volumes) || exit 1
	system_path="${volume_info%%|*}"
	data_path="${volume_info#*|}"
fi
system_volume="${system_path##*/}"
data_volume="${data_path##*/}"

# Display header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Bypass MDM By Assaf Dori (assafdori.com)   ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume: $system_volume"
success "Data Volume: $data_volume"
echo ""

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM from Recovery")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Starting MDM Bypass Process${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"

		# Create Temporary User
		echo -e "${CYAN}Creating Temporary Admin User${NC}"
		echo -e "${NC}Press Enter to use defaults (recommended)${NC}"

		# Get and validate real name
		read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
		realName="${realName:=Apple}"

		# Get and validate username
		while true; do
			read -p "Enter Temporary Username (Default is 'Apple'): " username
			username="${username:=Apple}"

			if validation_msg=$(validate_username "$username"); then
				break
			else
				warn "$validation_msg"
				echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
			fi
		done

		# Check if user already exists
		if check_user_exists "$dscl_path" "$username"; then
			warn "User '$username' already exists in the system"
			read -p "Do you want to use a different username? (y/n): " response
			if [[ "$response" =~ ^[Yy]$ ]]; then
				while true; do
					read -p "Enter a different username: " username
					if [ -z "$username" ]; then
						warn "Username cannot be empty"
						continue
					fi
					if validation_msg=$(validate_username "$username"); then
						if ! check_user_exists "$dscl_path" "$username"; then
							break
						else
							warn "User '$username' also exists. Try another name."
						fi
					else
						warn "$validation_msg"
					fi
				done
			else
				warn "Continuing with existing user '$username' (may cause conflicts)"
			fi
		fi

		# Get and validate password
		while true; do
			read -p "Enter Temporary Password (Default is '1234'): " passw
			passw="${passw:=1234}"

			if validation_msg=$(validate_password "$passw"); then
				break
			else
				warn "$validation_msg"
				echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
			fi
		done

		echo ""

		# Find available UID
		info "Checking for available UID..."
		available_uid=$(find_available_uid "$dscl_path")
		if [ $? -eq 0 ] && [ "$available_uid" != "501" ]; then
			info "UID 501 is in use, using UID $available_uid instead"
		else
			available_uid="501"
		fi
		success "Using UID: $available_uid"
		echo ""

		# Create User with error handling
		info "Creating user account: $username"

		if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" 2>/dev/null; then
			error_exit "Failed to create user account"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" || warn "Failed to set user shell"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName" || warn "Failed to set real name"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid" || warn "Failed to set UID"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" || warn "Failed to set GID"

		user_home="$data_path/Users/$username"
		if [ ! -d "$user_home" ]; then
			if mkdir -p "$user_home" 2>/dev/null; then
				success "Created user home directory"
			else
				error_exit "Failed to create user home directory: $user_home"
			fi
		else
			warn "User home directory already exists: $user_home"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" || warn "Failed to set home directory"

		if ! dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null; then
			error_exit "Failed to set user password"
		fi

		if ! dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null; then
			error_exit "Failed to add user to admin group"
		fi

		success "User account created successfully"
		echo ""

		# Block MDM domains
		info "Blocking MDM enrollment domains..."

		hosts_file="$system_path/etc/hosts"
		if [ ! -f "$hosts_file" ]; then
			warn "Hosts file does not exist, creating it"
			touch "$hosts_file" || error_exit "Failed to create hosts file"
		fi

		# Check if entries already exist to avoid duplicates
		grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >>"$hosts_file"
		grep -q "mdmenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com" >>"$hosts_file"
		grep -q "iprofiles.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com" >>"$hosts_file"

		success "MDM domains blocked in hosts file"
		echo ""

		# Remove configuration profiles
		info "Configuring MDM bypass settings..."

		config_path="$system_path/var/db/ConfigurationProfiles/Settings"

		# Create config directory if it doesn't exist
		if [ ! -d "$config_path" ]; then
			if mkdir -p "$config_path" 2>/dev/null; then
				success "Created configuration directory"
			else
				warn "Could not create configuration directory"
			fi
		fi

		# Mark setup as done
		touch "$data_path/private/var/db/.AppleSetupDone" 2>/dev/null && success "Marked setup as complete" || warn "Could not mark setup as complete"

		# Remove activation records
		rm -rf "$config_path/.cloudConfigHasActivationRecord" 2>/dev/null && success "Removed activation record" || info "No activation record to remove"
		rm -rf "$config_path/.cloudConfigRecordFound" 2>/dev/null && success "Removed cloud config record" || info "No cloud config record to remove"

		# Create bypass markers
		touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null && success "Created profile installed marker" || warn "Could not create profile marker"
		touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null && success "Created record not found marker" || warn "Could not create not found marker"

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       MDM Bypass Completed Successfully!     ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. Login with username: ${YEL}$username${NC} and password: ${YEL}$passw${NC}"
		echo ""
		break
		;;
	"Reboot & Exit")
		echo ""
		info "Rebooting system..."
		reboot
		break
		;;
	*)
		echo -e "${RED}Invalid option $REPLY${NC}"
		;;
	esac
done
