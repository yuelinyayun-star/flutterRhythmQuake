# Japan fault layer

## Source

Source: Geological Survey of Japan, AIST, Active Fault Database (GSJ).

- Official database: https://gbank.gsj.jp/activefault/
- Official layer registry: https://gbank.gsj.jp/activefault/js/mapInfos.js (`BehavioralSegments_ja`).
- Original KMZ: https://gbank.gsj.jp/activefault/DATA/layers/trace_gbank_j.kmz
- Terms: https://www.gsj.jp/license/index.html
- Data limitations: https://gbank.gsj.jp/activefault/attention.html

Retrieved 2026-09-09, unchanged, 522,227 bytes. SHA-256:
`3b25267d6e641c81e5d443fffd18a957f1866bc91659cdff1a72369979259eb5`.

The source document name is `活動セグメント150219-2.kmz`. Retrieval date is not a claim that the underlying survey was updated in 2026. This is the dataset currently referenced by the official site's layer registry. The local KA reference has a China fault layer but no Japan fault dataset or implementation.

GSJ allows secondary use with attribution under its published terms. The settings switch identifies GSJ and the Active Fault Database. These are approximate compiled fault traces, not parcel-level boundaries or a guarantee that no other faults exist; the official notice describes positional errors of up to several hundred meters in some areas.

## Rendering and settings

- Settings > map and notifications > map appearance > Japan faults; independently saved `map_overlay_jpFault`, default off.
- China faults use the same settings section, retaining `map_overlay_cnFault`.
- Source KMZ is packaged directly. ZIP decompression and UTF-8 XML parsing occur via `compute`, only when first enabled. Decoded results and concurrent loads are shared.
- Original KML normal StyleMap, color `990516d5` (ABGR), alpha and width 4 are read from the file. Flutter ARGB is `99d51605`. On 2026-09-09 the display stroke was reduced to 1.5 logical pixels at the user's request, matching the China layer; the parsed source width remains unchanged. No China age classifications are applied to Japan.
- Original coordinates and order are preserved. Both countries now use `CachedFaultLayer`: projected local paths, viewport-filtered vector drawing batches and a bounded one-picture-per-batch cache. Pans replay commands instead of clipping and rebuilding every line on each frame. Zoom changes rebuild commands with the same 1.5 logical-pixel width; source data is not simplified. See `china_fault_layer.md` for cache lifetime and test details. No polling, extra tile requests or station-frame processing.
- Noninteractive, above intensity fill and below stations. Hidden in mobile weather mode. Disabling removes rendering but retains parsed data for reuse.
- Placemark balloon HTML is not rendered or executed; names come from the original parent folders. No external KML links or icons are fetched.

## Verification

The snapshot contains 3,477 LineStrings and 31,942 coordinates. An independent .NET XML parser reads all coordinates in source order, canonicalized as longitude/latitude with nine decimals, semicolons within a line and LF after each line. Canonical SHA-256:
`773238297692ef1dbac3a9bb369d6c7abd17a07523e6264461ee9a8aff873233`.

Tests: `japan_fault_service_test.dart`, `china_fault_layer_test.dart` (both countries at desktop/mobile sizes), and the weather shortcut regression in `mobile_weather_panel_test.dart`.

Native device FPS and process memory have not been benchmarked. Overlay-only test screenshots omit online basemap tiles.

## Scope decision (2026-09-09)

The separately added seven-map marine supplement was removed at the user's
request because its coverage was incomplete and its packaged size was too large.
The original GSJ active-fault KMZ, China fault data, existing map switches and
the 1.5-pixel Japan display stroke are retained. No additional marine archive,
parser or shapefile dependency is shipped.
