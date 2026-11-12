import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../services/sources/native_station_core_library_io.dart';

typedef NativeAlign =
    Int32 Function(
      Pointer<Double>,
      IntPtr,
      IntPtr,
      IntPtr,
      Double,
      Pointer<Double>,
    );
typedef DartAlign =
    int Function(Pointer<Double>, int, int, int, double, Pointer<Double>);

final DartAlign _align = StationCoreLibrary.library
    .lookupFunction<NativeAlign, DartAlign>('rq_knet_align_component');

List<double>? align(
  List<double> samples,
  int offset,
  int count,
  double offsetGal,
) {
  if (!Platform.isWindows ||
      !StationCoreLibrary.supported ||
      count <= 0 ||
      count > 4000000 ||
      offset < 0 ||
      offset > samples.length ||
      count > samples.length - offset ||
      !offsetGal.isFinite) {
    return null;
  }
  final input = calloc<Double>(samples.length);
  final output = calloc<Double>(count);
  try {
    for (var i = 0; i < samples.length; i++) {
      input[i] = samples[i];
    }
    if (_align(input, samples.length, offset, count, offsetGal, output) != 0) {
      return null;
    }
    return List<double>.generate(count, (i) => output[i], growable: false);
  } finally {
    calloc.free(input);
    calloc.free(output);
  }
}
