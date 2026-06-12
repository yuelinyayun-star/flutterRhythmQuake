import 'package:flutter/material.dart';

class WeatherAlarm {
  final String id;
  final String headline;
  final String effective;
  final String description;
  final double? latitude;
  final double? longitude;
  final String type;

  WeatherAlarm({
    required this.id,
    required this.headline,
    required this.effective,
    required this.description,
    this.latitude,
    this.longitude,
    required this.type,
  });

  factory WeatherAlarm.fromJson(Map<String, dynamic> json) {
    return WeatherAlarm(
      id: json['id']?.toString() ?? '',
      headline: json['headline']?.toString() ?? json['title']?.toString() ?? '',
      effective: json['effective']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      latitude: double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: double.tryParse(json['longitude']?.toString() ?? ''),
      type: json['type']?.toString() ?? '',
    );
  }

  String get levelCode {
    if (type.length >= 2) return type.substring(type.length - 2);
    return '';
  }

  Color get levelColor {
    switch (levelCode) {
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

  String get levelLabel {
    switch (levelCode) {
      case '01':
        return '红色';
      case '02':
        return '橙色';
      case '03':
        return '黄色';
      case '04':
        return '蓝色';
      default:
        return '';
    }
  }

  String get disasterType {
    final patterns = {
      '暴雨': '暴雨',
      '暴雪': '暴雪',
      '台风': '台风',
      '寒潮': '寒潮',
      '大风': '大风',
      '雷雨大风': '雷雨大风',
      '沙尘暴': '沙尘暴',
      '高温': '高温',
      '干旱': '干旱',
      '雷电': '雷电',
      '冰雹': '冰雹',
      '霜冻': '霜冻',
      '大雾': '大雾',
      '霾': '霾',
      '道路结冰': '道路结冰',
      '雷暴大风': '雷暴大风',
    };
    for (final entry in patterns.entries) {
      if (headline.contains(entry.key)) return entry.value;
    }
    return '';
  }

  String get marqueeText {
    return '$headline · $effective · $description';
  }
}
