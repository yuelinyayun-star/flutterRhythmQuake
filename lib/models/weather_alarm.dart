import 'package:flutter/material.dart';

enum WeatherAlarmSource { fan, chinaWeatherLocal }

class WeatherAlarm {
  final String id;
  final String headline;
  final String effective;
  final String description;
  final double? latitude;
  final double? longitude;
  final String type;
  final WeatherAlarmSource source;

  WeatherAlarm({
    required this.id,
    required this.headline,
    required this.effective,
    required this.description,
    this.latitude,
    this.longitude,
    required this.type,
    this.source = WeatherAlarmSource.fan,
  });

  factory WeatherAlarm.fromFanJson(Map<String, dynamic> json) {
    return WeatherAlarm(
      id: json['id']?.toString() ?? '',
      headline: json['headline']?.toString() ?? json['title']?.toString() ?? '',
      effective: json['effective']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      latitude: double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: double.tryParse(json['longitude']?.toString() ?? ''),
      type: json['type']?.toString() ?? '',
      source: WeatherAlarmSource.fan,
    );
  }

  factory WeatherAlarm.fromJson(Map<String, dynamic> json) =>
      WeatherAlarm.fromFanJson(json);

  String get levelCode {
    if (type.length >= 2) return type.substring(type.length - 2);
    return '';
  }

  Color get levelColor {
    return source == WeatherAlarmSource.chinaWeatherLocal
        ? _localLevelColor(levelCode)
        : _fanLevelColor(levelCode);
  }

  String get levelLabel {
    return source == WeatherAlarmSource.chinaWeatherLocal
        ? _localLevelLabel(levelCode)
        : _fanLevelLabel(levelCode);
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
