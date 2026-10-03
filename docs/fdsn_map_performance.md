# FDSN Map Performance

Verified on Windows with Flutter 3.41.1, 2026-10-03. This change is limited
to the international FDSN station display pipeline.

## Changes

- Index source catalogues once, replace only stations receiving motion updates,
  and merge only recently observed stations. Preserve catalogue order rather
  than packet arrival order when markers overlap.
- Cache the immutable merged snapshot until an observation, catalogue, enabled
  source sequence, or earliest expiry changes. Expiry still uses original
  observation timestamps and the existing three-minute retention.
- Query a zoom-zero spatial grid for local views. Apply the original exact
  bounds and world-copy checks to its candidates, retaining intensity order.
  Small catalogues and broad/dense views use a linear scan.
- Reuse projected coordinates and glyphs by station identity after list changes.
  Values changing within the same displayed level do not invalidate pixels.
- Reuse atlas transform/rectangle buffers and the paint object. Existing marker
  sizes, labels, colors, pixel ratio handling and retained pan cache are unchanged.

No subscription cap, station thinning, reduced sample cadence, altered raw
measurements, intensity formula change, or network/proxy change is introduced.

## Verification

Controlled fixtures are confined to tests, never fed into production sources.

- 93 targeted tests passed across rendering, store lifetime, multiple providers,
  metadata, motion processing, foreground payloads, dashboard and proxy handling.
- 16 rendering/store tests passed with `RQ_EDITION=public`.
- 16 before/after RGBA comparisons had zero changed bytes: desktop/mobile,
  MMI/CSIS, fractional zoom, rotation, dateline/world copies and DPR 1/1.25/2.
- For 5,000 globally distributed stations over 120 local zoom frames, exact
  candidate visits fell from a 600,000 full-scan workload to 1,832 (desktop) and
  960 (mobile). Camera-only changes did not rebuild the index or projections.
- Same-level update assertions verify no new glyphs, picture recordings, index
  builds or atlas-buffer allocations after the initial visual change.
- Removing/reversing the station list reuses surviving coordinates and glyphs.
- A paired 28,000-catalogue/4,900-active update benchmark measured median
  4,545 us before versus 2,482 us after. Regression/public reruns measured
  4,488/2,637 us and 4,624/2,810 us respectively. Each median excludes ten
  warmup iterations and includes thirty measured iterations.

These are test-process measurements, not Release FPS, GPU profiling, or a
whole-application CPU claim. Camera timing varies between runs; operation counts
and pixel equivalence are the regression assertions. Live cloud-desktop CPU
improvement has not been measured for this change.

## Reproduce

```powershell
flutter test --no-pub --concurrency=1 test/fdsn_station_layer_test.dart test/fdsn_station_performance_test.dart test/fdsn_map_station_store_test.dart
flutter test --no-pub --concurrency=1 --dart-define=RQ_EDITION=public test/fdsn_station_layer_test.dart test/fdsn_station_performance_test.dart test/fdsn_map_station_store_test.dart
```

The optional `FDSN_RENDER_PHASE=before` define captures local raw RGBA baselines
under `tmp/fdsn_map_performance`; use it on the pre-change renderer only. Run
`FDSN_RENDER_PHASE=after` on the changed renderer against those same files.
Without the define the tests need no external baseline files. Local experiment
logs are in `tmp/fdsn_multisource_20261003/map_*.log`; temporary artifacts are not
required by normal CI.
