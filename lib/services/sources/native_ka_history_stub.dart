import 'ka_station_history.dart';

class NativeKaHistorySession {
  NativeKaHistorySession(int count) {
    throw UnsupportedError('Native KA history requires Windows');
  }
  static bool get supported => false;
  int get count => throw UnsupportedError('Native KA history requires Windows');
  static Map<String, int> get diagnostics => const {};
  List<KaStationHistory> get histories =>
      throw UnsupportedError('Native KA history requires Windows');
  void writeInput(
    int index, {
    required int level,
    required int expireSeconds,
    required int baseTimeMilliseconds,
    required bool isActive,
    required int? abnormalUpdateCount,
  }) => throw UnsupportedError('Native KA history requires Windows');
  void process() =>
      throw UnsupportedError('Native KA history requires Windows');
  void writeShindoInput(
    int index, {
    required double shindo,
    required int expireSeconds,
    required bool isActive,
  }) => throw UnsupportedError('Native KA history requires Windows');
  void setShindoAbnormalCount(int index, int? value) =>
      throw UnsupportedError('Native KA history requires Windows');
  void processShindoFrame(int originalTimeMilliseconds) =>
      throw UnsupportedError('Native KA history requires Windows');
  void resetShindoClock() =>
      throw UnsupportedError('Native KA history requires Windows');
  int observationFlags(int index) =>
      throw UnsupportedError('Native KA history requires Windows');
  KaHistoryResult result(int index) =>
      throw UnsupportedError('Native KA history requires Windows');
  void reset() => throw UnsupportedError('Native KA history requires Windows');
  void dispose() {}
}
