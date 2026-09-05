import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// 全国气象灾害预警地图项目模型
class WeatherAlertMapItem {
  static final _ringBounds = Expando<Rect>();
  final String id;
  final String aid;
  final String areaName;
  final String title;
  final String fileId;
  final LatLng center;
  final String signalType;
  final String signalLevel;
  final String typeCode;
  final String levelCode;
  final List<List<LatLng>> polygons;

  const WeatherAlertMapItem({
    required this.id,
    required this.aid,
    required this.areaName,
    required this.title,
    required this.fileId,
    required this.center,
    required this.signalType,
    required this.signalLevel,
    required this.typeCode,
    required this.levelCode,
    required this.polygons,
  });

  /// 获取对应的国家标准预警等级颜色
  Color get levelColor {
    return switch (signalLevel) {
      '红色' => const Color(0xFFE53935),
      '橙色' => const Color(0xFFFB8C00),
      '黄色' => const Color(0xFFFDD835),
      '蓝色' => const Color(0xFF1E88E5),
      _ => const Color(0xFF29B6F6),
    };
  }

  /// 等级背景上的文字颜色（黄色背景用黑色，红/橙/蓝用白色）
  Color get onLevelTextColor {
    return signalLevel == '黄色' ? const Color(0xFF1A1A1A) : Colors.white;
  }

  /// 英文标准灾害类型名称
  String get englishName {
    if (signalType.contains('暴雨') || signalType.contains('强降雨')) return 'RAIN STORM';
    if (signalType.contains('雨')) return 'HEAVY RAIN';
    if (signalType.contains('台风')) return 'TYPHOON';
    if (signalType.contains('风')) return 'GALE';
    if (signalType.contains('雷电') || signalType.contains('雷暴')) return 'LIGHTNING';
    if (signalType.contains('大雾') || signalType.contains('浓雾')) return 'HEAVY FOG';
    if (signalType.contains('霾')) return 'HAZE';
    if (signalType.contains('暴雪') || signalType.contains('大雪')) return 'BLIZZARD';
    if (signalType.contains('雪')) return 'SNOW';
    if (signalType.contains('高温')) return 'HEAT WAVE';
    if (signalType.contains('寒潮') || signalType.contains('强降温') || signalType.contains('低温')) return 'COLD WAVE';
    if (signalType.contains('冰雹')) return 'HAIL';
    if (signalType.contains('霜冻')) return 'FROST';
    if (signalType.contains('结冰') || signalType.contains('冰雪')) return 'ROAD ICING';
    if (signalType.contains('沙尘')) return 'SANDSTORM';
    if (signalType.contains('干旱')) return 'DROUGHT';
    if (signalType.contains('火')) return 'WILDFIRE';
    return 'WARNING';
  }

  /// 单字等级标识
  String get levelSingleChar {
    if (signalLevel.contains('红')) return '红';
    if (signalLevel.contains('橙')) return '橙';
    if (signalLevel.contains('黄')) return '黄';
    if (signalLevel.contains('蓝')) return '蓝';
    return signalLevel.isNotEmpty ? signalLevel.substring(0, 1) : '黄';
  }

  /// 竖排中文灾害类型名称（最多 2~3 字）
  List<String> get verticalChineseChars {
    final cleanType = signalType.replaceAll(RegExp(r'[（）\(\)\s]'), '');
    if (cleanType.length <= 2) {
      return cleanType.split('');
    }
    if (cleanType.startsWith('森林') || cleanType.startsWith('草原')) {
      return ['火', '险'];
    }
    if (cleanType.contains('雷雨大风') || cleanType.contains('雷暴大风')) {
      return ['雷', '风'];
    }
    if (cleanType.contains('道路结冰')) {
      return ['结', '冰'];
    }
    return cleanType.substring(0, 2).split('');
  }

  static String typeCodeToName(String code) {
    return switch (code) {
      '01' => '台风',
      '02' => '暴雨',
      '03' => '暴雪',
      '04' => '寒潮',
      '05' => '大风',
      '06' => '沙尘暴',
      '07' => '高温',
      '08' => '干旱',
      '09' => '雷电',
      '10' => '冰雹',
      '11' => '霜冻',
      '12' => '大雾',
      '13' => '霾',
      '14' => '道路结冰',
      '15' => '森林火险',
      '16' => '雷雨大风',
      _ => '气象灾害',
    };
  }

