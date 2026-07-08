$ErrorActionPreference = 'Stop'

flutter test test\source_surface_image_only_comparison_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
