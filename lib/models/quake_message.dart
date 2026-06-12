/// 地震消息数据模型
///
/// 本模块定义了地震消息的数据结构和数据源类型枚举。
/// 这是整个应用的核心数据模型，用于表示来自不同数据源的地震信息。
///
/// ## 数据流程
///
/// 1. 各数据源服务解析原始数据后创建 QuakeMessage
/// 2. 通过 SourceManager 进行去重和分发
/// 3. QuakeProvider 接收并存储消息
/// 4. UI 组件根据 QuakeMessage 显示地震信息

/// 地震数据源类型枚举
///
/// 定义了应用支持的所有地震数据来源。
/// 每个数据源都有对应的显示名称和预警标签。
enum QuakeSourceType {
  /// Wolfx - 日本气象厅紧急地震速报
  ///
  /// 通过 Wolfx WebSocket 服务获取 JMA 发布的紧急地震速报。
  /// 包含震源位置、震级、震度预测等信息。
  wolfx,

  /// NIED - 日本强震观测网
  ///
  /// 来自 K-NET 和 KiK-net 的实时强震数据。
  /// 提供日本本土的详细震度观测数据。
  nied,

  /// P2PQuake - JMA 地震情报推送
  ///
  /// 通过 P2PQuake WebSocket 服务获取 JMA 发布的地震情报。
  /// 包括震度速报、震源速报、海啸预警等。
  p2p,

  /// CENC - 中国地震台网中心
  ///
  /// 中国地震台网中心发布的地震速报信息。
  /// 包含国内地震的正式测定结果。
  cenc,

  /// USGS - 美国地质调查局
  ///
  /// 美国地质调查局发布的全球地震信息。
  /// 覆盖全球范围的地震事件。
  usgs,

  /// CWA - 台湾中央气象署
  ///
  /// 台湾中央气象署发布的地震情报。
  cwa,

  /// FSSN 地震信息
  ///
  /// FSSN 发布的地震信息。
  fssn,

  /// SC_EEW - 四川省地震局预警
  ///
  /// 四川省地震局发布的地震预警信息。
  sc_eew,

  /// FJ_EEW - 福建省地震局预警
  ///
  /// 福建省地震局发布的地震预警信息。
  fj_eew,

  /// CQ_EEW - 重庆市地震局预警
  ///
  /// 重庆市地震局发布的地震预警信息。
  cq_eew,

  /// CWA_EEW - 台湾地震预警
  ///
  /// 台湾中央气象署发布的地震预警信息。
  cwa_eew,

  /// CEA - 中国地震预警网
  ///
  /// 中国地震预警网发布的地震预警信息。
  cea,

  /// CEA_PR - 中国地震预警网省级网
  ///
  /// 中国地震预警网省级网络发布的地震预警信息。
  cea_pr,

  /// JMA_FAN - JMA 地震情报 (通过 FAN)
  ///
  /// 通过 FAN 平台获取的日本气象厅地震情报。
  jma_fan,

  /// HKO - 香港天文台
  ///
  /// 香港天文台发布的地震情报。
  hko,

  /// SA - ShakeAlert (美国西海岸预警)
  ///
  /// 美国西海岸地震预警系统发布的信息。
  sa,

  /// EMSC - 欧洲地中海地震中心
  ///
  /// 欧洲地中海地震中心发布的地震信息。
  emsc,

  /// BCSF - 法国中央地震研究所
  ///
  /// 法国中央地震研究所发布的地震信息。
  bcsf,

  /// GFZ - 德国地学研究中心
  ///
  /// 德国地学研究中心发布的地震信息。
  gfz,

  /// USP - 巴西圣保罗大学
  ///
  /// 巴西圣保罗大学地震中心发布的信息。
  usp,

  /// KMA_EQ - 韩国气象厅地震情报
  ///
  /// 韩国气象厅发布的地震情报。
  kma_eq,

  /// KMA_EEW_FAN - 韩国气象厅预警 (通过 FAN)
  ///
  /// 通过 FAN 平台获取的韩国气象厅地震预警。
  kma_eew_fan,

  /// 宁夏地震局
  ningxia,

  /// 广西地震局
  guangxi,

  /// 山西地震局
  shanxi,

  /// 北京地震局
  beijing,

  /// 云南地震局
  yunnan,

  /// CENC 烈度速报
  ///
  /// 中国地震台网中心发布的仪器烈度速报数据。
  /// 包含等震线图和各测站烈度信息。
  cencIr,

