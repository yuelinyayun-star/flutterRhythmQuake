# Offshore Search Geometry Experiment

> Experimental replay only. Production remains on the baseline variant.

## Promotion/Rejection Matrix

| Case | Baseline P90 | Applied guard P90 | Candidate P90 | Candidate frames | Large-error coverage | Improved coverage | Decision | Reason |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `20260610_nara_m36` | 13.0 km | 13.0 km | - | 0 | - | - | `pass_no_candidate` | No high-uncertainty boundary candidate emitted; baseline is unchanged. |
| `20260620_iwate_offshore_m34_ref` | 54.0 km | 54.0 km | - | 0 | - | - | `pass_no_candidate` | No high-uncertainty boundary candidate emitted; baseline is unchanged. |
| `20260621_fukushima_offshore_m32_eq6` | 311.0 km | 168.0 km | 136.7 km | 8 | 8/47 | 7/47 | `reject_as_primary_fix` | Candidate does not cover all large-error frames; inspect residual and member evolution first. |
| `20260622_iwate_east_offshore_m30_hinet` | 51.0 km | 49.0 km | 63.6 km | 2 | 2/2 | 2/2 | `reject_regression_risk` | Candidate P90 is not better than the baseline P90. |
| `20260622_iwate_offshore_m30_eq10` | 54.4 km | 54.4 km | - | 0 | 0/3 | 0/3 | `pass_no_candidate` | No high-uncertainty boundary candidate emitted; baseline is unchanged. |
| `20260622_kushiro_offshore_m30_jma` | 118.2 km | 40.0 km | 24.1 km | 8 | 8/8 | 8/8 | `positive_boundary_candidate` | Candidate covers and improves every large-error frame in this case. |
| `20260622_tomakomai_south_offshore_m35_hinet` | 55.0 km | 31.0 km | 27.8 km | 3 | 3/3 | 3/3 | `positive_boundary_candidate` | Candidate covers and improves every large-error frame in this case. |

## Variant Replay Table

