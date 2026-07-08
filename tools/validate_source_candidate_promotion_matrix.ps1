$ErrorActionPreference = 'Stop'

dart run tools\build_source_estimation_early_frame_report.dart `
  --input-directory .dart_tool\source_estimation_benchmark `
  --output-directory .dart_tool\source_estimation_early_frame_report\matrix `
  --markdown-directory .dart_tool\source_estimation_early_frame_report\matrix_md
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_candidate_promotion_report.dart `
  --input .dart_tool\source_estimation_early_frame_report\matrix `
  --output .dart_tool\source_candidate_promotion_report\matrix.json `
  --markdown docs\baselines\source_candidate_promotion_matrix.generated.md
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_candidate_promotion_matrix_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
