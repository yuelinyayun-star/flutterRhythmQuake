/// 统一地震事件数据模型
///
/// 本模块是重构后的核心数据模型，所有信源（Wolfx/FAN/P2PQuake）
/// 通过统一适配器 (QuakeEventAdapter) 转换为本模型，UI 和地图层直接消费。
///
/// ## 设计原则
///
/// 1. 所有字段都已预格式化，UI 不需要做任何 switch(source) 判断
/// 2. `isEew` 是信源的固有属性，在适配器中直接写死
/// 3. 颜色由 `className` 字符串统一控制，UI + 地图使用同一色彩体系

import 'quake_message.dart';
import 'source_payload.dart';
import 'cmt_moment_tensor.dart';
import 'cmt_solution_metadata.dart';
import 'volcano_event_data.dart';
import 'jma_lpgm_bulletin.dart';

class UnifiedQuakeData {
  final String source;
  final int origin;
  final String eventId;
  final bool isEew;
  final int timeZone;
  final String titleText;
  final String reportNumText;
  final bool useShindo;
  final String maxIntensity;
  final String className;
  final String hypocenter;
  final DateTime? originTime;
  final DateTime? reportTime;
  final double magnitude;
  final double depth;
  final String depthText;
  final double? lat;
  final double? lng;
  final bool isWarn;
  final bool isFinal;
  final bool isCanceled;
  final bool isAssumption;
  final String warnArea;
  final String apiTypeLabel;
  final String? nodalPlane1;
  final String? nodalPlane2;

  /// 矩心深度（km），CMT 反演产出。
  /// 与 [depth]（震源深度，速报值）区分；UI 显示用 [depth]，beachball 下方标注用此字段。
  final double? centroidDepth;

  /// Optional CMT tensor in North-East-Down coordinates for the focal sphere.
  final CmtMomentTensor? momentTensor;

  /// Optional raw CMT solution metadata, not used for event parameters or drawing.
  final CmtSolutionMetadata? cmtMetadata;
  final VolcanoEventData? volcanoEvent;
  final bool isJmaLpgm;
  final JmaLpgmBulletin? jmaLpgmBulletin;
  final QuakeMessage? rawEvent;
  final DateTime? arrivedAt;

  /// Cached catalog deliveries populate lists only, never active alerts/effects.
  final bool isHistory;
  final bool isSnapshot;
  final bool hasReportSequence;

  /// Feeds with source timestamps must not renew their lifetime on arrival.
  final bool useSourceTimeForExpiry;

  /// Original decoded event body, retained per report in history and handoff.
  /// GlobalQuake uses a tagged Java object representation, not wire bytes.
  final Map<String, dynamic>? sourcePayload;

  /// Transient playback state, deliberately excluded from persisted reports.
  final String? replaySessionId;
  final Duration replayClockOffset;
  bool get isReplay => replaySessionId != null;

  const UnifiedQuakeData({
    required this.source,
    required this.origin,
    required this.eventId,
    required this.isEew,
    required this.timeZone,
    required this.titleText,
    required this.reportNumText,
    required this.useShindo,
    required this.maxIntensity,
    required this.className,
    required this.hypocenter,
    this.originTime,
    this.reportTime,
    this.magnitude = -1,
    this.depth = -1,
    this.depthText = '',
    this.lat,
    this.lng,
    this.isWarn = false,
    this.isFinal = false,
    this.isCanceled = false,
    this.isAssumption = false,
    this.warnArea = '',
    this.apiTypeLabel = '',
    this.nodalPlane1,
    this.nodalPlane2,
    this.centroidDepth,
    this.momentTensor,
    this.cmtMetadata,
    this.volcanoEvent,
    this.isJmaLpgm = false,
    this.jmaLpgmBulletin,
    this.rawEvent,
    this.arrivedAt,
    this.isHistory = false,
    this.isSnapshot = false,
    this.hasReportSequence = true,
    this.useSourceTimeForExpiry = false,
    this.sourcePayload,
    this.replaySessionId,
    this.replayClockOffset = Duration.zero,
  });

  static const UnifiedQuakeData empty = UnifiedQuakeData(
    source: '',
    origin: -1,
    eventId: '',
    isEew: false,
    timeZone: 8,
    titleText: '暂无信息',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '-',
    className: 'gray',
    hypocenter: '等待地震事件...',
  );

  bool get isEmpty => origin == -1;

  bool get isRed =>
      className == 'red' || className == 'dark-red' || className == 'purple';
  bool get isOrange => className == 'orange' || className == 'dark-orange';
  bool get isDarkGray => className == 'dark-gray';
  bool get isVolcanoEvent => volcanoEvent != null;

