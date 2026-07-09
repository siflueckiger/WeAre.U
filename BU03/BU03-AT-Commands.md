# BU03 AT Commands

This file summarizes the BU03 AT commands that are verified in this repository and from the public BU03/BU04 command references found online.

## Verified commands

| Command | Purpose | Typical parameters | Used in this repo |
| --- | --- | --- | --- |
| `AT+SETCFG` | Set device configuration | `AT+SETCFG=<id>,<mode>,<channel>,<rate>` | Yes |
| `AT+GETCFG` | Read current configuration | No parameters | Yes |
| `AT+SAVE` | Persist configuration to flash | No parameters | Yes |
| `AT+GETDEV` | Read device information | No parameters | Not yet used |
| `AT+SETUWBMODE` | Select UWB algorithm/mode | Device-specific mode value | Not yet used |
| `AT+GETUWBMODE` | Read current UWB mode | No parameters | Not yet used |

## Notes

- `mode` in `AT+SETCFG` is used as `0 = tag`, `1 = base station / anchor` in the project sketches.
- `channel` and `rate` must match across all devices in the same setup.
- The project currently uses the `CmdM:4` data stream for ranging, which is not an AT command.
- No public JSON output mode was found in the available BU03 references.

## Repository references

- [AT-Anchor-Config-ESP32](./AT-Anchor-Config-ESP32/AT-Anchor-Config-ESP32.ino)
- [AT-Tag-Config-ESP32](./AT-Tag-Config-ESP32/AT-Tag-Config-ESP32.ino)
- [AT-Tag-Config.ino](./AT-Tag-Config.ino)
- [AT-CmdM4-Trilateration-ESP32](./AT-CmdM4-Trilateration-ESP32/AT-CmdM4-Trilateration-ESP32.ino)

## Public references used

- [Core Electronics BU03 AT commands PDF](./references/bu03-at-commands-core-electronics.pdf)
- [Ai-Thinker BU03/BU04 AT command PDF](./references/bu03-at-commands-aithinker.pdf)