| Case | Variant | Estimates | First delay | Median error | P90 error | P90 jump | Candidate frames | Candidate median | Candidate P90 | P95 runtime |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260610_nara_m36` | `baseline` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 64363.0 us |
| `20260610_nara_m36` | `expanded` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 80819.0 us |
| `20260610_nara_m36` | `expanded_weak_center` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 73287.0 us |
| `20260610_nara_m36` | `centroid_guard` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 81715.5 us |
| `20260610_nara_m36` | `centroid_guard_high_uncertainty` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 69383.5 us |
| `20260610_nara_m36` | `centroid_guard_high_uncertainty_diagnostic` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 68818.5 us |
| `20260610_nara_m36` | `soft_geometry_001` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 70360.0 us |
| `20260610_nara_m36` | `soft_geometry_003` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 73324.0 us |
| `20260610_nara_m36` | `soft_geometry_010` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 68675.5 us |
| `20260610_nara_m36` | `soft_geometry_030` | 37 | 4.0 s | 8.0 km | 13.0 km | 8.0 km | 0 | - | - | 131622.0 us |
| `20260620_iwate_offshore_m34_ref` | `baseline` | 53 | 22.0 s | 43.0 km | 54.0 km | 21.4 km | 0 | - | - | 38281.5 us |
| `20260620_iwate_offshore_m34_ref` | `expanded` | 53 | 22.0 s | 49.0 km | 96.0 km | 21.8 km | 0 | - | - | 44623.0 us |
| `20260620_iwate_offshore_m34_ref` | `expanded_weak_center` | 53 | 22.0 s | 49.0 km | 96.0 km | 21.8 km | 0 | - | - | 42057.5 us |
| `20260620_iwate_offshore_m34_ref` | `centroid_guard` | 53 | 22.0 s | 49.0 km | 120.0 km | 30.1 km | 7 | 120.5 km | 121.0 km | 39836.5 us |
| `20260620_iwate_offshore_m34_ref` | `centroid_guard_high_uncertainty` | 53 | 22.0 s | 43.0 km | 54.0 km | 21.4 km | 0 | - | - | 37978.0 us |
| `20260620_iwate_offshore_m34_ref` | `centroid_guard_high_uncertainty_diagnostic` | 53 | 22.0 s | 43.0 km | 54.0 km | 21.4 km | 0 | - | - | 38033.5 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_001` | 53 | 22.0 s | 43.0 km | 54.0 km | 21.4 km | 0 | - | - | 43097.5 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_003` | 53 | 22.0 s | 43.0 km | 54.0 km | 21.4 km | 0 | - | - | 38100.5 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_010` | 53 | 22.0 s | 43.0 km | 54.0 km | 21.4 km | 0 | - | - | 38093.5 us |
| `20260620_iwate_offshore_m34_ref` | `soft_geometry_030` | 53 | 22.0 s | 43.0 km | 54.0 km | 21.4 km | 0 | - | - | 45213.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `baseline` | 47 | 38.0 s | 165.0 km | 311.0 km | 4.5 km | 0 | - | - | 32043.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `expanded` | 47 | 38.0 s | 168.0 km | 432.0 km | 27.0 km | 0 | - | - | 32445.0 us |
| `20260621_fukushima_offshore_m32_eq6` | `expanded_weak_center` | 47 | 38.0 s | 168.0 km | 432.0 km | 27.0 km | 0 | - | - | 32571.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `centroid_guard` | 47 | 38.0 s | 131.0 km | 168.0 km | 4.0 km | 8 | 132.3 km | 136.7 km | 32256.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `centroid_guard_high_uncertainty` | 47 | 38.0 s | 131.0 km | 168.0 km | 4.0 km | 8 | 132.3 km | 136.7 km | 30511.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `centroid_guard_high_uncertainty_diagnostic` | 47 | 38.0 s | 165.0 km | 311.0 km | 4.5 km | 8 | 132.3 km | 136.7 km | 31058.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_001` | 47 | 38.0 s | 165.0 km | 311.0 km | 4.5 km | 0 | - | - | 34256.0 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_003` | 47 | 38.0 s | 165.0 km | 311.0 km | 4.5 km | 0 | - | - | 34689.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_010` | 47 | 38.0 s | 165.0 km | 311.0 km | 4.5 km | 0 | - | - | 30747.5 us |
| `20260621_fukushima_offshore_m32_eq6` | `soft_geometry_030` | 47 | 38.0 s | 165.0 km | 311.0 km | 4.5 km | 0 | - | - | 30993.0 us |
| `20260622_iwate_east_offshore_m30_hinet` | `baseline` | 39 | 18.0 s | 40.0 km | 51.0 km | 16.3 km | 0 | - | - | 30797.0 us |
| `20260622_iwate_east_offshore_m30_hinet` | `expanded` | 39 | 18.0 s | 40.0 km | 51.0 km | 16.3 km | 0 | - | - | 33912.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `expanded_weak_center` | 39 | 18.0 s | 40.0 km | 51.0 km | 16.3 km | 0 | - | - | 34673.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `centroid_guard` | 39 | 18.0 s | 40.0 km | 68.0 km | 29.8 km | 7 | 67.8 km | 68.0 km | 34610.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `centroid_guard_high_uncertainty` | 39 | 18.0 s | 40.0 km | 49.0 km | 16.3 km | 2 | 63.6 km | 63.6 km | 37471.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `centroid_guard_high_uncertainty_diagnostic` | 39 | 18.0 s | 40.0 km | 51.0 km | 16.3 km | 2 | 63.6 km | 63.6 km | 34629.0 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_001` | 39 | 18.0 s | 40.0 km | 51.0 km | 24.3 km | 0 | - | - | 32697.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_003` | 39 | 18.0 s | 40.0 km | 51.0 km | 16.3 km | 0 | - | - | 34429.0 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_010` | 39 | 18.0 s | 40.0 km | 51.0 km | 16.3 km | 0 | - | - | 33012.5 us |
| `20260622_iwate_east_offshore_m30_hinet` | `soft_geometry_030` | 39 | 18.0 s | 40.0 km | 51.0 km | 16.3 km | 0 | - | - | 35020.5 us |
| `20260622_iwate_offshore_m30_eq10` | `baseline` | 47 | 29.0 s | 24.0 km | 54.4 km | 22.0 km | 0 | - | - | 31472.0 us |
| `20260622_iwate_offshore_m30_eq10` | `expanded` | 47 | 29.0 s | 24.0 km | 60.0 km | 14.5 km | 0 | - | - | 39270.0 us |
| `20260622_iwate_offshore_m30_eq10` | `expanded_weak_center` | 47 | 29.0 s | 24.0 km | 60.0 km | 14.0 km | 0 | - | - | 35114.0 us |
| `20260622_iwate_offshore_m30_eq10` | `centroid_guard` | 47 | 29.0 s | 17.0 km | 54.4 km | 7.0 km | 0 | - | - | 32482.5 us |
| `20260622_iwate_offshore_m30_eq10` | `centroid_guard_high_uncertainty` | 47 | 29.0 s | 24.0 km | 54.4 km | 22.0 km | 0 | - | - | 33824.0 us |
| `20260622_iwate_offshore_m30_eq10` | `centroid_guard_high_uncertainty_diagnostic` | 47 | 29.0 s | 24.0 km | 54.4 km | 22.0 km | 0 | - | - | 31645.5 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_001` | 47 | 29.0 s | 24.0 km | 54.4 km | 22.0 km | 0 | - | - | 34861.5 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_003` | 47 | 29.0 s | 24.0 km | 54.4 km | 22.0 km | 0 | - | - | 35012.0 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_010` | 47 | 29.0 s | 24.0 km | 54.4 km | 22.0 km | 0 | - | - | 37025.5 us |
| `20260622_iwate_offshore_m30_eq10` | `soft_geometry_030` | 47 | 29.0 s | 24.0 km | 54.4 km | 28.5 km | 0 | - | - | 34632.0 us |
| `20260622_kushiro_offshore_m30_jma` | `baseline` | 42 | 11.0 s | 28.0 km | 118.2 km | 30.0 km | 0 | - | - | 33347.5 us |
| `20260622_kushiro_offshore_m30_jma` | `expanded` | 42 | 11.0 s | 28.0 km | 237.0 km | 30.0 km | 0 | - | - | 35580.5 us |
| `20260622_kushiro_offshore_m30_jma` | `expanded_weak_center` | 42 | 11.0 s | 28.0 km | 238.1 km | 30.0 km | 0 | - | - | 36862.0 us |
| `20260622_kushiro_offshore_m30_jma` | `centroid_guard` | 42 | 11.0 s | 25.0 km | 40.0 km | 25.0 km | 8 | 22.5 km | 24.1 km | 35956.0 us |
| `20260622_kushiro_offshore_m30_jma` | `centroid_guard_high_uncertainty` | 42 | 11.0 s | 25.0 km | 40.0 km | 25.0 km | 8 | 22.5 km | 24.1 km | 35649.0 us |
| `20260622_kushiro_offshore_m30_jma` | `centroid_guard_high_uncertainty_diagnostic` | 42 | 11.0 s | 28.0 km | 118.2 km | 30.0 km | 8 | 22.5 km | 24.1 km | 34764.0 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_001` | 42 | 11.0 s | 28.0 km | 116.2 km | 30.0 km | 0 | - | - | 33605.5 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_003` | 42 | 11.0 s | 28.0 km | 116.2 km | 30.0 km | 0 | - | - | 37668.5 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_010` | 42 | 11.0 s | 28.0 km | 109.9 km | 30.0 km | 0 | - | - | 39242.0 us |
| `20260622_kushiro_offshore_m30_jma` | `soft_geometry_030` | 42 | 11.0 s | 28.0 km | 84.7 km | 25.0 km | 0 | - | - | 33889.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `baseline` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 0 | - | - | 32721.5 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `expanded` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 0 | - | - | 40906.5 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `expanded_weak_center` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 0 | - | - | 37887.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `centroid_guard` | 42 | 29.0 s | 13.0 km | 31.0 km | 27.0 km | 3 | 27.8 km | 27.8 km | 34231.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `centroid_guard_high_uncertainty` | 42 | 29.0 s | 13.0 km | 31.0 km | 27.0 km | 3 | 27.8 km | 27.8 km | 37054.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `centroid_guard_high_uncertainty_diagnostic` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 3 | 27.8 km | 27.8 km | 39045.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_001` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 0 | - | - | 36776.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_003` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 0 | - | - | 36766.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_010` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 0 | - | - | 36009.0 us |
| `20260622_tomakomai_south_offshore_m35_hinet` | `soft_geometry_030` | 42 | 29.0 s | 13.0 km | 55.0 km | 27.0 km | 0 | - | - | 36194.0 us |
