# Early-est APP history capture

`early_est_history_20261009.original.json` is the unchanged `QuakeMessage.toMap()`
output read from the running local APP through its Dart VM service on 2026-10-09.
It contains the two rows reported in the user's screenshot, not raw upstream
packets. No timestamp, ID, coordinate, magnitude or report number was edited.

Jian report 6 carries `EARLY_event_1791522664003`, M4.9, longitude 126.08.
WHEWS report 9 carries `1791522664003`, M5.0, longitude 126.05. Both origins
are 2026-10-09 13:11:09 UTC+8, latitude 0.78 and depth 71 km. Comparison removes
only the known Jian ID prefix, leaving the event and original record unchanged.
