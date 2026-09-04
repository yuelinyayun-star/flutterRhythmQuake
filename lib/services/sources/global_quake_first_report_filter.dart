class GlobalQuakeFirstReportMagnitudeFilter {
  GlobalQuakeFirstReportMagnitudeFilter({
    double threshold = 0,
    this.maxTrackedEvents = 512,
  }) : _threshold = _normalizeThreshold(threshold);

  final int maxTrackedEvents;
  final Map<String, GlobalQuakeFirstReportDecision> _decisions = {};
  double _threshold;

  double get threshold => _threshold;

  void configure(double threshold) {
    final normalized = _normalizeThreshold(threshold);
    if (normalized == _threshold) return;
    _threshold = normalized;
    _decisions.clear();
  }

  GlobalQuakeFirstReportDecision evaluate({
    required String eventId,
    required double magnitude,
  }) {
    if (_threshold <= 0) {
      return GlobalQuakeFirstReportDecision(
        firstMagnitude: magnitude,
        allowed: true,
        isFirstReceivedReport: true,
      );
    }

    final existing = _decisions[eventId];
    if (existing != null) {
      return GlobalQuakeFirstReportDecision(
        firstMagnitude: existing.firstMagnitude,
        allowed: existing.allowed,
        isFirstReceivedReport: false,
      );
    }

    final decision = GlobalQuakeFirstReportDecision(
      firstMagnitude: magnitude,
      allowed: magnitude.isFinite && magnitude >= _threshold,
      isFirstReceivedReport: true,
    );
    _decisions[eventId] = decision;
    while (_decisions.length > maxTrackedEvents) {
      _decisions.remove(_decisions.keys.first);
    }
    return decision;
  }

  static double _normalizeThreshold(double threshold) {
    if (!threshold.isFinite) return 0;
    return threshold.clamp(0.0, 10.0).toDouble();
  }
}

class GlobalQuakeFirstReportDecision {
  const GlobalQuakeFirstReportDecision({
    required this.firstMagnitude,
    required this.allowed,
    required this.isFirstReceivedReport,
  });

  final double firstMagnitude;
  final bool allowed;
  final bool isFirstReceivedReport;
}
