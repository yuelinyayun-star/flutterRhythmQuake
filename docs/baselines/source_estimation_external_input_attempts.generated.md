# Source Estimation External Input Attempts

- Status: `pass`
- Queue: `.dart_tool/source_estimation_external_input_queue/report.json`
- Attempts: `docs/data/source_estimation_external_input_attempts.json`
- Attempt count: `18`
- Automatic clearances: `0`
- Negative-attempt-only rows: `18`

## Input Type Counts

| Input type | Count |
| --- | ---: |
| `authenticated_hinet_export_row` | 6 |
| `final_catalog_or_hinet_revision` | 1 |
| `local_jma_reference_capture_package` | 4 |
| `missing_gif_archive_copy` | 4 |
| `versioned_jma_final_catalog_record` | 3 |

## Validation

- Errors: none
- Warnings: `attempt_references_nonqueued_input:missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`, `attempt_references_nonqueued_input:missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`, `attempt_references_nonqueued_input:missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`, `attempt_references_nonqueued_input:missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`, `attempt_references_nonqueued_input:local_jma_reference_capture_package::20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21`, `attempt_references_nonqueued_input:local_jma_reference_capture_package::20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8`, `attempt_references_nonqueued_input:authenticated_hinet_export_row::20260622_iwate_east_offshore_m30_hinet`, `attempt_references_nonqueued_input:authenticated_hinet_export_row::20260622_tomakomai_south_offshore_m35_hinet`, `attempt_references_nonqueued_input:authenticated_hinet_export_row::20260623_tokachi_southeast_offshore_m34_hinet`, `attempt_references_nonqueued_input:authenticated_hinet_export_row::20260622_iwate_east_offshore_m30_hinet`, `attempt_references_nonqueued_input:authenticated_hinet_export_row::20260622_tomakomai_south_offshore_m35_hinet`, `attempt_references_nonqueued_input:authenticated_hinet_export_row::20260623_tokachi_southeast_offshore_m34_hinet`

## Attempts

| Case | Type | Method | Target | Result | Clearance |
| --- | --- | --- | --- | --- | --- |
| `20260620_iwate_offshore_m34_ref` | `missing_gif_archive_copy` | `local_exact_filename_extended_scan` | 20260620212727.jma_b.gif | `not_found` | `false` |
| `20260620_iwate_offshore_m34_ref` | `missing_gif_archive_copy` | `remote_hint_recheck` | https://www.kmoni.bosai.go.jp/data/map_img/RealTimeImg/jma_b/2026/06/20/20260620212727.jma_b.gif | `connection_failed_or_timed_out` | `false` |
| `20260620_iwate_offshore_m34_ref` | `missing_gif_archive_copy` | `local_exact_filename_rescan` | 20260620212727.jma_b.gif | `not_found` | `false` |
| `20260620_iwate_offshore_m34_ref` | `missing_gif_archive_copy` | `local_exact_filename_scan` | 20260620212727.jma_b.gif | `not_found` | `false` |
| `20260621_iwate_offshore_m33_eq8` | `final_catalog_or_hinet_revision` | `official_jma_final_catalog_and_hinet_revision_availability_check` | https://www.data.jma.go.jp/eqev/data/bulletin/hypo.html; https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en; https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en | `no_versioned_catalog_or_authenticated_revision_available` | `false` |
| `20260622_iwate_east_offshore_m30_hinet` | `authenticated_hinet_export_row` | `authenticated_source_login_page_check` | https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en; https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en | `login_required_no_exported_row` | `false` |
| `20260622_iwate_east_offshore_m30_hinet` | `authenticated_hinet_export_row` | `authenticated_source_form_login_check` | https://hinetwww11.bosai.go.jp/auth/?LANG=en -> https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en; https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en | `form_login_returned_login_page` | `false` |
| `20260622_kushiro_offshore_m30_jma` | `versioned_jma_final_catalog_record` | `official_jma_final_catalog_availability_check` | https://www.data.jma.go.jp/eqev/data/bulletin/hypo.html | `event_year_not_in_latest_final_catalog` | `false` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `authenticated_hinet_export_row` | `authenticated_source_login_page_check` | https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en; https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en | `login_required_no_exported_row` | `false` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `authenticated_hinet_export_row` | `authenticated_source_form_login_check` | https://hinetwww11.bosai.go.jp/auth/?LANG=en -> https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en; https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en | `form_login_returned_login_page` | `false` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `authenticated_hinet_export_row` | `authenticated_source_login_page_check` | https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en; https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en | `login_required_no_exported_row` | `false` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `authenticated_hinet_export_row` | `authenticated_source_form_login_check` | https://hinetwww11.bosai.go.jp/auth/?LANG=en -> https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en; https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en | `form_login_returned_login_page` | `false` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `versioned_jma_final_catalog_record` | `official_jma_final_catalog_availability_check` | https://www.data.jma.go.jp/eqev/data/bulletin/hypo.html | `event_year_not_in_latest_final_catalog` | `false` |
| `20260625_iwate_offshore_m32_jma` | `versioned_jma_final_catalog_record` | `official_jma_final_catalog_availability_check` | https://www.data.jma.go.jp/eqev/data/bulletin/hypo.html | `event_year_not_in_latest_final_catalog` | `false` |
| `20260625_iwate_offshore_m46_jma_eqsc9` | `local_jma_reference_capture_package` | `local_timestamp_keyword_capture_scan` | 202606260110*, 202606260111*, 202606260112*, iwate, 岩手 | `not_found` | `false` |
| `20260626_yamanashi_central_west_m26_jma_equake5` | `local_jma_reference_capture_package` | `local_timestamp_keyword_capture_scan` | 202606261540*, 202606261541*, 202606261542*, yamanashi, 山梨 | `not_found` | `false` |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `local_jma_reference_capture_package` | `local_timestamp_keyword_capture_scan` | 202606262316*, 202606262317*, 202606262318*, yamanashi, fuji, 山梨, 富士 | `not_found` | `false` |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `local_jma_reference_capture_package` | `local_timestamp_keyword_capture_scan` | 202606262228*, 202606262229*, 202606262230*, yamanashi, fuji, 山梨, 富士 | `not_found` | `false` |

## Decision

- These attempts are operational notes only. They do not clear capture repair, source truth, final catalog or split blockers.
- A negative attempt is not proof that an input is impossible to obtain; it only prevents repeated untracked searches.
