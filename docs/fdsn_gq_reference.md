# FDSN connection review against GlobalQuake

Reviewed 2026-09-09. This describes the native Dart connection path, not the
older optional Python relay in `fdsn_seedlink_relay.md`.

Current policy (2026-09-10): receive inactivity and observation freshness are
separate. EarthScope restarts at the live edge after an actual disconnect;
GEOFON retains sequence resume. See the final GQ/ObsPy follow-up below. Earlier
expiry-triggered reconnect descriptions are historical, not the current policy.

## Reference boundary

- Official repository: https://github.com/xspanger3770/GlobalQuake/tree/0.11.0
- Source revision: `c96985c86d5fb10c05d46054b0efc27d9cab7f53`.
- Inspected `FDSNWSDownloader`, `SeedlinkCommunicator`, `StationDatabaseManager`,
  `Station`, `Channel`, `GlobalStationManager`, and `SeedlinkNetworksReader`.
- Reference snapshot: `D:/flutterApp/_refs/GlobalQuake/source-snapshot/`.
  Git transport failed; individual original files were fetched at the fixed
  revision. This is not a completed Git clone.
- This reference is the open-source local SeedLink implementation. It is NOT a
  claim that the installed GlobalQuake 1.x client uses the same connection path.

## Findings and adaptations

| Stage | GQ 0.11.0 | Our native path after this change |
| --- | --- | --- |
| Metadata | Build channel database before streaming | Shared network-level channel catalog, warmed during discovery; exact NSLC and epoch matching |
| Availability | Retrieve INFO STREAMS and match channels to database | Complete EarthScope HTTP stream catalog; GEOFON INFO STREAMS; partial catalogs merge instead of replacing complete prior stations |
| Channel | Retain available selection; otherwise prefer lower sample rate | Retain available provider/selector across late provider discovery; keep existing motion-channel family priority |
| Provider | Choose least-assigned available SeedLink server | Global station budget, unique network.station, retain existing available provider; no fixed half-budget starvation |
| Receive | One worker per provider, route records to known station objects | One stream connection per provider; metadata waits do not block packet receipt; latest original record coalesced per NSLC while waiting |
| Count | Counts successful selection commands | Subscription ACK and receipt remain separate; linked count expires by original observation time, not arrival time or catalog size |
| Map | Separate station database from waveform processing | Remove 1200-visible-station cutoff; retain viewport culling, cached projection/text and canvas drawing |

The new channel catalog has a four-request concurrency bound. Requests for the
same provider/network share a future and failures have a one-minute cooldown.
Metadata parsing runs through `compute`; reconnecting an individual stream does
not discard the service-owned catalog.

## Verified current service interfaces

- EarthScope: https://docs.earthscope.org/service/seedlink
  - `rtserve.earthscope.org:18500` is the documented TLS endpoint, with normal
    certificate validation. GEOFON remains on its existing TCP endpoint.
  - Use one waveform connection per provider, not one per station.
- RingServer: https://github.com/EarthScope/ringserver/blob/main/doc/ringserver.md
  - `https://rtserve.earthscope.org/streams` was verified live.
  - Rows contain original stream ID, first time, last time.
  - `FDSN:1E_MONT1__H_N_Z/MSEED` preserves the blank location and channel HNZ.
  - Accept supported unlabeled miniSEED v2 streams only. Do not silently treat
    miniSEED3 or labeled streams as v2.

EarthScope INFO on the previous path returned only roughly 350 live stations
before the connection ended. Increasing the overall deadline alone did not
resolve it. The full HTTP directory returned roughly 3700 live candidates;
waveforms still come from the same provider's SeedLink service.

## Deliberate non-adaptations and remaining work

- Do not copy GQ's fallback that ignores location codes. Missing exact response
  metadata does not justify borrowing another instrument's gain or location.
- Do not copy the 24-hour catalog availability window into our live map.
  Existing three-minute live validity rules remain.
- Do not switch to GQ's single vertical channel or its motion algorithm. Existing
  channel-family subscriptions and PGA/PGV/MMI/CSIS calculations remain intact.
- The new metadata catalog is session-scoped, not GQ's persistent station
  database. Disk caching, HTTP 413 subdivision and lowest-sample-rate selection
  are not implemented by this change.
- Some official metadata owners remain unreachable or have no matching channel
  epoch. Such stations can receive records without a calculable physical value.
  No fabricated coordinates, sensitivity, timestamps or intensity are used.
- A complete catalog is not proof that every selected station is delivering
  fresh waveforms. Report selection, receipt and measured/located counts apart.
- This validation is on Windows; Android/iOS device networking was not tested.

## Reproduction

```powershell
flutter test --no-pub test/fdsn_stream_catalog_test.dart test/fdsn_channel_catalog_test.dart test/fdsn_connection_test.dart test/fdsn_processing_test.dart test/fdsn_station_layer_test.dart test/fdsn_station_service_stop_test.dart
flutter test --no-pub --dart-define=FDSN_LIVE=true --dart-define=FDSN_LIMIT=5000 --dart-define=FDSN_TICKS=20 test/fdsn_live_probe_test.dart
```