  /// FSSN-CMT - FSSN 震源机制解
  ///
  /// FSSN 地震学部反演的矩心矩张量解(Centroid Moment Tensor)。
  /// 包含断层面参数(nodalPlane)和矩张量分量，用于绘制震源球。
  fssnCmt,
}

/// QuakeSourceType 扩展方法
///
/// 提供数据源的显示名称和预警标签。
extension QuakeSourceTypeExtension on QuakeSourceType {
  /// 获取数据源的显示名称
  ///
  /// 用于在 UI 中显示数据源标识。
  /// 返回格式为 "机构名称 (国家/地区)" 的中文字符串。
  String get displayName {
    switch (this) {
      case QuakeSourceType.wolfx:
        return 'Wolfx (JMA)';
      case QuakeSourceType.nied:
        return 'NIED (日本)';
      case QuakeSourceType.p2p:
        return 'P2P 预警网';
      case QuakeSourceType.cenc:
        return '中国地震台网 (CENC)';
      case QuakeSourceType.usgs:
        return 'USGS (美国)';
      case QuakeSourceType.cwa:
        return '中央气象署 (CWA)';
      case QuakeSourceType.fssn:
        return 'FSSN 地震信息';
      case QuakeSourceType.sc_eew:
        return '四川省地震局';
      case QuakeSourceType.fj_eew:
        return '福建省地震局';
      case QuakeSourceType.cq_eew:
        return '重庆市地震局';
      case QuakeSourceType.cwa_eew:
        return '台湾中央气象署 (CWA)';
      case QuakeSourceType.cea:
        return '中国地震预警网地震预警';
      case QuakeSourceType.cea_pr:
        return '中国地震预警网省级网地震预警';
      case QuakeSourceType.jma_fan:
        return '日本气象厅 (JMA)';
      case QuakeSourceType.hko:
        return '香港天文台 (HKO)';
      case QuakeSourceType.sa:
        return 'ShakeAlert (美国)';
      case QuakeSourceType.emsc:
        return '欧洲地中海地震中心';
      case QuakeSourceType.bcsf:
        return '法国中央地震研究所';
      case QuakeSourceType.gfz:
        return '德国地学研究中心';
      case QuakeSourceType.usp:
        return '巴西圣保罗大学';
      case QuakeSourceType.kma_eq:
        return '韩国气象厅 (KMA)';
      case QuakeSourceType.kma_eew_fan:
        return '韩国气象厅预警 (KMA)';
      case QuakeSourceType.ningxia:
        return '宁夏地震局';
      case QuakeSourceType.guangxi:
        return '广西地震局';
      case QuakeSourceType.shanxi:
        return '山西地震局';
      case QuakeSourceType.beijing:
        return '北京地震局';
      case QuakeSourceType.yunnan:
        return '云南地震局';
      case QuakeSourceType.cencIr:
        return '中国地震台网烈度速报';
      case QuakeSourceType.fssnCmt:
        return 'FSSN 震源机制解';
    }
  }

  /// 获取数据源的预警标签
  ///
  /// 用于在预警通知中显示数据源类型。
  /// 返回格式为 "机构 预警类型" 的中文字符串。
  String get warningLabel {
    switch (this) {
      case QuakeSourceType.wolfx:
        return 'JMA 紧急地震速报';
      case QuakeSourceType.nied:
        return 'NIED 強震情報';
      case QuakeSourceType.p2p:
        return 'JMA 地震情報';
      case QuakeSourceType.cenc:
        return '中国地震台网预警';
      case QuakeSourceType.usgs:
        return 'USGS 地震情报';
      case QuakeSourceType.cwa:
        return '中央气象署 地震情报';
      case QuakeSourceType.fssn:
        return 'FSSN 地震信息';
      case QuakeSourceType.sc_eew:
        return '四川省地震局预警';
      case QuakeSourceType.fj_eew:
        return '福建省地震局预警';
      case QuakeSourceType.cq_eew:
        return '重庆市地震局预警';
      case QuakeSourceType.cwa_eew:
        return '中央气象署 预警';
      case QuakeSourceType.cea:
        return '中国地震预警网地震预警';
      case QuakeSourceType.cea_pr:
        return '中国地震预警网省级网地震预警';
      case QuakeSourceType.jma_fan:
        return 'JMA 地震预警';
      case QuakeSourceType.hko:
        return '香港天文台 地震情报';
      case QuakeSourceType.sa:
        return 'ShakeAlert 地震预警';
      case QuakeSourceType.emsc:
        return 'EMSC 地震情报';
      case QuakeSourceType.bcsf:
        return 'BCSF 地震情报';
      case QuakeSourceType.gfz:
        return 'GFZ 地震情报';
      case QuakeSourceType.usp:
        return 'USP 地震情报';
      case QuakeSourceType.kma_eq:
        return 'KMA 地震情报';
      case QuakeSourceType.kma_eew_fan:
        return 'KMA 地震预警';
      case QuakeSourceType.ningxia:
        return '宁夏地震局 地震情报';
      case QuakeSourceType.guangxi:
        return '广西地震局 地震情报';
      case QuakeSourceType.shanxi:
        return '山西地震局 地震情报';
      case QuakeSourceType.beijing:
        return '北京地震局 地震情报';
      case QuakeSourceType.yunnan:
        return '云南地震局 地震情报';
      case QuakeSourceType.cencIr:
        return '中国地震台网烈度速报';
      case QuakeSourceType.fssnCmt:
        return 'FSSN 震源机制解';
    }
  }
}

