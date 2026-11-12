// Field diagnostics log, enabled only by `--dart-define=RQ_FIELD_LOG=true`
// (cloud/field builds). Native platforms write through the Rust rolling log
// writer; web builds and normal builds compile to no-ops.
export 'field_diagnostics_stub.dart'
    if (dart.library.io) 'field_diagnostics_io.dart';