Unit tests use explicitly isolated protocol fixtures. The opt-in probe uses real
services and records raw observation times without rewriting data. Probe artifacts
are in `tmp/fdsn_connection_review/` and are not production station data.

- `before_gq_5000.json`: previous implementation, 180-second run.
- `intermediate_bulk_5000.json`: bulk metadata only; incomplete catalog issue still present.
- `intermediate_http_5000.json`: full catalog, before stable provider selection.
- `live_result_5000.json`: five-minute run after stable provider selection, with
  15-second counts and independent raw-time freshness; before the final linked
  count/map expiry correction described below.

Short live runs are sequential observations, not a fixed-waveform benchmark or
a guarantee of worldwide station availability.

## Results and acceptance gap

Both runs used the 5000-station setting and the real public services:

| At 180 seconds | Before this change | Full catalog + stable provider selection |
| --- | ---: | ---: |
| Successful subscriptions | 567 | 3868 |
| Stations with records received during run | 441 | 1950 |
| Stations with a calculated measurement during run | 357 | 1902 |
| Pending receive jobs | 373 | 0 |

**The large-station continuous-live requirement is NOT yet validated.** At 300
seconds, cumulative receipt was 2320 and measured+located was 2263, but only 25
located stations (23 measured) had an original observation within three minutes.
The old arrival-based linked counter still reported 1950. This must not be
presented as 1950 continuously fresh stations.

The final code changes linked-count expiry and map `lastMotionUpdate` to the
original observation time, rejects records that become stale while waiting for
metadata, and drains a newer queued record after an epoch lookup finishes.
A socket regression verifies that a record already 170 seconds old expires at
the next watchdog tick, instead of lasting three minutes from its arrival.
Those final expiry changes have unit coverage, not another five-minute live run.

An independent Python TLS receiver, without Dart, metadata lookup or intensity
calculation, received 1099 packets in 61 seconds using a vertical-only diagnostic
selection. Median packet arrival age increased from 14.8 to 47.5 seconds across
the sampled intervals. This is evidence that the observed delay is not exclusive
to Flutter computation, but does not establish a specific network/server cause.
The initial WSS diagnostic sent binary command frames and is not valid evidence
that the service is unavailable. The corrected follow-up is recorded below.

The remaining investigation is the end-to-end streaming backlog and channel
selection/bandwidth budget, including GQ's actual sample-rate-based selection.
Increasing the station limit, extending freshness to 24 hours, or replacing raw
observation times with local receipt times would not resolve that problem.

## Follow-up and Windows installer (2026-09-09 23:03 CST)

Windows Release and Inno Setup completed successfully without killing unrelated
Dart processes. The existing SQLite native library hash was verified before
building. Version remains 1.0.4; this request did not change the version number.

- Installer: `build/installer/FlutterRhythmQuake_v1.0.4_Setup.exe`
- Size: 28,696,677 bytes (27.37 MiB).
- SHA256: `4F9E7D1369523D4A96C8CD2D350452010171793E2169E6B6D797F04F4FAEB4AE`
- Contains the prior native FDSN fixes including observation-time expiry.
- Not installed automatically. Later diagnostics below do not change production.

### Actual sample-rate selection comparison

`tools/probe_seedlink_waveform_transport.py --gq-rate --seconds 90` fetches the
official channel metadata and intersects exact NSLC and currently valid epochs
with live stream availability. It chooses the lowest positive sample rate among
the currently supported vertical HNZ/HLZ/HHZ/BHZ/EHZ/SHZ channels per station.
This tests GQ's rate-selection principle on our supported families, not all GQ
band/instrument combinations or GQ's complete processing algorithm.

- 13,587 metadata channels; 3,632 selected stations.
- 90.9-second TLS receive interval: 1,800 packets, 979,768 bytes.
- Arrival-age medians in successive intervals: 15.3, 31.8, 49.0, 63.7, 78.3 sec.
- All 10,896 command replies parsed with no reported command error.
- This did not resolve growing arrival latency. No production selection change
  was justified by this experiment.

### WebSocket command handling

Reference: https://docs.fdsn.org/projects/seedlink/en/latest/protocol.html
(Appendix A), and https://docs.earthscope.org/service/seedlink.

- Send each command in its own text frame. The tested legacy session required
  CRLF terminators; a HELLO without CRLF timed out in the observed run.
- HELLO, STATION, SELECT, DATA, END with sequential replies returned a real
  520-byte SeedLink/miniSEED record for IU.ANMO.
- Sending many commands without draining replies closed the connection in the
  diagnostic. A 32-command window also returned ERROR and timed out. This is a
  specific observed interoperability problem, not a proven universal server limit.
- With `--wss --window 1 --limit 10 --seconds 30`, all 30 selection replies were
  successful in 12.0 seconds; all 10 stations received data, with 238 packets in
  30.5 seconds. Arrival-age medians were 6.8 and 6.2 seconds. All 10 remained fresh.
- Small-subscription success does not establish a scalable 5000-station solution.
  WSS has not been wired into production or this installer.

Next work must validate a scalable subscription/transport plan and sustained
freshness, not only count successful ACKs. These runs do not identify whether
the large-subscription backlog originates at a provider, a route, or their
interaction with the requested stream volume.

