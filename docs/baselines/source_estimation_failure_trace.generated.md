# Source Estimation Failure Trace

Generated from existing benchmark frame diagnostics.
No production estimator weights are changed by this report.

## `20260610_nara_m36`

- Estimate frames: 37
- Findings: `membership_changed_at_largest_jump`, `timing_picks_changed_at_largest_jump`

| Frame | Time | Error km | Jump km | Members (+/-) | Picks in event | Truth in search | Estimate |
| --- | --- | ---: | ---: | --- | ---: | --- | --- |
| first | 2026-06-10T18:01:34.000 | 7.0 | - | 5 (+5/-0) | 5/5 | true | 34.1396, 135.8030 |
| worst | 2026-06-10T18:01:40.000 | 14.0 | 1.0 | 46 (+0/-1) | 6/6 | true | 34.0794, 135.8235 |
| largest_jump | 2026-06-10T18:01:57.000 | 7.0 | 12.0 | 75 (+3/-0) | 6/6 | true | 34.2258, 135.8656 |
| final | 2026-06-10T18:02:10.000 | 4.0 | 2.0 | 69 (+5/-3) | 6/6 | true | 34.2069, 135.8446 |

### first

- Time: `2026-06-10T18:01:34.000`
- Member changes: +`NAR006, NAR008, NAR009, NARH03, NARH04` -``
- Timing picks inside members: `NAR006, NAR008, NAR009, NARH03, NARH04`
- Timing picks outside members: ``
- Timing picks outside accumulated event membership: ``
- Component centroid: 34.1433, 135.8138
- Scores: time 7.6, rank 0.5, final 9.3
- Geometry: `surrounded`, azimuthal gap 177.8 deg, nearest station 18.7 km, boundary margin 0.7 deg

### worst

- Time: `2026-06-10T18:01:40.000`
- Member changes: +`` -`MIEH03`
- Timing picks inside members: `MIEH05, NAR006, NAR008, NAR009, NARH03, NARH04`
- Timing picks outside members: ``
- Timing picks outside accumulated event membership: ``
- Component centroid: 34.2515, 135.8780
- Scores: time 263.5, rank 13.4, final 316.4
- Geometry: `surrounded`, azimuthal gap 47.4 deg, nearest station 16.8 km, boundary margin 0.9 deg

### largest jump

- Time: `2026-06-10T18:01:57.000`
- Member changes: +`FKIH02, HYGH04, SIG008` -``
- Timing picks inside members: `MIE015, MIEH05, MIEH09, NAR004, WKY007`
- Timing picks outside members: `NAR003`
- Timing picks outside accumulated event membership: ``
- Component centroid: 34.6671, 135.9188
- Scores: time 241.9, rank 22.6, final 300.8
- Geometry: `surrounded`, azimuthal gap 54.6 deg, nearest station 33.2 km, boundary margin 1.0 deg

### final

- Time: `2026-06-10T18:02:10.000`
- Member changes: +`AIC009, AICH08, AICH14, KGW004, SIG001` -`FKI010, KYTH03, TKS005`
- Timing picks inside members: `MIE007`
- Timing picks outside members: `KYT014, MIE005, MIE013, MIEH03, WKY011`
- Timing picks outside accumulated event membership: ``
- Component centroid: 34.8715, 135.8477
- Scores: time 445.2, rank 35.5, final 547.5
- Geometry: `surrounded`, azimuthal gap 143.7 deg, nearest station 58.9 km, boundary margin 0.8 deg

## `20260621_fukushima_offshore_m32_eq6`

- Estimate frames: 47
- Findings: `truth_outside_search_bbox`, `one_sided_boundary_solution`, `catastrophic_frame_error`, `large_interframe_jump`, `membership_changed_at_largest_jump`, `timing_picks_changed_at_largest_jump`

| Frame | Time | Error km | Jump km | Members (+/-) | Picks in event | Truth in search | Estimate |
| --- | --- | ---: | ---: | --- | ---: | --- | --- |
| first | 2026-06-21T23:41:50.000 | 120.0 | - | 5 (+5/-0) | 5/5 | false | 37.2052, 141.0212 |
| worst | 2026-06-21T23:41:55.000 | 313.0 | 3.0 | 15 (+2/-0) | 6/6 | false | 39.5453, 139.6612 |
| largest_jump | 2026-06-21T23:41:51.000 | 307.0 | 278.0 | 10 (+5/-0) | 6/6 | false | 39.4661, 139.6612 |
| final | 2026-06-21T23:43:08.000 | 168.0 | 0.0 | 4 (+0/-0) | 0/6 | false | 38.1330, 140.4801 |

### first

- Time: `2026-06-21T23:41:50.000`
- Member changes: +`MYG008, MYG010, MYG014, MYGH07, MYGH11` -``
- Timing picks inside members: `MYG008, MYG010, MYG014, MYGH07, MYGH11`
- Timing picks outside members: ``
- Timing picks outside accumulated event membership: ``
- Component centroid: 38.1813, 140.9951
- Scores: time 12.1, rank 3.9, final 17.9
- Geometry: `one_sided`, azimuthal gap 329.9 deg, nearest station 113.5 km, boundary margin -0.4 deg

