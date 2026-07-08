$ErrorActionPreference = 'Stop'

dart run tools\build_source_estimation_split_assignment_readiness_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_estimation_split_assignment_readiness_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