## Growth collapse and recovery audit (2026-09-10)

The user's observed collapse near 2000-3000 stations was reproduced in the
opt-in native service probe, without a map or a renderer. Keep the distinction
between subscription ACKs, currently fresh observations, and cumulative receipt.

- Baseline: `tmp/fdsn_connection_review/live_result_5000_20260910_disconnect_before.json`.
  EarthScope accepted all 3798 subscriptions. Total linked count reached 2629 at
  180 s, then fell to 2466 at 195 s, 230 at 210 s, and 168 at 225 s. EarthScope
  was still connected while its fresh observations dropped to zero. At 300 s its
  peer closed the socket, with reconnect pending; total linked count was 71.
- Recovery probe: `tmp/fdsn_connection_review/live_result_5000_20260910_disconnect_after.json`.
  Uses the same configured 5000 limit and a later live interval, not identical
  recorded input. After the collapse, EarthScope retried despite several early
  peer closes. Total linked count subsequently grew from 174 at 300 s to 254 at
  315 s, 1416 at 330 s, 2454 at 360 s, 2981 at 390 s and 3155 at 405 s.
  At 420 s EarthScope had closed again and was starting connection attempt 8;
  total linked count was 148, all from GEOFON. The completed seven-minute run
  therefore demonstrates renewed growth but also recurring connection loss,
  not stable recovery. The final snapshot does not establish whether attempt 8
  subsequently completed.

Production recovery corrections:

1. When all previously fresh observations in one connection expire, recover
   that connection without waiting another full idle timeout. Do not disconnect
   healthy providers, enlarge the three-minute freshness window, or rewrite time.
2. On this expiry or valid-data timeout, clear that connection's resume positions
   and use live `DATA`. Short peer interruptions still resume the next sequence;
   positions whose original observation is already stale are not reused.
3. A setup exception after socket assignment must detach/close that socket before
   retry, otherwise the existing-socket guard prevents the scheduled connection.
4. Detach before `destroy`: the local regression exposed synchronous `onDone`
   reentry that overwrote the close reason. This final cleanup change was made
   after the recovery probe launched; its cause labels may still say peer closed
   for a watchdog-initiated close. Recovery itself was exercised in that probe.

The test suite covers loss at 2500 of 3000 stations and subsequent recovery,
stalled resume returning to live data, expiry recovery, and unchanged-config
idempotence. The native source/display/processing regression run passed 29 tests.
This is evidence of recovery, not sustained freshness of 5000 stations or proof
of where the transport backlog originates. No installed app was restarted or
changed during these probes. No new installer was generated for these fixes.

## Repeated transport close isolation (2026-09-10)

The following probes have no Flutter runtime, waveform decoding/measurement,
map, application freshness watchdog, or automatic reconnect. They read original
miniSEED headers directly and report EOF separately from their observation limit.

| Transport | Subscriptions / OK replies | Last periodic station receipt count | Exit |
| --- | --- | --- | --- |
| TLS 18500 | 3791 / 11373 | 2891 at 153.2 s | Peer EOF at 154.8 s, 4572940 bytes, 8706 complete records |
| TCP 18000 | 3797 / 11391 | 1885 at 45.2 s | Peer EOF at 55.4 s, 2048684 bytes, 3852 complete records |

The station counts above are cumulative receipt at the last periodic snapshot,
not exact counts at EOF and not all currently fresh stations. Both runs received
no command error replies and ended with a partial record in the receive buffer.
Logs: `tmp/fdsn_connection_review/raw_disconnect_20260910.log` and
`tmp/fdsn_connection_review/raw_tcp_disconnect_20260910.log`.

This independently reproduces remote-end connection loss without our watchdog.
It does not distinguish server-originated closure from an intermediary on the
transport path. Neither a fixed 2000/3000-station cutoff nor switching to plain
TCP is supported as a solution. The production TLS endpoint remains unchanged.

The raw probe now has a diagnostic-only `--tcp` option, mutually exclusive with
`--wss`. Official endpoints: https://docs.earthscope.org/service/seedlink.
GQ's reviewed source also uses a ten-second reconnect and per-provider reader;
its existence does not establish uninterrupted service on this network.

The corrected native close-reason probe completed six minutes:
`tmp/fdsn_connection_review/live_result_5000_20260910_close_reason.json`.
At 165 s total linked was 3099 (EarthScope 2924, GEOFON 175); at 180 s
EarthScope reported `peer closed`, with reconnect pending and zero linked.
It reconnected on attempt 2, but only stale data arrived afterward: at 360 s
EarthScope had received 22432 packets cumulatively, rejected 11680 as stale,
and still had zero currently linked stations. GEOFON retained 155. There were
no native pending packet jobs or decoder rejection counts in that snapshot.

This run uses the detach-before-destroy correction, unlike the earlier recovery
probe. It confirms that successful socket reconnect alone does not restore live
data. The prior expiry recovery fixes do not yet resolve a short peer interruption
resuming into an increasingly stale backlog before the idle watchdog fires.
No further production parameter or endpoint changes were made for this audit.
Connection regressions were rerun: 15 tests passed. Python probe syntax and CLI
argument parsing were also checked.

