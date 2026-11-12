import 'dart:typed_data';

/// Owned outputs; no view into a native session survives a scoring call.
class NativeHypScoreResult {
  const NativeHypScoreResult(this.values, this.waves);
  final Float64List values;
  final Int8List waves;
  static const scenarioWords = 16;
  static const outputWords = 3 + 6 * scenarioWords;
}
