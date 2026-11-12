// One native call yields per-second K-NET numerical features for a station group.
// Returns null on unsupported platforms or invalid inputs (Dart fallback).
import 'knet_batch_stub.dart'
    if (dart.library.io) 'knet_batch_io.dart'
    as implementation;

class KnetBatchSecond {
  const KnetBatchSecond({
    required this.pga,
    required this.horizontalPga,
    required this.pgv,
    required this.rms,
    required this.energyRatio,
    required this.intensityProxy,
  });

  final double pga;
  final double horizontalPga;
  final double pgv;
  final double rms;
  final double? energyRatio;
  final double? intensityProxy;
}

List<KnetBatchSecond>? nativeKnetBatchFeatures({
  required List<List<double>?> components,
  required List<int> starts,
  required List<double> offsetsGal,
  required int sampleCount,
  required int samplesPerSecond,
  required double samplingHz,
  required double durationSeconds,
  required int baselineSeconds,
  required double epsilon,
}) => implementation.compute(
  components: components,
  starts: starts,
  offsetsGal: offsetsGal,
  sampleCount: sampleCount,
  samplesPerSecond: samplesPerSecond,
  samplingHz: samplingHz,
  durationSeconds: durationSeconds,
  baselineSeconds: baselineSeconds,
  epsilon: epsilon,
);
