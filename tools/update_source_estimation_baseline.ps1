$ErrorActionPreference = 'Stop'

flutter test test/source_estimation_batch_test.dart `
  --dart-define=SOURCE_ESTIMATION_UPDATE_BASELINE=true `
  --reporter expanded

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
