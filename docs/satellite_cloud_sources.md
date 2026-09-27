# Satellite Cloud Sources

Verified on 2026-09-22. Both new overlays default to off; existing FAN overlay
preferences are unchanged. The desktop and weather-only settings share the same
switches and persist `map_overlay_jmaSatelliteCloudLayer` and
`map_overlay_nsmcSatelliteCloudLayer`.

## JMA Himawari Infrared

- Official implementation: https://www.jma.go.jp/bosai/map.html
- Times: https://www.jma.go.jp/bosai/himawari/data/satimg/targetTimes_fd.json
- Product: full disk `fd`, infrared `B13/TBB`.
- Tile path: `/bosai/himawari/data/satimg/{basetime}/fd/{validtime}/B13/TBB/{z}/{x}/{y}.jpg`.
- Official map code uses native zooms 3-5 for `fd`; zoom 6 is a separate Japan
  product and is not requested by this layer. Zooms 3, 4 and 5 were verified
  against actual JPEG responses, not inferred from radar zoom rules.
- Times are UTC. Select the maximum valid observation, not the last list item.
- Poll every 10 minutes while enabled. Unchanged frames do not rebuild the layer.

## NSMC Global Infrared Mosaic

- Official documentation: https://www.nsmc.org.cn/nsmc/cn/image/wms.html
- Capabilities: https://data.nsmc.org.cn/NSMCAPI/v1/nsmc/image/wms/ability?request=GetCapabilities
- Times: https://data.nsmc.org.cn/nsmcapi/v1/nsmc/image/animation/datatime/mongodb?dataCode=GEO_MULT_GBAL_L2_GGM_IRX_GLL_YYYYMMDD_HHmm_4000M.PNG&hourRange=24
- Images: `https://data.nsmc.org.cn/NSMCAPI/v1/nsmc/image/wms/compose`.
- Layer: `GEOS_IRX`, the global hourly geostationary 10.8-micrometer infrared
  mosaic. This is not labelled as a single FY-4B satellite image.
- Parameters follow the official example: lowercase query keys,
  `request=GetMap`, `version=1.1.0`, `format=png`, UTC `datetime=YYYYMMDDhhmm`.
- Actual response to a 2048x1024 request was a decodable RGBA PNG despite an
  `image/jpeg` HTTP header. Cloud intensity is represented by alpha; JPG loses
  that information. Decode PNG bytes and retain their source opacity.
- Capabilities advertise EPSG:4326, not Web Mercator. Request longitudes -180 to
  180 and latitudes -85.0511287798066 to 85.0511287798066, then reproject rows to a
  2048x2048 EPSG:3857 image in `compute`, away from the UI isolate. Nearest source
  RGBA samples are retained without recoloring or opacity reconstruction.
- Poll the list every 30 minutes while enabled. Download and project an image
  only when the source reports a newer time. Keep the previous valid frame on
  failure. A cleared/stopped session cannot publish an in-flight response.
- The live capabilities document reports no fees or access restrictions, and
  these test requests required no credentials. Availability may change.

The NMC FY-4B presentation image at
https://m.nmc.cn/publish/satellite/fy4b-visible.htm was reachable but includes
labels and a basemap without verified georeferencing metadata. It is not stretched
onto the application map. The georeferenced NSMC WMS product is used instead.

## Verification

Run `flutter test --no-pub test/jma_satellite_cloud_service_test.dart
test/nsmc_satellite_cloud_service_test.dart test/satellite_cloud_settings_test.dart`.
For the optional real-image projection and service test, set
`NSMC_CLOUD_TEST_IMAGE` to an unmodified 2048x1024 PNG response from the above WMS
request. The test writes its projected output to `build/satellite-cloud-qa/` and
checks sampled RGBA values against the corresponding original rows.

Android uses the existing foreground-service snapshot channel. Cloud toggles
target only these two image services, without reconnecting earthquake APIs.
Resuming the UI requests cached frames rather than waiting for the next satellite
observation. Actual device IPC and background operation still require device
verification.
