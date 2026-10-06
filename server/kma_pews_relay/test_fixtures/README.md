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
