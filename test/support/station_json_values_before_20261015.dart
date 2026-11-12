// Frozen original WHEWS numeric loops; only the kind flag is supplied directly.
class FrozenStationJsonValues {
  FrozenStationJsonValues({bool kma = false}) : _kma = kma;
  final bool _kma;
  List<double>? primary(List<dynamic> raw) => _readPrimaryValues(raw);
  List<double>? motion(dynamic raw, int count) =>
      _readOptionalMotionValues(raw, count);
  List<double>? _readPrimaryValues(List<dynamic> raw) {
    final values = <double>[];
    for (final item in raw) {
      final value = _number(item);
      if (value == null || !value.isFinite) return null;
      final isInRange = _kma
          ? value >= -3 && value <= 11
          : value >= -3 && value <= 7;
      if (!isInRange) {
        return null;
      }
      values.add(value);
    }
    return List.unmodifiable(values);
  }

  List<double>? _readOptionalMotionValues(dynamic raw, int expectedLength) {
    if (raw == null) return const [];
    if (raw is! List || raw.length != expectedLength) return null;
    final values = <double>[];
    for (final item in raw) {
      final value = _number(item);
      if (value == null || !value.isFinite || value < 0) return null;
      values.add(value);
    }
    return List.unmodifiable(values);
  }

  double? _number(dynamic raw) {
    return switch (raw) {
      num value => value.toDouble(),
      String value => double.tryParse(value),
      _ => null,
    };
  }
}