  /// 跨 isolate 传递统一事件时使用的结构化表示。
  ///
  /// 不通过字符串拼接或重新计算字段，保留接纳层已经生成的展示字段，
  /// 让主 UI 只负责显示和后续 UI 效果。
  Map<String, dynamic> toMap() => {
    'source': source,
    'origin': origin,
    'eventId': eventId,
    'isEew': isEew,
    'timeZone': timeZone,
    'titleText': titleText,
    'reportNumText': reportNumText,
    'useShindo': useShindo,
    'maxIntensity': maxIntensity,
    'className': className,
    'hypocenter': hypocenter,
    'originTime': originTime?.toIso8601String(),
    'reportTime': reportTime?.toIso8601String(),
    'magnitude': magnitude,
    'depth': depth,
    'depthText': depthText,
    'lat': lat,
    'lng': lng,
    'isWarn': isWarn,
    'isFinal': isFinal,
    'isCanceled': isCanceled,
    'isAssumption': isAssumption,
    'warnArea': warnArea,
    'apiTypeLabel': apiTypeLabel,
    'nodalPlane1': nodalPlane1,
    'nodalPlane2': nodalPlane2,
    'centroidDepth': centroidDepth,
    'momentTensor': momentTensor?.toMap(),
    'cmtMetadata': cmtMetadata?.toMap(),
    'volcanoEvent': volcanoEvent?.toMap(),
    'isJmaLpgm': isJmaLpgm,
    'jmaLpgmBulletin': jmaLpgmBulletin?.toMap(),
    'rawEvent': rawEvent?.toMap(),
    'arrivedAt': arrivedAt?.toIso8601String(),
    'isHistory': isHistory,
    'isSnapshot': isSnapshot,
    'hasReportSequence': hasReportSequence,
    'useSourceTimeForExpiry': useSourceTimeForExpiry,
    'sourcePayload': sourcePayload,
  };

  factory UnifiedQuakeData.fromMap(Map<String, dynamic> map) {
    DateTime? parseTime(Object? value) {
      final text = value?.toString();
      if (text == null || text.trim().isEmpty) return null;
      return DateTime.tryParse(text);
    }

    double? parseDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    int? parseInt(Object? value) {
      if (value is num) return value.toInt();
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : int.tryParse(text);
    }

    final raw = map['rawEvent'];
    return UnifiedQuakeData(
      source: map['source']?.toString() ?? '',
      origin: (map['origin'] as num?)?.toInt() ?? -1,
      eventId: map['eventId']?.toString() ?? '',
      isEew: map['isEew'] == true,
      timeZone: parseInt(map['timeZone']) ?? 8,
      titleText: map['titleText']?.toString() ?? '',
      reportNumText: map['reportNumText']?.toString() ?? '',
      useShindo: map['useShindo'] == true,
      maxIntensity: map['maxIntensity']?.toString() ?? '-',
      className: map['className']?.toString() ?? 'gray',
      hypocenter: map['hypocenter']?.toString() ?? '',
      originTime: parseTime(map['originTime']),
      reportTime: parseTime(map['reportTime']),
      magnitude: parseDouble(map['magnitude']) ?? -1,
      depth: parseDouble(map['depth']) ?? -1,
      depthText: map['depthText']?.toString() ?? '',
      lat: parseDouble(map['lat']),
      lng: parseDouble(map['lng']),
      isWarn: map['isWarn'] == true,
      isFinal: map['isFinal'] == true,
      isCanceled: map['isCanceled'] == true,
      isAssumption: map['isAssumption'] == true,
      warnArea: map['warnArea']?.toString() ?? '',
      apiTypeLabel: map['apiTypeLabel']?.toString() ?? '',
      nodalPlane1: map['nodalPlane1']?.toString(),
      nodalPlane2: map['nodalPlane2']?.toString(),
      centroidDepth: parseDouble(map['centroidDepth']),
      momentTensor: map['momentTensor'] is Map
          ? CmtMomentTensor.fromNedMap(
              Map<dynamic, dynamic>.from(map['momentTensor'] as Map),
            )
          : null,
      cmtMetadata: map['cmtMetadata'] is Map
          ? CmtSolutionMetadata.fromMap(
              Map<dynamic, dynamic>.from(map['cmtMetadata'] as Map),
            )
          : null,
      volcanoEvent: map['volcanoEvent'] is Map
          ? VolcanoEventData.fromMap(
              Map<dynamic, dynamic>.from(map['volcanoEvent'] as Map),
            )
          : null,
      isJmaLpgm: map['isJmaLpgm'] == true,
      jmaLpgmBulletin: map['jmaLpgmBulletin'] is Map
          ? JmaLpgmBulletin.fromMap(
              Map<dynamic, dynamic>.from(map['jmaLpgmBulletin'] as Map),
            )
          : null,
      rawEvent: raw is Map
          ? QuakeMessage.fromMap(Map<String, dynamic>.from(raw))
          : null,
      arrivedAt: parseTime(map['arrivedAt']),
      isHistory: map['isHistory'] == true,
      isSnapshot: map['isSnapshot'] == true,
      hasReportSequence: map['hasReportSequence'] != false,
      useSourceTimeForExpiry: map['useSourceTimeForExpiry'] == true,
      sourcePayload: map['sourcePayload'] is Map
          ? snapshotSourcePayload(
              Map<String, dynamic>.from(map['sourcePayload'] as Map),
            )
          : null,
    );
  }

