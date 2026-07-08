$ErrorActionPreference = 'Stop'

dart run tools\build_source_candidate_region_timeline_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_candidate_region_timeline_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
