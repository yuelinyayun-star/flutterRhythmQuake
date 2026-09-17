# FDSN MMI audit, 2026-09-10

## Scope and evidence

The user's screenshot is at 16:28:05 UTC+8, with a GQ event time of
16:26:52 UTC+8 off Costa Rica. This audit does not change production processing,
station scale, transport or peak-hold policy.

The running Debug process was inspected through read-only VM object access;
no expression execution, hot reload or connection restart was used. At
08:33:46 UTC the 16 selected regional stations had actual PGA/PGV values and
MMI 1, with original observation times mostly 08:33:32-38 UTC (JTS 08:33:14).
This is a later snapshot, NOT proof of which records the app received at
08:27-08:28. See `tmp/fdsn_connection_review/mmi_runtime_costa_rica_20260910.json`.

Original archive request:

https://service.earthscope.org/fdsnws/dataselect/1/query?net=TC&sta=QUEP&loc=*&cha=EH?&start=2026-09-10T08:26:30&end=2026-09-10T08:29:00&nodata=404

The unmodified response is 105472 bytes, 206 miniSEED records, with SHA256
`e7439875fc6ea7a12631eff2719a2c329f626c3ca0ebdac78cb36190c803bc94`.
Channel metadata matches TC.QUEP..EHE/EHN/EHZ, epoch starting 2015-10-01,
sensitivity 3.0E8 counts/(m/s), sample rate 100 Hz. Original response and
metadata are retained under `tmp/fdsn_connection_review`.

ObsPy decodes each original 512-byte record independently. The opt-in Dart
test then checks EVERY sample against ObsPy, selects metadata through the
production NSLC/epoch parser, and calls the actual production metric function.
All 206 record comparisons passed. No waveform rescaling or rewriting was
performed before supplying the raw records to the Dart decoder.

| Channel | Peak MMI record start (UTC+8, rounded to seconds) | PGA Gal | PGV cm/s | MMI |
| --- | --- | ---: | ---: | ---: |
| EHE | 16:27:14 | 7.03 | 0.31 | 3.09 |
| EHN | 16:27:15 | 4.32 | 0.29 | 2.99 |
| EHZ | 16:27:13 | 3.29 | 0.13 | 2.58 |

Around 16:28:05, EHE is about 1.28, EHN about 1.10, and EHZ 1.00.
Current floor-to-integer display therefore yields 1 for all three. The last
record with MMI >=2 in this window ends around 16:27:40. These are archive
replay results, not a captured history of live delivery. Exact times and
values are in `costa_rica_QUEP_mmi_result.json`.

## Findings

- The metric path is connected and can produce elevated MMI from this event.
  The snapshot alone cannot establish whether its strongest records reached
  the live receiver, especially given the separate disconnection issue.
- The map keeps the latest per-station sample, not an event or recent peak.
  The one-second pending map can overwrite a stronger short record, and the
  three-minute retention controls visibility, not peak retention.
- Samples are keyed by provider/network/station, without channel/location.
  A weaker component with an equal or later record-start time can overwrite
  another component. This is not a defined horizontal-component combination.
- Raw counts are divided by the scalar channel sensitivity, demeaned per
  record, differentiated/integrated and converted to Gal/cm/s. This is an
  approximation, not full frequency-dependent instrument-response removal.
- The PGA/PGV bilinear coefficients match Worden 2012, but this implementation
  does not include ShakeMap's additional I-II segment or its full processing.
  The local PGA/PGV preference is also not a complete ShakeMap implementation.
- The checked open GQ revision c96985c uses `getMaxRatio60S` and
  `Scale.getColorRatio` for station color. That is not station MMI. The user's
  installed GQ is 1.1.0; the older open source is not proof of every 1.1.0
  display detail. Its serialized field name `maxIntensity` alone does not
  identify its physical meaning.

Source for GMICE coefficients and low-intensity extension:
https://usgs.github.io/shakelib/_modules/shakelib/gmice/wgrw12.html

Validation: existing processing/map suites passed 14 tests, including visible
level changes invalidating cached pixels. The original-event audit passed one
additional test with 206 record/sample comparisons. No production change was
made from the audit alone.

## Follow-up: nearest-integer display and peak-window inspection

The user subsequently approved nearest-integer MMI display. The shared map
digit/color level now uses `round()` (positive half values round upward),
while continuous MMI/PGA/PGV and the CSIS calculation remain unchanged. The
floor behavior described above records the pre-change audit, not current code.
OBS trigger thresholds were not changed as part of this display-only request.

An offline inspection at 08:28:05 UTC uses original records whose END times
are in `(referenceTime - window, referenceTime]`, excluding unfinished records.
This is a display-window comparison, not reconstructed live arrival ordering
or a physical three-component combination. Per-channel maximum MMI:

| Window | EHE | EHN | EHZ | Largest value rounded |
| --- | ---: | ---: | ---: | ---: |
| 10 seconds | 1.5755 | 1.6870 | 1.1356 | 2 |
| 30 seconds | 2.3633 | 2.4172 | 1.8529 | 2 |
| 60 seconds | 3.0924 | 2.9949 | 2.5813 | 3 |

The latest individual records around the reference time round to 1. No peak
window has been enabled in production. A future implementation must ingest
before the one-second pending-sample overwrite, retain raw observation times,
expire peaks without requiring another incoming packet, and distinguish
display peak age from station liveness. A later weak packet must not renew
an old strong peak's lifetime. Keep original samples separate from held
display state, including through the Android foreground-service bridge.
KMA has frame-based recentLevel/holdLevel handling, but irregular miniSEED
records require observation-time windows rather than assuming one frame/second.
