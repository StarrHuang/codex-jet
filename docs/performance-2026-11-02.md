# Codex Jet 0.20.1 performance verification

The main improvement is lower CPU usage while the dashboard is visible. The quota-clock hand now rotates in a Core Animation layer instead of rebuilding SwiftUI content at 24 frames per second. History persistence also avoids a redundant decode, and the token reader releases usage records outside its rolling seven-day window. Charts, reminder rules, polling intervals and languages remain compatible.

Measurements were taken on an Apple Silicon Mac running macOS 26.3 on 2026-11-02. They compare the installed 0.20.0 app with a signed universal 0.20.1 build. CPU percentages use one logical core as 100%. MB means 1,000,000 bytes; MiB means 1,048,576 bytes.

**Running app.** The dashboard was visible and idle, with its quota clock moving and existing history loaded. Manual and automatic refreshes were excluded from the idle intervals.

| Metric | 0.20.0, 20.2 seconds | 0.20.1, 20.2 seconds | 0.20.1 repeat, 40.3 seconds |
|---|---:|---:|---:|
| App CPU | 15.41% | 1.61% | 0.77% |
| Interrupt wakeups / second | 57.68 | 1.33 | 1.14 |
| Context switches / second | 1,010.92 | 14.68 | 7.89 |
| Kernel physical read / write | 0 / 0 bytes | 0 / 0 bytes | 0 / 0 bytes |
| Maximum thread count | 7 | 6 | 7 |

The first comparison is an approximately 90% reduction in app CPU; the repeat supports the direction of the result. A native `sample` trace before the change was dominated by SwiftUI rendering. This is a small local experiment rather than a population benchmark. GPU work, WindowServer CPU and battery energy were not measured.

Hidden-window CPU was already low: 0.05% before and 0.25% after, each over about 20 seconds. No physical or logical writes were recorded in either hidden interval. These small values do not establish a background improvement.

The optimized app's visible-idle footprint medians were 56.9 and 61.7 MiB; RSS medians were 157.1 and 150.2 MiB. The old app measured 99.1 MiB footprint and 136.4 MiB RSS. The old process had been running longer, and the machine was under memory pressure, so these app-memory snapshots are descriptive, not a matched memory-saving or leak test. Footprint and RSS measure different things; Apple explains their use in [Analyze and reduce your app's memory usage](https://developer.apple.com/videos/play/wwdc2021/10180/).

A separate 20.3-second interval containing one manual refresh recorded 9.78% app CPU, 2.52 MB physical reads, 1.58 MB physical writes and 1.62 MB logical writes. Refresh completed, the history sample count advanced, and the chart remained available. It is not compared with idle CPU. Initial startup still scans local logs: the new process had read approximately 1.41 GB by the first post-start snapshot. Cold scanning was not eliminated by this patch.

**History persistence.** The synthetic harness compares the previous `append` followed by `load(accountKey:)` call pattern with the new append-return-and-filter pattern. Both retain all accounts and the same atomic JSON format. This final repeat produced:

| Synthetic history | Previous wall / CPU | New wall / CPU |
|---|---:|---:|
| 5,000 samples, 1.13 MB | 100.5 / 99.3 ms | 65.4 / 63.7 ms |
| 50,000 samples, 11.35 MB | 961.7 / 955.1 ms | 640.1 / 634.9 ms |

This removes one full-file read/decode per refresh, reducing measured time by roughly one third. It does not halve physical disk traffic: page-cache reads and physical reads are different. Each refresh still atomically rewrites the full history file. The app now performs that work off the main actor.

**Long-running token cache.** A deterministic synthetic file starts with 100,000 usage records and 200,000 irrelevant lines, then receives 40 daily batches of 5,000 usage records. The final file is 102.21 MB. Old and new binaries used the same release optimization flags and separate copies of the same fixture.

| Metric | Before | After |
|---|---:|---:|
| Peak RSS, cold parse + 40 appends | 159.7 MB | 66.0 MB |
| CPU, cold parse + 40 appends | 21.68 s | 21.50 s |
| Mean of 20 unchanged refreshes after those appends | 30.06 ms | 24.78 ms |
| Cold parse wall time | 6.86 s | 6.81 s |

The matched append scenario used approximately 59% less peak RSS; unchanged refreshes were about 18% faster. Cold parsing and total append CPU were effectively unchanged. Every report hash chain matched between versions. The cache retains future records, model context and warning counts. Model-context dictionaries remain retained for correctness, so this is not a guarantee of constant memory for indefinitely growing files. Physical reads varied with page-cache state and do not support an I/O reduction claim.

**References and choices.** These are primary implementation references, not independent benchmarks of Codex Jet:

- [CodexBar refresh loop](https://github.com/steipete/CodexBar/blob/main/docs/refresh-loop.md): background work, coalesced refreshes and explicit scheduling policy. This patch moves history I/O off-main while keeping the existing five-minute cadence and reminder checks.
- [Stats reader lifecycle](https://github.com/exelban/stats/blob/master/Kit/module/reader.swift): separate collection work from presentation, with start/pause/stop ownership. Existing sampling remains active when the UI is hidden; the decorative hand stops.
- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess): useful access to SwiftUI menu presentation and native windows. No dependency was added; the hand observes its own hosting window.
- [Apple window occlusion notification](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification) and [CABasicAnimation](https://developer.apple.com/documentation/quartzcore/cabasicanimation): the hand stops for hidden/occluded windows and resumes without resetting its heading.

**Verification.** A clean scratch build passed all 12 existing behavioral harnesses, including English/Japanese/Korean localization checks. Native motion proofs passed for measured speed changes, heading continuity, hidden/inactive pause, resume, stale/unknown/empty states, Reduce Motion and the one-time announcement rim. The history harness passed account filtering, persisted date precision and failed-write byte preservation. Independent source review found no actionable correctness issue. The universal app passed strict signature checks, was installed locally, and preserved history bytes across installation. Native UI readback confirmed live reading, refresh, the restored chart and the clock's appearance. A synthetic temporary-reset popover render retained the quota curve.

Process metrics use `proc_pid_rusage` and `proc_pidinfo`; CPU mach ticks are converted with `mach_timebase_info` and were cross-checked against `ps` cumulative CPU time. An initial unconverted CPU sample was discarded. The machine has Command Line Tools without full Xcode, so Instruments energy/leak profiling was not performed. Raw traces, account data and real screenshots stay outside the repository. Reproduction instructions are in [tools/performance/README.md](../tools/performance/README.md).