  static String levelCodeToName(String code) {
    return switch (code) {
      '01' => '蓝色',
      '02' => '黄色',
      '03' => '橙色',
      '04' => '红色',
      _ => '黄色',
    };
  }

  /// 预警严重度权重（红色4 > 橙色3 > 黄色2 > 蓝色1）
  int get severityWeight {
    return switch (signalLevel) {
      '红色' => 4,
      '橙色' => 3,
      '黄色' => 2,
      '蓝色' => 1,
      _ => 2,
    };
  }

  /// CMA 官方 LOD 视距过滤规则：
  /// - 直辖市 (如北京 10101): 全级别可见
  /// - 省级预警 (aid 长度 <= 5): 全级别可见
  /// - 市级预警 (aid 长度 <= 7): Zoom >= 5.0 可见
  /// - 县级预警 (aid 长度 >= 9): Zoom >= 6.8 可见
  bool isIconVisibleAtZoom(double zoom) {
    if (aid.startsWith('10101') || aid.startsWith('10102') || aid.startsWith('10103') || aid.startsWith('10104')) {
      return true;
    }
    if (aid.length <= 5) return true;
    if (aid.length <= 7) return zoom >= 5.0;
    return zoom >= 6.8;
  }

  /// 从 API 数组条目解析单个预警对象
  /// 数据项结构: [areaName, fileId, lng, lat, id, id2, title, geometry]
  static WeatherAlertMapItem? fromRawList(List<dynamic> item) {
    if (item.length < 8) return null;
    try {
      final areaName = item[0]?.toString() ?? '';
      final fileId = item[1]?.toString() ?? '';
      final lng = double.tryParse(item[2]?.toString() ?? '');
      final lat = double.tryParse(item[3]?.toString() ?? '');
      final id = item[4]?.toString() ?? '';
      final title = item[6]?.toString() ?? '';
      final geometry = item[7];

      if (lat == null || lng == null) return null;

      // 解析 Area ID 和 类型/等级代码
      final parts = fileId.split('-');
      final aid = parts.isNotEmpty ? parts[0] : '';
      var typeCode = '00';
      var levelCode = '02';
      if (parts.length >= 3 && parts[2].length >= 4) {
        typeCode = parts[2].substring(0, 2);
        levelCode = parts[2].substring(2, 4);
      }

      // 提取预警类型与等级（优先使用官方编码，辅以标题正则）
      var signalType = typeCodeToName(typeCode);
      var signalLevel = levelCodeToName(levelCode);

      final match = RegExp(r'发布([^\s\[\]]+?)(蓝色|黄色|橙色|红色)预警').firstMatch(title);
      if (match != null) {
        signalType = match.group(1) ?? signalType;
        signalLevel = match.group(2) ?? signalLevel;
      } else {
        const keywords = [
          '台风', '暴雨', '暴雪', '寒潮', '大风', '沙尘暴', '高温',
          '干旱', '雷电', '冰雹', '霜冻', '大雾', '浓雾', '霾',
          '道路结冰', '森林火险', '雷雨大风', '雷暴大风'
        ];
        for (final kw in keywords) {
          if (title.contains(kw)) {
            signalType = kw;
            break;
          }
        }
        if (title.contains('红色')) {
          signalLevel = '红色';
        } else if (title.contains('橙色')) {
          signalLevel = '橙色';
        } else if (title.contains('黄色')) {
          signalLevel = '黄色';
        } else if (title.contains('蓝色')) {
          signalLevel = '蓝色';
        }
      }

      // 解析多边形轮廓
      final polygons = <List<LatLng>>[];
      if (geometry is Map<String, dynamic>) {
        final rawCoords = geometry['coordinates'];
        final geomType = geometry['type']?.toString();

        if (geomType == 'Polygon' && rawCoords is List) {
          for (final ring in rawCoords) {
            final parsedRing = _parseCoordRing(ring);
            if (parsedRing.isNotEmpty) polygons.add(parsedRing);
          }
        } else if (geomType == 'MultiPolygon' && rawCoords is List) {
          for (final poly in rawCoords) {
            if (poly is List) {
              for (final ring in poly) {
                final parsedRing = _parseCoordRing(ring);
                if (parsedRing.isNotEmpty) polygons.add(parsedRing);
              }
            }
          }
        }
      }

      return WeatherAlertMapItem(
        id: id.isNotEmpty ? id : '$lat,$lng,$title',
        aid: aid,
        areaName: areaName,
        title: title,
        fileId: fileId,
        center: LatLng(lat, lng),
        signalType: signalType,
        signalLevel: signalLevel,
        typeCode: typeCode,
        levelCode: levelCode,
        polygons: polygons,
      );
    } catch (_) {
      return null;
    }
  }

