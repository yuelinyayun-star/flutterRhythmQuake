# K-NET GIF/Waveform Directory ID Confirmation Worklist

- Status: `pass`
- Readiness report: `.dart_tool/knet_gif_waveform_alignment_readiness/report.json`
- Items: `8`
- Directory id unconfirmed: `8`
- Capture-only: `0`

## Validation

- Errors: none
- Warnings: none

## Items

| Priority | Case | Origin JST | Region | Candidate event | Directory id | Distance km | Time delta s | Next action |
| --- | --- | --- | --- | --- | --- | ---: | ---: | --- |
| `0` | `20260621_iwate_offshore_m33_eq8` | `2026-06-21T11:32:12` | `Iwate offshore` | `iwate_offshore_20260621_m33_equake_ref` | `20260621113200` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |
| `0` | `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:12` | `Kushiro offshore` | `kushiro_offshore_20260622_m30_jma` | `20260622163800` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |
| `0` | `20260624_fukushima_aizu_m32_jma_eq5` | `2026-06-24T13:24:45` | `Fukushima Aizu` | `fukushima_aizu_20260624_m32_jma_eq5` | `20260624132430` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |
| `0` | `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:21:49` | `Iwate offshore` | `iwate_offshore_20260625_m32_jma` | `20260625192130` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |
| `0` | `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `2026-06-26T22:29:02` | `Yamanashi east / Fuji Five Lakes` | `yamanashi_east_fuji_five_lakes_20260626_m56_jma_equake21` | `20260626222900` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |
| `0` | `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `2026-06-26T23:17:46` | `Yamanashi east / Fuji Five Lakes` | `yamanashi_east_fuji_five_lakes_20260626_m33_jma_equake8` | `20260626231730` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |
| `0` | `20260627_fukushima_aizu_m36_jma_equake17` | `2026-06-27T02:33:00` | `Fukushima Aizu` | `fukushima_aizu_20260627_m36_jma_equake17` | `20260627023300` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |
| `0` | `20260628_iwate_offshore_m41_jma` | `2026-06-28T14:39:37` | `Iwate offshore` | `iwate_offshore_20260628_m41_jma` | `20260628143930` | 0.0 | 0 | `confirm_nied_directory_id_then_download_waveforms` |

## Decision

- This worklist is diagnostic-only and does not change source estimation or frozen metrics.
- The `candidate_directory_id_unconfirmed` rows are the immediate confirmation targets; `capture_only_needs_waveform_candidate` rows remain queued for later seeding.
