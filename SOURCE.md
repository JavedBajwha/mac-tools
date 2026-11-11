# Script source

`m.sh` is adapted from `bypass-mdm-v2.sh` by Assaf Dori.

- Upstream: https://github.com/assafdori/bypass-mdm
- Source: https://github.com/assafdori/bypass-mdm/blob/main/bypass-mdm-v2.sh
- Upstream Git blob SHA: `7e5144fcf81de25167db35118ba1f32ba3ea72f3`
- Copied: 2026-11-11
- Licence: MIT; see LICENSE.

The local version selects a matching internal APFS System and Data pair before applying changes, mounts missing volumes, and keeps the device identifiers and mount paths in memory. It creates a temporary administrator using the fixed pilot credentials documented in the README and uses the paired Data volume for writable settings. The automated workflow has been tested with simulated Recovery commands and still needs a live hardware test.
