# Script source

`m.sh` is adapted from `bypass-mdm-v2.sh` by Assaf Dori.

- Upstream: https://github.com/assafdori/bypass-mdm
- Source: https://github.com/assafdori/bypass-mdm/blob/main/bypass-mdm-v2.sh
- Upstream Git blob SHA: `7e5144fcf81de25167db35118ba1f32ba3ea72f3`
- Copied: 2026-11-11
- Licence: MIT; see LICENSE.

This copy has not been run or verified on Mac hardware. The local changes extract volume names using Bash instead of `basename` and stop before the menu if detection fails. It makes local account and enrollment changes; it does not release a device from Apple Business Manager.
