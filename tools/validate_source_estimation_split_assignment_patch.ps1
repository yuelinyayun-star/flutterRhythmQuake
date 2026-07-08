$ErrorActionPreference = 'Stop'

dart run tools\build_source_estimation_split_assignment_patch.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_estimation_split_assignment_patch_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
