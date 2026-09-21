# GlobalQuake Protocol Capture

`stream_20260921.bin` is an unchanged TCP response capture from
`server.globalquake.net:38000` on 2026-09-21 after sending the application's
existing handshake. It contains handshake, station-intensity and cluster
packets, not a fabricated earthquake report. It exercises the decoded Java
object snapshot, including custom collection data. It does not validate a live
hypocenter notification.