A smaller TLS control (`--limit 100 --seconds 180`) reached its deadline without
EOF: 300 OK replies, 7284200 bytes, and 14005 records. At the last periodic
snapshot (167.4 s), 99 stations were fresh, but median arrival age had increased
from 7.3 s at the first snapshot to 80.6 s. This is not evidence of sustained
low-latency service, nor justification to lower the production station limit.
Log: `tmp/fdsn_connection_review/raw_tls_100_20260910.log`.

## GQ and ObsPy live-receiver follow-up (2026-09-10)

References checked directly:

- GQ 0.11.0 `SeedlinkNetworksReader`: each provider owns a reader, negotiates
  station selections and continuously reads records. After a real disconnect it
  creates a new reader; this path does not restore old per-station sequences.
  Its connected count is incremented on subscription acceptance, not freshness.
  https://github.com/xspanger3770/GlobalQuake/blob/0.11.0/GlobalQuakeCore/src/main/java/globalquake/core/seedlink/SeedlinkNetworksReader.java
- ObsPy `SeedLinkConnection`: network timeout timers reset on received bytes;
  resumption and requesting next available data are distinct modes. Keepalive
  is optional, not a way to turn delayed observations into current ones.
  https://docs.obspy.org/_modules/obspy/clients/seedlink/client/seedlinkconnection.html
- EarthScope supports TLS, TCP and WSS, limits clients to five concurrent
  connections, and asks for heartbeat intervals of at least four minutes.
  https://docs.earthscope.org/service/seedlink

Additional isolated transport experiments:

- TLS receive buffer 4 MiB: 3802 subscriptions, all 11406 replies OK; peer EOF at
  230.9 s. Fresh station count reached zero while bytes were still arriving.
  `tmp/fdsn_connection_review/tls_buffer4m_20260910.log`.
- TLS 96-command acknowledgement window: 3804 subscriptions; handshake took
  42.9 s, all 11412 replies OK. Peer EOF after 168.7 s of streaming. This is a
  bounded acknowledgement-window experiment, not an exact run of GQ or ObsPy.
  `tmp/fdsn_connection_review/tls_ack96_20260910.log`.
- WSS eight-command window and WSS BATCH mode closed during negotiation. BATCH
  suppresses individual ACKs, so it cannot establish accepted station counts.
  Neither experiment justifies a production WSS switch.

Production corrections following the reference audit and the user's observation
that GQ remains operational with delayed data:

1. Reset the network timeout on socket bytes, not on a fresh observation. Keep
   the existing three-minute network timeout, now independent of map freshness.
2. Recognized delayed station records demonstrate a live transport, but remain
   excluded from current station counts, measurements and map updates. Original
   timestamps and the three-minute observation window are unchanged.
3. Do not disconnect merely because every observation expired. This replaces the
   earlier expiry watchdog (including the interim resume-expiry extension tested
   during this audit). A new socket must not be used as a cure for ordinary delay.
4. EarthScope actual disconnects clear sequence cursors and request bare DATA on
   reconnect, matching GQ's live reader. This deliberately does not backfill the
   outage; raw records are neither synthesized nor timestamp-shifted. GEOFON's
   sequence-resume policy is preserved, and other healthy providers are untouched.
5. Diagnostics distinguish receive age, last fresh receipt age and close reason.
   When no fresh record has arrived, its receipt age is -1 rather than a fake
   fresh receipt time initialized by opening the socket.

The 31-test native connection/display/processing regression suite passed,
including continuous stale traffic without disconnect, freshness expiry followed
by fresh data on the same socket, true receive inactivity, live-edge reconnect,
sequence-enabled reconnect, and loss/recovery at 2500 of 3000 stations. Targeted
Flutter analysis passed. These fix client recovery semantics, not server or
network throughput; they cannot guarantee that an upstream connection never ends.

The completed six-minute live probe used the 5000 setting:
`tmp/fdsn_connection_review/live_result_5000_20260910_gq_live_policy.json`.
The full EarthScope connection accepted 3803 stations. At 300/315 s it had no
fresh stations but was still receiving bytes (receive age 2/1 s), with no local
reconnect. At 330 s the peer had closed; the next attempt also ended early.
At 360 s attempt 3 was receiving fresh records again, with 92 fresh EarthScope
stations and 41 GEOFON stations (133 total). Both receive age and last fresh
receipt age for EarthScope were 1 s. This is evidence of live-edge recovery, not
of recovered thousands or sustained low latency. The run ended shortly after
fresh receipt restarted. Actual peer closes and the transport backlog remain
unresolved. No installer was built and no installed application was changed.

## Raw timing and user-switched network control (2026-09-10)

The user changed networks. The second TLS run reused the exact ordered 100
station/selector entries saved by the first run, verified equal after completion.
Both ran for 180 seconds, without Flutter decoding, rendering or map callbacks.
No production transport, station limit, observation timestamp or expiry policy
was changed for these controls.

