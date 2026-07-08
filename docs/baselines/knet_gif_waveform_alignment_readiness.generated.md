# K-NET GIF/Waveform Alignment Readiness

- Status: `pass`
- Fixture directory: `test/fixtures/source_estimation`
- Waveform manifest: `tmp/knet_waveform_seed_download_manifest.json`
- Download report: `tmp/knet_downloads/download_report.json`
- Feature index: `tmp/knet_features/knet_waveform_feature_index.json`
- Capture fixtures: `22`
- Waveform candidates: `16`
- Matched capture/candidate pairs: `10`
- Ready for alignment: `0`
- Directory id unconfirmed: `10`
- Downloaded but feature build pending: `0`
- Capture-only cases needing waveform candidate: `12`
- Waveform-only cases without local capture: `6`

## Validation

- Errors: none
- Warnings: none

## Capture Cases

| Case | Origin JST | Region | Match | Directory id | Downloads | Features | Readiness | Next action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `20260610_nara_m36` | `2026-06-10T18:01:30` | `` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260620_ibaraki_offshore_m19_ref` | `2026-06-20T18:44:42` | `Ibaraki Prefecture offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260620_iwate_offshore_m34_ref` | `2026-06-20T21:25:27` | `Iwate offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260620_kyoto_s_m18_d12` | `2026-06-20T14:19:03` | `Kyoto Prefecture south` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260620_satsuma_m26_d179` | `2026-06-20T11:50:47` | `` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:12` | `Miyagi southeast offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260621_iwate_offshore_m33_eq8` | `2026-06-21T11:32:12` | `Iwate offshore` | `iwate_offshore_20260621_m33_equake_ref` | `20260621113200` | `success:0 failed:4 existing:0` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260622_fukushima_offshore_m22_eq4` | `2026-06-22T15:36:56` | `Fukushima offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260622_iwate_east_offshore_m30_hinet` | `2026-06-22T11:26:50` | `Iwate east offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260622_iwate_offshore_m30_eq10` | `2026-06-22T09:28:23` | `Iwate northeast offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:12` | `Kushiro offshore` | `kushiro_offshore_20260622_m30_jma` | `20260622163800` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `2026-06-22T20:37:47` | `Tomakomai south offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260622_wakayama_south_m25_hinet` | `2026-06-22T09:51:17` | `Wakayama south` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `2026-06-23T23:13:06` | `Tokachi southeast offshore` | - | - | `none` | `0` | `capture_only_needs_waveform_candidate` | `seed_waveform_candidate_for_local_capture` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `2026-06-24T13:24:45` | `Fukushima Aizu` | `fukushima_aizu_20260624_m32_jma_eq5` | `20260624132430` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:21:49` | `Iwate offshore` | `iwate_offshore_20260625_m32_jma` | `20260625192130` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `2026-06-26T23:04:00` | `Yamanashi east / Fuji Five Lakes` | `yamanashi_east_fuji_five_lakes_20260626_m26_jma_p2p` | `20260626230400` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `2026-06-26T23:17:46` | `Yamanashi east / Fuji Five Lakes` | `yamanashi_east_fuji_five_lakes_20260626_m33_jma_equake8` | `20260626231730` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `2026-06-26T22:29:02` | `Yamanashi east / Fuji Five Lakes` | `yamanashi_east_fuji_five_lakes_20260626_m56_jma_equake21` | `20260626222900` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260627_fukushima_aizu_m36_jma_equake17` | `2026-06-27T02:33:00` | `Fukushima Aizu` | `fukushima_aizu_20260627_m36_jma_equake17` | `20260627023300` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `2026-06-27T00:33:00` | `Yamanashi east / Fuji Five Lakes` | `yamanashi_east_fuji_five_lakes_20260627_m24_jma_p2p` | `20260627003300` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |
| `20260628_iwate_offshore_m41_jma` | `2026-06-28T14:39:37` | `Iwate offshore` | `iwate_offshore_20260628_m41_jma` | `20260628143930` | `none` | `0` | `candidate_directory_id_unconfirmed` | `confirm_nied_directory_id_then_download_waveforms` |

## Waveform-only Candidates

| Event | Origin JST | Directory id | Features | Downloads |
| --- | --- | --- | ---: | --- |
| `fukushima_offshore_20210213_m73` | `2021-02-13T23:07:50+09:00` | `20210213230800` | `2` | `success:4 failed:0 existing:2` |
| `fukushima_offshore_20220316_m74` | `2022-03-16T23:36:32+09:00` | `20220316233630` | `0` | `success:0 failed:4 existing:0` |
| `hokkaido_iburi_20180906_m66` | `2018-09-06T03:07:59+09:00` | `20180906030800` | `2` | `success:4 failed:0 existing:2` |
| `hyuganada_20240808_m71` | `2024-08-08T16:42:55+09:00` | `20240808164230` | `0` | `success:0 failed:4 existing:0` |
| `kumamoto_20160416_m73` | `2016-04-16T01:25:05+09:00` | `20160416012500` | `2` | `success:4 failed:0 existing:2` |
| `noto_peninsula_20240101_m76` | `2024-01-01T16:10:09+09:00` | `20240101161000` | `2` | `success:3 failed:1 existing:1` |

## Decision

- This report tracks whether local GIF capture fixtures already have a same-event official waveform path. It does not promote any case into frozen metrics and does not mutate runtime source estimation.
- `candidate_directory_id_unconfirmed` means the case is the current best overlap candidate, but its NIED waveform directory id still needs confirmation before download and feature generation.
- `capture_only_needs_waveform_candidate` means local GIF is present but the event has not yet been seeded into the waveform manifest.
