# Multi-provider FDSN stations

Updated 2026-10-03. This supplements the historical experiments in
`fdsn_gq_reference.md`; it does not establish a fix for upstream stream stalls.

## Sources

| Source | SeedLink | Station/channel metadata |
| --- | --- | --- |
| EarthScope | TLS `rtserve.earthscope.org:18500` | `https://service.earthscope.org/fdsnws/station/1/query` |
| GEOFON | TCP `geofon.gfz.de:18000` | `https://geofon.gfz-potsdam.de/fdsnws/station/1/query` plus existing EIDA owner routing |
| GeoNet | TCP `link.geonet.org.nz:18000` | `https://service.geonet.org.nz/fdsnws/station/1/query` |
| RESIF | TCP `rtserve.resif.fr:18000` | `https://ws.resif.fr/fdsnws/station/1/query` |
| IPGP | TCP `rtserver.ipgp.fr:18000` | `https://ws.ipgp.fr/fdsnws/station/1/query` |
| ORFEUS | TCP `eida.orfeus-eu.org:18000` | `https://www.orfeus-eu.org/fdsnws/station/1/query` |
| BGR | TCP `eida.bgr.de:18000` | `https://eida.bgr.de/fdsnws/station/1/query` |

The registry is `lib/services/sources/fdsn_source_catalog.dart`.
Native and Android background capture share this registry. Web retains its
existing unsupported direct-SeedLink stub; this is not a browser TCP gateway.

References verified during implementation:

- https://docs.earthscope.org/service/seedlink
- https://www.geonet.org.nz/data/access/FDSN
- https://seismology.epos-france.fr/real-time-seedlink/
- https://ws.resif.fr/fdsnws/station/1/
- https://github.com/xspanger3770/GlobalQuake/blob/0.11.0/GlobalQuakeCore/src/main/java/globalquake/core/database/StationDatabase.java

## Ownership and lifecycle

- Identity is `network.station`. Identical station names on different networks
  remain separate. Different channels/locations of the same station do not
  cause cross-provider duplicate subscriptions.
- Only enabled providers participate. Fresh supported motion streams in their
  complete catalogues are considered before applying the existing total limit.
- IPGP/BGR take precedence over regional aggregators. GeoNet/RESIF/ORFEUS take
  precedence over GEOFON; all six take precedence over
  EarthScope. EarthScope supplies only stations absent from these available
  regional catalogues. There is **no EarthScope-specific station cap**.
- Each provider uses one waveform connection, plus its bounded discovery query.
  This is not multiple connections to the same EarthScope server.
- Regional discovery can start streams independently; EarthScope bulk expansion
  waits for the regional discovery attempts. Refreshes apply one combined
  selection rather than repeatedly restarting healthy connections.
- A provider losing all selections has its old socket stopped. Connection
  identity includes both host and port. Stops invalidate pending work.
- An empty completed discovery clears its previous catalogue. Expired cached
  catalogues are discarded when a refresh fails. Metadata requests are warmed
  only for selected networks.
- Channel sensitivity/coordinates still require exact original NSLC and epoch
  matches. No metadata source is silently relabeled as EarthScope. Raw timestamps,
  waveform processing and the three-minute observation freshness rule are unchanged.
- A single map layer deduplicates fresh cached observations during handover.
  Android station payloads preserve the actual provider name.

## Settings

Seven independent source controls are under the existing FDSN station settings.
Existing EarthScope/GEOFON preferences are preserved. On first migration,
Additional providers inherit whether either old provider was enabled; the new values
are persisted once. Explicitly disabled values are never overwritten. The
FDSN API master switch and the existing total station limit are unchanged.
Exception: ORFEUS is opt-in/default-off because direct Dart metadata requests
returned HTTP 403 from this environment. PowerShell metadata success used the
machine's existing system proxy and is not proof of native direct availability.
No global proxy settings are changed. Its SeedLink transport remains available.

## Verification and limitations

Read-only discovery returned 488 GeoNet station entries and 480 RESIF entries
during the initial probe. These are directory counts, not counts of fresh
calculated stations. Both providers returned SeedLink HELLO and official
channel metadata HTTP 200. Raw discovery XML is retained under the ignored
`tmp/fdsn_multisource_20261003/` directory.

The initial 420-second real-service run (1000 total selections) used four
providers, received 996 distinct source/station observations cumulatively and
calculated values for 967. Its final fresh linked count was only 253. EarthScope
had a peer close and reconnect; GeoNet and RESIF still received bytes but their
observations had become stale. Thus multi-provider operation is confirmed,
**not sustained low-latency delivery or a resolved disconnection cause**.
This run preceded the final incremental regional startup and selected-only
metadata warmup changes. The final-code probe separately asserts unique
station ownership and no EarthScope overlap with regional catalogues.

