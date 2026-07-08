import 'dart:convert';
import 'dart:typed_data';

class JmaIntensityStation {
  final String stationId;
  final double latitude;
  final double longitude;
  final DateTime? activeFrom;
  final DateTime? activeUntil;
  final String rawNameHex;

  const JmaIntensityStation({
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.activeFrom,
    required this.activeUntil,
    required this.rawNameHex,
  });

  bool wasActiveAt(DateTime instant) {
    if (activeFrom != null && instant.isBefore(activeFrom!)) return false;
    if (activeUntil != null && instant.isAfter(activeUntil!)) return false;
    return true;
  }

  Map<String, Object?> toJson() => {
    'stationId': stationId,
    'latitude': latitude,
    'longitude': longitude,
    'activeFrom': activeFrom?.toIso8601String(),
    'activeUntil': activeUntil?.toIso8601String(),
    'rawNameHex': rawNameHex,
  };
}

class JmaIntensityObservation {
  final String stationId;
  final DateTime? onsetTime;
  final String intensityClass;
  final double? instrumentalIntensity;
  final DateTime? peakAccelerationTime;
  final double? peakAccelerationGal;
  final double? northSouthAccelerationGal;
  final double? eastWestAccelerationGal;
  final double? verticalAccelerationGal;

  const JmaIntensityObservation({
    required this.stationId,
    required this.onsetTime,
    required this.intensityClass,
    required this.instrumentalIntensity,
    required this.peakAccelerationTime,
    required this.peakAccelerationGal,
    required this.northSouthAccelerationGal,
    required this.eastWestAccelerationGal,
    required this.verticalAccelerationGal,
  });

  Map<String, Object?> toJson({JmaIntensityStation? station}) => {
    'stationId': stationId,
    'latitude': station?.latitude,
    'longitude': station?.longitude,
    'onsetTime': onsetTime?.toIso8601String(),
    'intensityClass': intensityClass,
    'instrumentalIntensity': instrumentalIntensity,
    'peakAccelerationTime': peakAccelerationTime?.toIso8601String(),
    'peakAccelerationGal': peakAccelerationGal,
    'northSouthAccelerationGal': northSouthAccelerationGal,
    'eastWestAccelerationGal': eastWestAccelerationGal,
    'verticalAccelerationGal': verticalAccelerationGal,
  };
}

class JmaIntensityHypocenter {
  final String recordType;
  final DateTime originTime;
  final double latitude;
  final double longitude;
  final double? depthKm;
  final double? magnitude;
  final String magnitudeType;
  final String maximumIntensityClass;
  final int? intensityStationCount;
  final String determinationFlag;
  final String rawRegionHex;

  const JmaIntensityHypocenter({
    required this.recordType,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
    required this.magnitudeType,
    required this.maximumIntensityClass,
    required this.intensityStationCount,
    required this.determinationFlag,
    required this.rawRegionHex,
  });

  Map<String, Object?> toJson() => {
    'recordType': recordType,
    'originTime': originTime.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
    'magnitudeType': magnitudeType,
    'maximumIntensityClass': maximumIntensityClass,
    'intensityStationCount': intensityStationCount,
    'determinationFlag': determinationFlag,
    'rawRegionHex': rawRegionHex,
  };
}

class JmaIntensityEvent {
  final String eventId;
  final List<JmaIntensityHypocenter> hypocenters;
  final List<JmaIntensityObservation> observations;

  const JmaIntensityEvent({
    required this.eventId,
    required this.hypocenters,
    required this.observations,
  });

  JmaIntensityHypocenter get preferredHypocenter => hypocenters.first;

  Map<String, Object?> toJson(Map<String, JmaIntensityStation> stations) => {
    'eventId': eventId,
    'preferredHypocenter': preferredHypocenter.toJson(),
    'alternateHypocenters': hypocenters
        .skip(1)
        .map((item) => item.toJson())
        .toList(growable: false),
    'observations': observations
        .map((item) => item.toJson(station: stations[item.stationId]))
        .toList(growable: false),
  };
}

class JmaIntensityStationTableParser {
  const JmaIntensityStationTableParser();

  Map<String, JmaIntensityStation> parse(Uint8List bytes) {
    final stations = <String, JmaIntensityStation>{};
    for (final line in _splitLines(bytes)) {
      final fields = _splitBytes(line, 0x09);
      if (fields.length < 6) continue;
      final stationId = _ascii(fields[0]).trim();
      final latitude = _degreeMinute(_ascii(fields[2]));
      final longitude = _degreeMinute(_ascii(fields[3]));
      if (stationId.isEmpty || latitude == null || longitude == null) continue;
      stations[stationId] = JmaIntensityStation(
        stationId: stationId,
        latitude: latitude,
        longitude: longitude,
        activeFrom: _stationDate(_ascii(fields[4])),
        activeUntil: _stationDate(_ascii(fields[5])),
        rawNameHex: _hex(fields[1]),
      );
    }
    return stations;
  }

