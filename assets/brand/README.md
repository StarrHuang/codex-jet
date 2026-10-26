# Quota clock identity

- `app-icon.png`: square master with transparency, generated with the built-in image-generation tool for this project. `scripts/build-icon.sh` creates the standard macOS ICNS sizes from this master.
- `clock-mark.svg`: editable flat companion mark for small sizes. The native `QuotaLogo` uses the same open ring and clock hands for the dashboard and popover. The compact menu bar retains its percentage, nearest reset countdown and traffic light without adding an icon.

The open mint ring represents remaining capacity and a renewing cycle; clock hands connect the mark to quota pace and reset timing. It is an independent project identity, not an OpenAI or Apple logo.

The exact generation prompt is preserved in `prompt.txt`. The icon was generated with the built-in tool, then resized only to produce the standard ICNS sizes.
