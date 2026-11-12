# JMA tsunami protocol references

- `jian.documented.json`: exact JSON code block from
  https://api.sismotide.top/api/#ws-jma-tsunami, fetched 2026-10-10.
  Only HTML highlighting tags were removed and HTML entities decoded. This is
  the provider's documented example (`md5: example`), not a live observation.
- `32-39_*_250206_VTSE41.original.xml`: unchanged XML files extracted from JMA's
  https://xml.kishou.go.jp/jmaxml_20260917_Samples.zip, linked on
  https://xml.kishou.go.jp/tec_material.html, fetched 2026-10-10.
  These are JMA's official sample bulletins, not current warnings.

Tests read their original issue/validity times, names, categories and values.
No event IDs, clocks, levels or coordinates are rewritten to make them live.

- `whews.forecast_stations.documented.json` and
  `whews.observations.documented.fragment.txt`: unchanged `<pre>` examples from
  https://api.beecld.com/assets/ws-jma-tsunami-tjFjtoYv.js, fetched 2026-10-19.
  These are provider documentation examples, not live observations. The latter
  is a JSON property fragment; tests add only enclosing braces to read it.
  Separately labelled protocol tests construct ordering/correction cases.