/// 地震消息数据类
///
/// 表示一次地震事件的完整信息，包括震源参数、震度信息、
/// 海啸预警等。这是应用中地震数据的核心数据结构。
///
/// ## 字段说明
///
/// ### 基本参数
/// - [source]: 数据来源
/// - [eventId]: 事件唯一标识
/// - [location]: 震中位置描述
/// - [magnitude]: 震级
/// - [latitude]/[longitude]: 震中坐标
/// - [depth]: 震源深度 (km)
/// - [originTime]: 发震时间
///
/// ### 状态标志
/// - [isTest]: 是否为测试/训练报
/// - [isHistory]: 是否为历史事件
/// - [isInfoEvent]: 是否为情报事件
/// - [isTsunamiWarning]: 是否有海啸预警
///
/// ### 震度信息
/// - [maxIntensity]: 最大烈度/震度
/// - [jmaShindo]: JMA 震度等级字符串
///
/// ### 报告信息
/// - [reportNumber]: 报告编号
/// - [reportTime]: 报告发布时间
///
/// ### EEW 特有字段
/// - [isWarn]: 是否为警报级预警
/// - [isFinal]: 是否为最终报
/// - [isCanceled]: 是否为取消报
/// - [isAssumption]: 是否为假定震源
/// - [reportNumText]: 报告编号的显示文本
///
/// ### 区域字段
/// - [verify]: 验证状态
/// - [province]: 省份信息
class QuakeMessage {
  /// 数据来源
  ///
  /// 标识此消息来自哪个数据源服务。
  final QuakeSourceType source;

  /// 事件唯一标识
  ///
  /// 用于去重和追踪同一地震事件的多次报告。
  /// 不同数据源可能使用不同的 ID 格式。
  final String eventId;

  /// 震中位置描述
  ///
  /// 人类可读的位置描述，如 "四川省成都市都江堰市"。
  final String location;

  /// 震级
  ///
  /// 地震震级，通常使用里氏震级或面波震级。
  /// -1 表示未知或未测定。
  final double magnitude;

  /// 震中纬度
  ///
  /// 北纬为正，南纬为负。
  final double latitude;

  /// 震中经度
  ///
  /// 东经为正，西经为负。
  final double longitude;

  /// 震源深度
  ///
  /// 单位：公里 (km)。
  /// -1 表示未知或未测定。
  final double depth;

  /// 发震时间
  ///
  /// 地震发生的 UTC 时间。
  final DateTime originTime;

  /// 是否为测试/训练报
  ///
  /// JMA 和其他机构会定期发布测试报用于系统演练。
  /// 此类消息通常不应触发用户通知。
  final bool isTest;

  /// 最大烈度/震度
  ///
  /// 中国烈度标准：1-12 度
  /// JMA 震度标准：1-7 级 (整数)
  final int? maxIntensity;

  /// 是否有海啸预警
  ///
  /// 为 true 时，[tsunamiWarning] 字段包含预警详情。
  final bool isTsunamiWarning;

  /// 海啸预警内容
  ///
  /// 海啸预警等级或详情，如 "大海啸警报"、"海啸警报已解除"。
  final String? tsunamiWarning;

  /// 是否为历史事件
  ///
  /// 标识此消息是否为历史地震记录而非实时事件。
  final bool isHistory;

