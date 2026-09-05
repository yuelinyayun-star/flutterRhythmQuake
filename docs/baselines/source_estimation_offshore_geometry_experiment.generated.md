# Offshore Search Geometry Experiment

> Experimental replay only. Production remains on the baseline variant.

## Promotion/Rejection Matrix

| Case | Baseline P90 | Applied guard P90 | Candidate P90 | Candidate frames | Large-error coverage | Improved coverage | Decision | Reason |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `20260610_nara_m36` | 10.8 km | 10.8 km | - | 0 | - | - | `pass_no_candidate` | No high-uncertainty boundary candidate emitted; baseline is unchanged. |
| `20260620_iwate_offshore_m34_ref` | 83.0 km | 83.0 km | - | 0 | - | - | `pass_no_candidate` | No high-uncertainty boundary candidate emitted; baseline is unchanged. |
| `20260621_fukushima_offshore_m32_eq6` | 184.4 km | 188.0 km | - | 0 | 0/47 | 0/47 | `pass_no_candidate` | No high-uncertainty boundary candidate emitted; baseline is unchanged. |
| `20260622_iwate_east_offshore_m30_hinet` | 56.6 km | 56.6 km | 61.0 km | 2 | 2/2 | 2/2 | `reject_regression_risk` | Candidate P90 is not better than the baseline P90. |
| `20260622_iwate_offshore_m30_eq10` | 54.0 km | 54.0 km | - | 0 | 0/3 | 0/3 | `pass_no_candidate` | No high-uncertainty boundary candidate emitted; baseline is unchanged. |
| `20260622_kushiro_offshore_m30_jma` | 28.0 km | 20.1 km | 14.2 km | 1 | 1/1 | 1/1 | `positive_boundary_candidate` | Candidate covers and improves every large-error frame in this case. |
| `20260622_tomakomai_south_offshore_m35_hinet` | 50.1 km | 94.0 km | 95.8 km | 2 | - | - | `reject_regression_risk` | Candidate P90 is not better than the baseline P90. |

## Variant Replay Table

