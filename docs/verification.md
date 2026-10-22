# Verification

Behavior checks use synthetic inputs and temporary files. They do not include account readings, credentials, or conversation content.

Run the suite on macOS:

```sh
./scripts/test-core.sh
./scripts/test-history.sh
./scripts/test-radar.sh
./scripts/test-deadline.sh
./scripts/test-ride.sh
./scripts/test-tokens.sh
./scripts/test-reminders.sh
./scripts/test-reset-time.sh
./scripts/test-banked.sh
./scripts/test-menu.sh
./scripts/test-flight.sh
```

Build the app with `./scripts/build-app.sh`. For a release package, use `./scripts/build-app.sh --universal` followed by `./scripts/package-release.sh`; the packaging script checks the signature and both CPU architectures.

The behavior suite covers local Codex RPC parsing, stale and missing readings, account-separated history, quota pace and reset estimates, local token-log aggregation, reminder states, banked-reset identity checks, public radar parsing, and quota-to-flight mapping. Network calls to the third-party radar are not required by these tests.

## Local Metal checks

On a Mac with Metal, run `./scripts/test-flight-3d.sh` and `./scripts/proof-flight-motion.sh`. These checks cover projected 3D geometry, rendered maneuvers, and live-view transitions. Pass `--reduce-motion` to check the reduced-motion path. These local graphics checks are not part of the GitHub Actions suite.
