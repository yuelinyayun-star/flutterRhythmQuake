import 'package:flutter/material.dart';

enum WeatherAlarmSource { fan, whews, chinaWeatherLocal, jmaLocal }

class WeatherAlarm {
  final String id;
  final String headline;
  final String effective;
  final String expires;
  final String description;
  final double? latitude;
  final double? longitude;
  final String type;
  final WeatherAlarmSource source;
  final DateTime receivedAtUtc;

  WeatherAlarm({
    required this.id,
    required this.headline,
    required this.effective,
    this.expires = '',
    required this.description,
    this.latitude,
    this.longitude,
    required this.type,
    this.source = WeatherAlarmSource.fan,
    DateTime? receivedAtUtc,
  }) : receivedAtUtc = (receivedAtUtc ?? DateTime.now()).toUtc();

  Map<String, dynamic> toMap() => {
    'id': id,
    'headline': headline,
    'effective': effective,
    'expires': expires,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'type': type,
    'source': source.name,
    'receivedAtUtc': receivedAtUtc.toIso8601String(),
  };

  factory WeatherAlarm.fromMap(Map<dynamic, dynamic> map) {
    final sourceName = map['source']?.toString();
    final source = WeatherAlarmSource.values.firstWhere(
      (item) => item.name == sourceName,
      orElse: () => WeatherAlarmSource.fan,
    );
    return WeatherAlarm(
      id: map['id']?.toString() ?? '',
      headline: map['headline']?.toString() ?? '',
      effective: map['effective']?.toString() ?? '',
      expires: map['expires']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      latitude: _parseNumber(map['latitude']),
      longitude: _parseNumber(map['longitude']),
      type: map['type']?.toString() ?? '',
      source: source,
      receivedAtUtc: DateTime.tryParse(map['receivedAtUtc']?.toString() ?? ''),
    );
  }

  factory WeatherAlarm.fromFanJson(
    Map<String, dynamic> json, {
    WeatherAlarmSource source = WeatherAlarmSource.fan,
  }) {
    return WeatherAlarm(
      id: json['id']?.toString() ?? '',
      headline: json['headline']?.toString() ?? json['title']?.toString() ?? '',
      effective: json['effective']?.toString() ?? '',
      expires:
          (json['expires'] ?? json['expireTime'] ?? json['endTime'])
              ?.toString() ??
          '',
      description: json['description']?.toString() ?? '',
      latitude: double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: double.tryParse(json['longitude']?.toString() ?? ''),
      type: json['type']?.toString() ?? '',
      source: source,
    );
  }

  factory WeatherAlarm.fromJson(Map<String, dynamic> json) =>
      WeatherAlarm.fromFanJson(json);

  DateTime? get effectiveInstantUtc => _parseChinaStandardTime(effective);

  DateTime? get expiresInstantUtc => _parseChinaStandardTime(expires);

  DateTime get validUntilUtc =>
      expiresInstantUtc ??
      (effectiveInstantUtc ?? receivedAtUtc).add(const Duration(hours: 24));

  bool isExpired([DateTime? now]) =>
      !validUntilUtc.isAfter((now ?? DateTime.now()).toUtc());

  String get revisionKey =>
      '$id|$effective|$headline|$type|$description|$expires';

