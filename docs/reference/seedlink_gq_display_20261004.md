# SeedLink GlobalQuake display audit

## Reference and boundaries

Reference: GlobalQuake open-source `0.11.0`, commit
`c96985c86d5fb10c05d46054b0efc27d9cab7f53`.

- `GlobalQuakeCore/.../analysis/BetterAnalysis.java`
- `GlobalQuakeCore/.../analysis/WaveformTransformator.java`
- `GlobalQuakeCore/.../station/AbstractStation.java`
- `GlobalQuakeCore/.../utils/Scale.java`
- `GlobalQuakeCore/src/main/resources/scales/pgaScale3.png`
- `GlobalQuakeClient/.../feature/FeatureGlobalStation.java`
- `GlobalQuakeCore/.../globe/GlobeRenderer.java`

Source: https://github.com/xspanger3770/GlobalQuake/tree/0.11.0

This implements the local display signal, not the GQ earthquake location engine.
It does not connect to a GlobalQuake server or claim parity with closed-source 1.x.
The 2-5 Hz third-order Butterworth design and Direct Form II implementation use
`iirjdart`, the Dart port of the filter library used by the reference.
GQ attribution is retained in source and registered with Flutter LicenseRegistry.

Shape and numeric/color mode are independent. MMI and estimated Chinese intensity
retain their original calculations, integer levels and palettes. Their existing
`fdsn_intensity_scale` preference is restored. The default is circle shape with
signal ratio; explicitly saved MMI, Chinese intensity and shape choices remain
unchanged.
The additional ratio mode is labeled `信号比值` in settings. It uses the original
80-row color lookup, one-decimal labels below the symbol, and event-colored
flashing frame. All three numeric modes work with all three shape choices.
The category mode uses response input units: velocity triangle, acceleration
inverted triangle, displacement square, unknown circle. Unknown input is not
inferred from a provider or channel name. Calibration-based PGA/PGV/MMI and OBS
inputs remain independent of the selected display mode. Ratio event frames are
only drawn in ratio mode; they do not replace the MMI/Chinese intensity colors.

Intentional platform adaptations:

- Flat Web-Mercator projection, labels at zoom 6. The nominal circle radius is
  `7 * clamp(2^((zoom-7)/2), 0.5, 1)` logical pixels: 7 at zoom 7 and closer,
  3.5 at zoom 5 and farther (minimum diameter 7 pixels). Other shapes and event frames scale
  by the same continuous factor; zoom changes never rebuild the sprite atlas.
- Calibri 13 where available, existing bundled font as fallback elsewhere.
- History advances on observation seconds, not arrival-clock timer callbacks.
  This keeps delayed packet bursts and replay pacing from changing the window.
- The original add-then-trim history retains 59 completed one-second values.
- Late/duplicate records do not roll back a newer baseline; gaps over one second
  reinitialize. Unsupported Nyquist range or undefined background remains gray.
- Existing active-station retention and provider controls remain in force.
- Desktop hover details and the GQ globe camera are not introduced by this change.

## Original-data verification

The existing TC.QUEP EHE/EHN/EHZ original MiniSEED capture was not edited:

`tmp/fdsn_connection_review/costa_rica_TC_QUEP_20260910.mseed`

SHA-256: `e7439875fc6ea7a12631eff2719a2c329f626c3ca0ebdac78cb36190c803bc94`

`fdsn_record_mmi_audit_test.dart` compared all 206 native-decoded records with the
existing ObsPy audit JSON, sample for sample. `SeedLinkGqOracle.java` ran the
original upstream Analysis, BetterAnalysis, WaveformTransformator and
AbstractStation Java sources against that same input, using controlled
observation-second ticks. All 186 initialized ratios had absolute error 0;
all 77 event records matched. No original sample or timestamp was adjusted.

The Java harness needs the four pinned source files above on javac's input,
the GQ 0.11 dependency jar and Gson 2.10.1 on its classpath, and UTF-8 source/JVM
encoding. The locally generated classes in `tmp/gq_reference` must precede the
dependency jar on the runtime classpath. Arguments are the original audit JSON
and output JSON. The Dart oracle test reads `tmp/gq_reference/ratios.json` and
explicitly skips, rather than fabricating observations, when audit data is absent.

## Performance and regression checks

- Continuous analysis precedes the metadata/coalescing queue. Only calibrated
  metrics coalesce while metadata loads; each original accepted waveform packet
  reaches the detector first. Socket decoding yields after a 4 ms batch budget.
- Fixed-size history per stream; shared immutable filter designs (32-entry cap),
  independent filter delay states; no raw waveform retention for display.
- A fixed 18-slot atlas contains 4 white shapes and 14 characters, tinted in a
  single batch. Changing numbers do not build TextPainters or grow textures.
- Camera-coordinate caching, viewport culling, stable spatial index, retained
  viewport pictures, and a separate 2 Hz event-frame repaint boundary.
- 5000-station tests confirm no projection/index/atlas rebuild for value changes,
  no base-layer repaint for flashing, and unchanged pixels on timestamp updates.
- Pixel checks: 390x844 and 1280x720; DPR 1, 1.25, 2, 3; fractional zoom,
  rotation, world wrapping, shape changes, one-decimal labels and expiry.

Windows AOT workload (not 5000 real stations): 5000 independent analyzers fed the
same untouched EHZ capture, 330000 records / 75005000 samples / 150.01 observation
seconds. Initial run: 2854 ms; shared-design run: 2518 ms, about 16.8 ms computation
per observation second. Standalone process RSS was about 55 MiB; this is **not**
application RSS and includes runtime/heap reservation.

Flutter test-engine results varied with concurrent regression work: 5000 changed
ratios took about 9.3-10.2 ms per pump. These are **not** installed-app FPS or CPU
measurements. Whole-app CPU, GPU and memory targets need separate live profiling.

66 targeted regression tests passed, including connection recovery, slow metadata,
original decode, foreground payloads, map storage, rendering and signal analysis.
Scoped analyzer: no errors/warnings, 10 pre-existing informational lint findings.
No installer, deployment or GitHub push was performed for this change.

### Restored modes and zoom sizing regression

24 targeted tests passed across `seedlink_station_style_test.dart`,
`fdsn_station_layer_test.dart`, `fdsn_processing_test.dart` and
`fdsn_station_performance_test.dart`. Checks cover legacy preference parsing,
all nine metric/shape combinations at 390x844 and 1280x720, original MMI/CSIS
colors, independent labels, inactive-metric updates without repaint, active
updates without projection/atlas rebuild, continuous fractional zoom, wrapped
coordinate anchoring, and 5000-station workloads. Test fixtures are isolated
rendering inputs, not modified production observations. Scoped analyzer reported
no errors/warnings and eight existing informational brace-style findings in
`quake_map_view.dart`. This follow-up has not been packaged into an installer.

AOT workload reproduction:

```powershell
dart compile exe tools/benchmark_seedlink_signal.dart -o tmp/gq_reference/benchmark_seedlink_signal.exe
& ./tmp/gq_reference/benchmark_seedlink_signal.exe
```
