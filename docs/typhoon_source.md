# Typhoon Source

The map and Android foreground service use the same `TyphoonService`.
As of 2026-09-21 it fetches Zhejiang's public website endpoints, following KA
commit `8748cf7abc82b7d172b42ec0ef616a9116de95a1`:

- https://typhoon.slt.zj.gov.cn/Api/TyhoonActivity
- https://typhoon.slt.zj.gov.cn/Api/TyphoonInfo/{tfid}

These are website endpoints, not an API with a verified availability guarantee.
Requests include a timestamp query parameter and currently require no key.

## Refresh and Lifecycle

- Read the activity list, deduplicate IDs, then fetch each detail.
- Poll five minutes after successful completion; retry after 30 seconds on
  activity/detail failure. The service no longer relies on FAN notifications.
- Failed activity requests preserve the in-memory snapshot. An explicitly empty
  activity list removes all current typhoons.
- Failed details retain previous data only for IDs still in the activity list.
  Inactive detail records are excluded from the active snapshot.
- Stop/restart invalidates old in-flight callbacks and timers.
- The new single-entry cache contains original decoded detail objects and a
  fetch timestamp. It is usable for one hour; legacy FAN cache is not read.
  Partial failures and empty activity snapshots clear the persisted cache, so
  retained details never acquire a new cache age and removed IDs do not return.

## Presentation

The current Chinese forecast preference and map appearance remain unchanged.
All returned agency forecasts remain in the model. Change detection includes
forecast paths and wind radii, not just the latest observed position.
Wind radius order is NE, SE, NW, SW upstream and NE, SE, SW, NW on the map.
Zero radii preserve quadrant positions; malformed radius sets are not rendered.
Original raw observations are not changed to manufacture missing information.

Regression capture provenance: `test/fixtures/typhoon/README.md`.