  static DateTime? _parseChinaStandardTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll('/', '-').replaceFirst(' ', 'T');
    final hasExplicitZone = RegExp(
      r'(?:Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(normalized);
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    if (hasExplicitZone || parsed.isUtc) return parsed.toUtc();
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).subtract(const Duration(hours: 8));
  }

  String get levelCode {
    if (type.length >= 2) return type.substring(type.length - 2);
    return '';
  }

  Color get levelColor {
    switch (source) {
      case WeatherAlarmSource.chinaWeatherLocal:
        return _localLevelColor(levelCode);
      case WeatherAlarmSource.jmaLocal:
        return _jmaLevelColor(levelCode);
      case WeatherAlarmSource.fan:
      case WeatherAlarmSource.whews:
        return _fanLevelColor(levelCode);
    }
  }

  String get levelLabel {
    switch (source) {
      case WeatherAlarmSource.chinaWeatherLocal:
        return _localLevelLabel(levelCode);
      case WeatherAlarmSource.jmaLocal:
        return _jmaLevelLabel(levelCode);
      case WeatherAlarmSource.fan:
      case WeatherAlarmSource.whews:
        return _fanLevelLabel(levelCode);
    }
  }

  static Color _fanLevelColor(String code) {
    switch (code) {
      case '01':
        return const Color(0xFFE74C3C);
      case '02':
        return const Color(0xFFE67E22);
      case '03':
        return const Color(0xFFEBC033);
      case '04':
        return const Color(0xFF3498DB);
      default:
        return const Color(0xFF3498DB);
    }
  }

  static Color _localLevelColor(String code) {
    switch (code) {
      case '01':
        return const Color(0xFF3498DB);
      case '02':
        return const Color(0xFFEBC033);
      case '03':
        return const Color(0xFFE67E22);
      case '04':
        return const Color(0xFFE74C3C);
      default:
        return const Color(0xFF3498DB);
    }
  }

  static String _fanLevelLabel(String code) {
    switch (code) {
      case '01':
        return '\u7ea2\u8272';
      case '02':
        return '\u6a59\u8272';
      case '03':
        return '\u9ec4\u8272';
      case '04':
        return '\u84dd\u8272';
      default:
        return '';
    }
  }

  static String _localLevelLabel(String code) {
    switch (code) {
      case '01':
        return '\u84dd\u8272';
      case '02':
        return '\u9ec4\u8272';
      case '03':
        return '\u6a59\u8272';
      case '04':
        return '\u7ea2\u8272';
      default:
        return '';
    }
  }

  static Color _jmaLevelColor(String code) {
    switch (code) {
      case '04':
        return const Color(0xFFAF0000);
      case '03':
        return const Color(0xFFE74C3C);
      case '02':
        return const Color(0xFFEBC033);
      case '01':
        return const Color(0xFF3498DB);
      default:
        return const Color(0xFFEBC033);
    }
  }

  static String _jmaLevelLabel(String code) {
    switch (code) {
      case '04':
        return '\u7279\u5225';
      case '03':
        return '\u8b66\u5831';
      case '02':
        return '\u6ce8\u610f';
      default:
        return '';
    }
  }

  String get disasterType {
    const patterns = <String, String>{
      '\u66b4\u96e8': '\u66b4\u96e8',
      '\u66b4\u96ea': '\u66b4\u96ea',
      '\u53f0\u98ce': '\u53f0\u98ce',
      '\u5bd2\u6f6e': '\u5bd2\u6f6e',
      '\u5927\u98ce': '\u5927\u98ce',
      '\u96f7\u96e8\u5927\u98ce': '\u96f7\u96e8\u5927\u98ce',
      '\u6c99\u5c18\u66b4': '\u6c99\u5c18\u66b4',
      '\u9ad8\u6e29': '\u9ad8\u6e29',
      '\u5e72\u65f1': '\u5e72\u65f1',
      '\u96f7\u7535': '\u96f7\u7535',
      '\u51b0\u96f9': '\u51b0\u96f9',
      '\u971c\u51bb': '\u971c\u51bb',
      '\u5927\u96fe': '\u5927\u96fe',
      '\u972d': '\u972d',
      '\u9053\u8def\u7ed3\u51b0': '\u9053\u8def\u7ed3\u51b0',
      '\u96f7\u66b4\u5927\u98ce': '\u96f7\u66b4\u5927\u98ce',
      '\u66b4\u98a8\u96ea\u7279\u5225\u8b66\u5831': '\u66b4\u98a8\u96ea',
      '\u66b4\u98a8\u96ea\u8b66\u5831': '\u66b4\u98a8\u96ea',
      '\u5927\u96e8\u7279\u5225\u8b66\u5831': '\u5927\u96e8',
      '\u5927\u96e8\u8b66\u5831': '\u5927\u96e8',
      '\u5927\u96e8\u6ce8\u610f\u5831': '\u5927\u96e8',
      '\u96f7\u6ce8\u610f\u5831': '\u96f7\u7535',
      '\u6fc3\u9727\u6ce8\u610f\u5831': '\u5927\u96fe',
      '\u5f37\u98a8\u6ce8\u610f\u5831': '\u5927\u98ce',
      '\u571f\u7802\u707d\u5bb3\u7279\u5225\u8b66\u5831':
          '\u571f\u7802\u707d\u5bb3',
      '\u571f\u7802\u707d\u5bb3\u6ce8\u610f\u5831': '\u571f\u7802\u707d\u5bb3',
    };
    for (final entry in patterns.entries) {
      if (headline.contains(entry.key)) return entry.value;
    }
    return '';
  }

  String get marqueeText {
    return '$headline \u00b7 $effective \u00b7 $description';
  }
}

double? _parseNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
