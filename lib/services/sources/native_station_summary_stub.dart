import 'dart:typed_data';
import 'native_ka_history.dart';

class NativeStationSummary {
  static bool get supported => false;
  static Map<String, int> get diagnostics => const {};
  NativeStationSummary() {
    throw UnsupportedError('Native station summary');
  }
  void update(
    int kind,
    int count,
    void Function(Float64List) write, {
    List<String> codes = const [],
    List<String> regions = const [],
    bool reuseText = false,
  }) => throw UnsupportedError('Native station summary');
  void cells(int count, void Function(Float64List) write) =>
      throw UnsupportedError('Native station summary');
  void niedLevels(int count, void Function(Int32List) write) =>
      throw UnsupportedError('Native station summary');
  void niedKaResults(
    NativeKaHistorySession producer,
    void Function(Uint8List) writeActive,
  ) => throw UnsupportedError('Native station summary');
  List<int> get indices => throw UnsupportedError('Native station summary');
  T readIndices<T>(T Function(List<int>) bind) =>
      throw UnsupportedError('Native station summary');
  List<(String, int)> get areas =>
      throw UnsupportedError('Native station summary');
  void dispose() {}
}
