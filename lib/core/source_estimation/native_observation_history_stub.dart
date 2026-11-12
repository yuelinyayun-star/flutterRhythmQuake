import 'dart:typed_data';
import 'native_observation_snapshot.dart';
import 'native_observation_commit.dart';
import 'native_nied_observation_summary.dart';

class NativeObservationHistory {
  NativeObservationHistory() {
    throw UnsupportedError('Native observation history unavailable');
  }
  static bool get supported => false;
  static Map<String, int> get diagnostics => const {};
  static void batchUpdates(void Function() action) => action();
  int get length => 0;
  int get capacityBytes => 0;
  int append(Int64List row, int cutoffUs) =>
      throw UnsupportedError('Native observation history unavailable');
  void appendDeferred(
    Int64List row,
    int cutoffUs,
    NativeObservationCommit owner,
  ) => throw UnsupportedError('Native observation history unavailable');
  NativeObservationSnapshot snapshot() =>
      throw UnsupportedError('Native observation history unavailable');
  NativeNiedObservationSummary niedSummary(DateTime? observedAt) =>
      throw UnsupportedError('Native observation history unavailable');
  double? pretriggerSeconds(DateTime earliest, DateTime fallback) =>
      throw UnsupportedError('Native observation history unavailable');
  bool fastRiseExceeds(DateTime observedAt, int digit) =>
      throw UnsupportedError('Native observation history unavailable');
  void clear() {}
  void dispose() {}
}
