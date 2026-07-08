$ErrorActionPreference = 'Stop'

dart run tools\build_plum_replay_capture_gap_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\plum_replay_capture_gap_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
