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
./scripts/test-quota-flow.sh
./scripts/test-localization.sh
```

Build the app with `./scripts/build-app.sh`. For a release package, use `./scripts/build-app.sh --universal` followed by `./scripts/package-release.sh`; the packaging script checks the signature and both CPU architectures.

The behavior suite covers local Codex RPC parsing, stale and missing readings, account-separated history, quota pace and reset estimates, local token-log aggregation, reminder states, banked-reset identity checks, public radar parsing, and quota-clock state mapping. Network calls to the third-party radar are not required by these tests.

For a release build, verify that `CFBundleIconFile` names the generated app icon, the ICNS contains the required icon sizes, the app passes strict signature verification, and its executable contains both `arm64` and `x86_64`. Scan the source and release archive for credentials, account data, and private developer paths before publishing.

## Local motion checks

On macOS, run `./scripts/proof-quota-motion.sh` to check observed-arc interpolation, measured-pace hand motion, inactive and unknown/stale states, and an announcement rim that does not change the quota arc. Pass `--reduce-motion` to check the static reduced-motion path. This local visual check is not part of the GitHub Actions suite.