| Approximate elapsed time | Original network median record-start age | New network median record-start age |
| --- | --- | --- |
| 15 s | 10.6 s | 9.0 s |
| 31 s | 22.2 s | 25.2 s |
| 62 s | 47.0 s | 48.9 s |
| 124 s | 100.1 s | 91.1 s |
| 170 s | 133.4 s | 124.8 s |

The original run received 5704 records; the new run received 7160. Both ended
at their deadline, not EOF. All 100 stations were still within the existing
three-minute freshness window at completion; that count does not mean low latency.

Each audit retained unmodified miniSEED bytes and receipt timestamps for a bounded
32-channel sample. ObsPy read the record start/end times, sample counts and rates.
Mean record-end age was 138.0 seconds on the original network and 128.1 seconds
on the new one. Public `/streams` timestamps for the same NSLCs, fetched after
each run, were on average 144.3 and 135.5 seconds ahead of those received record
ends respectively. The catalogue fetch was not simultaneous with receipt; these
differences are not measurements of server-internal processing time. They show
that newer same-channel records existed while the client received older ones.

Evidence:

- `tmp/fdsn_connection_review/arrival_clock_audit_20260910.json` and `.log`
- `tmp/fdsn_connection_review/arrival_clock_new_network_20260910.json` and `.log`

A further new-network TCP/18000 control reused those same 100 selectors for
90 seconds. Median record-start age rose from 7.2 seconds at 15.1 seconds elapsed
to 40.7 seconds at 60.3 seconds and 51.4 seconds at 75.4 seconds. It received
4400 records and all 300 subscription replies were OK; it ended at its deadline
without EOF. The bounded 32-channel audit had median record-end age 62.1 seconds.
This does not support switching production from TLS to plain TCP as a fix.
Evidence: `tmp/fdsn_connection_review/arrival_clock_new_network_tcp_20260910.json`
and its `.log`.

Other independent controls on the preceding network also developed increasing
latency: 100 stations over serial-command WSS, and 100 stations using the official
EarthScope Python `seedlink-client` 0.2.0 with v4/TLS. The latter's final connection
reset occurred near the user's network switch, so it is not evidence of an
independent server disconnect. Its increasing latency before the switch remains
observable. Selecting only the lowest-rate vertical channel for each station
also failed to sustain freshness in the separate 3764-station control; this does
not justify removing production waveform components.

The network change did not eliminate the accumulation. This does not prove a
particular server, carrier or local networking component is responsible. It does
establish that Flutter UI/decoder changes alone cannot resolve the backlog seen
by these independent raw receivers. A stable delivery solution remains unverified.

References: https://docs.earthscope.org/service/seedlink and
https://github.com/EarthScope/seedlink-client.

## Station zoom stability and rendering (2026-09-10)

Connection investigation was paused at the user's request. This change is
limited to `fdsn_station_layer.dart` and its rendering tests:

- Retained drawing bounds now use the same fractional pixel origin as the map,
  rather than the camera's floored pixel bounds. A stationary zoom anchor has
  identical rendered pixels across tested fractional zooms, including zoom 18.913.
- Longitude wrapping draws all visible world copies. The old nearest-copy
  selection failed the independent pixel-position test at overview zooms.
- Intensity ordering uses stable buckets, keeping stronger stations on top.
- A small device-density-aware atlas caches the existing circles, borders and
  numeric labels. Each viewport picture submits visible station sprites in one
  `drawRawAtlas` call. Zoom does not rebuild the atlas; there is no station cap,
  clustering, change to measurements, or suppression of low-level stations.
- Timestamp-only updates reuse prepared glyphs and reschedule actual observation
  expiry. Offscreen visual updates do not invalidate visible pixels. Atlas images
  are disposed on replacement, layer removal or empty active input.

The same 5000-station widget workload measured 15.391 ms per zoom pump before
the change and 4.132 ms in the final isolated run. These are test-engine timings,
not installed-app FPS or GPU benchmarks. Timestamp-update workload was 29.073 ms
including synthetic test input construction and the entire pump; instrumentation
inside layer preparation measured 2.230 ms per update. It did not repaint.
Logs: `tmp/fdsn_review/zoom_before.log`, `zoom_final.log`.

Rendering, processing, connection and station-stop tests passed (33 tests).
Pixel checks cover world copies, the stationary zoom anchor, cached versus fresh
viewports, rotation, expiry, density changes (1, 1.25, 2, 3), MMI/CSIS and two-digit
markers. The 5000-station zoom workload verifies one atlas build across 60 camera
updates. Desktop/mobile-sized MMI/CSIS snapshots were visually inspected.
No installed app or installer was updated as part of this rendering change.

## Peer-close investigation and primary references (2026-09-10)

Scope: prevent the unexpected connection closure itself. Reconnect recovery,
station expiry and map rendering are not fixes for this investigation.

A standalone TLS/18500 receiver subscribed to 3809 stations with the existing
three-component family selectors. All 11427 command responses were received,
with no command errors. The receiver has no reconnect loop. It received
5352086 application bytes / 10204 complete records, covering 2956 stations,
before peer EOF at 266.6 seconds, before its 480-second deadline.

New read-only Windows SIO_TCP_INFO instrumentation sampled the same socket:

