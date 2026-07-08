# Source Estimation Split Audit

- Status: `pass`
- Dataset: `source_estimation_p1`
- Frozen at: `2026-06-20`
- Split manifest: `test/fixtures/source_estimation/dataset_splits.json`
- Case count: `25`
- Detection metric denominator cases: `2`
- Unassigned reference events: `12`
- Explicit unassigned references: `12`
- Legacy unspecified unassigned events: `0`
- Quiet-window target/current/remaining: `2/2/0`
- Quiet-window planned captures: `0`
- Quiet-window plan: `docs/data/source_estimation_quiet_window_capture_plan.json`
- Quiet-window required layers: `8` (`acmap_b`, `acmap_s`, `dcmap_b`, `dcmap_s`, `jma_b`, `jma_s`, `vcmap_b`, `vcmap_s`)
- Split assignment planned/unplanned: `12/0`
- Split assignment plan: `docs/data/source_estimation_split_assignment_plan.json`

## Validation

- Errors: none
- Warnings: `unassigned_reference_event_count:12`

## Cases

| Split | Case | Type | Metrics | Split status | Truth | Region |
| --- | --- | --- | --- | --- | --- | --- |
| `test` | `20260620_ibaraki_offshore_m19_ref` | `event` | yes | `unspecified` | `user_provided_equake_reports_low_precision_reference` | `Ibaraki Prefecture offshore` |
| `train` | `20260610_nara_m36` | `event` | yes | `unspecified` | `existing_project_replay_label` | `` |
| `train` | `20260614_quiet_175544` | `noise` | no | `unspecified` | `` | `` |
| `unassigned` | `20260620_iwate_offshore_m34_ref` | `event` | no | `unassigned_reference` | `hinet_hypocenter_information` | `Iwate offshore` |
| `unassigned` | `20260621_fukushima_offshore_m32_eq6` | `event` | no | `unassigned_reference` | `user_provided_hinet_hypocenter` | `Miyagi southeast offshore` |
| `unassigned` | `20260621_iwate_offshore_m33_eq8` | `event` | no | `unassigned_reference` | `user_provided_equake_final_report_reference` | `Iwate offshore` |
| `unassigned` | `20260622_kushiro_offshore_m30_jma` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Kushiro offshore` |
| `unassigned` | `20260624_fukushima_aizu_m32_jma_eq5` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Fukushima Aizu` |
| `unassigned` | `20260625_iwate_offshore_m32_jma` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Iwate offshore` |
| `unassigned` | `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Yamanashi east / Fuji Five Lakes` |
| `unassigned` | `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Yamanashi east / Fuji Five Lakes` |
| `unassigned` | `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Yamanashi east / Fuji Five Lakes` |
| `unassigned` | `20260627_fukushima_aizu_m36_jma_equake17` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Fukushima Aizu` |
| `unassigned` | `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Yamanashi east / Fuji Five Lakes` |
| `unassigned` | `20260628_iwate_offshore_m41_jma` | `event` | no | `unassigned_reference` | `jma_source_and_intensity_information` | `Iwate offshore` |
| `unassigned` | `quiet_20260625_233535_jst_live` | `noise` | no | `unassigned_reference` | `` | `` |
| `validation` | `20260620_kyoto_s_m18_d12` | `event` | no | `unspecified` | `user_provided_equake_screenshot` | `Kyoto Prefecture south` |
| `validation` | `20260620_satsuma_m26_d179` | `event` | no | `unspecified` | `user_provided_equake_screenshot` | `` |
| `validation` | `20260622_fukushima_offshore_m22_eq4` | `event` | no | `validation_reference` | `equake_source_estimation_reference` | `Fukushima offshore` |
| `validation` | `20260622_iwate_east_offshore_m30_hinet` | `event` | no | `validation_reference` | `user_provided_hinet_hypocenter` | `Iwate east offshore` |
| `validation` | `20260622_iwate_offshore_m30_eq10` | `event` | no | `validation_reference` | `user_provided_hinet_hypocenter` | `Iwate northeast offshore` |
| `validation` | `20260622_tomakomai_south_offshore_m35_hinet` | `event` | no | `validation_reference` | `user_provided_hinet_hypocenter` | `Tomakomai south offshore` |
| `validation` | `20260622_wakayama_south_m25_hinet` | `event` | no | `validation_reference` | `user_provided_hinet_hypocenter` | `Wakayama south` |
| `validation` | `20260623_tokachi_southeast_offshore_m34_hinet` | `event` | no | `validation_reference` | `user_provided_hinet_hypocenter` | `Tokachi southeast offshore` |
| `validation` | `noto_m27_20260621_jma_eq5` | `event` | no | `validation_reference` | `JMA` | `石川県能登地方` |
