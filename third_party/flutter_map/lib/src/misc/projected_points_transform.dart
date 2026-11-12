import 'dart:ui';

/// Optional batch backend. Inputs are immutable projected geometry; output must
/// retain order, every point, and the scalar transformation operation order.
class ProjectedPointsTransform {
  static List<Offset> Function(List<Offset>, List<List<Offset>>?, double,
      double, double, double, double, double, double, double, double)? batch;
}
