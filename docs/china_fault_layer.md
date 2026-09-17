# China fault overlay

## Reference and data

- Reference inspected: local `kanameishi-dev/src/components/MainMapComponent.vue`, China fault watcher and `loadBaseMap`.
- Source: local KA `public/json/cn.fault.topo.json`, copied unchanged into `assets/maps/cn.fault.topo.json`.
- Original asset SHA-256: `ba94d866e2e2c350ef7a150cbca4d6d7844b4a8c606a5215dd37ac7bf0640692`.
- The previously bundled `cn.fault.modified.topo.json` is not used by this layer.
- KA uses red for `Qh`, orange for `Qp3`, CSS green for other age values, opacity 0.5 and stroke width 1.5. This layer follows that styling and defaults off.

## Integration

- Settings > map and notifications > map appearance, provider key `cnFault`, preferences key `map_overlay_cnFault`. Moved out of the weather/volcano information section on 2026-09-09; stored values are unchanged.
- Preferences are restored both at application startup and in the settings page.
- Layer is above the unified intensity fill and below stations. Existing relative layer order is unchanged.
- Mobile weather mode excludes this seismic layer. The weather-only settings shortcut does not offer its switch.
- `IgnorePointer` keeps map gestures and underlying interactions available.

## Performance

- Disabled by default: no data loading or fault widgets until enabled.
- Local asset, no additional polling or network requests.
- Shared in-flight/result future avoids concurrent or repeated asset reads and parses.
- Native JSON/topology decoding runs through `compute`, outside the UI isolate.
- Source coordinates are not simplified in storage or in decoding. Negative arc references use TopoJSON one's complement and reverse order.
- `CachedFaultLayer` caches projected paths rather than using the generic `PolylineLayer`'s per-frame segment clipping and screen-path reconstruction. All original points are retained; no asset or decoded coordinate simplification is applied.
- Consecutive batches of 32 traces retain original draw order, colors, alpha and a constant 1.5 logical-pixel width. Each batch retains at most one vector `Picture`, with a 256-pixel viewport overscan. A pan replays cached commands; crossing coverage or changing zoom replaces that picture. Invisible batches are skipped using projected bounds. This is a vector command cache, not bitmap tiles or per-zoom image accumulation.
- The layer uses the map camera's CRS, world repetitions and rotation transformer, with local path coordinates for precision. It has its own repaint boundary and never handles pointer events.
- Changing data or CRS invalidates paths and pictures; disabling the layer disposes pictures explicitly. Moving and zooming do not reread the source asset.
- Turning off disposes the rendering subtree; the shared decoded data stays cached for later use. Rendering caches are recreated on re-enable.
- No custom frame callback, station-update work or periodic rebuild has been added.

## Verification

`flutter test --no-pub test/china_fault_layer_test.dart`

- The 2,354 source records contain two null geometries; decoding yields 2,608 lines and 48,439 joined points.
- Compared every name, age, line order and coordinate against `topojson-client@3.1.0`, using coordinates formatted to nine decimal places. Canonical JSON SHA-256: `73ac1e59669311bbde4aecaa21838d24b2d88b705526de0daa94c4627375e6f3`.
- Regression covers default-off/provider notifications, shared reads, retry after load failure, rendering at 1280x720 and 430x850, map dragging/zooming, retained widget identity and repeated toggling. `fault_render_cache_test.dart` compares real-data pixels with the original unsimplified renderer after pan, overscan crossings, zoom, rotation and world wrapping.
- Test render captures in `tmp/china_fault_review` deliberately omit online basemap tiles. They verify the overlay, not a full installed application screenshot.
- A debug widget-test benchmark with both real datasets enabled measures UI-side steady-pan work, not raster/GPU time or device FPS. Initial run: previous renderer median 18.425 ms / p95 20.495 ms; cached renderer median 4.047 ms / p95 5.417 ms. Repeat results are written to `tmp/china_fault_review/pan-benchmark.txt`; timings vary by machine load. Device FPS and application process memory have not been benchmarked by this suite.