- State was ESTABLISHED (4) during transfer and CLOSE_WAIT (7) after EOF,
  before local cleanup. This supports peer-initiated TCP closure; it does not
  identify which remote service component requested closure or why.
- The longest observed receive gap was 2.780 seconds. The last successful
  receive preceded EOF by 0.003 seconds. This was not an application-side
  three-minute no-data watchdog expiration.
- Sampled receive windows were nonzero, mostly 65535 bytes; the final value
  was 65535. Sampling does not exclude transient window changes between reads.
- Local retransmission / timeout counters remained zero. Those counters do
  not establish absence of remote retransmissions or network path loss.
- Strict TLS EOF handling (`suppress_ragged_eofs=False`) returned empty bytes,
  not SSLEOFError. This is consistent with an orderly TLS EOF, not evidence
  that the SeedLink application successfully completed its data stream.

Evidence: `tmp/fdsn_connection_review/close_tcp_info_20260910.log` and
`close_tcp_info_20260910.json`. Raw miniSEED audit records are preserved unchanged.

Primary sources checked:

- https://docs.earthscope.org/service/seedlink : five concurrent connections
  maximum, keepalive no more frequently than four minutes, and selection of
  many channels over one connection. No published 2000/3000-station cutoff.
- https://github.com/EarthScope/ringserver/blob/main/doc/ring.conf : separate
  ClientTimeout and NetIOTimeout settings. The example network I/O timeout is
  ten seconds; this is NOT confirmation of the deployed service setting.
- https://raw.githubusercontent.com/EarthScope/ringserver/v4.5.6/src/clients.c :
  SendDataMB returns a fatal error when TLS or TCP send polling times out;
  the client loop closes on fatal stream errors. This is a concrete candidate
  closure mechanism, not a proven diagnosis for the captured connection.
- https://docs.obspy.org/_modules/obspy/clients/seedlink/client/seedlinkconnection.html :
  timeout/keepalive/reconnect facilities do not promise to prevent peer closure.
- https://learn.microsoft.com/en-us/windows/win32/api/mstcpip/ne-mstcpip-tcpstate :
  TCPSTATE enumeration used to interpret the captured socket state.
- https://docs.python.org/3/library/ssl.html : strict unexpected-EOF handling.

The independent raw receiver reproduces closure without Flutter rendering or
waveform decoding. Server send failure versus other upstream closure still
requires discrimination; a client EOF and CLOSE_WAIT do not expose the remote
reason. No production timeout, heartbeat, component selection or reconnect
settings were changed on the basis of these hypotheses.

### Controlled follow-up: preconnect window and INFO response

RFC 7323 specifies that window scaling is negotiated when TCP opens. The earlier
post-connect SO_RCVBUF experiment did not test that negotiation. A diagnostic
option now sets SO_RCVBUF before connect, with tests verifying call order, socket
cleanup and unchanged default behavior. It is not a production setting.

The frozen 3809-station selection from the preceding audit was reused unchanged:

| Test | Outcome |
| --- | --- |
| TLS, preconnect 4 MiB, resolved ingress 18.190.248.70 | Windows 10054 reset at 373.3 s, 3861004 application bytes, 7337 records, 2666 stations seen |
| TLS, preconnect 4 MiB, resolved ingress 3.146.240.204 | Windows 10054 reset at 377.0 s, 4079212 application bytes, 7756 records, 2727 stations seen |
| TLS, default buffer, first ingress, one INFO ID after 60 s | Request sent at 61.431 s; reset at 61.7 s without an INFO response |
| TLS, same ingress/query, first 100 stations | 180.1 s deadline reached without disconnect; no INFO packet received by that deadline |
| TLS, same ingress, first 5 stations, one INFO ID after 30 s | INFO packet received 0.448 s after request; transfer continued |

Both full preconnect-buffer tests received all 11427 subscription responses
without command errors. TCP_INFO verified an effective receive window near
4 MiB, including before closure. Increasing the preconnect buffer did not
prevent the failure. The different ingress test first hit the diagnostic's
3-second subscription write timeout; that failed handshake is preserved
separately and is NOT counted as a peer-close result. Its completed retry used
a 12-second handshake write timeout, retaining the 3-second receive polling
timeout and the same selectors. Sequential tests and overlapping network load
do not provide a controlled throughput comparison; no throughput claim is made.

The selected ingress addresses were verified against the official hostname's
current DNS answers. TLS SNI and certificate verification retained the official
hostname. DNS also returned an elb.us-east-2.amazonaws.com CNAME. No production
IP pinning, DNS override, proxy or route change was made.

The INFO experiment uses a single legal query, not periodic keepalives. The
small control confirms a valid response can be received with this implementation.
The large transfer resetting immediately after a write is consistent with an
upstream connection already being invalid while buffered data is still arriving.
This remains an inference: socket counters do not identify which endpoint or
intermediary generated the reset, nor prove a specific server timeout. Packet
capture / service-side logs are still needed to distinguish these causes.

Evidence logs and matching original-record audits under
`tmp/fdsn_connection_review/`:

- `close_preconnect4m_20260910`
- `close_preconnect4m_other_ingress_20260910` (failed handshake, log only)
- `close_preconnect4m_other_ingress_handshake12_20260910`
- `close_info_challenge_20260910`
- `close_info_control100_20260910`
- `close_info_control5_20260910`

