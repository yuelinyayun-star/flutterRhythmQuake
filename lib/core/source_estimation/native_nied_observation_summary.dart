import 'dart:typed_data';

/// Owned result values only; neither history rows nor native pointers escape.
class NativeNiedObservationSummary {
  NativeNiedObservationSummary(this.values);
  final Float64List values;

  double change(int seconds, int fallbackAscend) {
    final index = switch (seconds) {
      1 => 0,
      4 => 1,
      9 => 2,
      _ => throw ArgumentError.value(seconds),
    };
    return values[8].toInt() & (1 << index) != 0
        ? values[index]
        : fallbackAscend.toDouble();
  }

  double immediateChange(int fallbackAscend) =>
      values[8].toInt() & 8 != 0 ? values[3] : fallbackAscend.toDouble();
}
