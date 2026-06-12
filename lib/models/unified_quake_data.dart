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
  final QuakeMessage? rawEvent;
  final DateTime? arrivedAt;

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
    this.rawEvent,
    this.arrivedAt,
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

  bool get isRed => className == 'red' || className == 'dark-red' || className == 'purple';
  bool get isOrange => className == 'orange' || className == 'dark-orange';
  bool get isDarkGray => className == 'dark-gray';

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
    QuakeMessage? rawEvent,
    DateTime? arrivedAt,
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
      rawEvent: rawEvent ?? this.rawEvent,
      arrivedAt: arrivedAt ?? this.arrivedAt,
    );
  }
}