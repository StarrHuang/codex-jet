# Performance tools

Run from the repository root on macOS. Keep measurements outside the checkout. These tools do not change the running app, login or quota history; synthetic benchmarks write only into the artifact directories you provide.

For running-process CPU, footprint, RSS, disk counters, wakeups and threads:

```sh
artifacts=$(mktemp -d "${TMPDIR:-/tmp}/codexjet-perf.XXXXXX")
clang -O2 tools/performance/proc-metrics.c -o "$artifacts/proc-metrics"
# Replace 12345 with the exact CodexReset process PID.
python3 tools/performance/profile-process.py 12345 --seconds 30 --label visible-idle --helper "$artifacts/proc-metrics" --output "$artifacts/visible-idle.json"
```

Measure visible-idle, hidden-idle and refresh separately. Wait for startup scanning to finish before an idle sample. A CPU value of 100% is one core; CPU uses kernel-counter deltas rather than `ps`'s recent estimate. The helper converts mach ticks to nanoseconds on Intel and Apple Silicon. Disk counters are physical I/O, not all logical file reads; the separate logical-write field has a different meaning. The child CPU field counts exited children, not a complete live process tree. Footprint is reported alongside RSS because they are not interchangeable. Raw samples contain process metrics and monotonic times, without command lines or account/session content.

For history persistence, use a new artifact path for each run. The failed-write regression leaves one fixture directory read-only on purpose.

```sh
swift run -c release --package-path tools/performance/history-benchmark --scratch-path "$artifacts/history-build" HistoryStorePerformance "$artifacts/history-fixtures"
```

For a synthetic token-reader comparison against the pre-optimization version:

```sh
git show v0.20.0:Sources/ResetCore/LocalTokenUsageReader.swift > "$artifacts/LocalTokenUsageReader-Baseline.swift"
swiftc -O -whole-module-optimization -parse-as-library Sources/ResetCore/LocalTokenUsage.swift "$artifacts/LocalTokenUsageReader-Baseline.swift" tools/performance/token-reader-bench.swift -o "$artifacts/token-baseline"
swiftc -O -whole-module-optimization -parse-as-library Sources/ResetCore/LocalTokenUsage.swift Sources/ResetCore/LocalTokenUsageReader.swift tools/performance/token-reader-bench.swift -o "$artifacts/token-optimized"
"$artifacts/token-baseline" --prepare "$artifacts/canonical"
ditto "$artifacts/canonical" "$artifacts/before"
ditto "$artifacts/canonical" "$artifacts/after"
"$artifacts/token-baseline" --run warm "$artifacts/before" > "$artifacts/token-before.json"
"$artifacts/token-optimized" --run warm "$artifacts/after" > "$artifacts/token-after.json"
```

`cold` measures initial parsing; `appendcache` adds 40 daily batches; `warm` also measures 20 unchanged refreshes. Each run needs its own fresh copy of the canonical fixture because append scenarios mutate their synthetic files. Compare `report_hash_chain_sha256` and `final_report_sha256` before comparing time or memory. `peak_rss_bytes` comes from `getrusage`; MB and MiB conversions must be stated explicitly. `logical_parse_bytes_from_fixture_offsets` describes expected fixture parsing and is not an instrumented physical-I/O counter. `token-reader-profile.py` can additionally sample kernel counters while a benchmark runs; its JSON summary goes to stdout, while `--output` stores the benchmark's own JSON.

The UI motion regression is `scripts/proof-quota-motion.sh`, with an optional `--reduce-motion` argument. It opens a short-lived synthetic clock window and verifies compositor motion and window pause/resume with the native event loop running. It performs no account or notification I/O.

See [the measured results](../../docs/performance-2026-11-02.md) for scope, units and limitations. None of the tools establish battery usage or prove the absence of leaks.
