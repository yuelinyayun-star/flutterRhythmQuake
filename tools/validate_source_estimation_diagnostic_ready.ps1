$ErrorActionPreference = 'Stop'

dart run tools\build_source_estimation_diagnostic_ready_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_estimation_diagnostic_ready_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
