import 'dart:collection';

class KaHistoryResult {
  const KaHistoryResult(
    this.level,
    this.ascend,
    this.triggerStamp,
    this.activity,
    this.abnormalUpdateCount,
  );
  final int level, ascend, triggerStamp;
  final double activity;
  final int? abnormalUpdateCount;
}

/// Original newest-first KA levels, with optional native calculation ownership.
abstract class KaStationHistory extends ListBase<int> {
  bool get isNative;

  /// An independently owned, growable snapshot of the original history.
  List<int> detachedCopy();
  KaHistoryResult update({
    required int level,
    required int expireSeconds,
    required int baseTimeMilliseconds,
    required bool isActive,
    required int? abnormalUpdateCount,
  });
  void replace(Iterable<int> values);
}
