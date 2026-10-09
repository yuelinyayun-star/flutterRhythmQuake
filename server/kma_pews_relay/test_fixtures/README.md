# Original KMA protection responses

These fixtures are unchanged response bodies captured by the production relay
on 2026-10-06 and downloaded from its anomaly archive. They are not generated
station data. Both requests returned HTTP 200 and Content-Type: text/html.

| Fixture | Requested UTC frame | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| captcha_original.html | 2026-10-06 05:00:10 | 1798 | 070169b75a0a54fb70b9e439e9022e3c5070e8f97a5ef9dd771fde423ae080d4 |
| firewall_original.html | 2026-10-06 05:00:34 | 310 | f68ab4450bafa8848d5efd0546b4251b0e19a4e741391cbbe00ff6ae6e58cd1f |

Tests verify these hashes and check rejection before binary decoding. No cookie,
credential, or detected client IP is present in either original body.

## Original SASMEX snapshot

`sasmex_snapshot_original.json` is the unchanged HTTP response from
`https://ws.yuelinrhythm.top/sasmex/snapshot`, retrieved on 2026-10-08.
SHA-256: `81a7d867e8de1d5cb00cab50a6fcb676e83fc9a1e0f2cf65f767b873612a7aed`.

Its real Socket.IO cache is empty; its separate CAP archive contains an older
event. Tests use it to verify that querying the real IO cache cannot return CAP
archive data. Its original CAP circle string also tests the circle decoder;
the snapshot is never converted into a fabricated Socket.IO earthquake frame.


## 2026-10-08 双连接对照原始捕获

Firestore 文件为服务器实读 `sasno-d79e1` 的 `app/events` HTTP 响应原始字节，文档事件仍为 2026-10-06，未改写。三个 IO 帧来自同一网页实际根命名空间捕获；只有握手和 ping，没有制造业务事件。

- `sasmex_firestore_20261008.original.json` SHA-256 `7cbb2cb1219799624f830ff7b0cc2d07e34aa6cda2bc127574fa7a9c93c12fe4`
- `sidesis_handshake_20261008.original.frame` SHA-256 `f6f51d282f008fac8f6d0e67c46d8e56587e48e966ab0eea3e57800ddb5d7098`
- `sidesis_namespace_20261008.original.frame` SHA-256 `b4787c0d01ff4673e19ade123e781435ab29ff22cd9c55184a05740aaefb407d`
- `sidesis_ping_20261008.original.frame` SHA-256 `d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35`