The final-code 180-second probe completed at 05:30:34 UTC:

| Source | Selected and acknowledged | Fresh linked at completion |
| --- | ---: | ---: |
| EarthScope | 258 | 249 |
| GEOFON | 228 | 228 |
| GeoNet | 257 | 257 |
| RESIF | 257 | 254 |

All 1000 selected identities were unique; EarthScope overlap with the discovered
regional station set was zero. All four final connections were open, with no
peer close recorded on those connections. The 988 fresh linked observations
use the existing three-minute freshness window, not a claim of zero latency.
Earlier incremental selections account for cumulative receipt exceeding 1000;
only the final simultaneous subscription total is used in this table.
This shorter follow-up does not invalidate the longer run's remaining risks.

The combined regression suite passed 55 tests; the focused multi-source suite
also passed all 11 tests with `RQ_EDITION=public`. Static analysis reported no
errors or warnings (existing style-only infos remain in map/background code).

Evidence files (ignored runtime output, not application input):

- `tmp/fdsn_connection_review/live_result_1000_multisource_20261003.json`
- `tmp/fdsn_connection_review/live_result_1000_multisource_final_20261003.json`
- `tmp/fdsn_multisource_20261003/final_live.log`

Focused regression tests cover ownership, no per-source cap, source disable,
preference migration, correct metadata routing, Android payload roundtrip,
map handover, same-host/different-port sockets and empty-owner cleanup.
The existing miniSEED codec, rendering and connection tests remain in use.
No Android device soak test or release installer build is part of this change.

## Keepalive and live recovery (2026-10-03)

- Send `INFO ID` after four minutes with no inbound bytes, after subscription
  acknowledgements complete. Never send more than once per four minutes on a
  connection object, including across reconnects. EarthScope publishes this
  minimum interval. The no-byte timeout is five minutes so keepalive can run.
- Parse 520-byte `SLINFO *` / `SLINFO  ` frames separately, including fragmented
  and coalesced frames. Their contents are never scanned as waveform headers
  or used to refresh observation timestamps. Servers that keep sending waveforms
  but do not answer INFO are not disconnected just for that missing reply.
- A connection gets two minutes of startup grace. If at least 80% of stations
  with observations received in the last minute have no observation inside the
  existing three-minute freshness window, sustain that condition for one minute
  before attempting live recovery. Count stations, not their packet rates.
- Recovery clears resume sequence/time cursors and requests bare `DATA`. It can
  leave a real waveform gap: no missing samples or history frames are fabricated.
  This is a bounded attempt to abandon a backlog, not proof that the server has
  current data. If upstream observations are old it cannot make them current.
- Live recovery cooldown grows 5, 10, 20, 30 minutes and resets only after five
  minutes of broadly healthy observations. Ordinary failed reconnects back off
  from 10 seconds to five minutes until valid observations return.
- No raw data/timestamps, sensitivity formula, observation freshness threshold,
  or EarthScope-specific subscription limit is changed. Transport diagnostics
  expose heartbeat counts, live recovery counts and next allowed recovery time.
- Per-station provider ownership still comes from catalogue discovery, not a
  new simultaneous duplicate subscription or automatic latency race.
- IPGP/ORFEUS/BGR negotiate BATCH before bulk subscriptions. If refused, wait
  for each modifier acknowledgement before sending the next command. In BATCH
  mode there are no per-station acknowledgements; diagnostics count acceptance
  only when a selected station actually delivers a parsed waveform record.
  BGR/ORFEUS relay metadata can use the same official EIDA ownership routing
  already used for GEOFON, retaining original NSLC, epoch and source identity.

### Reference implementation comparison

- ObsPy `SeedLinkConnection` (published 1.5.1 docs): keepalive is configurable
  and disabled by default; idle keepalive uses `INFO ID`. It distinguishes INFO
  from data and supports state-file sequence/time resume. Network timeout is
  about missing traffic, not a guarantee of low observation latency.
  https://docs.obspy.org/_modules/obspy/clients/seedlink/client/seedlinkconnection.html
- Current EarthScope libslink: separate keepalive, network/I/O timeout and resume
  configuration. Its v3 negotiation sends a saved sequence plus one when resume
  is enabled, otherwise a live DATA request. Borrow protocol handling, not an
  assumption that an archival resume policy suits a realtime map.
  https://github.com/EarthScope/libslink/blob/main/slutils.c
  https://github.com/EarthScope/libslink/blob/main/network.c
