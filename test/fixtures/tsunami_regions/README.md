# Official tsunami warning geometry

## NTWC Kamchatka original bulletin with observations

`ntwc_kamchatka_20250730_B12.original.json` is the unchanged official response:
https://www.tsunami.gov/events/PAAQ/2025/07/29/t06p1k/12/WEAK51/PAAQ.json

Downloaded 2026-10-22. SHA256
`bc25c5ab3e5f80ec13cc589d8c8527e230d211d8531b2ff7fdc05127f7fbc78e`.
It contains 298 station/forecast-point rows and 30 observations timed between
the source event origin and bulletin issue. Raw measurements and units are
retained. The test passes the complete detail through the Mock tsunami-model
entry; placeholder times are not presented as measurements.

## INCOIS original public bulletin

`incois_20260820_B1.original.json` is an unchanged copy of the official response
captured on 2026-10-20:
https://tsunami.incois.gov.in/itews/DSSProducts/OPR/incois2026qmbb/NTWC/B1/incois2026qmbb_B1_NTWC_Pub.json

SHA256 `2f40f91b793fed7eac5938448f0c35d9bc0b988abcf13d09dd5f57c775137c38`.
It is an information bulletin with no station observations, not an active warning.

## NMEFC original bulletin

`nmefc_20240403_B2.original.html` is the unchanged UTF-8 official bulletin:
https://obs.nmefc.cn/Warning/TsunamiAdvice/202404030758_2_file/202404030758_2.html

Fetched 2026-10-21. SHA256 `84cab39c67d530a41fa0bc7dd6116bb636cf336f8e222a4d60199b0162488750`.
Its three forecast rows use centimetres and ranges; referenced coastal/amplitude maps are JPGs.
This fixture is source evidence, not a vector geometry or a live injected warning.

`Coastal_Forecast_Point_20240403_B2.original.jpg` is the same bulletin's unchanged
official coastal forecast image, used to verify the right sidebar image display:
https://obs.nmefc.cn/Warning/TsunamiAdvice/202404030758_2_file/Coastal_Forecast_Point.jpg

SHA256 `449b84a4c70bb26abacee402b25f989cb30c624d274353793761d71569596d3c`.
It is an image attachment, not a source of vector warning boundaries.

## NOAA original geometry

`noaa_ntwc_20250918.original.kmz` is the unchanged NOAA NTWC event KMZ:

https://www.tsunami.gov/events/PAAQ/2025/09/18/t2ssp5/1/WEAK51/PAAQevent.kmz

Downloaded 2026-10-20. SHA256:
`fb78fe47cb19ba2001c3c86dbeee48d9f93533e4f1783aebfb60a7ac7295807f`

It contains the actual AK791 Western Aleutians advisory polygons and the
official `advisory` KML LineStyle color `5014A0FF` (KML aabbggrr).
Flutter renders the corresponding ARGB `50FFA014`, preserving source opacity.
The accompanying source bulletin JSON is
`../noaa_ntwc_advisory_20250918.json`.

The official map constructs event KMZ URLs in:
https://www.tsunami.gov/js/esri.js (`addWWAKML`).
Official color legend: https://www.tsunami.gov/?page=help

Tests do not rewrite the original coordinates, issue time, category or archive
bytes. Explicitly labelled protocol cases test malformed documents and color
selection; their test coordinates are not actual forecast-zone boundaries.

## CAT original CAP polygons

Downloaded unchanged on 2026-10-20 from CAT's own bulletin file listing:
https://diredimoat.semar.gob.mx/cat/rss/listado_xml.json

- `cat_20260717_alert.original.xml`:
  https://diredimoat.semar.gob.mx/cat/rss/BOLETIN_ALERTA_001_20260717_090502.xml
  SHA256 `ac11debbba5738d4018ac7271c09d77b7aa996b7d0c831420cc4ed33fba5ec09`