  /// JMA 震度等级字符串
  ///
  /// JMA 特有的震度表示，如 "5弱"、"5强"、"6弱"、"6强"。
  final String? jmaShindo;

  /// 测定类型
  ///
  /// - "automatic": 自动测定，精度较低
  /// - "reviewed": 人工复核，精度较高
  final String? reviewType;

  /// 信息类型名称
  ///
  /// 地震信息的具体类型，如 "正式测定"、"速报" 等。
  final String? infoTypeName;

  /// 验证状态
  ///
  /// 信息的验证或确认状态。
  final String? verify;

  /// 是否为情报事件
  ///
  /// 标识此消息是否为情报类事件（非预警）。
  final bool isInfoEvent;

  /// 报告编号
  ///
  /// 同一地震事件的第几号报告，用于追踪更新。
  final int? reportNumber;

  /// 报告发布时间
  ///
  /// 机构发布此报告的时间，通常晚于发震时间。
  final DateTime? reportTime;

  /// 省份信息
  ///
  /// 震中所在省份，用于国内地震。
  final String? province;

  /// 断层面解 1 (strike/dip/rake)
  ///
  /// FSSN-CMT 震源机制解，格式如 "75/33/7"。
  final String? nodalPlane1;

  /// 断层面解 2 (strike/dip/rake)
  ///
  /// FSSN-CMT 震源机制解，格式如 "340/86/122"。
  final String? nodalPlane2;

  // ═══════════════════════════════════════════════════════════════════════════
  // EEW 特有字段
  // ═══════════════════════════════════════════════════════════════════════════

  /// 是否为警报级预警
  ///
  /// JMA: isWarn = true 表示发布了紧急地震警报
  /// CENC/CEA: isWarn = true 表示预估烈度 >= 6.5
  /// CWA: isWarn = true 表示预估震度 >= 5
  final bool isWarn;

  /// 是否为最终报
  ///
  /// 标识此报告是否为该事件的最终确定信息。
  /// 收到最终报后可以认为该事件的参数已确定。
  final bool isFinal;

  /// 是否为取消报
  ///
  /// 标识此前的预警被取消或撤销。
  final bool isCanceled;

  /// 是否为假定震源
  ///
  /// 标识震源参数为假定值，精度较低。
  /// JMA 在震度速报阶段可能使用假定震源。
  final bool isAssumption;

  /// 报告编号的显示文本
  ///
  /// 如 "第1报"、"第3报"、"キャンセル報"。
  final String? reportNumText;

  /// 构造函数
  ///
  /// 创建一个地震消息实例。
  /// 必填参数包括数据源、事件ID、位置、震级、坐标、深度和发震时间。
  QuakeMessage({
    required this.source,
    required this.eventId,
    required this.location,
    required this.magnitude,
    required this.latitude,
    required this.longitude,
    required this.depth,
    required this.originTime,
    this.isTest = false,
    this.maxIntensity,
    this.isTsunamiWarning = false,
    this.tsunamiWarning,
    this.isHistory = false,
    this.jmaShindo,
    this.reviewType,
    this.infoTypeName,
    this.verify,
    this.isInfoEvent = false,
    this.reportNumber,
    this.reportTime,
    this.province,
    this.nodalPlane1,
    this.nodalPlane2,
    this.isWarn = false,
    this.isFinal = false,
    this.isCanceled = false,
    this.isAssumption = false,
    this.reportNumText,
  });

