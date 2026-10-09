Original response from the website's public `heartbeat_stations` table, fetched
2026-10-08T04:31:41.511832+00:00 with the exact five-field select used by the page.

Source: https://lridvfywjpugfskukqif.supabase.co/rest/v1/heartbeat_stations

SHA-256: `2dc80d88f8c28c223e3df68273ae8db2ae4358f9c5a4cb8422b623f8a2c581c5`

One actual row: amozoc. This is an HTTP cache response, not a captured Socket.IO
heartbeat or a current observation of intensity. Tests never change its source
time, coordinates, identifier, or any other source field. Server test fixture
`test_fixtures/sasmex_stations_20261008.original.json` contains the same bytes.

`sasmex_station_relay_20261008.original.json` is the unmodified initial WS text
received from our deployed `wss://ws.yuelinrhythm.top/sasmex-station` on
2026-10-08T04:49 UTC. It contains canonical station fields and the exact source
row in `sourcePayload`. Service health/time are relay metadata, not station
observation timestamps. Offline tests replay this capture only.
