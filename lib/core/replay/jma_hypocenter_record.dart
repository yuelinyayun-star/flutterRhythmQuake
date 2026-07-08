import 'jma_catalog.dart';

/// Parses JMA's 96-byte fixed-width hypocenter record.
class JmaHypocenterRecordParser {
  const JmaHypocenterRecordParser();

  JmaCatalogEvent? parse(String line) {
    if (line.length < 96 || _field(line, 1, 1) != 'J') return null;
    final determinationFlag = _field(line, 96, 96);
    if (determinationFlag == 'N' || determinationFlag == 'F') return null;

    final year = _integer(line, 2, 5);
    final month = _integer(line, 6, 7);
    final day = _integer(line, 8, 9);
    final hour = _integer(line, 10, 11);
    final minute = _integer(line, 12, 13);
    final secondHundredths = _integer(line, 14, 17);
    final latitudeDegrees = _integer(line, 22, 24);
    final latitudeMinutes = _impliedDecimal(line, 25, 28, 2);
    final longitudeDegrees = _integer(line, 33, 36);
    final longitudeMinutes = _impliedDecimal(line, 37, 40, 2);
    if ([
      year,
      month,
      day,
      hour,
      minute,
      secondHundredths,
      latitudeDegrees,
      latitudeMinutes,
      longitudeDegrees,
      longitudeMinutes,
    ].any((value) => value == null)) {
      return null;
    }

    final second = secondHundredths! ~/ 100;
    final milliseconds = (secondHundredths % 100) * 10;
    final originTime = DateTime.utc(
      year!,
      month!,
      day!,
      hour! - 9,
      minute!,
      second,
      milliseconds,
    );
    final latitude = latitudeDegrees! + latitudeMinutes! / 60;
    final longitude = longitudeDegrees! + longitudeMinutes! / 60;
    final depthKm = _depth(line);
    final magnitude = _magnitude(_field(line, 53, 54));
    final eventId = _eventId(originTime, latitude, longitude, depthKm);

    return JmaCatalogEvent(
      eventId: eventId,
      resourceId: 'jma:hypocenter:$eventId',
      revision: 'from_catalog_file',
      status: determinationFlag == 'K' ? 'final' : 'reviewed',
      originTime: originTime,
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      magnitude: magnitude,
      region: _asciiRegion(_field(line, 69, 92)),
      sourceUrl: null,
      metadata: {
        'recordType': 'J',
        'magnitudeType': _field(line, 55, 55).trim(),
        'travelTimeTable': _field(line, 59, 59).trim(),
        'hypocenterEvaluation': _field(line, 60, 60).trim(),
        'hypocenterAuxiliary': _field(line, 61, 61).trim(),
        'maximumIntensity': _field(line, 62, 62).trim(),
        'stationCount': _integer(line, 93, 95),
        'determinationFlag': determinationFlag,
      },
    );
  }

  double? _depth(String line) {
    final raw = _field(line, 45, 49);
    if (raw.trim().isEmpty) return null;
    if (raw.endsWith('  ')) {
      return double.tryParse(raw.substring(0, 3).trim());
    }
    return _impliedDecimal(line, 45, 49, 2);
  }

  double? _magnitude(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (RegExp(r'^[A-Z]\d$').hasMatch(value)) {
      final decade = value.codeUnitAt(0) - 'A'.codeUnitAt(0) + 1;
      return -(decade + int.parse(value.substring(1)) / 10);
    }
    final numeric = int.tryParse(value);
    return numeric == null ? null : numeric / 10;
  }

  String _eventId(
    DateTime originTime,
    double latitude,
    double longitude,
    double? depthKm,
  ) {
    String two(int value) => value.toString().padLeft(2, '0');
    final jst = originTime.add(const Duration(hours: 9));
    return '${jst.year}${two(jst.month)}${two(jst.day)}'
        '${two(jst.hour)}${two(jst.minute)}${two(jst.second)}'
        '${two(jst.millisecond ~/ 10)}-'
        '${latitude.toStringAsFixed(4)}-'
        '${longitude.toStringAsFixed(4)}-'
        '${(depthKm ?? -1).toStringAsFixed(2)}';
  }

  String _asciiRegion(String value) {
    if (value.codeUnits.any((code) => code < 0x20 || code > 0x7e)) return '';
    return value.trim();
  }

  String _field(String line, int start, int end) =>
      line.substring(start - 1, end);

  int? _integer(String line, int start, int end) =>
      int.tryParse(_field(line, start, end).trim());

  double? _impliedDecimal(String line, int start, int end, int decimalPlaces) {
    final raw = _field(line, start, end).trim();
    if (raw.isEmpty) return null;
    if (raw.contains('.')) return double.tryParse(raw);
    final value = int.tryParse(raw);
    if (value == null) return null;
    var divisor = 1;
    for (var i = 0; i < decimalPlaces; i++) {
      divisor *= 10;
    }
    return value / divisor;
  }
}
