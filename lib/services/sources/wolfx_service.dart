/// Wolfx 地震预警聚合服务
///
/// 本模块实现了 Wolfx WebSocket API 的数据获取与处理。
/// Wolfx 是一个聚合多个地震预警数据源的实时推送服务。
///
/// 支持的数据源：
/// - **JMA**: 日本气象厅紧急地震速报
/// - **CENC**: 中国地震台网中心地震预警
/// - **FJ_EEW**: 福建省地震局地震预警
/// - **CQ_EEW**: 重庆市地震局地震预警
/// - **SC_EEW**: 四川省地震局地震预警
/// - **CWA**: 台湾中央气象署地震预警
///
/// 主要功能：
/// - WebSocket 实时连接管理
/// - 多格式消息解析与分发
/// - 自动重连与错误处理
/// - 心跳检测与响应
///
/// 数据流程：
/// 1. 建立 WebSocket 连接到 wss://ws-api.wolfx.jp/all_eew
/// 2. 接收实时推送的地震预警消息
/// 3. 根据消息类型分发到对应的处理方法
/// 4. 解析数据并转换为统一的 QuakeMessage 格式
/// 5. 通过回调通知上层应用

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'base_source.dart';
import '../../models/unified_quake_data.dart';
import '../quake_event_adapter.dart';
import '../../models/quake_message.dart';
import '../../models/source_status.dart';
import '../../core/intensity_calculator.dart';

/// Wolfx 服务类
///
/// 继承自 BaseSourceService，实现 Wolfx API 的具体逻辑。
/// 负责管理 WebSocket 连接、消息解析和数据分发。
class WolfxService extends BaseSourceService {
  /// 服务名称标识
  @override
  String get name => 'Wolfx';

  // ═══════════════════════════════════════════════════════════════════════════
  // 连接配置
  // ═══════════════════════════════════════════════════════════════════════════

  /// WebSocket 服务端点 URL
  ///
  /// Wolfx API 的统一入口，订阅所有地震预警数据流。
  final String _wsUrl = "wss://ws-api.wolfx.jp:443/all_eew";

  /// WebSocket 通道实例
  WebSocketChannel? _channel;

  // ═══════════════════════════════════════════════════════════════════════════
  // 状态变量
  // ═══════════════════════════════════════════════════════════════════════════

  /// 重连定时器
  Timer? _reconnectTimer;

  /// 重试计数器
  int _retryCount = 0;

  void Function(List<QuakeMessage>)? onJmaEqlistUpdated;
  void Function(List<QuakeMessage>)? onCencEqlistUpdated;

