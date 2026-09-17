# Official Weather.com.cn Capture

Captured on 2026-09-06. Files are unmodified HTTP response bodies, UTF-8.

- `beijing.js`: https://d1.weather.com.cn/wap_40d/101010100.html
- `beijing_location.jsonp`: https://d4.weather.com.cn/geong/v1/api with
  `params={"method":"stationinfo","lat":39.9,"lng":116.4,"callback":"getData"}`
- Request Referer: https://m.weather.com.cn/

The hourly parser reads only `fc1h_24` and preserves each raw row. These are
test snapshots, never production fallback data. Code tables and field usage
were checked against https://j.i8tq.com/e_index/indexTopNew.js?20210730 and
https://j.i8tq.com/todayDetail/newMain.js?2019052016.

Current-condition captures on 2026-09-07 (unmodified UTF-8 HTTP bodies):

- `beijing_current.js`: https://d1.weather.com.cn/sk_2d/101010100.html
- `yiwu_current.js`: https://d1.weather.com.cn/sk_2d/101210904.html
- `yiwu_outlook.js`: https://d1.weather.com.cn/wap_40d/101210904.html

The official mobile page's `indexTopNew.js` reads `dataSK.weather` and
`dataSK.weathercode` from this endpoint, separately from hourly forecasts.
The parser preserves the raw date and time labels; they use Beijing time.