- GlobalQuake 0.11.0 open-source reader: one task per server, 90-second reader
  timeout, fresh reader/selection on reconnect and retry delay starting at ten
  seconds with doubling on failures. Current GlobalQuake's documented client
  connects to its own primary/backup servers. The old code cannot establish
  the current proprietary backend's exact recovery policy.
  https://github.com/xspanger3770/GlobalQuake/blob/0.11.0/GlobalQuakeCore/src/main/java/globalquake/core/seedlink/SeedlinkNetworksReader.java
  https://globalquake.net/guide/configuration/properties-files
- Current SeisComP RecordStream: explicit timeout/retry controls, SeedLink 3/4
  transports, routing/balancing over multiple streams, and distinct combined
  archive/realtime access. No documentation claim that keepalive cures backlog.
  https://www.seiscomp.de/doc/apps/global_recordstream.html
  https://docs.gempa.de/seiscomp/current/apps/seedlink.html

Additional provider documentation:

- https://geoscope.ipgp.fr/index.php/en/data/continuous-data/description
- https://www.orfeus-eu.org/data/odc/realtime/
- https://eida.bgr.de/eida/

### Verification of this follow-up

- 70 focused regressions passed, including the existing codec, metadata,
  desktop/mobile map-layer and Android payload tests. Public-edition health and
  multi-source suites passed 26 tests. Analysis of touched Dart files found no
  issues; `git diff --check` passed. No release installers were built.
- The first 480-second probe (before BATCH compatibility was added) reproduced
  sustained lag on EarthScope, GeoNet and RESIF. Each performed one live reset;
  by completion they again had 156/155/154 fresh stations respectively and last
  valid receipt ages of 2/2/0 seconds. IPGP/ORFEUS/BGR handshake stalls in this
  run are not counted as successful provider verification.
- The subsequent BATCH-enabled 300-second probe, 07:09:16-07:14:16 UTC, received
  and decoded waveforms from all seven sources and explicitly required real
  calibrated measurements from IPGP and BGR. The final selection was 1000
  distinct network/station identities, with zero EarthScope/regional overlap:
  EarthScope 156, GEOFON 155, GeoNet 155, RESIF 155, IPGP 111, ORFEUS 113, BGR 155.
  IPGP delivered 110 and ORFEUS 113 distinct stations in this run; BGR delivered
  163 cumulatively across changing startup selections (not simultaneous count).
- This is NOT a sustained latency pass: fresh linked stations peaked at 998,
  then fell to 227 at 300 seconds; no sustained-lag recovery threshold had yet
  completed on those final connections. The regression/live test success
  establishes protocol and recovery behavior, not elimination of the underlying
  backlog. Further transport/processing throughput diagnosis remains necessary.
- Direct ORFEUS station/channel HTTP requests returned 403. No intensities were
  fabricated; the provider remains default-off pending usable metadata access.
  Some other relayed station epochs also remain unavailable. Calibration tests
  require exact metadata, never substitute another station or rewrite timestamps.

Evidence (ignored diagnostic output):

- `tmp/fdsn_connection_review/live_result_1000_seven_source_health_20261003.json`
- `tmp/fdsn_connection_review/live_result_1000_seven_source_batch_20261003.json`
- `tmp/fdsn_multisource_20261003/batch_live.log`
- `tmp/fdsn_multisource_20261003/regression_health.log`
- `tmp/fdsn_multisource_20261003/public_health.log`

## Automatic system proxy for FDSN

Only FDSN station/channel/routing metadata, stream discovery and SeedLink
waveforms use this network layer. Other API clients, authentication and map tiles
are unchanged; there is no global HttpOverrides or machine-specific proxy port.

- Windows reads the enabled current-user proxy using
  `WinHttpGetIEProxyConfigForCurrentUser`, including protocol-specific endpoints
  and bypass patterns. Disabled proxy settings select DIRECT. Explicit PAC URLs
  and WPAD use `WinHttpGetProxyForUrl` in a worker isolate. WPAD reporting that
  no proxy exists is DIRECT, not an invented proxy address.
- An explicit HTTP_PROXY/HTTPS_PROXY environment setting takes precedence and
  honors Dart's NO_PROXY rules. Other native platforms retain direct networking
  when those environment variables are absent; this change does not add Android,
  macOS or Linux desktop GUI proxy discovery. VPN/TUN routing remains OS-managed.
- Browser builds retain package:http's browser client and browser-managed proxy
  behavior. They do not import the native Windows/FFI transport.
- HTTP proxy endpoints without credentials are supported. SOCKS-only endpoints
  and credential-bearing proxy URLs are not supported by this transport; no
  silent direct fallback is appended when a chosen proxy fails or rejects CONNECT.
