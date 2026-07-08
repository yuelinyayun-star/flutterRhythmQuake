$ErrorActionPreference = 'Stop'

flutter test test\source_estimation_batch_test.dart `
  test\quiet_window_20260625_replay_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_trigger_threshold_review_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_trigger_threshold_review_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
