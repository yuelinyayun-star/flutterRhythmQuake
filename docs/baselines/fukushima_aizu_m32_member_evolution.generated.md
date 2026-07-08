# Fukushima/Miyagi M3.2 Member Evolution

Generated from `.dart_tool\source_estimation_benchmark\20260624_fukushima_aizu_m32_jma_eq5.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260624_fukushima_aizu_m32_jma_eq5`
- Source-trigger frames: 73
- Estimate frames: 61
- Findings: 

## Selected Frames

| Frame | Time | State | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Truth in search | Picks outside members | Geometry |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- |
| `first_detection` | 2026-06-24T13:24:52.000 | candidate | 4 (+4/-0) | 8.7 km | 8.7 km | - / - | - | 0/0 | - |
| `first_estimate` | 2026-06-24T13:24:54.000 | confirmed | 5 (+0/-0) | 6.1 km | 12.1 km | 1.0 km / - | true | 1/6 | surrounded |
| `largest_member_turnover` | 2026-06-24T13:26:28.000 | rejected | 5 (+5/-50) | 138.9 km | 138.9 km | - / - | - | 0/0 | - |
| `largest_estimate_jump` | 2026-06-24T13:25:36.000 | confirmed | 10 (+0/-0) | 112.6 km | 112.6 km | 12.0 km / 39.6 km | true | 5/6 | surrounded |
| `worst_error` | 2026-06-24T13:25:35.000 | confirmed | 10 (+0/-0) | 112.6 km | 112.6 km | 28.0 km / 3.5 km | true | 6/6 | surrounded |
| `final_detection` | 2026-06-24T13:26:28.000 | rejected | 5 (+5/-50) | 138.9 km | 138.9 km | - / - | - | 0/0 | - |

## Largest Jump Window

Rows marked with `*` changed source event ID.

| Index | Time | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Members |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 77 | 2026-06-24T13:25:32.000 | 12 (+0/-0) | 100.4 km | 100.4 km | 16.0 km / 0.9 km | `FKSH04, FKSH12, IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, ... +4` |
| 78 | 2026-06-24T13:25:33.000 | 11 (+0/-1) | 108.9 km | 108.9 km | 16.0 km / 0.0 km | `FKSH12, IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, ... +3` |
| 79 | 2026-06-24T13:25:34.000 | 10 (+0/-1) | 112.6 km | 112.6 km | 25.0 km / 10.0 km | `IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, IBRH17, ... +2` |
| 80 | 2026-06-24T13:25:35.000 | 10 (+0/-0) | 112.6 km | 112.6 km | 28.0 km / 3.5 km | `IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, IBRH17, ... +2` |
| 81 | 2026-06-24T13:25:36.000 | 10 (+0/-0) | 112.6 km | 112.6 km | 12.0 km / 39.6 km | `IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, IBRH17, ... +2` |
| 82 | 2026-06-24T13:25:37.000 | 10 (+0/-0) | 112.6 km | 112.6 km | 10.0 km / 8.3 km | `IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, IBRH17, ... +2` |
| 83 | 2026-06-24T13:25:38.000 | 10 (+0/-0) | 112.6 km | 112.6 km | 10.0 km / 7.1 km | `IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, IBRH17, ... +2` |
| 84 | 2026-06-24T13:25:39.000 | 10 (+0/-0) | 112.6 km | 112.6 km | 10.0 km / 0.0 km | `IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, IBRH17, ... +2` |
| 85 | 2026-06-24T13:25:40.000 | 9 (+0/-1) | 116.1 km | 116.1 km | 10.0 km / 0.0 km | `IBR005, IBR006, IBR013, IBRH09, IBRH15, IBRH16, IBRH17, IBRH18, ... +1` |

## Largest Jump Detail

- Time: `2026-06-24T13:25:36.000`
- Event ID: `nied_gif-2026-06-24T13:24:52.000`
- Added members: ``
- Removed members: ``
- Largest component stations: `IBR005, IBR006, IBR013, IBRH09, IBRH12, IBRH15, IBRH16, IBRH17, IBRH18, TCGH16`
- Timing picks outside current members: `NIG023, NIGH19, TCG001, TCGH13, TCGH19`
