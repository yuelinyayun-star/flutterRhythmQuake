import 'eew_event_group.dart';

class EewHistoryRetention {
  static const defaultMaxPerSource = 15;
  static const maxPerSourceKey = 'eew_history_max_per_source';
  static const keepForeverKey = 'eew_history_keep_forever';

  final int maxPerSource;
  final bool keepForever;

  const EewHistoryRetention({
    this.maxPerSource = defaultMaxPerSource,
    this.keepForever = false,
  }) : assert(maxPerSource > 0);

  List<EewEventGroup> apply(Iterable<EewEventGroup> groups) {
    final ordered = groups.toList()
      ..sort((a, b) => b.firstArrivedAt.compareTo(a.firstArrivedAt));
    if (keepForever) return ordered;
    final counts = <String, int>{};
    return ordered.where((group) {
      final source = group.latest.source;
      final count = counts.update(
        source,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      return count <= maxPerSource;
    }).toList();
  }
}