  UnifiedQuakeData copyWith({
    String? source,
    int? origin,
    String? eventId,
    bool? isEew,
    int? timeZone,
    String? titleText,
    String? reportNumText,
    bool? useShindo,
    String? maxIntensity,
    String? className,
    String? hypocenter,
    DateTime? originTime,
    DateTime? reportTime,
    double? magnitude,
    double? depth,
    String? depthText,
    double? lat,
    double? lng,
    bool? isWarn,
    bool? isFinal,
    bool? isCanceled,
    bool? isAssumption,
    String? warnArea,
    String? apiTypeLabel,
    String? nodalPlane1,
    String? nodalPlane2,
    double? centroidDepth,
    CmtMomentTensor? momentTensor,
    CmtSolutionMetadata? cmtMetadata,
    VolcanoEventData? volcanoEvent,
    bool? isJmaLpgm,
    JmaLpgmBulletin? jmaLpgmBulletin,
    QuakeMessage? rawEvent,
    DateTime? arrivedAt,
    bool? isHistory,
    bool? isSnapshot,
    bool? hasReportSequence,
    bool? useSourceTimeForExpiry,
    Map<String, dynamic>? sourcePayload,
    String? replaySessionId,
    Duration? replayClockOffset,
  }) {
    return UnifiedQuakeData(
      source: source ?? this.source,
      origin: origin ?? this.origin,
      eventId: eventId ?? this.eventId,
      isEew: isEew ?? this.isEew,
      timeZone: timeZone ?? this.timeZone,
      titleText: titleText ?? this.titleText,
      reportNumText: reportNumText ?? this.reportNumText,
      useShindo: useShindo ?? this.useShindo,
      maxIntensity: maxIntensity ?? this.maxIntensity,
      className: className ?? this.className,
      hypocenter: hypocenter ?? this.hypocenter,
      originTime: originTime ?? this.originTime,
      reportTime: reportTime ?? this.reportTime,
      magnitude: magnitude ?? this.magnitude,
      depth: depth ?? this.depth,
      depthText: depthText ?? this.depthText,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      isWarn: isWarn ?? this.isWarn,
      isFinal: isFinal ?? this.isFinal,
      isCanceled: isCanceled ?? this.isCanceled,
      isAssumption: isAssumption ?? this.isAssumption,
      warnArea: warnArea ?? this.warnArea,
      apiTypeLabel: apiTypeLabel ?? this.apiTypeLabel,
      nodalPlane1: nodalPlane1 ?? this.nodalPlane1,
      nodalPlane2: nodalPlane2 ?? this.nodalPlane2,
      centroidDepth: centroidDepth ?? this.centroidDepth,
      momentTensor: momentTensor ?? this.momentTensor,
      cmtMetadata: cmtMetadata ?? this.cmtMetadata,
      volcanoEvent: volcanoEvent ?? this.volcanoEvent,
      isJmaLpgm: isJmaLpgm ?? this.isJmaLpgm,
      jmaLpgmBulletin: jmaLpgmBulletin ?? this.jmaLpgmBulletin,
      rawEvent: rawEvent ?? this.rawEvent,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      isHistory: isHistory ?? this.isHistory,
      isSnapshot: isSnapshot ?? this.isSnapshot,
      hasReportSequence: hasReportSequence ?? this.hasReportSequence,
      useSourceTimeForExpiry:
          useSourceTimeForExpiry ?? this.useSourceTimeForExpiry,
      sourcePayload: sourcePayload ?? this.sourcePayload,
      replaySessionId: replaySessionId ?? this.replaySessionId,
      replayClockOffset: replayClockOffset ?? this.replayClockOffset,
    );
  }
}
