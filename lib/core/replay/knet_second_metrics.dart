import 'knet_second_metrics_stub.dart'
    if (dart.library.io) 'knet_second_metrics_io.dart'
    as implementation;

class KnetSecondMetrics {
  const KnetSecondMetrics(
    this.vectors,
    this.pga,
    this.pgv,
    this.sumSquare,
    this.horizontalPga,
    this.finalVelocities,
  );
  final List<double> vectors;
  final double pga;
  final double pgv;
  final double sumSquare;
  final double horizontalPga;
  final List<double> finalVelocities;
}

KnetSecondMetrics? nativeKnetSecondMetrics(
  List<double>? ns,
  List<double>? ew,
  List<double>? ud,
  int start,
  int count,
  double dt,
  List<double> initial,
) => implementation.calculate(ns, ew, ud, start, count, dt, initial);
