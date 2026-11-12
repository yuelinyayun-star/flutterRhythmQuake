import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'knet_second_metrics.dart';
import '../../services/sources/native_station_core_library_io.dart';

typedef _Native =
    Int32 Function(
      Pointer<Double>,
      IntPtr,
      Double,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
    );
typedef _Dart =
    int Function(
      Pointer<Double>,
      int,
      double,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
    );

final _Dart _compute = StationCoreLibrary.library
    .lookupFunction<_Native, _Dart>('rq_knet_second_metrics');

KnetSecondMetrics? calculate(
  List<double>? ns,
  List<double>? ew,
  List<double>? ud,
  int start,
  int count,
  double dt,
  List<double> initial,
) {
  if (!Platform.isWindows || !StationCoreLibrary.supported) {
    return null;
  }
  if (count <= 0 ||
      count > 4000000 ||
      initial.length != 3 ||
      !dt.isFinite ||
      dt <= 0 ||
      start < 0 ||
      initial.any((v) => !v.isFinite) ||
      (ns != null && ns.length < start + count) ||
      (ew != null && ew.length < start + count) ||
      (ud != null && ud.length < start + count)) {
    return null;
  }
  final xyz = calloc<Double>(count * 3);
  final velocities = calloc<Double>(3);
  final vectors = calloc<Double>(count);
  final metrics = calloc<Double>(7);
  try {
    for (var i = 0; i < count; i++) {
      xyz[i * 3] = ns?[start + i] ?? 0;
      xyz[i * 3 + 1] = ew?[start + i] ?? 0;
      xyz[i * 3 + 2] = ud?[start + i] ?? 0;
    }
    for (var i = 0; i < 3; i++) {
      velocities[i] = initial[i];
    }
    if (_compute(xyz, count, dt, velocities, vectors, metrics) != 0) {
      return null;
    }
    return KnetSecondMetrics(
      List<double>.generate(count, (i) => vectors[i], growable: false),
      metrics[0],
      metrics[1],
      metrics[2],
      metrics[3],
      [metrics[4], metrics[5], metrics[6]],
    );
  } finally {
    calloc.free(xyz);
    calloc.free(velocities);
    calloc.free(vectors);
    calloc.free(metrics);
  }
}
