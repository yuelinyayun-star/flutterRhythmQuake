import 'dart:convert';

class FdsnChannelSensitivity {
  const FdsnChannelSensitivity(
    this.sensitivity,
    this.unit,
    this.start,
    this.end, {
    this.latitude,
    this.longitude,
    this.elevation,
  });
  final double sensitivity;
  final String unit;
  final DateTime start;
  final DateTime? end;
  final double? latitude;
  final double? longitude;
  final double? elevation;

  bool covers(DateTime time) =>
      !time.isBefore(start) && (end == null || time.isBefore(end!));

  static DateTime? _utc(String value) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value.endsWith('Z') ? value : '${value}Z');
  }

  /// FDSN station level=channel text Scale is InstrumentSensitivity.Value.
  static FdsnChannelSensitivity? parse(
    String text, {
    required String network,
    required String station,
    required String location,
    required String channel,
    required DateTime time,
  }) {
    FdsnChannelSensitivity? selected;
    for (final line in const LineSplitter().convert(text)) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final c = line.split('|').map((v) => v.trim()).toList(growable: false);
      if (c.length < 17 ||
          c[0] != network ||
          c[1] != station ||
          c[2] != location ||
          c[3] != channel) {
        continue;
      }
      final scale = double.tryParse(c[11]);
      final start = _utc(c[15]);
      final end = _utc(c[16]);
      if (scale == null ||
          !scale.isFinite ||
          scale <= 0 ||
          start == null ||
          (c[16].isNotEmpty && end == null)) {
        continue;
      }
      final parsed = FdsnChannelSensitivity(
        scale,
        c[13].toUpperCase(),
        start,
        end,
        latitude: double.tryParse(c[4]),
        longitude: double.tryParse(c[5]),
        elevation: double.tryParse(c[6]),
      );
      if (parsed.covers(time) &&
          (selected == null || start.isAfter(selected.start))) {
        selected = parsed;
      }
    }
    return selected;
  }
}
