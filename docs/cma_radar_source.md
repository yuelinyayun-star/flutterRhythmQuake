# China Weather Radar Source

The existing nationwide radar toggle now fetches directly from China Weather:

- List: `https://d1.weather.com.cn/radar_channel/radar/json/radar_list.json`
- Query: `callback=readRadarList` and `_` as current epoch milliseconds.
- Pictures: `https://d1.weather.com.cn/radar_channel/radar/pic/` plus listed `fn`.
- JSONP is parsed, never executed. Select maximum valid `dt`, checking filename
  against timestamp. UTC+8 source times are stored as UTC instants.
- Both requests include the China Weather Referer and a browser User-Agent.
  A 200 HTML response is not accepted as an image. PNGs pass signature,
  dimension limits and actual decoding; their bytes are not modified.

Foreground and Android background check the list every two minutes. Unchanged
or older frames do not trigger PNG downloads. Failure preserves the last valid
frame; failed new frames remain eligible for retry. Session guards discard late
downloads after stop/restart. Restart replays cache to new Android subscribers.
No request or fallback to the FAN radar endpoint remains.

Legacy `FanRadarService`/`FanRadarFrame` names and `fanRadar` handoff kind are kept
for compatibility. The existing toggle and map opacity (0.60) remain unchanged.
Registration bounds remain southwest `(12.316339, 69.64609)`, northeast
`(54.376029, 140.209411)` (lat/lon). FAN and direct-source 2026-09-21 22:00 PNGs
were byte-identical (SHA-256
`D5908B73522F069E46992B0465FFFF2A93B3802224A024B8E15B2FFDDCAA95A9`).
This replacement preserves existing positioning, not the different bounds in
the provider's Baidu-map frontend; it does not claim new georeferencing calibration.

## Hourly Precipitation

The independent `precipitationChinaLayer` toggle uses the same validated image
pipeline with its own service instance, timer, cache and Android handoff kind
(`cmaPrecipitation`). It does not replace the existing global precipitation tiles.

- List: `https://d1.weather.com.cn/radar_channel/prec1h/rainList.json`
- Query: `callback=getPreObs1h` and `_` as current epoch milliseconds.
- Pictures: `https://d1.weather.com.cn/radar_channel/prec1h/` plus listed `picPath`.
- Validate `prec_YYYYMMDDHH.png` against the original ten-digit `dt` field.
- Source timestamps use UTC+8; poll every ten minutes for a new hourly image.
- Bounds: southwest `(18, 73)`, northeast `(55, 136)` (lat/lon), from the
  provider's `https://i.tq121.com.cn/j/radarMap/mapPack.js` precipitation overlay.
- Display opacity remains 0.60. Original PNG bytes are retained unchanged.

No animation UI is added. Public accessibility does not establish redistribution
rights or a guaranteed service level.
