# 2026-06-21 Noto M2.7 Multilayer Reference

## Truth

JMA:

```text
origin:       2026-06-21 21:07:56 UTC+8
region:       石川県能登地方
epicenter:    37.50 N, 137.20 E
depth:        10 km
magnitude:    M2.7
max intensity: 1
tsunami:      no concern
```

## EQuake Reference

Final report 5:

```text
origin:       2026-06-21 21:07:54 UTC+8
epicenter:    37.47 N, 137.19 E
depth:        5 km
magnitude:    M2.1
quality:      A / 80.8% / 0.53 s / 88 deg
triggers:     20 (P:2 / S:15 / O:3)
M stations:   8
```

Compared with JMA:

| Metric | Difference |
|---|---:|
| Horizontal epicenter error | 3.45 km |
| Origin time | -2 s |
| Depth | -5 km |
| Magnitude | -0.6 |

EQuake is reference-only. JMA remains the event truth.

## Capture

```text
directory:    tmp/captures/noto_m27_20260621_210754_multilayer
window:       2026-06-21 22:07:24 to 22:09:54 JST
timestamps:   151
layers:       jma/acmap/vcmap/dcmap x surface/borehole
GIF:          1208 / 1208
missing:      0
decoder:      nied_gif_layered_v2
split:        unassigned_reference
```

Layer alignment:
[`noto_m27_20260621_multilayer_alignment.generated.md`](noto_m27_20260621_multilayer_alignment.generated.md)

This event must remain outside frozen metrics until event-level split assignment
is reviewed.
