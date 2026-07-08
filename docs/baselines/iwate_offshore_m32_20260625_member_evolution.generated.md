# 20260625_iwate_offshore_m32_jma Member Evolution

Generated from `.dart_tool\source_estimation_benchmark\20260625_iwate_offshore_m32_jma.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260625_iwate_offshore_m32_jma`
- Source-trigger frames: 58
- Estimate frames: 56
- Findings: `large_estimate_jump`

## Selected Frames

| Frame | Time | State | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Truth in search | Picks outside members | Geometry |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- |
| `first_detection` | 2026-06-25T19:21:56.000 | candidate | 5 (+5/-0) | 29.3 km | 25.6 km | - / - | - | 0/0 | - |
| `first_estimate` | 2026-06-25T19:21:57.000 | confirmed | 5 (+1/-1) | 28.6 km | 28.6 km | 144.0 km / - | true | 1/6 | one_sided |
| `largest_member_turnover` | 2026-06-25T19:22:40.000 | confirmed | 22 (+1/-5) | 87.1 km | 87.1 km | 35.0 km / 40.2 km | true | 3/6 | one_sided |
| `largest_estimate_jump` | 2026-06-25T19:22:00.000 | confirmed | 10 (+1/-0) | 33.9 km | 33.9 km | 40.0 km / 123.1 km | true | 1/6 | surrounded |
| `worst_error` | 2026-06-25T19:21:57.000 | confirmed | 5 (+1/-1) | 28.6 km | 28.6 km | 144.0 km / - | true | 1/6 | one_sided |
| `final_detection` | 2026-06-25T19:22:53.000 | ended | 2 (+0/-0) | 181.4 km | 181.4 km | - / - | - | 0/0 | - |

## Largest Jump Window

Rows marked with `*` changed source event ID.

| Index | Time | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Members |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 37 | 2026-06-25T19:21:56.000 | 5 (+5/-0) | 29.3 km | 25.6 km | - / - | `IWT004, IWT016, IWTH01, IWTH14, IWTH21` |
| 38 | 2026-06-25T19:21:57.000 | 5 (+1/-1) | 28.6 km | 28.6 km | 144.0 km / - | `IWT004, IWT006, IWT016, IWTH01, IWTH14` |
| 39 | 2026-06-25T19:21:58.000 | 9 (+4/-0) | 35.2 km | 35.2 km | 123.0 km / 23.0 km | `IWT004, IWT005, IWT006, IWT016, IWT020, IWTH01, IWTH02, IWTH14, ... +1` |
| 40 | 2026-06-25T19:21:59.000 | 9 (+0/-0) | 35.2 km | 35.2 km | 123.0 km / 0.0 km | `IWT004, IWT005, IWT006, IWT016, IWT020, IWTH01, IWTH02, IWTH14, ... +1` |
| 41 | 2026-06-25T19:22:00.000 | 10 (+1/-0) | 33.9 km | 33.9 km | 40.0 km / 123.1 km | `IWT003, IWT004, IWT005, IWT006, IWT016, IWT020, IWTH01, IWTH02, ... +2` |
| 42 | 2026-06-25T19:22:01.000 | 11 (+1/-0) | 39.0 km | 39.0 km | 40.0 km / 0.2 km | `IWT003, IWT004, IWT005, IWT006, IWT016, IWT020, IWT021, IWTH01, ... +3` |
| 43 | 2026-06-25T19:22:02.000 | 13 (+2/-0) | 38.6 km | 38.6 km | 39.0 km / 1.7 km | `IWT003, IWT004, IWT005, IWT006, IWT016, IWT017, IWT020, IWT021, ... +5` |
| 44 | 2026-06-25T19:22:03.000 | 15 (+2/-0) | 39.6 km | 39.6 km | 27.0 km / 12.2 km | `IWT003, IWT004, IWT005, IWT006, IWT016, IWT017, IWT020, IWT021, ... +7` |
| 45 | 2026-06-25T19:22:04.000 | 16 (+1/-0) | 41.8 km | 41.8 km | 33.0 km / 8.4 km | `AOMH17, IWT003, IWT004, IWT005, IWT006, IWT016, IWT017, IWT020, ... +8` |

## Largest Jump Detail

- Time: `2026-06-25T19:22:00.000`
- Event ID: `nied_gif-2026-06-25T19:21:56.000`
- Added members: `IWT003`
- Removed members: ``
- Largest component stations: `IWT003, IWT004, IWT005, IWT006, IWT016, IWT020, IWTH01, IWTH02, IWTH14, IWTH18`
- Timing picks outside current members: `IWTH21`
