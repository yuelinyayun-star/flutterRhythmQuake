import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../services/sources/native_station_core_library_io.dart';

typedef _Native = Double Function(Pointer<Double>, IntPtr, Double, Double);
typedef _Dart = double Function(Pointer<Double>, int, double, double);

final _Dart _compute = StationCoreLibrary.library
    .lookupFunction<_Native, _Dart>('rq_knet_duration_proxy');

double? calculate(List<double> values, double hz, double duration) {
  if (!Platform.isWindows || !StationCoreLibrary.supported) return null;
  if (values.isEmpty ||
      values.length > 4000000 ||
      !hz.isFinite ||
      hz <= 0 ||
      !duration.isFinite ||
      values.any((x) => !x.isFinite)) {
    return null;
  }
  final samples = calloc<Double>(values.length);
  try {
    for (var i = 0; i < values.length; i++) {
      samples[i] = values[i];
    }
    final result = _compute(samples, values.length, hz, duration);
    return result.isNaN ? double.nan : result;
  } finally {
    calloc.free(samples);
  }
}
