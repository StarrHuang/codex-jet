# Codex Jet — Usage & Reset

Codex Jet is a native macOS app for watching Codex quota use, reset timing, and local token activity. It reads the existing Codex CLI sign-in on this Mac, keeps quota history locally, and can show the public global reset radar from [codex-reset.com](https://codex-reset.com/).

Codex Jet is an independent community project. It is not affiliated with or endorsed by OpenAI. The global radar is third-party information and does not confirm that a reset has reached your account.

## Install

Requires macOS 14 or later and an installed, signed-in Codex CLI. Download the latest universal Apple Silicon and Intel release from [GitHub Releases](https://github.com/StarrHuang/codex-jet/releases), then run the installer from a clone:

```sh
git clone https://github.com/StarrHuang/codex-jet.git
cd codex-jet
./scripts/install.sh
```

The installer checks the release checksum and app signature before installing to `~/Applications/Codex Jet.app`. Each Mac uses its own Codex sign-in and local history. The release is ad-hoc signed and has not been notarized with an Apple Developer ID.

To build from source:

```sh
./scripts/build-app.sh
open 'dist/Codex Jet.app'
```

See [deployment](docs/deployment.md) for updates and release packaging. See [verification](docs/verification.md) for the public test entrypoints.

## What it shows

- Current Codex quota windows, reset times, and history, with separate status for stale or missing readings.
- Measured recent pace and clearly labeled window-average estimates, with a forecast of remaining quota at reset.
- Local token activity by model and hour, based on Codex session usage records.
- Optional banked-reset cards read from the current local account, with identity checks and manual-redemption scenarios.
- An optional public global reset radar with third-party source, confidence, and update time shown separately from personal quota.
- Reset reminders and a flight visualization driven by observed quota and pace.

## Data boundaries

Quota and banked-card readings use the current Mac's existing Codex sign-in. Codex Jet does not bundle credentials, start a model-generation request, or upload quota history. The app stores account-separated quota history in `~/Library/Application Support/CodexReset/history.json`; it uses a one-way account key and does not store the account email.

Token summaries are computed from local session usage metadata. Conversation text is not read for the summary or uploaded. Empty hours mean no usage record was found, not verified zero usage.

The global radar is fetched separately from `codex-reset.com`; those requests do not include personal quota or account data. Its probabilities and event observations are third-party information and are not an account reset guarantee.

## Credits

- [codex-reset.com](https://codex-reset.com/) supplies the independent public global reset radar used by the app.
- The compact weekly quota-card presentation was inspired by the Tokei app. No Tokei source code or artwork is included.
- [CodexBar](https://github.com/steipete/CodexBar) informed the window-pace comparison and is cited as a source of product and implementation ideas. Codex Jet's implementation is independent.

The included fictional roadster artwork was generated for this project and contains no manufacturer marks. The release does not include third-party video or product imagery.
