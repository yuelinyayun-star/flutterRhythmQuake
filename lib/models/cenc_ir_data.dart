/// CENC 烈度速报数据模型
///
/// 本模块定义了中国地震台网中心 (CENC) 仪器烈度速报的数据结构。
/// CENC 烈度速报提供地震发生后各测站的仪器烈度观测数据。
///
/// ## 数据内容
///
/// - **基本信息**: 事件ID、发震时间、位置、深度等
/// - **等震线图**: GeoJSON 格式的烈度等值线
/// - **测站烈度**: 各观测站的仪器烈度、PGA、PGV 等
///
/// ## 数据来源
///
/// 数据通过 FAN 平台获取，包含：
/// - uniEventId: 统一事件标识
/// - contour_geojson: 等震线 GeoJSON 数据
/// - instrument_intensity_json: 测站烈度 JSON 数组

library;

import 'dart:convert';

enum CencIrDataSource { fan, nowQuake }

/// CENC 烈度速报数据
///
/// 包含一次地震事件的完整烈度速报信息。
class CencIrData {
  final CencIrDataSource source;

  /// 数据源中的烈度速报编号。
  final String reportId;

  /// 统一事件标识
  ///
  /// CENC 分配的唯一事件 ID，用于跨系统关联。
  final String uniEventId;

  /// 发震时间
  ///
  /// 地震发生的 UTC 时间。
  final DateTime oriTime;

  /// 数据生成时间
  ///
  /// 烈度速报数据的生成时间。
  final DateTime gmtCreate;

  /// 震中位置名称
  ///
  /// 人类可读的震中位置描述。
  final String locName;

  /// 震中经度
  final double epiLon;

  /// 震中纬度
  final double epiLat;

  /// 震源深度
  ///
  /// 单位：公里 (km)。
  final double focDepth;

  /// 主题代码
  ///
  /// 用于分类的事件代码。
  final String subjectCodes;

  /// 烈度信息文本
  ///
  /// 烈度速报的文字描述。
  final String intensityInfoText;

  /// 等震线 GeoJSON 数据
  ///
  /// 包含烈度等值线的 GeoJSON FeatureCollection。
  /// 可用于在地图上绘制等震线图。
  final Map<String, dynamic>? contourGeojson;

  /// 测站仪器烈度列表
  ///
  /// 各观测站的仪器烈度观测数据。
  final List<InstrumentIntensity> instrumentIntensities;

  /// 构造函数
  CencIrData({
    this.source = CencIrDataSource.fan,
    this.reportId = '',
    required this.uniEventId,
    required this.oriTime,
    required this.gmtCreate,
    required this.locName,
    required this.epiLon,
    required this.epiLat,
    required this.focDepth,
    required this.subjectCodes,
    required this.intensityInfoText,
    this.contourGeojson,
    this.instrumentIntensities = const [],
  });

  Map<String, dynamic> toMap() => {
    'source': source.name,
    'reportId': reportId,
    'uniEventId': uniEventId,
    'oriTime': oriTime.toIso8601String(),
    'gmtCreate': gmtCreate.toIso8601String(),
    'locName': locName,
    'epiLon': epiLon,
    'epiLat': epiLat,
    'focDepth': focDepth,
    'subjectCodes': subjectCodes,
    'intensityInfoText': intensityInfoText,
    'contourGeojson': contourGeojson,
    'instrumentIntensities': instrumentIntensities
        .map((item) => item.toMap())
        .toList(),
  };

