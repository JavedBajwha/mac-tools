# Mac Tools

`m.sh` is adapted from Assaf Dori’s `bypass-mdm-v2.sh` for macOS Recovery. Use it on a Mac you own or are authorised to manage. It creates a local administrator and changes local enrolment settings. The device’s assignment in Apple Business Manager remains in place.

## Download and run

1. Boot into macOS Recovery, connect to the internet and open **Utilities → Terminal**. On an Intel Mac, such as the MacBook Pro A2251, hold **Command + R** at startup. An existing macOS installation must be present.

2. Download the script to Recovery’s temporary folder.

   ```bash
   curl -fL https://tinyurl.com/bajwha-mac -o /tmp/m.sh
   ```

   If the short link fails, download directly from GitHub.

   ```bash
   curl -fL https://raw.githubusercontent.com/JavedBajwha/mac-tools/main/m.sh -o /tmp/m.sh
   ```

3. Once the download succeeds, start the script.

   ```bash
   bash /tmp/m.sh
   ```

4. If the volumes are unmounted, the script looks for a single internal APFS System and Data pair and attempts to mount it. Enter your FileVault password if macOS prompts for it. Check that the menu shows the correct **System Volume** and **Data Volume**. If either is incorrect, press **Control + C** and check the troubleshooting steps below.

5. Choose **1 — Bypass MDM from Recovery**. Enter a unique temporary administrator username and a strong password. The script can display the password on screen. Check the output for failed writes or account errors before restarting.

## Troubleshoot volume detection

On the MacBook Pro A2251, Recovery could see and mount both macOS volumes, but the original script reported **“Could not detect system volume”** because Recovery lacked `basename`. The updated script reads the volume names using Bash itself. If an old download still shows `basename: command not found`, download `m.sh` again using the command above.

If the mounted volumes are unavailable, the script checks APFS volume groups and tries to mount a matching internal pair. It stops before showing the menu if it cannot find a unique pair, unlock the Data volume, or verify the required folders. The checks below help diagnose those cases.

### If the volumes are missing, locked or unmounted

Run these read-only checks in Recovery Terminal.

```bash
diskutil list
ls -la /Volumes
```

- If both volumes appear in `diskutil list` but either is missing under `/Volumes`, open **Disk Utility → View → Show All Devices**. Select the volume, click **Mount**, and enter the FileVault password if prompted.
- If both are mounted under the default names, check the folders the script needs. Substitute the actual volume names if yours differ.

  ```bash
  ls -ld "/Volumes/Macintosh HD/System"
  ls -ld "/Volumes/Macintosh HD - Data/private/var/db/dslocal/nodes/Default"
  ```

- If the internal disk is missing from `diskutil list`, or either required folder is still missing after mounting, stop before selecting option 1. Check whether Disk Utility sees the internal drive and whether macOS is installed. A volume detection error alone does not establish a drive fault.

See [SOURCE.md](SOURCE.md) for the upstream source and [LICENSE](LICENSE) for the MIT licence.
