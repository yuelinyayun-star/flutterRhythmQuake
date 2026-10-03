# Windows Profile Measurement, 2026-10-03

## Scope

This is a diagnostic development build, not a release installer. The running
installed executable had exited before a baseline interval could be captured.
The earlier Task Manager screenshot is therefore not a controlled baseline.

The profile entrypoint uses a copy of the user's existing settings and history
under `tmp/profile_run/support`. No station source, station count limit, display
scale, refresh setting, or observation was changed to meet a performance number.
Windows secure credentials remain managed by the existing platform plugin.

## Changes

- The desktop status block uses the same left edge as the right sidebar. It
  reserves space for action buttons and wraps inside the remaining fixed width.
  Global station updates no longer rebuild on unrelated station/clock changes.
  **Subsequent UI correction:** the shared block width/offset change was reverted
  after user feedback. Only the international list now wraps to the existing
  status content's width; ordinary status positioning and time lines retain
  their prior layout. The measurements and compiled payload below predate this
  correction. The independent global-status update optimization is retained.
- SeedLink link counts sum the already deduplicated connection counts instead
  of repeatedly copying all station keys for every newly linked station.
- Raw SeedLink bursts decode in batches of at most 128 records per event-loop
  turn. Remaining bytes stay queued, in order; this does not sample the input.
- MiniSEED decoding uses typed sample arrays and avoids per-word difference
  lists. PGA/PGV loops avoid duplicate traversals without changing the formula.
  The existing ObsPy/libmseed fixture comparison verifies every decoded sample.
- Instrument metadata caches retain epochs for subscribed stations only and
  invalidate when selection changes. Metadata endpoints are unchanged.
- Windows history storage skips repeated reads of event bodies by caching
  digests, and encodes multiple new archive chunks per worker invocation.
  This extends the separate-file/lazy-history work in windows_history_storage.md.

## Measurement

OS counters use 16 logical CPUs, total-process CPU-time deltas and actual elapsed
wall time. Working set is the total process working set, not Dart heap size.
The last run used 45 samples at roughly two-second intervals. No heap walk or
CPU-profile collection was performed during that final interval.

| Profile revision | Mean CPU | Peak CPU | Mean working set | Peak working set |
| --- | ---: | ---: | ---: | ---: |
| First diagnostic revision | 9.59% | 14.24% | 589.32 MiB | 647.30 MiB |
| Final diagnostic revision | 7.99% | 13.64% | 502.47 MiB | 533.01 MiB |

The network feed is live, not an identical replay workload. These rows describe
observed runs, not a controlled percentage-improvement guarantee. A separate
mid-run Windows counter read reported private working set 410,820,608 bytes
(391.79 MiB); this is one observation, not a private-working-set average.

At the end, seven connections had received data from 4,945 stations. Each had one
connection attempt. The interval received 289,886 additional raw packets. Some
upstream records were stale; EarthScope also sent encoding-4 records unsupported
by the existing decoder. Neither was replaced with fabricated observations.

The last 600 reported frames had build p95 14.216 ms and raster p95 16.333 ms.
These are frame processing times, not a guarantee that every incoming event or
user interaction renders immediately. This run did not cover a new real EEW
with all station-history capture active.

All 217 existing history files retained their sizes and modification times
through the final idle interval. Only the small settings file changed in the
watched support directory. Process I/O transfer counters include network and
device I/O and must not be represented as physical disk write throughput.
Existing history still occupies about 345 MB in this copy. No history or
migration backup was deleted to make storage figures smaller.

**Not accepted against the requested targets:** CPU peaks still exceed a single
digit, and both total/private working set remain above approximately 200 MB.
No claim of target compliance or complete elimination of stutter is made.

## Reproduce

The combined regression run passed 109 tests. A separate public-edition run
passed 21 tests. Focused Dart analysis reported no issues, and `git diff --check`
passed. Test logs: `combined_regression.log`, `public_regression.log`, and
`analyze_final.log` under `tmp/profile_run`.

Build with:

```powershell
flutter build windows --profile --no-pub -t tool/performance_profile.dart --dart-define=RQ_EDITION=personal
```

Use `tools/run_performance_profile.ps1` with the existing isolated test copy.
The custom entrypoint deliberately requires `RQ_PROFILE_ROOT`; do not launch
the executable without the launcher or point it at the live installed data.
The full Profile folder is needed, not just the small executable.

Artifacts from this run are under `tmp/profile_run`: `os_final.json`,
`runtime_before_final.json`, `runtime_after_final.json`, `files_before_final.json`,
`files_after_final.json`, and test logs. These local runtime captures may contain
environment details; they are not release assets.

Compiled Dart payload `build/windows/x64/runner/Profile/data/app.so` SHA-256:
`1DE6CC29D8CF961BBC6B2E46191BDB7F5EA05ED0730BEE0604CDE0C14415F0A7`.
The complete Profile directory contains 119 files, 89,550,608 bytes, excluding
the isolated user-data copy and logs.