### worst

- Time: `2026-06-21T23:41:55.000`
- Member changes: +`FKSH19, MYGH14` -``
- Timing picks inside members: `MYG008, MYG009, MYG010, MYG014, MYGH07`
- Timing picks outside members: `IWT026`
- Timing picks outside accumulated event membership: ``
- Component centroid: 38.1805, 141.0482
- Scores: time 1086.8, rank 10.4, final 1260.2
- Geometry: `one_sided`, azimuthal gap 306.3 deg, nearest station 127.6 km, boundary margin -0.4 deg

### largest jump

- Time: `2026-06-21T23:41:51.000`
- Member changes: +`FKS006, FKSH20, IWT026, MYG002, MYG009` -``
- Timing picks inside members: `IWT026, MYG008, MYG009, MYG010, MYG014, MYGH07`
- Timing picks outside members: ``
- Timing picks outside accumulated event membership: ``
- Component centroid: 38.3433, 141.0570
- Scores: time 544.4, rank 5.5, final 631.5
- Geometry: `one_sided`, azimuthal gap 304.2 deg, nearest station 125.7 km, boundary margin -0.4 deg

### final

- Time: `2026-06-21T23:43:08.000`
- Member changes: +`` -``
- Timing picks inside members: ``
- Timing picks outside members: `FKS002, FKS019, FKSH19, MYGH07, MYGH14, TCGH16`
- Timing picks outside accumulated event membership: `FKS002, FKS019, FKSH19, MYGH07, MYGH14, TCGH16`
- Component centroid: 35.8305, 139.5854
- Scores: time 761.8, rank 21.1, final 897.2
- Geometry: `one_sided`, azimuthal gap 188.2 deg, nearest station 15.0 km, boundary margin 1.0 deg

## `20260622_kushiro_offshore_m30_jma`

- Estimate frames: 42
- Findings: `one_sided_boundary_solution`, `large_interframe_jump`, `membership_changed_at_largest_jump`

| Frame | Time | Error km | Jump km | Members (+/-) | Picks in event | Truth in search | Estimate |
| --- | --- | ---: | ---: | --- | ---: | --- | --- |
| first | 2026-06-22T16:38:23.000 | 102.0 | - | 5 (+5/-0) | 6/6 | true | 42.2238, 144.8340 |
| worst | 2026-06-22T16:38:30.000 | 139.0 | 6.0 | 13 (+3/-0) | 6/6 | true | 41.8338, 144.8887 |
| largest_jump | 2026-06-22T16:38:28.000 | 136.0 | 253.0 | 10 (+1/-0) | 6/6 | true | 41.8338, 144.8194 |
| final | 2026-06-22T16:39:04.000 | 33.0 | 3.0 | 2 (+0/-0) | 6/6 | true | 43.1787, 143.8473 |

### first

- Time: `2026-06-22T16:38:23.000`
- Member changes: +`HKD085, HKD091, KSRH02, KSRH07, KSRH09` -``
- Timing picks inside members: `HKD085, HKD091, KSRH02, KSRH07, KSRH09`
- Timing picks outside members: `HKD086`
- Timing picks outside accumulated event membership: ``
- Component centroid: 42.9761, 144.0035
- Scores: time 35.4, rank 4.7, final 45.4
- Geometry: `one_sided`, azimuthal gap 326.5 deg, nearest station 102.9 km, boundary margin 0.0 deg

### worst

- Time: `2026-06-22T16:38:30.000`
- Member changes: +`HKD088, HKD095, KSRH01` -``
- Timing picks inside members: `HKD085, HKD086, HKD091, KSRH02, KSRH07, KSRH09`
- Timing picks outside members: ``
- Timing picks outside accumulated event membership: ``
- Component centroid: 43.1536, 144.0313
- Scores: time 170.6, rank 8.5, final 204.7
- Geometry: `one_sided`, azimuthal gap 310.5 deg, nearest station 141.6 km, boundary margin -0.4 deg

### largest jump

- Time: `2026-06-22T16:38:28.000`
- Member changes: +`HKD089` -``
- Timing picks inside members: `HKD085, HKD086, HKD091, KSRH02, KSRH07, KSRH09`
- Timing picks outside members: ``
- Timing picks outside accumulated event membership: ``
- Component centroid: 43.1159, 144.1360
- Scores: time 152.4, rank 8.1, final 183.3
- Geometry: `one_sided`, azimuthal gap 315.8 deg, nearest station 138.3 km, boundary margin -0.4 deg

### final

- Time: `2026-06-22T16:39:04.000`
- Member changes: +`` -``
- Timing picks inside members: ``
- Timing picks outside members: `HKD066, HKD099, HKD103, HKD113, KSRH10, NMRH02`
- Timing picks outside accumulated event membership: ``
- Component centroid: 43.2814, 145.6618
- Scores: time 166.2, rank 0.8, final 192.0
- Geometry: `surrounded`, azimuthal gap 155.8 deg, nearest station 82.6 km, boundary margin 1.1 deg