Additional references:
https://www.rfc-editor.org/rfc/rfc7323.html#section-2.1 and
https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-troubleshooting.html .
AWS's reset explanations are possible mechanisms, not confirmation of the
EarthScope deployment's timeout values or target health.

## Original GQ backend and frozen full-selection comparison (2026-09-10)

This run builds the open-source `GlobalQuakeServer` at commit
`c96985c86d5fb10c05d46054b0efc27d9cab7f53`, using the repository's bundled
`seisFile-2.1.0-SNAPSHOT` dependency. It is not the installed GQ client's
connection to the remote GQ server on port 38000.

`tools/GqBackendConnectionProbe.java` instantiates the original backend and runs
its unmodified `SeedlinkNetworksReader`. The diagnostic consumer overrides only
`GlobalStation.addRecord` to count original miniSEED records and end times.
It does not run a map, waveform analysis or source estimation. The reference
handshake remains synchronous STATION, SELECT and DATA acknowledgements per
station; END and waveform reading happen only after the entire loop.

`tools/prepare_gq_connection_comparison.py` matched the previous 3809-station
selection to original official channel metadata. 3751 stations had matching
valid numeric metadata; 58 are explicitly listed as missing, not fabricated.
The frozen input is `tmp/fdsn_connection_review/gq_equal_family_20260910.json`.
It preserves every selected network/station/family selector and the original
metadata row. The equal-family GQ configuration is deliberately a controlled
input, not GQ's usual automatic single-channel selection policy.

Completed same-input runs (all 3751 stations, 11253 OK replies for raw probes):

| Receiver | Transfer observation | Received records | End reason |
| --- | ---: | ---: | --- |
| Independent TCP/18000 | 117.5 seconds | 2566, 1464 distinct stations | peer EOF |
| Independent TLS/18500 | 255.7 seconds | 9515, 2933 distinct stations | peer EOF |
| Actual Dart receiver, TLS/18500 | 297.812 seconds including setup | 7768 parsed packets | peer closed, attempt 1 |

Dart published 2072 distinct stations before observations aged out. That number
is NOT equivalent to the independent raw receivers' all-age station count.
Its final queue was empty and no decode rejection was recorded. The opt-in
`test/fdsn_equal_selection_live_test.dart` stops at the first observed close,
before the existing 10-second reconnect. A testing-only exact-stream entrypoint
bypasses UI station-limit rounding and discovery refresh; socket, decoder,
freshness and close handling remain the actual production implementation.

The first attempted Dart run used the normal connect entrypoint, which rounded
3751 to the supported 4000 limit and started discovery. It was stopped and is
excluded from the equal-input comparison; the retained log is
`full_equal_dart_20260910.log`. Only `full_equal_dart_frozen_20260910` is valid.

Raw evidence is under `tmp/fdsn_connection_review/`:

- `full_equal_tcp_20260910.log` and `.json`
- `full_equal_tls_20260910.log` and `.json`
- `full_equal_dart_frozen_20260910.log` and `.json`
- `gq_backend_equal_20260910.log`, with final result in its same-named directory
- `full_equal_wss_20260910.log` and, on completion, `.json`

The first GQ and serial-command WSS runs were interrupted during subscription
by a local network transition at 07:33:34 UTC. Windows WLAN-AutoConfig event
8003 at 15:33:34.166 local time records WLAN 2 disconnecting. GQ logged
`Connection reset`; WSS's underlying exception was WinError 10053. GQ's last
periodic sample showed 2428 acknowledgements and zero records. Neither run
reached END/data transfer. These are NOT independent EarthScope streaming
disconnect controls and not full transfer successes.

The user confirmed that the new USB sharing network could remain connected.
The same input was restarted in `gq_backend_equal_usb_20260910` and
`full_equal_wss_usb_20260910`, alongside `full_equal_tls_usb_20260910` as a
same-input transport control. Final results must be checked before reporting
either long-handshake run as a full transfer success.

Completed USB-network controls, still using the identical 3751 selectors:

| Receiver | Observation | Records/packets | End reason |
| --- | ---: | ---: | --- |
| Independent TCP/18000 | 95.5 seconds | 2627 records, 1527 raw stations | peer EOF |
| Independent TLS/18500 | 250.2 seconds | 9751 records, 2945 raw stations | peer EOF |
| Actual Dart receiver, TLS/18500 | 276.163 seconds including setup | 9435 parsed packets | peer closed, attempt 1 |

Dart published 2298 distinct stations before aging out. TCP closed while its
1527 observed stations were still fresh, without Flutter, station-expiry logic
or a reconnect timer. The USB controls therefore reproduce remote EOF without
the preceding WLAN-disconnect interruption. Neither transport was promoted to
production as a fix. Logs/audits use `full_equal_tcp_usb_20260910`,
`full_equal_tls_usb_20260910`, and `full_equal_dart_usb_20260910` prefixes.

### Targeted packet capture