| Case | Variant | Estimates | First delay | Median error | P90 error | P90 jump | Candidate frames | Candidate median | Candidate P90 | P95 runtime |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260610_nara_m36` | `baseline` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 928692.0 us |
| `20260610_nara_m36` | `expanded` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 1285251.5 us |
| `20260610_nara_m36` | `expanded_weak_center` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 1111944.0 us |
| `20260610_nara_m36` | `centroid_guard` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 547487.0 us |
| `20260610_nara_m36` | `centroid_guard_high_uncertainty` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 549809.0 us |
| `20260610_nara_m36` | `centroid_guard_high_uncertainty_diagnostic` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 652970.0 us |
| `20260610_nara_m36` | `soft_geometry_001` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 573418.0 us |
| `20260610_nara_m36` | `soft_geometry_003` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 556211.0 us |
| `20260610_nara_m36` | `soft_geometry_010` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 528299.0 us |
| `20260610_nara_m36` | `soft_geometry_030` | 37 | 4.0 s | 7.0 km | 10.8 km | 10.0 km | 0 | - | - | 559185.5 us |
| `20260620_iwate_offshore_m34_ref` | `baseline` | 56 | 22.0 s | 43.0 km | 83.0 km | 20.0 km | 0 | - | - | 410772.0 us |
| `20260620_iwate_offshore_m34_ref` | `expanded` | 56 | 22.0 s | 43.0 km | 83.0 km | 20.0 km | 0 | - | - | 947049.5 us |
| `20260620_iwate_offshore_m34_ref` | `expanded_weak_center` | 56 | 22.0 s | 43.0 km | 82.0 km | 20.0 km | 0 | - | - | 1211235.5 us |
| `20260620_iwate_offshore_m34_ref` | `centroid_guard` | 56 | 22.0 s | 43.0 km | 83.0 km | 20.0 km | 3 | 124.2 km | 127.1 km | 505083.5 us |
| `20260620_iwate_offshore_m34_ref` | `centroid_guard_high_uncertainty` | 56 | 22.0 s | 43.0 km | 83.0 km | 21.8 km | 3 | 124.2 km | 127.1 km | 496034.5 us |
| `20260620_iwate_offshore_m34_ref` | `centroid_guard_high_uncertainty_diagnostic` | 56 | 22.0 s | 43.0 km | 83.0 km | 20.0 km | 0 | - | - | 400949.5 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_001` | 56 | 22.0 s | 43.0 km | 83.0 km | 20.0 km | 0 | - | - | 403431.0 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_003` | 56 | 22.0 s | 43.0 km | 83.0 km | 20.0 km | 0 | - | - | 380744.5 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_010` | 56 | 22.0 s | 43.0 km | 83.0 km | 20.0 km | 0 | - | - | 408493.0 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_030` | 56 | 22.0 s | 43.0 km | 83.0 km | 21.8 km | 0 | - | - | 478011.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `baseline` | 47 | 38.0 s | 141.0 km | 184.4 km | 18.0 km | 0 | - | - | 337786.0 us |
| `20260621_fukushima_offshore_m32_eq6` | `expanded` | 47 | 38.0 s | 182.0 km | 182.0 km | 0.0 km | 0 | - | - | 269107.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `expanded_weak_center` | 47 | 38.0 s | 216.0 km | 216.0 km | 0.0 km | 0 | - | - | 214370.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `centroid_guard` | 47 | 38.0 s | 154.0 km | 188.0 km | 50.5 km | 14 | 139.8 km | 139.8 km | 266556.0 us |
| `20260621_fukushima_offshore_m32_eq6` | `centroid_guard_high_uncertainty` | 47 | 38.0 s | 154.0 km | 188.0 km | 49.0 km | 12 | 139.8 km | 139.8 km | 338426.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `centroid_guard_high_uncertainty_diagnostic` | 47 | 38.0 s | 141.0 km | 184.4 km | 18.0 km | 0 | - | - | 275716.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_001` | 47 | 38.0 s | 141.0 km | 184.4 km | 18.0 km | 0 | - | - | 278231.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_003` | 47 | 38.0 s | 141.0 km | 184.4 km | 18.0 km | 0 | - | - | 267900.0 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_010` | 47 | 38.0 s | 141.0 km | 184.4 km | 18.0 km | 0 | - | - | 275744.0 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_030` | 47 | 38.0 s | 141.0 km | 206.0 km | 34.0 km | 0 | - | - | 277308.0 us |
| `20260622_iwate_east_offshore_m30_hinet` | `baseline` | 39 | 18.0 s | 43.0 km | 56.6 km | 19.3 km | 0 | - | - | 320665.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `expanded` | 39 | 18.0 s | 43.0 km | 56.6 km | 21.8 km | 0 | - | - | 898051.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `expanded_weak_center` | 39 | 18.0 s | 43.0 km | 56.6 km | 22.7 km | 0 | - | - | 741983.0 us |
| `20260622_iwate_east_offshore_m30_hinet` | `centroid_guard` | 39 | 18.0 s | 43.0 km | 56.6 km | 19.0 km | 2 | 63.6 km | 63.6 km | 359540.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `centroid_guard_high_uncertainty` | 39 | 18.0 s | 43.0 km | 56.6 km | 19.3 km | 2 | 63.6 km | 63.6 km | 324153.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `centroid_guard_high_uncertainty_diagnostic` | 39 | 18.0 s | 43.0 km | 56.6 km | 19.3 km | 2 | 61.0 km | 61.0 km | 373922.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_001` | 39 | 18.0 s | 43.0 km | 56.6 km | 19.3 km | 0 | - | - | 362704.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_003` | 39 | 18.0 s | 43.0 km | 56.6 km | 17.6 km | 0 | - | - | 342191.0 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_010` | 39 | 18.0 s | 43.0 km | 56.6 km | 17.6 km | 0 | - | - | 307341.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_030` | 39 | 18.0 s | 43.0 km | 56.6 km | 17.6 km | 0 | - | - | 303596.0 us |
| `20260622_iwate_offshore_m30_eq10` | `baseline` | 47 | 29.0 s | 27.0 km | 54.0 km | 25.5 km | 0 | - | - | 324731.0 us |
| `20260622_iwate_offshore_m30_eq10` | `expanded` | 47 | 29.0 s | 30.0 km | 54.0 km | 25.5 km | 0 | - | - | 864131.0 us |
| `20260622_iwate_offshore_m30_eq10` | `expanded_weak_center` | 47 | 29.0 s | 30.0 km | 54.0 km | 26.0 km | 0 | - | - | 809447.5 us |
| `20260622_iwate_offshore_m30_eq10` | `centroid_guard` | 47 | 29.0 s | 30.0 km | 54.0 km | 25.5 km | 0 | - | - | 353122.5 us |
| `20260622_iwate_offshore_m30_eq10` | `centroid_guard_high_uncertainty` | 47 | 29.0 s | 28.0 km | 54.0 km | 25.5 km | 0 | - | - | 407614.0 us |
| `20260622_iwate_offshore_m30_eq10` | `centroid_guard_high_uncertainty_diagnostic` | 47 | 29.0 s | 27.0 km | 54.0 km | 25.5 km | 0 | - | - | 415476.0 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_001` | 47 | 29.0 s | 27.0 km | 54.0 km | 25.5 km | 0 | - | - | 323333.5 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_003` | 47 | 29.0 s | 27.0 km | 54.0 km | 25.5 km | 0 | - | - | 325795.5 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_010` | 47 | 29.0 s | 27.0 km | 54.0 km | 25.5 km | 0 | - | - | 344914.0 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_030` | 47 | 29.0 s | 27.0 km | 54.0 km | 25.5 km | 0 | - | - | 425166.5 us |
| `20260622_kushiro_offshore_m30_jma` | `baseline` | 44 | 11.0 s | 17.0 km | 28.0 km | 11.0 km | 0 | - | - | 665424.0 us |
| `20260622_kushiro_offshore_m30_jma` | `expanded` | 44 | 11.0 s | 13.0 km | 28.0 km | 10.8 km | 0 | - | - | 1306422.0 us |
| `20260622_kushiro_offshore_m30_jma` | `expanded_weak_center` | 44 | 11.0 s | 13.0 km | 28.0 km | 10.8 km | 0 | - | - | 1611077.0 us |
| `20260622_kushiro_offshore_m30_jma` | `centroid_guard` | 44 | 11.0 s | 13.0 km | 19.8 km | 11.0 km | 3 | 14.2 km | 14.2 km | 629018.0 us |
| `20260622_kushiro_offshore_m30_jma` | `centroid_guard_high_uncertainty` | 44 | 11.0 s | 15.0 km | 20.1 km | 13.4 km | 3 | 14.2 km | 14.2 km | 516831.0 us |
| `20260622_kushiro_offshore_m30_jma` | `centroid_guard_high_uncertainty_diagnostic` | 44 | 11.0 s | 17.0 km | 28.0 km | 11.0 km | 1 | 14.2 km | 14.2 km | 524810.5 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_001` | 44 | 11.0 s | 17.0 km | 28.0 km | 11.0 km | 0 | - | - | 473680.0 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_003` | 44 | 11.0 s | 17.0 km | 28.0 km | 11.0 km | 0 | - | - | 623582.5 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_010` | 44 | 11.0 s | 17.0 km | 28.0 km | 11.0 km | 0 | - | - | 473910.5 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_030` | 44 | 11.0 s | 17.0 km | 28.0 km | 11.0 km | 0 | - | - | 479097.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `baseline` | 42 | 29.0 s | 13.0 km | 50.1 km | 26.0 km | 0 | - | - | 397574.5 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `expanded` | 42 | 29.0 s | 13.0 km | 52.0 km | 13.0 km | 0 | - | - | 877591.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `expanded_weak_center` | 42 | 29.0 s | 13.0 km | 52.0 km | 13.0 km | 0 | - | - | 869346.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `centroid_guard` | 42 | 29.0 s | 12.0 km | 94.0 km | 26.0 km | 3 | 93.9 km | 93.9 km | 396734.5 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `centroid_guard_high_uncertainty` | 42 | 29.0 s | 12.0 km | 94.0 km | 26.0 km | 3 | 93.9 km | 93.9 km | 401973.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `centroid_guard_high_uncertainty_diagnostic` | 42 | 29.0 s | 13.0 km | 50.1 km | 26.0 km | 2 | 95.8 km | 95.8 km | 410423.5 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_001` | 42 | 29.0 s | 13.0 km | 50.1 km | 26.0 km | 0 | - | - | 513012.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_003` | 42 | 29.0 s | 17.0 km | 49.4 km | 18.0 km | 0 | - | - | 390059.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_010` | 42 | 29.0 s | 16.0 km | 49.4 km | 18.0 km | 0 | - | - | 393175.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_030` | 42 | 29.0 s | 22.0 km | 50.5 km | 18.0 km | 0 | - | - | 400072.5 us |
