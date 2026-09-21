# JMA Voice Captures

`p2p_history_20260921.json` is the unmodified HTTP body captured on 2026-09-21
with Invoke-WebRequest -OutFile from:
https://api.p2pquake.net/v2/history?codes=551&limit=10

It includes the Hyuganada 2026/09/21 22:38:00 DetailScale bulletin shown by the
user (M4.8, depth 30 km, 191 station observations), its preceding bulletins,
and a separate zero-depth DetailScale bulletin. These are historical regression
inputs, not live information. Tests select entries without rewriting the payload.
