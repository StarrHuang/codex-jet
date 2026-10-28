# Codex Jet visual identity

The mark is an open capacity ring with simple clock hands. The app uses a mint tile and deep green mark; the menu bar uses the same outline colored by the existing quota runway state. No letters, avatars, OpenAI logo or Apple logo are used.

- `Sources/ResetApp/QuotaBrand.swift` is the canonical vector geometry shared by the app, sidebar, menu popover and persistent reminder.
- `app-icon.png` is a 1024px preview generated directly from that vector. `scripts/build-icon.sh` renders the vector again and builds every standard ICNS size, including the small variants macOS uses in notifications. Notification Center owns the notification icon and may cache it.
- `clock-mark.svg` is the editable flat export of the same geometry.
- `tools/render-brand.swift` is the deterministic native renderer. No account data is read.
- `prompt.txt` documents the earlier 0.17 generated icon; it is historical provenance, not the current icon source.

The installed macOS 14+ ICNS includes its traditional transparent safe margin. A future App Store / Icon Composer build must use an opaque unmasked background and separate foreground layers; this ICNS preview is not represented as an iOS submission asset.

## Visual rules

Use one brand name, Codex Jet. Mint is a stable identity color, not a claim that quota is safe. Green/yellow/red mean the measured pace can last / is near depletion at the target / may deplete early. Unknown remains neutral and has a textual explanation. Small status marks have a darker light-appearance palette. Keep percentage and nearest deadline text compact; preserve the default-visible consumption curve in the popover.

The live quota clock remains data-driven; its ring is observed balance and hand speed is measured usage. Brand art is static. Temporary-reset attention is brief and never implies that an account refill already happened.

References: [Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications), [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar). Checked 2026-10-28.