  /// 是否为手动关闭
  ///
  /// 用于区分手动断开和异常断开。
  /// 手动断开时不触发自动重连。
  bool _isManualClose = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // 连接管理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 发起连接
  ///
  /// 建立 WebSocket 连接到 Wolfx 服务器。
  /// 连接成功后自动监听消息流，连接失败则触发重连机制。
  @override
  void connect() async {
    _isManualClose = false;
    _reconnectTimer?.cancel();
    await _cleanup();
    onStatusChanged?.call(SourceStatus.connecting);
    print("正在建立 Wolfx 链路: $_wsUrl (尝试次数: ${_retryCount + 1})");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _channel!.stream.listen(
        (data) {
          // 连接恢复正常，重置重试计数
          if (_retryCount > 0) {
            print("Wolfx 链路已恢复正常");
          }
          _retryCount = 0;
          onStatusChanged?.call(SourceStatus.connected);
          _dispatch(data);
        },
        onDone: () {
          print("Wolfx 链路远程关闭");
          _handleFailure();
        },
        onError: (err) {
          print("Wolfx 链路传输错误: $err");
          _handleFailure();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("Wolfx 初始握手失败: $e");
      _handleFailure();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 消息分发
  // ═══════════════════════════════════════════════════════════════════════════

  /// 消息分发器
  ///
  /// 根据消息类型将数据分发到对应的处理方法。
  ///
  /// 支持的消息类型：
  /// - `heartbeat`: 心跳消息，需要回复 pong
  /// - `jma_eew`: 日本气象厅紧急地震速报
  /// - `cenc_eew`: 中国地震台网中心地震预警
  /// - `fj_eew`: 福建省地震局地震预警
  /// - `cq_eew`: 重庆市地震局地震预警
  /// - `sc_eew`: 四川省地震局地震预警
  /// - `cenc_eqlist`: 中国地震台网地震列表
  /// - 空类型: 台湾中央气象署地震预警
  ///
  /// 参数：
  /// - [data]: 原始消息数据
  void _dispatch(dynamic data) {
    try {
      final json = jsonDecode(data);
      if (json is! Map<String, dynamic>) return;

      final String type = json['type']?.toString() ?? '';

      // 处理心跳消息
      if (type == 'heartbeat') {
        _channel?.sink.add(
          jsonEncode({
            "type": "pong",
            "timestamp": json['timestamp']?.toString(),
          }),
        );
        return;
      }

      // 根据类型分发到对应处理方法
      switch (type) {
        case 'jma_eew':
          _handleJmaEew(json);
          _emitUnified('jmaEew', json);
          break;
        case 'cenc_eew':
          _handleCencEew(json);
          _emitUnified('ceaEew', json);
          break;
        case 'fj_eew':
          _handleFjEew(json);
          _emitUnified('fjEew', json);
          break;
        case 'cq_eew':
          _handleCqEew(json);
          _emitUnified('cqEew', json);
          break;
        case 'sc_eew':
          _handleScEew(json);
          _emitUnified('scEew', json);
          break;
        case 'cenc_eqlist':
          _handleCencEqlist(json);
          final cencItems = QuakeEventAdapter.convertWolfxCencEqlist(json);
          if (cencItems.isNotEmpty) onCencEqlistUpdated?.call(cencItems);
          final firstEntry = json['No1'];
          if (firstEntry is Map) {
            _emitUnified('cencEqlist', Map<String, dynamic>.from(firstEntry));
          }
          break;
        case 'jma_eqlist':
          final jmaItems = QuakeEventAdapter.convertWolfxJmaEqlist(json);
          if (jmaItems.isNotEmpty) onJmaEqlistUpdated?.call(jmaItems);
          final jmaFirst = json['No1'];
          if (jmaFirst is Map) {
            _emitUnified('jmaEqlist', Map<String, dynamic>.from(jmaFirst));
          }
          break;
        case '':
          _handleCwaNoType(json);
          _emitUnified('cwaEew', json);
          break;
        default:
          print("Wolfx 未知 type: $type");
      }
    } catch (e) {
      print("Wolfx 数据解析异常: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JMA 緊急地震速報处理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理日本气象厅紧急地震速报
  ///
  /// JMA (Japan Meteorological Agency) 是日本官方的地震预警机构。
  /// EEW (Early Earthquake Warning) 是地震预警系统。
  ///
  /// 消息字段：
  /// - `Title`: 标题
  /// - `CodeType`: 代码类型
  /// - `Issue`: 发布信息（嵌套对象）
  /// - `EventID`: 事件唯一标识
  /// - `Serial`: 报告序号
  /// - `AnnouncedTime`: 发布时间
  /// - `OriginTime`: 地震发生时间
  /// - `Hypocenter`: 震中地名
  /// - `Latitude`/`Longitude`: 震中坐标
  /// - `Magunitude`: 震级（注意拼写）
  /// - `Depth`: 震源深度
  /// - `MaxIntensity`: 最大震度（字符串型，如"5強"）
  /// - `Accuracy`: 精度信息
  /// - `MaxIntChange`: 最大震度变化
  /// - `WarnArea`: 警报区域
  /// - `isSea`: 是否为海域地震
  /// - `isTraining`: 是否为训练报
  /// - `isAssumption`: 是否为假定震源
  /// - `isWarn`: 是否发布警报
  /// - `isFinal`: 是否为最终报
  /// - `isCancel`: 是否为取消报
  ///
  /// 参数：
  /// - [json]: JSON 格式的消息数据
  void _handleJmaEew(dynamic json) {
    print('RAW >> Wolfx jma_eew: $json');
    try {
      // ─── 基础字段 ───
      final String titleRaw = json['Title']?.toString() ?? '';
      final String codeType = json['CodeType']?.toString() ?? '';

      // Issue 嵌套对象
      final issue = json['Issue'];
      final String issueSource = issue is Map
          ? (issue['Source']?.toString() ?? '')
          : '';
      final String issueStatus = issue is Map
          ? (issue['Status']?.toString() ?? '')
          : '';

      final String eventId = json['EventID']?.toString() ?? '';
      final int serial = int.tryParse(json['Serial']?.toString() ?? '') ?? 0;
      final String announcedTime = json['AnnouncedTime']?.toString() ?? '';
      final String originTimeStr = json['OriginTime']?.toString() ?? '';

      // ─── 震源信息 ───
      final String hypocenter = json['Hypocenter']?.toString() ?? '';
      final double latitude =
          double.tryParse(json['Latitude']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(json['Longitude']?.toString() ?? '') ?? 0.0;
      final double magnitude =
          double.tryParse(json['Magunitude']?.toString() ?? '') ?? 0.0;
      final double depth =
          double.tryParse(json['Depth']?.toString() ?? '') ?? 0.0;

      // JMA MaxIntensity 是弱/強字符串型
      final String maxIntensityRaw = json['MaxIntensity']?.toString() ?? '';

      // ─── 精度信息 ───
      final accuracy = json['Accuracy'];
      final String accEpicenter = accuracy is Map
          ? (accuracy['Epicenter']?.toString() ?? '')
          : '';
      final String accDepth = accuracy is Map
          ? (accuracy['Depth']?.toString() ?? '')
          : '';
      final String accMagnitude = accuracy is Map
          ? (accuracy['Magnitude']?.toString() ?? '')
          : '';

      // ─── 震度变化信息 ───
      final maxIntChange = json['MaxIntChange'];
      final String micString = maxIntChange is Map
          ? (maxIntChange['String']?.toString() ?? '')
          : '';
      final String micReason = maxIntChange is Map
          ? (maxIntChange['Reason']?.toString() ?? '')
          : '';

      // ─── 警报区域信息 ───
      final warnArea = json['WarnArea'];
      final String waChiiki = warnArea is Map
          ? (warnArea['Chiiki']?.toString() ?? '')
          : '';
      final String waShindo1 = warnArea is Map
          ? (warnArea['Shindo1']?.toString() ?? '')
          : '';
      final String waShindo2 = warnArea is Map
          ? (warnArea['Shindo2']?.toString() ?? '')
          : '';
      final String waTime = warnArea is Map
          ? (warnArea['Time']?.toString() ?? '')
          : '';
      final String waType = warnArea is Map
          ? (warnArea['Type']?.toString() ?? '')
          : '';
      final bool waArrive = warnArea is Map
          ? (warnArea['Arrive'] == true)
          : false;

      // ─── 布尔标志 ───
      final bool isSea = json['isSea'] == true;
      final bool isTraining = json['isTraining'] == true;
      final bool isAssumption = json['isAssumption'] == true;
      final bool isWarn = json['isWarn'] == true;
      final bool isFinal = json['isFinal'] == true;
      final bool isCancel = json['isCancel'] == true;

      final String originalText = json['OriginalText']?.toString() ?? '';

      // ─── 过滤训练/取消报 ───
      if (isTraining || isCancel) {
        print("Wolfx JMA EEW: 跳过${isTraining ? "训练报" : "取消报"} $eventId");
        return;
      }

      final originTime = DateTime.tryParse(originTimeStr.replaceAll('/', '-')) ?? DateTime.now();
      final DateTime? parsedAnnouncedTime = announcedTime.isNotEmpty
          ? DateTime.tryParse(announcedTime.replaceAll('/', '-'))
          : null;

      // JMA 震度字符串: "5強" -> "5+", "5弱" -> "5-", "3" -> "3"
      // 仅用于 jmaShindo 震度徽章显示，不转为数值型 maxIntensity
      final String? jmaShindo = maxIntensityRaw.isNotEmpty
          ? _formatShindo(maxIntensityRaw)
          : null;

      print(
        "Wolfx JMA EEW: $hypocenter M${magnitude.toStringAsFixed(1)} "
        "深度${depth.round()}km 震度$maxIntensityRaw"
        "${isWarn ? " [警报]" : ""}${isFinal ? " [最终报]" : ""}",
      );

      // 旧管道已关闭，统一走 emitUnified 新管道
    } catch (e) {
      print("Wolfx JMA EEW 解析异常: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 中国地震台网预警处理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理中国地震台网中心地震预警
  ///
  /// CENC EEW 格式与 JMA EEW 类似，但字段风格略有差异。
  ///
  /// 参数：
  /// - [json]: JSON 格式的消息数据
  void _handleCencEew(dynamic json) {
    print('RAW >> Wolfx cenc_eew: $json');
    try {
      final String id = json['ID']?.toString() ?? '';
      final String eventId = json['EventID']?.toString() ?? '';
      final String reportTime = json['ReportTime']?.toString() ?? '';
      final int reportNum =
          int.tryParse(json['ReportNum']?.toString() ?? '') ?? 0;
      final String originTimeStr = json['OriginTime']?.toString() ?? '';

      final String hypocenter = json['HypoCenter']?.toString() ?? '';
      final double latitude =
          double.tryParse(json['Latitude']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(json['Longitude']?.toString() ?? '') ?? 0.0;
      final double magnitude =
          double.tryParse(json['Magnitude']?.toString() ?? '') ?? 0.0;

      final depthRaw = json['Depth'];
      final double depth = depthRaw != null
          ? (double.tryParse(depthRaw.toString()) ?? 0.0)
          : 0.0;

      final int? maxIntensity = int.tryParse(
        json['MaxIntensity']?.toString() ?? '',
      );

      final originTime = DateTime.tryParse(originTimeStr) ?? DateTime.now();
      final DateTime? parsedReportTime = reportTime.isNotEmpty
          ? DateTime.tryParse(reportTime)
          : null;

      print(
        "Wolfx CENC EEW: $hypocenter M${magnitude.toStringAsFixed(1)} "
        "深度${depth.round()}km 烈度$maxIntensity",
      );

      // 旧管道已关闭，统一走 emitUnified 新管道
    } catch (e) {
      print("Wolfx CENC EEW 解析异常: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 省级地震预警处理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理福建省地震局地震预警
  ///
  /// 福建省地震局提供的地震预警服务。
  /// 消息格式与 CENC 类似，但震级字段拼写为 `Magunitude`。
  ///
  /// 参数：
  /// - [json]: JSON 格式的消息数据
  void _handleFjEew(dynamic json) {
    print('RAW >> Wolfx fj_eew: $json');
    try {
      final String id = json['ID']?.toString() ?? '';
      final String eventId = json['EventID']?.toString() ?? '';
      final String reportTime = json['ReportTime']?.toString() ?? '';
      final int reportNum =
          int.tryParse(json['ReportNum']?.toString() ?? '') ?? 0;
      final String originTimeStr = json['OriginTime']?.toString() ?? '';

      final String hypocenter = json['HypoCenter']?.toString() ?? '';
      final double latitude =
          double.tryParse(json['Latitude']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(json['Longitude']?.toString() ?? '') ?? 0.0;
      final double magnitude =
          double.tryParse(json['Magunitude']?.toString() ?? '') ?? 0.0;
      final bool isFinal = json['isFinal'] == true;

      final depthRaw = json['Depth'];
      final double depth = depthRaw != null
          ? (double.tryParse(depthRaw.toString()) ?? 0.0)
          : 0.0;

      final originTime = DateTime.tryParse(originTimeStr) ?? DateTime.now();
      final DateTime? parsedReportTime = reportTime.isNotEmpty
          ? DateTime.tryParse(reportTime)
          : null;

      print(
        "Wolfx 福建 EEW: $hypocenter M${magnitude.toStringAsFixed(1)}"
        "${isFinal ? " [最终报]" : ""}",
      );

      // 旧管道已关闭
      // 旧管道已关闭，统一走新管道 (emitUnified)
    } catch (e) {
      print("Wolfx 福建 EEW 解析异常: $e");
    }
  }

  /// 处理重庆市地震局地震预警
  ///
  /// 重庆市地震局提供的地震预警服务。
  ///
  /// 参数：
  /// - [json]: JSON 格式的消息数据
  void _handleCqEew(dynamic json) {
    print('RAW >> Wolfx cq_eew: $json');
    try {
      final String id = json['ID']?.toString() ?? '';
      final String eventId = json['EventID']?.toString() ?? '';
      final String reportTime = json['ReportTime']?.toString() ?? '';
      final int reportNum =
          int.tryParse(json['ReportNum']?.toString() ?? '') ?? 0;
      final String originTimeStr = json['OriginTime']?.toString() ?? '';

      final String hypocenter = json['HypoCenter']?.toString() ?? '';
      final double latitude =
          double.tryParse(json['Latitude']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(json['Longitude']?.toString() ?? '') ?? 0.0;
      final double magnitude =
          double.tryParse(json['Magnitude']?.toString() ?? '') ?? 0.0;

      final depthRaw = json['Depth'];
      final double depth = depthRaw != null
          ? (double.tryParse(depthRaw.toString()) ?? 0.0)
          : 0.0;

      final int? maxIntensity = int.tryParse(
        json['MaxIntensity']?.toString() ?? '',
      );

      final originTime = DateTime.tryParse(originTimeStr) ?? DateTime.now();
      final DateTime? parsedReportTime = reportTime.isNotEmpty
          ? DateTime.tryParse(reportTime)
          : null;

      print(
        "Wolfx 重庆 EEW: $hypocenter M${magnitude.toStringAsFixed(1)} "
        "深度${depth.round()}km 烈度$maxIntensity",
      );

      // 旧管道已关闭
      // 旧管道已关闭，统一走新管道 (emitUnified)
    } catch (e) {
      print("Wolfx 重庆 EEW 解析异常: $e");
    }
  }

  /// 处理四川省地震局地震预警
  ///
  /// 四川省地震局提供的地震预警服务。
  /// 注意：震级字段可能为 `Magnitude` 或 `Magunitude`。
  ///
  /// 参数：
  /// - [json]: JSON 格式的消息数据
  void _handleScEew(dynamic json) {
    print('RAW >> Wolfx sc_eew: $json');
    try {
      final String id = json['ID']?.toString() ?? '';
      final String eventId = json['EventID']?.toString() ?? '';
      final String reportTime = json['ReportTime']?.toString() ?? '';
      final int reportNum =
          int.tryParse(json['ReportNum']?.toString() ?? '') ?? 0;
      final String originTimeStr = json['OriginTime']?.toString() ?? '';
      final String hypocenter =
          json['HypoCenter']?.toString() ??
          json['Hypocenter']?.toString() ??
          '';
      final double latitude =
          double.tryParse(json['Latitude']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(json['Longitude']?.toString() ?? '') ?? 0.0;
      final double magnitude =
          double.tryParse(
            (json['Magnitude'] ?? json['Magunitude'] ?? '0.0').toString(),
          ) ??
          0.0;
      final double depth =
          double.tryParse(json['Depth']?.toString() ?? '') ?? 0.0;
      final int? maxIntensity = int.tryParse(
        json['MaxIntensity']?.toString() ?? '',
      );

      final originTime = DateTime.tryParse(originTimeStr) ?? DateTime.now();
      final DateTime? parsedReportTime = reportTime.isNotEmpty
          ? DateTime.tryParse(reportTime)
          : null;

      print(
        "Wolfx 四川 EEW: $hypocenter M${magnitude.toStringAsFixed(1)} "
        "深度${depth.round()}km",
      );

      // 旧管道已关闭
      // 旧管道已关闭，统一走新管道 (emitUnified)
    } catch (e) {
      print("Wolfx 四川 EEW 解析异常: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 地震列表处理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理中国地震台网地震列表
  ///
  /// 批量推送最近 50 条地震记录。
  /// 数据格式为 No1 到 No50 的编号条目。
  ///
  /// 参数：
  /// - [json]: JSON 格式的消息数据
  void _handleCencEqlist(dynamic json) {
    try {
      int emitted = 0;
      for (int i = 1; i <= 50; i++) {
        final entry = json['No$i'];
        if (entry is! Map) continue;

        final String timeStr = entry['time']?.toString() ?? '';
        final String locationName = entry['location']?.toString() ?? '';
        final String placeName = entry['placeName']?.toString() ?? '';
        final double magnitude =
            double.tryParse(entry['magnitude']?.toString() ?? '') ?? 0.0;
        final double depth =
            double.tryParse(entry['depth']?.toString() ?? '') ?? 0.0;
        final double latitude =
            double.tryParse(entry['latitude']?.toString() ?? '') ?? 0.0;
        final double longitude =
            double.tryParse(entry['longitude']?.toString() ?? '') ?? 0.0;
        final String reviewType = entry['type']?.toString() ?? '';
        final String md5 = entry['md5']?.toString() ?? '';
        final String eventID = entry['EventID']?.toString() ?? '';
        final DateTime originTime =
            DateTime.tryParse(timeStr.replaceAll(' ', 'T')) ?? DateTime.now();

      // 旧管道已关闭
      // 旧管道已关闭，统一走新管道 (emitUnified)
        emitted++;
      }
      if (emitted > 0) print('Wolfx cenc_eqlist WS: $emitted items');
    } catch (e) {
      print("Wolfx cenc_eqlist WS error: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CWA 地震预警处理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理台湾中央气象署地震预警
  ///
  /// CWA (Central Weather Administration) 是台湾的气象主管机构。
  /// 注意：CWA 消息没有 `type` 字段，需要通过其他特征识别。
  /// 震级字段拼写为 `Magunitude`，最大震度为字符串型（如"5強"）。
  ///
  /// 参数：
  /// - [json]: JSON 格式的消息数据
  void _handleCwaNoType(dynamic json) {
    print('RAW >> Wolfx cwa_eew: $json');
    try {
      final String id = json['ID']?.toString() ?? '';
      final String reportTime = json['ReportTime']?.toString() ?? '';
      final int reportNum =
          int.tryParse(json['ReportNum']?.toString() ?? '') ?? 0;
      final String originTimeStr = json['OriginTime']?.toString() ?? '';

      final String hypocenter = json['HypoCenter']?.toString() ?? '';
      final double latitude =
          double.tryParse(json['Latitude']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(json['Longitude']?.toString() ?? '') ?? 0.0;
      final double magnitude =
          double.tryParse(json['Magunitude']?.toString() ?? '') ?? 0.0;
      final double depth =
          double.tryParse(json['Depth']?.toString() ?? '') ?? 0.0;

      // CWA MaxIntensity 字符串 -> 符号格式, 仅用于 jmaShindo 震度徽章
      final String maxIntensityRaw = json['MaxIntensity']?.toString() ?? '';
      final String? jmaShindo = maxIntensityRaw.isNotEmpty 
          ? _formatShindo(maxIntensityRaw) 
          : null;

      final originTime = DateTime.tryParse(originTimeStr) ?? DateTime.now();
      final DateTime? parsedReportTime = reportTime.isNotEmpty
          ? DateTime.tryParse(reportTime)
          : null;

      print(
        "Wolfx CWA EEW: $hypocenter M${magnitude.toStringAsFixed(1)} "
        "深度${depth.round()}km 震度$maxIntensityRaw",
      );

      // 旧管道已关闭
      // 旧管道已关闭，统一走新管道 (emitUnified)
    } catch (e) {
      print("Wolfx CWA EEW 解析异常: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════════════════════════════

  /// 格式化震度字符串
  ///
  /// 参考 kanameishi 的 formatShindo 函数
  /// 将震度转换为符号格式：
  /// - "5強" -> "5+"
  /// - "5弱" -> "5-"
  /// - "6強" -> "6+"
  /// - "6弱" -> "6-"
  String _formatShindo(String intensity) {
    if (intensity.isEmpty) return intensity;
    
    return intensity
        .replaceAll('強', '+')
        .replaceAll('弱', '-')
        .replaceAll('級', '')
        .trim();
  }

  /// 震度回退计算
  ///
  /// 当原始数据中没有震度信息时，根据震级和深度估算。
  /// 不同数据源使用不同的估算公式。
  ///
  /// 参数：
  /// - [source]: 数据源类型
  /// - [current]: 当前震度值（如果有）
  /// - [magnitude]: 震级
  /// - [depth]: 震源深度
  ///
  /// 返回：
  /// - 估算的震度值
  int? _fallbackIntensity({
    required QuakeSourceType source,
    required int? current,
    required double magnitude,
    required double depth,
  }) {
    if (current != null && current > 0) return current;

    // 根据数据源选择估算方法
    switch (source) {
      case QuakeSourceType.cenc:
      case QuakeSourceType.fj_eew:
      case QuakeSourceType.cq_eew:
      case QuakeSourceType.sc_eew:
        // 中国烈度标准 (CSIS)
        return IntensityCalculator.calcCsisLevel(magnitude, depth, 0);
      case QuakeSourceType.cwa_eew:
        // 台湾 CWB 震度等级
        return IntensityCalculator.calcCwbLevel(magnitude, depth, 0);
      default:
        return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 错误处理与重连
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理连接失败
  ///
  /// 当连接出错或断开时调用。
  /// 如果不是手动关闭，则安排自动重连。
  void _handleFailure() {
    if (_isManualClose) return;
    onStatusChanged?.call(SourceStatus.error);
    _retryCount++;

    // 指数退避重连：1, 2, 4, 8, 16, 32 秒，最大 60 秒
    final delay = (_retryCount > 6 ? 60 : (1 << _retryCount)).clamp(1, 60);
    print("Wolfx 链路异常，${delay}秒后重连 (第${_retryCount}次)");

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), connect);
  }

  /// 清理资源
  ///
  /// 关闭 WebSocket 连接并释放相关资源。
  Future<void> _cleanup() async {
    await _channel?.sink.close();
    _channel = null;
  }

  /// 断开连接
  ///
  /// 手动断开 WebSocket 连接。
  /// 设置手动关闭标志，避免触发自动重连。
  @override
  void disconnect() {
    _isManualClose = true;
    _reconnectTimer?.cancel();
    _cleanup();
    onStatusChanged?.call(SourceStatus.disconnected);
    print("Wolfx 链路已手动断开");
  }

  /// 通过适配器转换并发射统一事件
  void _emitUnified(String source, Map<String, dynamic> data) {
    final result = QuakeEventAdapter.convert(source, data, 0);
    if (result != null) {
      emitUnified(result);
    }
  }

  /// 释放资源
  ///
  /// 完全清理所有资源，包括定时器和连接。
  @override
  void dispose() {
    disconnect();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