  /// 判断经纬度坐标是否在当前预警的多边形染色区域内
  bool containsLocation(LatLng point) {
    for (final poly in polygons) {
      if (isPointInPolygon(point, poly)) return true;
    }
    return false;
  }

  /// 判断经纬度坐标是否在多边形环内（Ray-casting 射线法）
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var bounds = _ringBounds[polygon];
    if (bounds == null) {
      var west = polygon.first.longitude;
      var east = west;
      var south = polygon.first.latitude;
      var north = south;
      for (final vertex in polygon) {
        if (vertex.longitude < west) west = vertex.longitude;
        if (vertex.longitude > east) east = vertex.longitude;
        if (vertex.latitude < south) south = vertex.latitude;
        if (vertex.latitude > north) north = vertex.latitude;
      }
      bounds = Rect.fromLTRB(west, south, east, north);
      _ringBounds[polygon] = bounds;
    }
    // Keep edge inclusion decisions in the original ray-casting algorithm.
    if (point.longitude < bounds.left || point.longitude > bounds.right ||
        point.latitude < bounds.top || point.latitude > bounds.bottom) {
      return false;
    }
    var inside = false;
    final px = point.longitude;
    final py = point.latitude;

    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      final intersect = ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static List<LatLng> _parseCoordRing(dynamic ring) {
    final points = <LatLng>[];
    if (ring is! List) return points;

    for (final pt in ring) {
      if (pt is String) {
        // "116.089 24.839" 格式
        final parts = pt.trim().split(RegExp(r'\s+|,'));
        if (parts.length >= 2) {
          final lng = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          if (lat != null && lng != null) {
            points.add(LatLng(lat, lng));
          }
        }
      } else if (pt is List && pt.length >= 2) {
        // [116.089, 24.839] 格式
        final lng = double.tryParse(pt[0]?.toString() ?? '');
        final lat = double.tryParse(pt[1]?.toString() ?? '');
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      }
    }
    return points;
  }
}

/// 预警详细信息模型（对应 CMA 官方 webdata 详情）
class WeatherAlertDetail {
  final String head;
  final String alertId;
  final String province;
  final String city;
  final String stationName;
  final String signalType;
  final String signalLevel;
  final String typeCode;
  final String levelCode;
  final String issueTime;
  final String issueContent;
  final String relieveTime;
  final String fileId;

  const WeatherAlertDetail({
    required this.head,
    required this.alertId,
    required this.province,
    required this.city,
    required this.stationName,
    required this.signalType,
    required this.signalLevel,
    required this.typeCode,
    required this.levelCode,
    required this.issueTime,
    required this.issueContent,
    required this.relieveTime,
    required this.fileId,
  });

  String get detailWebUrl {
    final cleanFile = fileId.endsWith('.html') ? fileId : '$fileId.html';
    return 'http://www.weather.com.cn/alarm/newalarmcontent.shtml?file=$cleanFile';
  }

  factory WeatherAlertDetail.fromJson(Map<String, dynamic> json, String fileId) {
    return WeatherAlertDetail(
      head: json['head']?.toString() ?? '',
      alertId: json['ALERTID']?.toString() ?? '',
      province: json['PROVINCE']?.toString() ?? '',
      city: json['CITY']?.toString() ?? '',
      stationName: json['STATIONNAME']?.toString() ?? '',
      signalType: json['SIGNALTYPE']?.toString() ?? '',
      signalLevel: json['SIGNALLEVEL']?.toString() ?? '',
      typeCode: json['TYPECODE']?.toString() ?? '',
      levelCode: json['LEVELCODE']?.toString() ?? '',
      issueTime: json['ISSUETIME']?.toString() ?? json['TIME']?.toString() ?? '',
      issueContent: json['ISSUECONTENT']?.toString() ?? '',
      relieveTime: json['RELIEVETIME']?.toString() ?? '',
      fileId: fileId,
    );
  }

  static WeatherAlertDetail? fromRawJs(String rawJs, String fileId) {
    try {
      final jsonStart = rawJs.indexOf('{');
      final jsonEnd = rawJs.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) return null;
      final jsonStr = rawJs.substring(jsonStart, jsonEnd + 1);
      final decoded = json.decode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return WeatherAlertDetail.fromJson(decoded, fileId);
      }
    } catch (_) {}
    return null;
  }
}
