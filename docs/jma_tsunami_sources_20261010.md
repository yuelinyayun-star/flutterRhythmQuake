# JMA tsunami source integration — 2026-10-10

## Connected local code

- P2PQuake `wss://api.p2pquake.net/v2/ws`, code 552.
- WHEWS `wss://api.beecld.com/ws/all`, `jma_tsunami`.
- Jian `wss://api.sismotide.top/all`, `jma-tsunami`, under the existing Jian
  preference and authentication. No extra socket or independent poller.

Desktop and Android subscribe to the same tsunami stream. Original Jian Data
is retained as sourcePayload. Its originTime is the **bulletin issue epoch**;
it is not used as an earthquake origin time or shifted by nine hours.
The displayed time uses the computer's timezone. headline/EventID and number
are used for report ordering; issue time orders different transports without
comparable serials. endTime is the explicit validity deadline.

The shared model distinguishes none / forecast / watch / warning /
majorWarning. Forecasts have blue coastal segments and appear in the existing
tsunami sidebar. They reuse the existing coastline blink and shared animation
clock, without warning audio. Mixed
reports retain each region's own grade. Same-time P2P all-clear cannot erase
an explicit forecast. Past reports cannot roll back a later report.

## Official JMA access, verified

JMA publishes an Atom feed and individual XML bulletins:

- Information: https://xml.kishou.go.jp/xmlpull.html
- High-frequency earthquake/volcano feed (updated every minute):
  https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml
- Long feed (updated hourly):
  https://www.data.jma.go.jp/developer/xml/feed/eqvol_l.xml
- Current XML format, sample archive and code definitions:
  https://xml.kishou.go.jp/tec_material.html

VTSE41 covers tsunami warning/advisory/forecast. Official sample bulletins
contain both Kind codes 71 and 72 named 津波予報（若干の海面変動）. An advisory
lifting headline can coexist with forecasts, so a mention of 解除 in the
headline must not discard those regions. This public interface is PULL XML,
not a verified public WebSocket. A separate official source was investigated
but not enabled by this change.

P2P's maintained schema:
https://github.com/p2pquake/epsp-specifications/blob/master/json-api-v2.yaml

552 area.grade enumerates MajorWarning / Warning / Watch / Unknown. 551's
earthquake.domesticTsunami separately includes NonEffective; that field is not
a full forecast-region dataset.

## Evidence and validation

Jian protocol: https://api.sismotide.top/api/#ws-jma-tsunami

Regression inputs are unchanged official XML samples and the exact Jian
documentation JSON example. They are explicitly labelled in
test/fixtures/jma_tsunami/README.md, and are not represented as live captures.
Tests cover original payload preservation, timestamps, mixed grades, forecast
validity, model serialization, warning-to-forecast ordering, same-time all-clear,
one-socket snapshot/live delivery and local replay. No warnings are broadcast
to a running user application during verification.

Final validation: 184 tests passed across 12 regression files, including
rendering the actual existing coastline with the unchanged official forecast
sample at its own issue time and removing it at its original validity deadline.
Changed tsunami/parser/test files have no analyzer errors or warnings.