- `cat_20260717_followup.original.xml`:
  https://diredimoat.semar.gob.mx/cat/rss/BOLETIN_SEGUIMIENTO_003_20260717_110847.xml
  SHA256 `bb27d132dc888f67e696166c8b081ad7209c5dbfce5c1d5532bd2950af16ca34`

These actual CAP documents put WKT `POLYGON ((longitude latitude, ...))`
inside `<polygon>`. Reading them as standard CAP latitude,longitude pairs
would discard the boundaries. The Rust parser supports CAT's actual format
without rewriting the source XML or coordinates.

CAT's official frontend
https://diredimoat.semar.gob.mx/cat/js/app.js selects primary `#d71717` for
ALERTA and `#ec8210` for SEGUIMIENTO in `aplicarEstilo()`.

## INCOIS official frontend route

https://tsunami.incois.gov.in/TEWS/js/indexHome.js loads
`/itews/DSSProducts/OPR/{event}/{service}/B{report}/level2/{event}_B{report}_{service}_threatmap.geojson`
for type II/III bulletins. Features contain `BOX_NAME`, `PLACE_NAME`,
`THREAT_CAT` and actual polygon geometry. It uses red `#ff0000` for
Warning/Threat, orange `#ffa500` for Alert, yellow `#ffff00` for Watch.
NoThreat/Threatpa are not active warning outlines.

The captured type-I `incois2026qmbb` information bulletin has no threat map
(official path returned 404). INCOIS route/codec tests are therefore labelled
protocol-only; no fabricated boundary is presented as an actual INCOIS sample.

`incois_20120411_B2.original.kmz` is an unchanged actual historical warning
product, downloaded 2026-10-20 from the KMZ link in the official second bulletin:
https://tsunami.incois.gov.in/DSSProducts/Product_NTWC/Web/dss120411083800_Bulletin2_box_pub_A.html

Original KMZ:
https://tsunami.incois.gov.in/DSSProducts/Product_NTWC/SHP/dss120411083800/B2/dss120411083800_B2_pub.kmz

SHA256 `9fddba7f1eda315133e5ea854477a9b2f85b8f0b2534b063dff6438e2a3ab771`

The original KML has 55 polygon placemarks: 38 Watch, 14 Alert, 3 Warning.
Its style IDs (`PolyStyle10`, `PolyStyle121`, `PolyStyle147`) are not status
names. The original placemark name supplies the status; each LineStyle supplies
its own exact ABGR color. Point and legend placemarks are excluded.
Test coordinates, number of areas, categories and colors come from the untouched
archive. It is not the separate 2011-10-05 exercise bulletin.

## PTWC original Hawaii warning

`ptwc_hawaii_20250730.original.json` and `.original.kmz` were downloaded
unchanged on 2026-10-20:

- https://www.tsunami.gov/events/PHEB/2025/07/29/25210002/4/WEHW40/PHEB.json
  SHA256 `20188ad2fae481a5a3db755cbfcd7d15f2e3a08e63488b6cbb13d8c981e2f155`
- https://www.tsunami.gov/events/PHEB/2025/07/29/25210002/4/WEHW40/PHEBevent.kmz
  SHA256 `1d5c7c62e34f220b5cfeec61d344d9c3358c9b86c94f4291454989db5942a35d`

Original bulletin: 2025-07-30 01:51:32 UTC, report 4, Warning.
The KML uses the older Google Earth 2.0 namespace and has 39 coastal zones:
35 Warning, 4 Advisory. All 39 zones retain valid outlines (49 rings).
Of the original 82 rings, 33 contain only one/two coordinates and cannot form
polygon outlines; they are omitted without changing the source file.
The original ABGR `660000FF` and `5014A0FF` become ARGB `66FF0000` and
`50FFA014`, including their opacity.

## CWA named coastal base map

The unchanged ExpTech resource is shipped as `assets/maps/tw.tsunami.geo.json`,
with source/hash and full upstream AGPL-3.0 license beside it. It is a static
base map matching the official six region names, not an actual CWA warning
document. Tests use explicitly labelled protocol metadata to activate named
zones; no historical CWA report is altered or passed off as an active warning.
