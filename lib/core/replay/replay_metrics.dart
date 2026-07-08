class ReplayMetricDistribution {
  final int count;
  final double? min;
  final double? median;
  final double? p90;
  final double? p95;
  final double? max;

  const ReplayMetricDistribution({
    required this.count,
    required this.min,
    required this.median,
    required this.p90,
    required this.p95,
    required this.max,
  });

  Map<String, Object?> toJson() => {
    'count': count,
    'min': min,
    'median': median,
    'p90': p90,
    'p95': p95,
    'max': max,
  };
}

class ReplayMetricCalculator {
  const ReplayMetricCalculator._();

  static double? percentile(List<double> values, double percentile) {
    if (percentile < 0 || percentile > 1) {
      throw RangeError.range(percentile, 0, 1, 'percentile');
    }
    if (values.isEmpty) return null;
    final sorted = List<double>.from(values)..sort();
    if (sorted.length == 1) return sorted.single;
    final position = (sorted.length - 1) * percentile;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final fraction = position - lower;
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
  }

  static ReplayMetricDistribution distribution(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    return ReplayMetricDistribution(
      count: sorted.length,
      min: sorted.isEmpty ? null : sorted.first,
      median: percentile(sorted, 0.5),
      p90: percentile(sorted, 0.9),
      p95: percentile(sorted, 0.95),
      max: sorted.isEmpty ? null : sorted.last,
    );
  }

  static double? ratio(int numerator, int denominator) {
    if (denominator < 0) {
      throw RangeError.value(denominator, 'denominator');
    }
    if (denominator == 0) return null;
    return numerator / denominator;
  }

  static double zeroWhenNoDenominatorRatio(int numerator, int denominator) {
    return ratio(numerator, denominator) ?? 0;
  }
}