  double? _degreeMinute(String raw) {
    final value = raw.trim();
    if (value.length < 4) return null;
    final degreeDigits = value.length - 2;
    final degrees = int.tryParse(value.substring(0, degreeDigits));
    final minutes = int.tryParse(value.substring(degreeDigits));
    if (degrees == null || minutes == null || minutes >= 60) return null;
    return degrees + minutes / 60.0;
  }

  DateTime? _stationDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.length != 12) return null;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    final day = int.tryParse(value.substring(6, 8));
    final hour = int.tryParse(value.substring(8, 10));
    final minute = int.tryParse(value.substring(10, 12));
    if ([year, month, day, hour, minute].any((item) => item == null)) {
      return null;
    }
    if (year == 9999 ||
        month == 99 ||
        day == 99 ||
        hour == 99 ||
        minute == 99) {
      return null;
    }
    return _jstToUtc(year!, month!, day!, hour!, minute!, 0, 0);
  }
}

class JmaIntensityArchiveParser {
  const JmaIntensityArchiveParser();

  List<JmaIntensityEvent> parse(Uint8List bytes) {
    final events = <JmaIntensityEvent>[];
    var hypocenters = <JmaIntensityHypocenter>[];
    var observations = <JmaIntensityObservation>[];

    void flush() {
      if (hypocenters.isEmpty) return;
      final preferred = hypocenters.first;
      events.add(
        JmaIntensityEvent(
          eventId: _eventId(preferred),
          hypocenters: List.unmodifiable(hypocenters),
          observations: List.unmodifiable(observations),
        ),
      );
      hypocenters = <JmaIntensityHypocenter>[];
      observations = <JmaIntensityObservation>[];
    }

    for (final lineBytes in _splitLines(bytes)) {
      if (lineBytes.length < 96) continue;
      final record = Uint8List.sublistView(lineBytes, 0, 96);
      final recordType = String.fromCharCode(record[0]);
      if (recordType == 'A') {
        flush();
        final hypocenter = _parseHypocenter(record);
        if (hypocenter != null) hypocenters.add(hypocenter);
      } else if (recordType == 'B' || recordType == 'D') {
        final hypocenter = _parseHypocenter(record);
        if (hypocenter != null) hypocenters.add(hypocenter);
      } else if (hypocenters.isNotEmpty &&
          record[0] >= 0x30 &&
          record[0] <= 0x39) {
        final observation = _parseObservation(
          record,
          hypocenters.first.originTime,
        );
        if (observation != null) observations.add(observation);
      }
    }
    flush();
    return events;
  }