- Metadata requests resolve their route before sending, including redirects.
  SeedLink plaintext uses HTTP CONNECT; TLS SeedLink uses CONNECT followed by
  normal certificate/hostname-verified TLS. Original waveforms are unchanged.
- Configuration is shared/cached for 15 seconds. Active waveform watchdogs check
  the route every 15 seconds and reconnect only when it changes. Switching routes
  clears old resume cursors and resets reconnect backoff. Disconnected sources
  resolve the latest route on their next scheduled retry. Unchanged routes do not
  cause connection churn. Stopping a source still closes its sockets/clients.

Proxy availability is not the same as network reachability: disabling the system
proxy restores direct connection behavior, but cannot make an upstream service
reachable from a network that blocks that direct route. Closing a proxy program
while leaving the OS proxy enabled is a proxy failure, not a disabled proxy.

The preceding independent six-minute transport diagnostic compared the same
1000-station EarthScope selection. Direct received 5,436,099 bytes and ended with
zero fresh stations; the HTTP-proxied TLS route received 121,502,723 bytes and
ended with 997 fresh stations. Its final interval median record-start age was
7.565 seconds. This evidence is specific to this network/run, not a guarantee of
all-day availability. Full application-source validation is recorded separately.

### Verification of automatic proxy integration

- 85 focused tests passed (including 15 proxy tests); public-edition proxy,
  health and multi-source tests passed 41. Tests include native Windows PAC,
  direct/proxy/direct transitions on a running SeedLink service, unchanged-route
  stability, bypasses, HTTP redirect routing, proxy rejection, timeout cleanup,
  coalesced original tunnel bytes and source stop behavior.
- The web-only client factory compiled to JavaScript without importing dart:io
  or Windows FFI. This is a compilation smoke check, not a browser runtime test.
- The production resolver automatically detected the current Windows proxy.
  ORFEUS returned HTTP 200 and 1734 real NL channel rows; the TLS EarthScope
  connection returned its real HELLO banner with certificate checks enabled.
- The actual seven-source service probe ran 08:08:09-08:14:09 UTC on 2026-10-03.
  It selected 1000 unique network/station identities with no EarthScope/regional
  duplication. Fresh linked stations were 948 at 15 seconds and 999 at every
  30-360 second snapshot. All seven final waveform connections used the detected
  proxy, each with one connection attempt and zero live recoveries. End-of-run
  fresh calibrated/located measurements: 965. Missing metadata was not fabricated.
- This is a six-minute source-service test, not a packaged-app GUI, cloud-host,
  mobile-native or all-day stability validation. No release installers were built
  and no repository push was performed.

Evidence: `tmp/fdsn_multisource_20261003/proxy_regression_final.log`,
`tmp/fdsn_multisource_20261003/proxy_public_final.log`,
`tmp/fdsn_multisource_20261003/automatic_proxy_live.log`, and
`tmp/fdsn_connection_review/live_result_1000_automatic_proxy_20261003.json`.

## Per-provider map status

The bottom-right station status area now replaces the combined FDSN timestamp
line with enabled provider names and individual live station counts, in source
registry order. This is a separate wrapping group below the station timestamp
lines, never part of the WSS source group. Disabling the master switch hides it.

Counts are distinct selected network/station identities with received, decoded,
non-future observations at most 180 seconds old on a connected waveform source.
They are not catalogue entries, accepted subscription commands, packet counts,
or the number of stations with successfully calibrated physical measurements.

Display health uses each selected station's latest original record timestamp:

- At most 30 seconds old: timely.
- Over 30 through 180 seconds: delayed, but included in the displayed count.
- Over 180 seconds: stale, excluded from that count.
- No valid observation (including future-only data): missing, not counted.
- The display score is `(0.5 * delayed + stale + missing) / selected`.
  It interpolates green, yellow, orange and red. This is a UI health score, not
  a seismic intensity formula or a change to waveform acceptance thresholds.
- Connection/subscription failure is red with zero live stations. Startup is
  yellow; successful discovery with no assigned station is gray, not an error.

Desktop tooltips give the state, selected/live counts and age-bucket counts.
Four numeric character positions prevent count changes from shifting the row.
The receiver summarizes at five-second intervals (and on selection changes),
publishing only changed summaries. The dashboard no longer listens to every
FDSN latest-observation timestamp. Android forwards the small summary through
the foreground station payload, without moving station histories to the UI.

Tests: `fdsn_source_status_test.dart` validates age boundaries, per-station
weighting, original timestamps, serialization, native receiver failures and
cleanup. `source_dashboard_global_stations_test.dart` covers source separation,
registry order, counts, colors, disabling, narrow/landscape layouts and enlarged
text. UI screenshot fixtures are test-only, not live service readings.
