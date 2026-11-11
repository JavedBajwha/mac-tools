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

## If Recovery says `basename: command not found`

Exit the script with **Control + C**. Enter these lines in the same Recovery Terminal window. The first line defines the function and normally prints nothing.

```bash
basename() { echo "$1" | sed 's|.*/||'; }
export -f basename
basename "/Volumes/Macintosh HD"
```

If the last command prints `Macintosh HD`, rerun `bash /tmp/m.sh` and check both volume names again. This workaround lasts for the current Terminal session.

If detection still fails, run `diskutil list` and `ls -la /Volumes` to check what Recovery can see. In Disk Utility, confirm the macOS System and Data volumes are mounted and unlocked.

See [SOURCE.md](SOURCE.md) for the upstream source and [LICENSE](LICENSE) for the MIT licence.
