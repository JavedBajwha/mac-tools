# Mac Tools

`m.sh` is a copy of Assaf Dori’s `bypass-mdm-v2.sh` for macOS Recovery. Use it on a Mac you own or are authorised to manage. It creates a local administrator and changes local enrolment settings. The device’s assignment in Apple Business Manager remains in place.

## Download and run

1. Boot into macOS Recovery, connect to the internet and open **Utilities → Terminal**. On an Intel Mac, such as the MacBook Pro A2251, hold **Command + R** at startup. An existing macOS installation must be present. If its Data volume is locked, mount and unlock it in Disk Utility first.

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

4. Check that the menu shows the correct **System Volume** and **Data Volume**. If either is blank or incorrect, press **Control + C** and check the troubleshooting steps below.

5. Choose **1 — Bypass MDM from Recovery**. Enter a unique temporary administrator username and a strong password. The script can display the password on screen. Check the output for failed writes or account errors before restarting.

## Troubleshoot volume detection

If the script says **“Could not detect system volume”**, look for `basename: command not found` above it. On the MacBook Pro A2251 where this happened, `diskutil list` showed both APFS volumes, `ls -la /Volumes` showed both were mounted, and the System and Data folders were accessible. The missing `basename` command caused the blank volume names. The workaround below restored detection.

### If Recovery says `basename: command not found`

Exit the script with **Control + C**. Enter these lines in the same Recovery Terminal window. The first line defines the function and normally prints nothing.

```bash
basename() { echo "$1" | sed 's|.*/||'; }
export -f basename
basename "/Volumes/Macintosh HD"
```

If the last command prints `Macintosh HD`, rerun `bash /tmp/m.sh` and check both volume names again. This workaround lasts for the current Terminal session.

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
