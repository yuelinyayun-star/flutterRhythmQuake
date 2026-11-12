import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../services/sources/native_station_core_library_io.dart';
import 'knet_batch.dart';

typedef _Native =
    Int32 Function(
      Pointer<Pointer<Double>>,
      Pointer<IntPtr>,
      Pointer<IntPtr>,
      Pointer<Double>,
      IntPtr,
      IntPtr,
      Double,
      Double,
      IntPtr,
      Double,
      Pointer<Double>,
    );
typedef _Dart =
    int Function(
      Pointer<Pointer<Double>>,
      Pointer<IntPtr>,
      Pointer<IntPtr>,
      Pointer<Double>,
      int,
      int,
      double,
      double,
      int,
      double,
      Pointer<Double>,
    );

// Look up lazily, only after checking platform/override availability.
final _Dart _batch = StationCoreLibrary.library.lookupFunction<_Native, _Dart>(
  'rq_knet_batch_features',
);

List<KnetBatchSecond>? compute({
  required List<List<double>?> components,
  required List<int> starts,
  required List<double> offsetsGal,
  required int sampleCount,
  required int samplesPerSecond,
  required double samplingHz,
  required double durationSeconds,
  required int baselineSeconds,
  required double epsilon,
}) {
  if (!Platform.isWindows || !StationCoreLibrary.supported) {
    return null;
  }
  if (components.length != 3 ||
      starts.length != 3 ||
      offsetsGal.length != 3 ||
      sampleCount < 1 ||
      sampleCount > 4000000 ||
      samplesPerSecond < 1 ||
      samplesPerSecond > sampleCount ||
      !samplingHz.isFinite ||
      samplingHz <= 0 ||
      !durationSeconds.isFinite ||
      !epsilon.isFinite ||
      offsetsGal.any((v) => !v.isFinite)) {
    return null;
  }
  for (var i = 0; i < 3; i++) {
    final data = components[i];
    if (data == null) {
      continue;
    }
    if (data.length > 4000000 ||
        starts[i] < 0 ||
        starts[i] > data.length ||
        sampleCount > data.length - starts[i]) {
      return null;
    }
    // Preserve Dart fallback semantics for non-finite values.
    if (data.skip(starts[i]).take(sampleCount).any((v) => !v.isFinite)) {
      return null;
    }
  }
  final channels = calloc<Pointer<Double>>(3);
  final lengths = calloc<IntPtr>(3);
  final offsets = calloc<IntPtr>(3);
  final dc = calloc<Double>(3);
  final secondCount = sampleCount ~/ samplesPerSecond;
  final result = calloc<Double>(secondCount * 6);
  try {
    for (var axis = 0; axis < 3; axis++) {
      dc[axis] = offsetsGal[axis];
      final values = components[axis];
      if (values == null) {
        channels[axis] = nullptr;
        continue;
      }
      final buffer = calloc<Double>(values.length);
      channels[axis] = buffer;
      lengths[axis] = values.length;
      offsets[axis] = starts[axis];
      for (var i = 0; i < values.length; i++) {
        buffer[i] = values[i];
      }
    }
    final code = _batch(
      channels,
      lengths,
      offsets,
      dc,
      sampleCount,
      samplesPerSecond,
      samplingHz,
      durationSeconds,
      baselineSeconds,
      epsilon,
      result,
    );
    if (code != 0) return null;
    double? optional(double n) => n.isNaN ? null : n;
    return List<KnetBatchSecond>.generate(secondCount, (s) {
      final row = s * 6;
      return KnetBatchSecond(
        pga: result[row],
        horizontalPga: result[row + 1],
        pgv: result[row + 2],
        rms: result[row + 3],
        energyRatio: optional(result[row + 4]),
        intensityProxy: optional(result[row + 5]),
      );
    }, growable: false);
  } finally {
    for (var i = 0; i < 3; i++) {
      if (channels[i] != nullptr) calloc.free(channels[i]);
    }
    calloc.free(channels);
    calloc.free(lengths);
    calloc.free(offsets);
    calloc.free(dc);
    calloc.free(result);
  }
}
