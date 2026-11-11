# Mac Tools

`m.sh` is adapted from Assaf Dori’s `bypass-mdm-v2.sh` for testing in macOS Recovery on Macs you own or are authorised to manage. It creates a temporary local administrator and changes local enrolment settings. The Mac’s Apple Business Manager assignment remains in place.

## Run the pilot

Start the Mac in Recovery, connect to the internet, and open **Utilities → Terminal**. On an Intel Mac such as the A2251, hold **Command + R** at startup. The Mac needs an existing APFS macOS installation with an accessible Data volume.

```bash
curl -fL https://tinyurl.com/bajwha-mac -o /tmp/m.sh && bash /tmp/m.sh
```

If the short link fails, use GitHub directly.

```bash
curl -fL https://raw.githubusercontent.com/JavedBajwha/mac-tools/main/m.sh -o /tmp/m.sh && bash /tmp/m.sh
```

The script first reads the APFS volume groups and identifies one internal System and Data pair. It keeps both device IDs and mount paths in memory for the rest of the run. It mounts either volume if needed, checks the installed macOS folders, generates a temporary administrator and password, and applies the local enrolment changes. This flow runs without menu selections, typed credentials, or a FileVault prompt.

Save the username and password shown in Terminal. After **Local changes completed**, restart the Mac and use those credentials. Each successful run creates a fresh temporary account. If an error appears after the script prints a login, keep those details because the account has already been created.

## If the script stops

- **Missing or ambiguous installation.** The script requires exactly one internal APFS System and Data pair. Run `diskutil list` and `diskutil apfs listVolumeGroups` to see what Recovery detects.
- **Data volume could not be mounted.** This pilot requires a Data volume that Recovery can mount without an unlock prompt. Check the drive and Data volume in Disk Utility.
- **Required folder is missing or unwritable.** Check that macOS is installed and that Recovery can access the paired Data volume.
- **`basename: command not found`.** Download the current script again. The older script failed on the A2251 even though both volumes were accessible because `basename` was missing from that Recovery environment.

See [SOURCE.md](SOURCE.md) for upstream attribution and [LICENSE](LICENSE) for the MIT licence.
