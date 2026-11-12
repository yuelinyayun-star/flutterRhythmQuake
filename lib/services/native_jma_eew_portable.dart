/// Explicit compatibility for platforms without the station-core native API.
abstract final class NativeJmaEew {
  static bool get supported => false;
  static int? longPeriodClass({
    required String source,
    required bool isEew,
    required Object? value,
  }) {
    if (source != 'jmaEew' || !isEew || (value is! String && value is! num)) {
      return null;
    }
    final parsed = double.tryParse(value.toString().trim());
    return parsed != null &&
            parsed.isFinite &&
            parsed >= 0 &&
            parsed <= 4 &&
            parsed == parsed.truncateToDouble()
        ? parsed.toInt()
        : null;
  }

  static bool isPlum({
    required String source,
    required bool isEew,
    required bool isAssumption,
    required bool wireIsPlum,
  }) => source == 'jmaEew' && isEew && (isAssumption || wireIsPlum);
}
