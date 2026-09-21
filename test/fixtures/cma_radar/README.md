# China Weather Radar Capture

Captured on 2026-09-21 from China Weather with
`Referer: https://www.weather.com.cn/` and `User-Agent: Mozilla/5.0`.

- `radar_list_20260921.jsonp`: unchanged response from
  `https://d1.weather.com.cn/radar_channel/radar/json/radar_list.json?callback=readRadarList`.
- `ACHN_QREF_20260921_221200.png`: unchanged latest PNG named by that response,
  from `https://d1.weather.com.cn/radar_channel/radar/pic/`.

Tests replay these bytes, not manufactured radar observations. Reversed or
shortened lists reuse original entries to check selection and stale responses;
invalid protocol/HTML/truncated-image cases are explicit fault injection.