  JmaIntensityHypocenter? _parseHypocenter(Uint8List record) {
    final year = _intField(record, 2, 5);
    final month = _intField(record, 6, 7);
    final day = _intField(record, 8, 9);
    final hour = _intField(record, 10, 11);
    final minute = _intField(record, 12, 13);
    final secondHundredths = _intField(record, 14, 17);
    final latitudeDegrees = _intField(record, 22, 24);
    final latitudeMinutes = _decimalField(record, 25, 28, 2);
    final longitudeDegrees = _intField(record, 33, 36);
    final longitudeMinutes = _decimalField(record, 37, 40, 2);
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
    ].any((item) => item == null)) {
      return null;
    }
    return JmaIntensityHypocenter(
      recordType: _field(record, 1, 1),
      originTime: _jstToUtc(
        year!,
        month!,
        day!,
        hour!,
        minute!,
        secondHundredths! ~/ 100,
        (secondHundredths % 100) * 10,
      ),
      latitude: latitudeDegrees! + latitudeMinutes! / 60,
      longitude: longitudeDegrees! + longitudeMinutes! / 60,
      depthKm: _depth(record),
      magnitude: _magnitude(_field(record, 53, 54)),
      magnitudeType: _field(record, 55, 55).trim(),
      maximumIntensityClass: _field(record, 62, 62).trim(),
      intensityStationCount: _intField(record, 91, 95),
      determinationFlag: _field(record, 96, 96),
      rawRegionHex: _hex(Uint8List.sublistView(record, 68, 90)),
    );
  }

  JmaIntensityObservation? _parseObservation(
    Uint8List record,
    DateTime eventOrigin,
  ) {
    final stationId = _field(record, 1, 7).trim();
    if (stationId.isEmpty) return null;
    return JmaIntensityObservation(
      stationId: stationId,
      onsetTime: _observationTime(
        eventOrigin,
        day: _intField(record, 9, 10),
        hour: _intField(record, 11, 12),
        minute: _intField(record, 13, 14),
        secondTenths: _intField(record, 15, 17),
      ),
      intensityClass: _field(record, 19, 19).trim(),
      instrumentalIntensity: _decimalField(record, 21, 22, 1),
      peakAccelerationTime: _peakTime(
        eventOrigin,
        minute: _intField(record, 24, 25),
        secondTenths: _intField(record, 26, 28),
      ),
      peakAccelerationGal: _decimalField(record, 30, 34, 1),
      northSouthAccelerationGal: _decimalField(record, 37, 41, 1),
      eastWestAccelerationGal: _decimalField(record, 44, 48, 1),
      verticalAccelerationGal: _decimalField(record, 51, 55, 1),
    );
  }

  DateTime? _observationTime(
    DateTime eventOrigin, {
    required int? day,
    required int? hour,
    required int? minute,
    required int? secondTenths,
  }) {
    if ([day, hour, minute, secondTenths].any((item) => item == null)) {
      return null;
    }
    final eventJst = eventOrigin.add(const Duration(hours: 9));
    var year = eventJst.year;
    var month = eventJst.month;
    if (day! < eventJst.day - 20) {
      month++;
      if (month == 13) {
        month = 1;
        year++;
      }
    } else if (day > eventJst.day + 20) {
      month--;
      if (month == 0) {
        month = 12;
        year--;
      }
    }
    return _jstToUtc(
      year,
      month,
      day,
      hour!,
      minute!,
      secondTenths! ~/ 10,
      (secondTenths % 10) * 100,
    );
  }

  DateTime? _peakTime(
    DateTime eventOrigin, {
    required int? minute,
    required int? secondTenths,
  }) {
    if (minute == null || secondTenths == null) return null;
    final eventJst = eventOrigin.add(const Duration(hours: 9));
    var hour = eventJst.hour;
    if (minute < eventJst.minute - 30) {
      hour++;
    } else if (minute > eventJst.minute + 30) {
      hour--;
    }
    final base = DateTime(
      eventJst.year,
      eventJst.month,
      eventJst.day,
      hour,
      minute,
      secondTenths ~/ 10,
      (secondTenths % 10) * 100,
    );
    return DateTime.utc(
      base.year,
      base.month,
      base.day,
      base.hour - 9,
      base.minute,
      base.second,
      base.millisecond,
    );
  }

  double? _depth(Uint8List record) {
    final raw = _field(record, 45, 49);
    if (raw.trim().isEmpty) return null;
    if (raw.endsWith('  ')) {
      return double.tryParse(raw.substring(0, 3).trim());
    }
    return _decimalField(record, 45, 49, 2);
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

  String _eventId(JmaIntensityHypocenter hypocenter) {
    final jst = hypocenter.originTime.add(const Duration(hours: 9));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${jst.year}${two(jst.month)}${two(jst.day)}'
        '${two(jst.hour)}${two(jst.minute)}${two(jst.second)}'
        '${two(jst.millisecond ~/ 10)}-'
        '${hypocenter.latitude.toStringAsFixed(4)}-'
        '${hypocenter.longitude.toStringAsFixed(4)}';
  }
}

List<Uint8List> _splitLines(Uint8List bytes) {
  final lines = <Uint8List>[];
  var start = 0;
  for (var index = 0; index < bytes.length; index++) {
    if (bytes[index] != 0x0a) continue;
    var end = index;
    if (end > start && bytes[end - 1] == 0x0d) end--;
    lines.add(Uint8List.sublistView(bytes, start, end));
    start = index + 1;
  }
  if (start < bytes.length) {
    lines.add(Uint8List.sublistView(bytes, start));
  }
  return lines;
}

List<Uint8List> _splitBytes(Uint8List bytes, int separator) {
  final parts = <Uint8List>[];
  var start = 0;
  for (var index = 0; index < bytes.length; index++) {
    if (bytes[index] != separator) continue;
    parts.add(Uint8List.sublistView(bytes, start, index));
    start = index + 1;
  }
  parts.add(Uint8List.sublistView(bytes, start));
  return parts;
}

String _ascii(Uint8List bytes) => ascii.decode(bytes, allowInvalid: true);

String _field(Uint8List record, int start, int end) =>
    _ascii(Uint8List.sublistView(record, start - 1, end));

int? _intField(Uint8List record, int start, int end) {
  final raw = _field(record, start, end).trim();
  if (raw.isEmpty || raw.contains('/')) return null;
  return int.tryParse(raw);
}

double? _decimalField(Uint8List record, int start, int end, int decimalPlaces) {
  final raw = _field(record, start, end).trim();
  if (raw.isEmpty || raw.contains('/')) return null;
  if (raw.contains('.')) return double.tryParse(raw);
  final value = int.tryParse(raw);
  if (value == null) return null;
  var divisor = 1;
  for (var index = 0; index < decimalPlaces; index++) {
    divisor *= 10;
  }
  return value / divisor;
}

DateTime _jstToUtc(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
  int millisecond,
) {
  return DateTime.utc(year, month, day, hour - 9, minute, second, millisecond);
}

String _hex(Uint8List bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
