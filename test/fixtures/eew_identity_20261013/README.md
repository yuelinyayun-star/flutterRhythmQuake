# Live EEW identity audit, 2026-10-13 19:12 (Asia/Shanghai)

The 44 records in `reports.original.json` were captured from authenticated FAN,
Jian, WHEWS overseas/domestic, Jian ICL, China EEW ICL HTTP, and Wolfx WS/HTTP
connections. Report objects are unchanged; IDs, clocks and coordinates were not
rewritten. These are initial/latest snapshots, including old events, not newly
issued live warnings. Credentials are excluded.

`capture-manifest.json` records SHA-256 of full original response files retained
in the local audit archive. `connections.json` distinguishes successful business
connections from supplementary endpoint failures. SASMEX returned heartbeat but
no event, and GlobalQuake accepted the TCP handshake and returned cluster packets
but no hypocenter packet during this observation window.

JMA, KMA, ShakeAlert and ICL preserve the same event IDs across the sampled APIs.
CWA uses the previously verified FAN namespace. Wolfx SC/FJ append report numbers
to EventID; existing adapters remove those suffixes from comparison identity.

Jian CEA-pr uses `b4t9t7uxnzhyy`, while Jian CEA, FAN CEA/CEA-pr and Wolfx CENC use
`202610131615.0001` for the same sampled origin. Time/coordinate fallback alone
does not retain a stable speech/admission key. The identity registry retains
aliases only after the existing matcher has linked them, without broadening
tolerances or modifying original reports.
