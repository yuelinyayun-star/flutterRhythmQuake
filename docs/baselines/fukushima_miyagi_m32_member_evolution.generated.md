# 20260621_fukushima_offshore_m32_eq6 Member Evolution

Generated from `.dart_tool/source_estimation_benchmark/20260621_fukushima_offshore_m32_eq6.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260621_fukushima_offshore_m32_eq6`
- Source-trigger frames: 54
- Estimate frames: 47
- Findings: `large_estimate_jump`, `member_turnover_at_largest_jump`, `truth_outside_estimator_search_box`

## Selected Frames

| Frame | Time | State | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Truth in search | Picks outside members | Geometry |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- |
| `first_detection` | 2026-06-21T23:41:49.000 | candidate | 5 (+5/-0) | 137.6 km | 140.2 km | - / - | - | 0/0 | - |
| `first_estimate` | 2026-06-21T23:41:50.000 | confirmed | 5 (+0/-0) | 137.6 km | 129.0 km | 120.0 km / - | false | 0/5 | one_sided |
| `largest_member_turnover` | 2026-06-21T23:42:49.000 | candidate | 24 (+22/-0) | 133.8 km | 319.0 km | - / - | - | 0/0 | - |
| `largest_estimate_jump` | 2026-06-21T23:41:51.000 | confirmed | 10 (+5/-0) | 134.2 km | 134.2 km | 307.0 km / 278.0 km | false | 0/6 | one_sided |
| `worst_error` | 2026-06-21T23:41:55.000 | confirmed | 15 (+2/-0) | 124.9 km | 124.9 km | 313.0 km / 3.2 km | false | 1/6 | one_sided |
| `final_detection` | 2026-06-21T23:43:08.000 | confirmed | 24 (+0/-0) | 133.8 km | 311.5 km | 168.0 km / 0.0 km | false | 0/6 | one_sided |

## Largest Jump Window

Rows marked with `*` changed source event ID.

| Index | Time | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Members |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 71 | 2026-06-21T23:41:49.000 | 5 (+5/-0) | 137.6 km | 140.2 km | - / - | `MYG008, MYG010, MYG014, MYGH07, MYGH11` |
| 72 | 2026-06-21T23:41:50.000 | 5 (+0/-0) | 137.6 km | 129.0 km | 120.0 km / - | `MYG008, MYG010, MYG014, MYGH07, MYGH11` |
| 73 | 2026-06-21T23:41:51.000 | 10 (+5/-0) | 134.2 km | 134.2 km | 307.0 km / 278.0 km | `FKS006, FKSH20, IWT026, MYG002, MYG008, MYG009, MYG010, MYG014, ... +2` |
| 74 | 2026-06-21T23:41:52.000 | 14 (+4/-0) | 129.4 km | 129.4 km | 311.0 km / 5.6 km | `FKS001, FKS005, FKS006, FKSH20, IWT026, MYG002, MYG007, MYG008, ... +6` |
| 75 | 2026-06-21T23:41:53.000 | 13 (+0/-1) | 124.9 km | 124.9 km | 311.0 km / 0.0 km | `FKS001, FKS005, FKS006, FKSH20, MYG002, MYG007, MYG008, MYG009, ... +5` |
| 76 | 2026-06-21T23:41:54.000 | 13 (+0/-0) | 124.9 km | 124.9 km | 311.0 km / 0.0 km | `FKS001, FKS005, FKS006, FKSH20, MYG002, MYG007, MYG008, MYG009, ... +5` |
| 77 | 2026-06-21T23:41:55.000 | 15 (+2/-0) | 124.9 km | 124.9 km | 313.0 km / 3.2 km | `FKS001, FKS005, FKS006, FKSH19, FKSH20, MYG002, MYG007, MYG008, ... +7` |

## Largest Jump Detail

- Time: `2026-06-21T23:41:51.000`
- Event ID: `nied_gif-2026-06-21T23:41:49.000`
- Added members: `FKS006, FKSH20, IWT026, MYG002, MYG009`
- Removed members: ``
- Largest component stations: `FKS006, FKSH20, IWT026, MYG002, MYG008, MYG009, MYG010, MYG014, MYGH07, MYGH11`
- Timing picks outside current members: ``