  factory CencIrData.fromMap(Map<dynamic, dynamic> map) {
    DateTime parseTime(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    double parseDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final rawItems = map['instrumentIntensities'];
    return CencIrData(
      source: CencIrDataSource.values.firstWhere(
        (item) => item.name == map['source']?.toString(),
        orElse: () => CencIrDataSource.fan,
      ),
      reportId: map['reportId']?.toString() ?? '',
      uniEventId: map['uniEventId']?.toString() ?? '',
      oriTime: parseTime(map['oriTime']),
      gmtCreate: parseTime(map['gmtCreate']),
      locName: map['locName']?.toString() ?? '',
      epiLon: parseDouble(map['epiLon']),
      epiLat: parseDouble(map['epiLat']),
      focDepth: parseDouble(map['focDepth']),
      subjectCodes: map['subjectCodes']?.toString() ?? '',
      intensityInfoText: map['intensityInfoText']?.toString() ?? '',
      contourGeojson: map['contourGeojson'] is Map
          ? Map<String, dynamic>.from(map['contourGeojson'] as Map)
          : null,
      instrumentIntensities: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => InstrumentIntensity.fromMap(
                    Map<dynamic, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }

  /// 从 JSON 创建实例
  ///
  /// 解析 FAN 平台返回的 CENC 烈度速报数据。
  ///
  /// 参数：
  /// - [json]: 原始 JSON 数据
  ///
  /// 返回：
  /// - 解析后的 CencIrData 实例
  ///
  /// ## 数据格式处理
  ///
  /// - instrument_intensity_json 可能是 List 或 JSON 字符串
  /// - contour_geojson 可能是 Map 或 JSON 字符串
  factory CencIrData.fromJson(Map<String, dynamic> json) {
    List<InstrumentIntensity> instruments = [];
    if (json['instrument_intensity_json'] is List) {
      for (final item in json['instrument_intensity_json']) {
        if (item is Map) {
          instruments.add(
            InstrumentIntensity.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    } else if (json['instrument_intensity_json'] is String) {
      try {
        final decoded = jsonDecode(json['instrument_intensity_json']);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              instruments.add(
                InstrumentIntensity.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      } catch (_) {}
    }

    Map<String, dynamic>? contour;
    if (json['contour_geojson'] is Map) {
      contour = Map<String, dynamic>.from(json['contour_geojson']);
    } else if (json['contour_geojson'] is String) {
      try {
        final decoded = jsonDecode(json['contour_geojson']);
        if (decoded is Map) {
          contour = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return CencIrData(
      source: CencIrDataSource.fan,
      reportId: json['id']?.toString() ?? '',
      uniEventId: json['uniEventId']?.toString() ?? '',
      oriTime:
          DateTime.tryParse(json['oriTime']?.toString() ?? '') ??
          DateTime.now(),
      gmtCreate:
          DateTime.tryParse(json['gmtCreate']?.toString() ?? '') ??
          DateTime.now(),
      locName: json['locName']?.toString() ?? '',
      epiLon: double.tryParse(json['epiLon']?.toString() ?? '') ?? 0.0,
      epiLat: double.tryParse(json['epiLat']?.toString() ?? '') ?? 0.0,
      focDepth: double.tryParse(json['focDepth']?.toString() ?? '') ?? 0.0,
      subjectCodes: json['subjectCodes']?.toString() ?? '',
      intensityInfoText: json['intensity_info_text']?.toString() ?? '',
      contourGeojson: contour,
      instrumentIntensities: instruments,
    );
  }

  factory CencIrData.fromNowQuakeJson(Map<String, dynamic> json) {
    final stations = <InstrumentIntensity>[];
    final rawStations = json['stations'];
    if (rawStations is List) {
      for (final item in rawStations) {
        if (item is Map) {
          stations.add(
            InstrumentIntensity.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final eventId = json['eq_id']?.toString() ?? '';
    return CencIrData(
      source: CencIrDataSource.nowQuake,
      reportId: eventId,
      uniEventId: eventId,
      oriTime: _parseUtc8Time(json['happen_time']),
      gmtCreate: _parseUtc8Time(json['update_time']),
      locName: json['hypocenter']?.toString() ?? '',
      epiLon: _doubleValue(json['longitude']),
      epiLat: _doubleValue(json['latitude']),
      focDepth: _doubleValue(json['depth']),
      subjectCodes: 'base-info,intensity-report,seismicity',
      intensityInfoText: json['info']?.toString() ?? '',
      instrumentIntensities: stations,
    );
  }

  static DateTime _parseUtc8Time(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    final normalized = value.replaceFirst(' ', 'T');
    return DateTime.tryParse('$normalized+08:00') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static double _doubleValue(dynamic raw) {
    if (raw is num) {
      return raw.toDouble();
    }
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }
}

/// 仪器烈度数据
///
/// 单个观测站的仪器烈度观测结果。
class InstrumentIntensity {
  /// 测站名称
  final String stationName;

  /// 测站经度
  final double longitude;

  /// 测站纬度
  final double latitude;

  /// 仪器烈度
  ///
  /// 根据仪器记录计算得到的地震烈度值。
  final double intensity;

  /// 峰值地面加速度
  ///
  /// 单位：cm/s² (gal)
  final double? pga;

  /// 峰值地面速度
  ///
  /// 单位：cm/s
  final double? pgv;

  /// 构造函数
  InstrumentIntensity({
    required this.stationName,
    required this.longitude,
    required this.latitude,
    required this.intensity,
    this.pga,
    this.pgv,
  });

  Map<String, dynamic> toMap() => {
    'stationName': stationName,
    'longitude': longitude,
    'latitude': latitude,
    'intensity': intensity,
    'pga': pga,
    'pgv': pgv,
  };

  factory InstrumentIntensity.fromMap(Map<dynamic, dynamic> map) =>
      InstrumentIntensity(
        stationName: map['stationName']?.toString() ?? '',
        longitude: _parseNumber(map['longitude']),
        latitude: _parseNumber(map['latitude']),
        intensity: _parseNumber(map['intensity']),
        pga: _parseNullableNumber(map['pga']),
        pgv: _parseNullableNumber(map['pgv']),
      );

  bool get hasUsableCoordinate {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        (latitude != 0 || longitude != 0);
  }

  /// 从 JSON 创建实例
  ///
  /// 支持多种字段名称格式：
  /// - stationName / name
  /// - longitude / lon
  /// - latitude / lat
  /// - intensity / int
  ///
  /// 参数：
  /// - [json]: 测站烈度 JSON 数据
  ///
  /// 返回：
  /// - 解析后的 InstrumentIntensity 实例
  factory InstrumentIntensity.fromJson(Map<String, dynamic> json) {
    return InstrumentIntensity(
      stationName:
          json['stationName']?.toString() ??
          json['name']?.toString() ??
          json['stName']?.toString() ??
          json['stID']?.toString() ??
          '',
      longitude:
          double.tryParse(
            json['longitude']?.toString() ??
                json['lon']?.toString() ??
                json['stlo']?.toString() ??
                '',
          ) ??
          0.0,
      latitude:
          double.tryParse(
            json['latitude']?.toString() ??
                json['lat']?.toString() ??
                json['stla']?.toString() ??
                '',
          ) ??
          0.0,
      intensity:
          double.tryParse(
            json['INT']?.toString() ??
                json['intensity']?.toString() ??
                json['int']?.toString() ??
                json['estimateInt']?.toString() ??
                '',
          ) ??
          0.0,
      pga: double.tryParse(
        json['pga']?.toString() ?? json['PGA']?.toString() ?? '',
      ),
      pgv: double.tryParse(
        json['pgv']?.toString() ?? json['PGV']?.toString() ?? '',
      ),
    );
  }
}

double _parseNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _parseNullableNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