  /// 创建一个副本并更新指定字段
  ///
  /// 用于更新已有地震事件的参数。
  /// 返回新的 QuakeMessage 实例，未指定的字段保持原值。
  QuakeMessage copyWith({
    String? eventId,
    String? location,
    double? magnitude,
    double? latitude,
    double? longitude,
    double? depth,
    DateTime? originTime,
    bool? isTest,
    int? maxIntensity,
    bool? isTsunamiWarning,
    String? tsunamiWarning,
    bool? isHistory,
    String? jmaShindo,
    String? reviewType,
    String? infoTypeName,
    String? verify,
    bool? isInfoEvent,
    int? reportNumber,
    DateTime? reportTime,
    String? province,
    String? nodalPlane1,
    String? nodalPlane2,
    bool? isWarn,
    bool? isFinal,
    bool? isCanceled,
    bool? isAssumption,
    String? reportNumText,
  }) {
    return QuakeMessage(
      source: source,
      eventId: eventId ?? this.eventId,
      location: location ?? this.location,
      magnitude: magnitude ?? this.magnitude,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      depth: depth ?? this.depth,
      originTime: originTime ?? this.originTime,
      isTest: isTest ?? this.isTest,
      maxIntensity: maxIntensity ?? this.maxIntensity,
      isTsunamiWarning: isTsunamiWarning ?? this.isTsunamiWarning,
      tsunamiWarning: tsunamiWarning ?? this.tsunamiWarning,
      isHistory: isHistory ?? this.isHistory,
      jmaShindo: jmaShindo ?? this.jmaShindo,
      reviewType: reviewType ?? this.reviewType,
      infoTypeName: infoTypeName ?? this.infoTypeName,
      verify: verify ?? this.verify,
      isInfoEvent: isInfoEvent ?? this.isInfoEvent,
      reportNumber: reportNumber ?? this.reportNumber,
      reportTime: reportTime ?? this.reportTime,
      province: province ?? this.province,
      nodalPlane1: nodalPlane1 ?? this.nodalPlane1,
      nodalPlane2: nodalPlane2 ?? this.nodalPlane2,
      isWarn: isWarn ?? this.isWarn,
      isFinal: isFinal ?? this.isFinal,
      isCanceled: isCanceled ?? this.isCanceled,
      isAssumption: isAssumption ?? this.isAssumption,
      reportNumText: reportNumText ?? this.reportNumText,
    );
  }

  /// 转换为 Map
  ///
  /// 将消息对象序列化为 Map，用于数据库存储。
  ///
  /// 返回：
  /// - 包含所有字段的 Map，布尔值转换为 0/1 整数
  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'source': source.toString(),
      'location': location,
      'magnitude': magnitude,
      'latitude': latitude,
      'longitude': longitude,
      'depth': depth,
      'originTime': originTime.toIso8601String(),
      'isTest': isTest ? 1 : 0,
      'maxIntensity': maxIntensity,
      'isTsunamiWarning': isTsunamiWarning ? 1 : 0,
      'tsunamiWarning': tsunamiWarning,
      'isHistory': isHistory ? 1 : 0,
      'jmaShindo': jmaShindo,
      'reviewType': reviewType,
      'infoTypeName': infoTypeName,
      'verify': verify,
      'isInfoEvent': isInfoEvent ? 1 : 0,
      'reportNumber': reportNumber,
      'reportTime': reportTime?.toIso8601String(),
      'province': province,
      'nodalPlane1': nodalPlane1,
      'nodalPlane2': nodalPlane2,
      'isWarn': isWarn ? 1 : 0,
      'isFinal': isFinal ? 1 : 0,
      'isCanceled': isCanceled ? 1 : 0,
      'isAssumption': isAssumption ? 1 : 0,
      'reportNumText': reportNumText,
    };
  }

  /// 从 Map 创建实例
  ///
  /// 从数据库存储的 Map 数据反序列化消息对象。
  ///
  /// 参数：
  /// - [map]: 包含消息数据的 Map
  ///
  /// 返回：
  /// - 反序列化后的 QuakeMessage 实例
  factory QuakeMessage.fromMap(Map<String, dynamic> map) {
    return QuakeMessage(
      eventId: map['eventId'],
      source: QuakeSourceType.values.firstWhere(
        (e) => e.toString() == map['source'],
        orElse: () => QuakeSourceType.wolfx,
      ),
      location: map['location'],
      magnitude: map['magnitude'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      depth: map['depth'],
      originTime: DateTime.parse(map['originTime']),
      isTest: map['isTest'] == 1,
      maxIntensity: map['maxIntensity'],
      isTsunamiWarning: map['isTsunamiWarning'] == 1,
      tsunamiWarning: map['tsunamiWarning'],
      isHistory: map['isHistory'] == 1,
      jmaShindo: map['jmaShindo'],
      reviewType: map['reviewType'],
      infoTypeName: map['infoTypeName'],
      verify: map['verify'],
      isInfoEvent: map['isInfoEvent'] == 1,
      reportNumber: map['reportNumber'],
      reportTime: map['reportTime'] != null
          ? DateTime.parse(map['reportTime'])
          : null,
      province: map['province'],
      isWarn: map['isWarn'] == 1,
      isFinal: map['isFinal'] == 1,
      isCanceled: map['isCanceled'] == 1,
      isAssumption: map['isAssumption'] == 1,
      reportNumText: map['reportNumText'],
    );
  }
}
