enum FdsnSourceConnectionState { connecting, streaming, failed, idle }

/// Display-only health summary. Observation timestamps and stream selection
/// remain owned by the receiver; no packet or intensity values are rewritten.
class FdsnSourceStatus {
  const FdsnSourceStatus({
    required this.source,
    required this.state,
    this.selected = 0,
    this.timely = 0,
    this.delayed = 0,
    this.stale = 0,
    this.missing = 0,
  });

  final String source;
  final FdsnSourceConnectionState state;
  final int selected;
  final int timely;
  final int delayed;
  final int stale;
  final int missing;

  static const timelyAge = Duration(seconds: 30);
  static const usableAge = Duration(minutes: 3);

  int get linked =>
      state == FdsnSourceConnectionState.streaming ? timely + delayed : 0;

  // Each station has one vote, regardless of its channel count or packet rate.
  double get delayScore => selected == 0
      ? 0
      : ((delayed * .5 + stale + missing) / selected).clamp(0.0, 1.0);

  factory FdsnSourceStatus.fromObservations({
    required String source,
    required FdsnSourceConnectionState state,
    required Iterable<DateTime?> observations,
    required DateTime now,
  }) {
    var selected = 0, timely = 0, delayed = 0, stale = 0, missing = 0;
    final epoch = now.microsecondsSinceEpoch;
    for (final observation in observations) {
      selected++;
      final age = observation == null
          ? null
          : epoch - observation.microsecondsSinceEpoch;
      if (age == null || age < 0) {
        missing++;
      } else if (age <= timelyAge.inMicroseconds) {
        timely++;
      } else if (age <= usableAge.inMicroseconds) {
        delayed++;
      } else {
        stale++;
      }
    }
    return FdsnSourceStatus(
      source: source,
      state: state,
      selected: selected,
      timely: timely,
      delayed: delayed,
      stale: stale,
      missing: missing,
    );
  }

  Map<String, Object> toJson() => {
    'source': source,
    'state': state.name,
    'selected': selected,
    'timely': timely,
    'delayed': delayed,
    'stale': stale,
    'missing': missing,
  };

  static FdsnSourceStatus? fromJson(Map raw) {
    final source = raw['source'];
    final state = FdsnSourceConnectionState.values
        .where((s) => s.name == raw['state'])
        .firstOrNull;
    final counts = [
      raw['selected'],
      raw['timely'],
      raw['delayed'],
      raw['stale'],
      raw['missing'],
    ];
    if (source is! String ||
        state == null ||
        counts.any((v) => v is! int || v < 0)) {
      return null;
    }
    final values = counts.cast<int>();
    if (values.skip(1).fold(0, (a, b) => a + b) != values[0]) return null;
    return FdsnSourceStatus(
      source: source,
      state: state,
      selected: values[0],
      timely: values[1],
      delayed: values[2],
      stale: values[3],
      missing: values[4],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FdsnSourceStatus &&
      source == other.source &&
      state == other.state &&
      selected == other.selected &&
      timely == other.timely &&
      delayed == other.delayed &&
      stale == other.stale &&
      missing == other.missing;

  @override
  int get hashCode =>
      Object.hash(source, state, selected, timely, delayed, stale, missing);
}
