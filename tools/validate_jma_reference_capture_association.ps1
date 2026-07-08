$ErrorActionPreference = 'Stop'

dart run tools\build_jma_reference_capture_association_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_jma_reference_capture_review_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\jma_reference_capture_association_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\jma_reference_capture_review_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\jma_reference_capture_package_import_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
