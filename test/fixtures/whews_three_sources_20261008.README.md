# Source evidence

- `funvisis_documented_20261008.json` and `cwa_tsunami_documented_20261008.json`
  preserve the valid published JSON example values fetched from
  https://api.beecld.com/#ws-funvisis and
  https://api.beecld.com/#ws-cwa-tsunami on 2026-10-08.
  They are documentation examples, not live observations. The CWA `...`
  strings stay exactly as published and have no inferred numerical heights.
- `cat_tsunami_captured_20260917.json` is the unchanged CAT frame extracted from
  `catalog_20260917/whews_all.json`, an existing aggregate capture.
  The current CAT documentation's URL strings are malformed JSON; they are
  not repaired or used as a valid event.
- Lifecycle tests construct explicit application-model scenarios separately.
  No original fixture is retimed, edited, or injected into a running APP.
- `cwa_tsunami_captured_20261008.raw.json` is the exact `Data` field preserved
  by the running APP after its real WHEWS aggregate subscription on 2026-10-08.
  Its Information description quotes removal of the Pacific tsunami threat;
  the source level remains Information. No replacement frame/md5 is invented.