An administrator PktMon capture ran from 06:39:46.957 to 06:59:20.414 UTC,
restricted to the two addresses currently returned by official DNS and TCP
ports 18000, 18500 and 443. It used 128-byte snapshots and a bounded circular
file. The capture was confirmed idle with no filters beforehand; all six added
filters were removed after stopping. No unrelated capture was interrupted.

For raw TCP local port 59667, the trace contains a server-to-client FIN/PSH/ACK
at 06:55:56.034387 UTC followed by the client's FIN at 06:55:57.301225 UTC.
This is direct evidence of remote-first closure for that flow. It does not
identify which upstream component initiated the close or its internal reason.
The TLS flow's logged EOF is separate evidence; its captured header subset
must not be interpreted as a complete TLS close-notify transcript.

`tools/analyze_seedlink_capture.py` decodes native WLAN and Ethernet frames
using dpkt in an isolated temporary dependency directory. Its window fields
are unscaled, and capture bytes can include retry/coalescing effects. It does
not claim packet loss, server timeout configuration or absence of all network
stalls from incomplete snapshots. Capture artifacts:
`comparison_capture_20260910.etl`, `.pcapng`, `.summary.json` and `.log`.

A second capture, `comparison_gq_wss_capture_20260910`, ran from 07:13:06.007
to 07:34:24.787 UTC and was stopped after the network transition. It contains
no FIN/RST for the old GQ/WSS flows before WLAN capture ceases, consistent with
the separately recorded local link loss. Its six filters were removed too.
The USB repeat uses a separate bounded capture, `comparison_usb_capture_20260910`.

The USB capture stopped at 08:01:05.626 UTC. Its TLS flow on local port 60511
contains a server-to-client FIN at 07:41:40.616493 UTC, corroborating the
250.2-second raw TLS EOF independently of application timers.

At 07:59:46 UTC both long-handshake USB probes again failed together. The
system logged a network disconnect at 07:59:47.020 UTC and WLAN association
at 07:59:47.460 UTC. On inspection, the RNDIS interface had lost
192.168.66.2 and held only 169.254.76.63, while WLAN had 10.253.233.127 and
the only IPv4 default route. GQ's last periodic snapshot was 1686 accepted
stations, zero records. WSS again reported underlying WinError 10053.
These second long-handshake failures remain network-transition interrupted,
not full-stream server-close evidence. This does not invalidate the earlier
USB TCP/TLS/Dart EOF controls, which finished before this transition.

An additional explicitly experimental GQ topology is logged under
`gq_backend_three_20260910`: the original backend/reader handles three source
objects for EarthScope, with the frozen 3751 stations partitioned round-robin
as 1251/1250/1250, no duplicates or station removal. This is NOT GQ's default
single-provider topology. The experiment stops on the first failed source,
before reconnect, or after its observation deadline. Its capture prefix is
`comparison_gq_three_capture_20260910`.

The three-connection experiment completed at 08:23:18.119 UTC with reason
`backend-disconnected`, 66802 original miniSEED records and 2139 observed
stations. Source 2 finished all 1250 subscriptions and began receiving data;
source 0 then finished its 1251 subscriptions and also began receiving data.
Source 1's last periodic snapshot was 1115/1250 acknowledgements, still in
handshake. Thus the complete 3751-station transfer was NOT established.
Source 0 reported the first failure (`null` exception message). The harness
then intentionally stopped sources 1 and 2 before reconnect; their subsequent
`Socket closed`/interrupted logs are not independent peer failures.

After the first administrator prompt was cancelled, the user requested it
again. The targeted capture started at 08:13:50.251 UTC without restarting
the GQ experiment and ended at 08:24:11.005 UTC. The probe's three sockets
used local ports 49711/49712/49713 to 18.190.248.70:18000. Port 49713 has a
server-to-client FIN/PSH/ACK at 08:23:17.893367 UTC, before the backend's
first failure log. Port 49712 has a later client-to-server FIN at
08:23:18.476895 UTC, consistent with the harness shutdown. This establishes
remote-first closure of a GQ probe socket, not the upstream internal cause.
There was no NetworkProfile disconnect event in the inspected failure window;
event 4004 at 08:21:20 UTC reported a tethering-operation-state change with
the network-connectivity-change flag false. This event alone is not proof
that the network had no transient impairment.

The capture transcript records stop completion and successful removal of the
six temporary filters. No probe/capture helper process remained afterward.
The non-elevated follow-up `pktmon status` was denied access, so this is
cleanup evidence from the elevated transcript, not an independent status
query. Raw evidence: `gq_backend_three_20260910/result.json` and
`comparison_gq_three_capture_20260910.pcapng`, `.summary.json`, `.log`.
No three-connection production change was made based on this failed trial.

The built backend's `SeedlinkReader.class` is byte-identical to the reference
repository's bundled dependency. SHA256:
`ef370e520f8e6f2f1e0cf3c9a7ae90a7dd2ba45d9d103048d955bb363528800f`.

Production transport, component selection and reconnect policy were not changed
as a result of these failed controls. A durable connection fix is not yet
validated. Regression checks: 17 connection tests passed; the opt-in live test
was skipped in the offline suite. Five diagnostic socket helper tests passed,
and analysis of the receiver and new test reported no issues.
