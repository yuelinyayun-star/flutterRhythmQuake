/// FAN 地震数据聚合服务
///
/// 本模块实现了 FanStudio 地震数据聚合平台的数据获取与处理。
/// FAN 是一个聚合全球多个地震机构数据的实时推送服务。
///
/// 支持的数据源：
/// - **CENC**: 中国地震台网中心
/// - **CEA**: 中国地震局
/// - **CEA-PR**: 中国地震局（省级）
/// - **JMA**: 日本气象厅
/// - **CWA**: 台湾中央气象署
/// - **CWA-EEW**: 台湾地震预警
/// - **USGS**: 美国地质调查局
/// - **HKO**: 香港天文台
/// - **KMA**: 韩国气象厅
/// - **SA**: 沙特地质调查局
/// - **FSSN**: 中国地震科学台网
/// - **EMSC**: 欧洲地中海地震中心
/// - **BCSF**: 法国地球科学局
/// - **GFZ**: 德国地球科学研究中心
/// - **USP**: 圣保罗大学地震中心
/// - **省级台网**: 宁夏、广西、山西、北京、云南等
///
/// 主要功能：
/// - WebSocket 实时连接管理
/// - 多服务器故障转移
/// - 多格式消息解析与分发
/// - 自动重连与心跳检测
/// - CENC 烈度速报数据处理
///
/// 数据流程：
/// 1. 建立 WebSocket 连接到 FAN 服务器
/// 2. 订阅地震列表数据
/// 3. 接收实时推送的地震信息
/// 4. 根据数据特征识别数据源类型
/// 5. 解析数据并转换为统一的 QuakeMessage 格式

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'base_source.dart';
import '../../models/unified_quake_data.dart';
import '../quake_event_adapter.dart';
import '../../models/quake_message.dart';
import '../../models/source_status.dart';
import '../../models/cenc_ir_data.dart';
import '../../models/weather_alarm.dart';
import '../../models/tsunami_message.dart';
import '../../utils/fe_regions.dart';
import '../../core/intensity_calculator.dart';
import '../../core/utils/quake_time.dart';

/// FAN 服务类
///
/// 继承自 BaseSourceService，实现 FAN API 的具体逻辑。
/// 负责管理 WebSocket 连接、消息解析和数据分发。
class FanService extends BaseSourceService {
  /// 服务名称标识
  @override
  String get name => 'FAN';

  /// CENC 烈度速报数据回调
  ///
  /// 当收到 CENC 烈度速报数据时触发。
  /// 用于处理包含等震线图的详细烈度数据。
  void Function(CencIrData)? onCencIrData;

  /// CENC 烈度速报列表回调
  ///
  /// 当收到 cencirlist_response 时触发，传递原始列表数据。
  void Function(List<Map<String, dynamic>>)? onCencIrListUpdated;

  /// FSSN 地震列表更新回调
  ///
  /// 当收到 FSSN 地震列表数据时触发。
  void Function(List<QuakeMessage>)? onFssnListUpdated;

  /// CENC 地震列表更新回调
  ///
  /// 当收到 CENC 地震列表数据时触发。
  void Function(List<QuakeMessage>)? onCencListUpdated;

  /// CWA 地震列表更新回调
  ///
  /// 当收到 CWA 地震列表数据时触发。
  void Function(List<QuakeMessage>)? onCwaListUpdated;

  /// 气象预警回调
  ///
  /// 当收到 weatheralarm 数据时触发。
  void Function(WeatherAlarm)? onWeatherAlarm;

  // ═══════════════════════════════════════════════════════════════════════════
  // 服务器配置
  // ═══════════════════════════════════════════════════════════════════════════

  /// WebSocket 服务器 URL 列表
  ///
  /// 支持多个中继服务器，按顺序尝试连接。
  /// 当一个服务器连接失败时，自动切换到下一个。
  static const List<String> _wsUrls = [
    'wss://ws.fanstudio.tech:443/all',
    'wss://ws.fanstudio.hk:443/all',
  ];

  /// 获取可选择的服务器名称列表
  static List<String> get serverOptions => ['ws.fanstudio.tech', 'ws.fanstudio.hk'];

  /// 设置默认连接的服务器索引（在 connect() 之前调用）
  void setDefaultServerIndex(int index) {
    if (index >= 0 && index < _wsUrls.length) {
      _currentUrlIndex = index;
    }
  }

  /// 手动请求 CENC 烈度速报详情
  ///
  /// 发送 [cencirdetail] 请求获取指定事件的完整烈度数据
  /// （包括 instrument_intensity_json 和 contour_geojson）。
  void requestCencIrDetail(String id) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({'type': 'cencirdetail', 'id': id}));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 状态变量
  // ═══════════════════════════════════════════════════════════════════════════

  /// WebSocket 通道实例
  WebSocketChannel? _channel;

  /// 连接初始化是否已完成
  ///
  /// 防止 `_onConnected()` 在每条消息到达时都被重新调用。
  bool _connectedInitDone = false;

  /// 重连定时器
  Timer? _reconnectTimer;

  /// 重试当前退避延迟（秒）
  ///
  /// 线性退避：初始 3s，每次 +1s，上限 10s
  int _retryInterval = 3;

  /// 连接超时定时器
  Timer? _connectTimeoutTimer;

  /// 保活/重订阅定时器
  Timer? _keepaliveTimer;

  /// 最后收到消息的时间
  DateTime _lastMessageAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 已处理的 CENC 烈度速报 ID 集合（用于去重）
  final Set<String> _seenCencIrIds = {};

  /// 当前使用的 URL 索引
  int _currentUrlIndex = 0;

  /// 是否为手动关闭
  bool _isManualClose = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // 连接管理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 发起连接
  ///
  /// 清理现有连接状态并开始新的连接尝试。
  @override
  void connect() {
    _isManualClose = false;
    _reconnectTimer?.cancel();
    _keepaliveTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _retryInterval = 3;
    _cleanup();
    _doConnect(_currentUrlIndex);
  }

  /// 执行连接
  ///
  /// 尝试连接到指定索引的 WebSocket 服务器。
  /// 参考 kanameishi 的 WebSocketObj 设计：
  /// - 连接超时 10 秒
  /// - 所有 URL 失败后线性退避重连
  ///
  /// 参数：
  /// - [urlIndex]: 要连接的服务器 URL 索引
  void _doConnect(int urlIndex) {
    // 所有 URL 都尝试失败，按线性退避调度重连
    if (urlIndex >= _wsUrls.length) {
      debugPrint('FAN: 所有地址连接失败，${_retryInterval}秒后重试');
      onStatusChanged?.call(SourceStatus.error);
      _scheduleReconnect();
      return;
    }

    onStatusChanged?.call(SourceStatus.connecting);
    final url = _wsUrls[urlIndex];
    debugPrint('正在建立 FAN 链路: $url (重试间隔: ${_retryInterval}s)');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _lastMessageAt = DateTime.now();
      bool hasReceivedData = false;

      // 连接超时保护：10 秒后连接仍未完成则关闭
      _connectTimeoutTimer?.cancel();
      _connectTimeoutTimer = Timer(const Duration(seconds: 10), () {
        debugPrint('FAN: 连接超时(10s)，切换到下一地址');
        _cleanup();
        _doConnect(urlIndex + 1);
      });

      _channel!.stream.listen(
        (data) {
          hasReceivedData = true;
          _lastMessageAt = DateTime.now();
          // 连接恢复正常，重置退避间隔
          if (_retryInterval > 3) {
            debugPrint('FAN 链路已恢复正常');
          }
          _retryInterval = 3;
          _currentUrlIndex = urlIndex;
          _connectTimeoutTimer?.cancel();
          onStatusChanged?.call(SourceStatus.connected);
          if (!_connectedInitDone) {
            _connectedInitDone = true;
            _onConnected();
          }
          _dispatch(data);
        },
        onDone: () {
          _keepaliveTimer?.cancel();
          _connectTimeoutTimer?.cancel();
          if (!hasReceivedData) {
            debugPrint('FAN: 无效路径或服务端拒绝连接，服务端已关闭链路 ($url)');
          } else {
            _currentUrlIndex = (_currentUrlIndex + 1) % _wsUrls.length;
          }
          debugPrint('FAN 链路远程关闭');
          _handleFailure();
        },
        onError: (err) {
          _keepaliveTimer?.cancel();
          _connectTimeoutTimer?.cancel();
          debugPrint('FAN 链路传输错误: $err');
          _handleFailure();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('FAN 初始握手失败: $e');
      _connectTimeoutTimer?.cancel();
      _doConnect(urlIndex + 1);
    }
  }

  /// 连接成功后的初始化
  ///
  /// 立即发送订阅请求并启动保活定时器。
  /// 参考 kanameishi 的 WebSocketObj.onopen 逻辑。
  void _onConnected() {
    _channel?.sink.add('query');
    _channel?.sink.add('cwalist');
    _channel?.sink.add('cenclist');
    _channel?.sink.add('cencirlist');
    _channel?.sink.add('fssnlist');

    _startKeepalive();
  }

  /// 启动保活/重订阅定时器
  ///
  /// 服务器每分钟自动推送 heartbeat，客户端可选回复 ping。
  /// 本定时器作为额外保活：每 30 秒发一次 ping 确保连接活跃。
  /// 同时定期检查 90 秒无消息则触发重连。
  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_channel == null) return;

      final idle = DateTime.now().difference(_lastMessageAt).inSeconds;
      if (idle > 90) {
        debugPrint('FAN: 保活超时(${idle}s)，触发重连');
        _keepaliveTimer?.cancel();
        _handleFailure();
        return;
      }

      // 每 30 秒发一次 ping 保活
      _channel?.sink.add('ping');
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 消息路由
  // ═══════════════════════════════════════════════════════════════════════════

  /// 消息分发器
  ///
  /// 根据消息类型将数据分发到对应的处理方法。
  ///
  /// 支持的消息类型：
  /// - `heartbeat`: 心跳消息，需要回复 pong
  /// - `pong`: 心跳响应
  /// - `query_response`: 查询响应
  /// - `error`: 错误消息
  /// - `fssnlist_response`: FSSN 地震列表响应
  /// - `cenclist_response`: CENC 地震列表响应
  /// - `cencirlist_response`: CENC 烈度速报列表响应
  /// - `cencirdetail_response`: CENC 烈度速报详情响应
  /// - `initial_all`: 初始全量数据 (type/源key同级)
  /// - `initial`/`update`: 增量数据 (data内key为源名)
  ///
  /// 参数：
  /// - [rawData]: 原始消息数据
  void _dispatch(dynamic rawData) {
    try {
      final json = jsonDecode(rawData.toString());
      if (json is! Map<String, dynamic>) return;

      final String type = json['type']?.toString() ?? '';

      // 处理心跳消息
      // 服务端每分钟发送 heartbeat，客户端可选回复 ping 包
      if (type == 'heartbeat') {
        _channel?.sink.add('ping');
        return;
      }

      if (type == 'pong') {
        return;
      }

      if (type == 'error') {
        debugPrint('FAN 服务端错误: ${json['message']}');
        final errorMsg = json['message']?.toString() ?? '';
        if (errorMsg.contains('连接数超限')) {
          _currentUrlIndex = (_currentUrlIndex + 1) % _wsUrls.length;
          _retryInterval = 3;
          _cleanup();
        }
        return;
      }

      // query_response / initial_all: 源key都在根层与type同级
      // 参考 kanameishi status.js:L1375 — 两者合并处理
      if (type == 'query_response' || type == 'initial_all') {
        for (final entry in json.entries) {
          final sourceName = entry.key;
          if (sourceName == 'type' || sourceName == 'ver' || sourceName == 'id' || sourceName == 'timestamp') continue;
          final value = entry.value;
          if (value is Map) {
            _parsePayload(
              Map<String, dynamic>.from(value),
              sourceHint: sourceName,
              isInitialLoad: true,
            );
          }
        }
        return;
      }

      // FSSN 地震列表响应
      if (type == 'fssnlist_response') {
        _handleEqlistResponse(json, QuakeSourceType.fssn);
        return;
      }

      // CWA 地震列表响应
      if (type == 'cwalist_response') {
        _handleEqlistResponse(json, QuakeSourceType.cwa);
        return;
      }

      // CENC 地震列表响应
      if (type == 'cenclist_response') {
        _handleEqlistResponse(json, QuakeSourceType.cenc);
        return;
      }

      // CENC 烈度速报列表：新事件作为 CENC 信息事件推送
      if (type == 'cencirlist_response') {
        final items = json['Data'];
        if (items is List) {
          final isEmpty = _seenCencIrIds.isEmpty;
          final mappedList = <Map<String, dynamic>>[];
          for (final item in items) {
            if (item is! Map) continue;
            final mapped = _mapCencIrFields(Map<String, dynamic>.from(item));
            mappedList.add(mapped);
            final id = item['id']?.toString() ?? '';
            if (id.isEmpty || _seenCencIrIds.contains(id)) continue;
            _seenCencIrIds.add(id);
            if (isEmpty) continue;
            final parsed = _parseFanEvent(mapped, QuakeSourceType.cenc, isInitialLoad: true);
            if (parsed != null) emit(parsed);
          }
          onCencIrListUpdated?.call(mappedList);
        }
        if (_seenCencIrIds.length > 50) {
          final list = _seenCencIrIds.toList();
          _seenCencIrIds.clear();
          _seenCencIrIds.addAll(list.skip(list.length - 50));
        }
        return;
      }

      // CENC 烈度速报详情
      if (type == 'cencirdetail_response') {
        final data = json['Data'];
        if (data is Map) {
          final detail = Map<String, dynamic>.from(data);
          if (detail.containsKey('uniEventId') &&
              (detail.containsKey('instrument_intensity_json') ||
                  detail.containsKey('contour_geojson'))) {
            _handleCencIrData(detail);
          }
        }
        return;
      }

      // update: 有独立的 source 字段 + Data 字段
      if (type == 'update') {
        debugPrint('FAN update 报文: $rawData');
        final sourceName = json['source']?.toString();
        final data = json['Data'];
        if (data is Map) {
          _parsePayload(
            Map<String, dynamic>.from(data),
            sourceHint: sourceName,
            isInitialLoad: false,
          );
        }
        return;
      }

      // initial: 优先 source 字段，无则遍历根key
      if (type == 'initial') {
        final sourceName = json['source']?.toString();
        final data = json['Data'];
        if (data is Map && sourceName != null) {
          _parsePayload(Map<String, dynamic>.from(data), sourceHint: sourceName, isInitialLoad: true);
        } else if (data is Map) {
          _parsePayload(Map<String, dynamic>.from(data), isInitialLoad: true);
        } else {
          for (final entry in json.entries) {
            final k = entry.key;
            if (k == 'type' || k == 'ver' || k == 'id' || k == 'timestamp' || k == 'source' || k == 'md5') continue;
            final v = entry.value;
            if (v is Map) {
              _parsePayload(Map<String, dynamic>.from(v), sourceHint: k, isInitialLoad: true);
            }
          }
        }
        return;
      }

      // 兼容 FAN 单源直推：无 type，直接是事件对象
      if (type.isEmpty &&
          (json.containsKey('Data') ||
              json.containsKey('shockTime') ||
              json.containsKey('eventId') ||
              json.containsKey('id'))) {
        final sourceHint = json['source']?.toString();
        final data = json['Data'];
        if (data is Map && sourceHint != null) {
          _parsePayload(Map<String, dynamic>.from(data), sourceHint: sourceHint);
        } else if (data is Map) {
          _parsePayload(Map<String, dynamic>.from(data));
        } else {
          _parsePayload(json);
        }
        return;
      }

      debugPrint('FAN 未识别 type: $type');
    } catch (e) {
      debugPrint('FAN 数据解析异常: $e');
    }
  }

  /// 处理地震列表响应
  ///
  /// 解析地震列表数据并批量回调。
  ///
  /// 参数：
  /// - [json]: JSON 格式的响应数据
  /// - [source]: 数据源类型
  void _handleEqlistResponse(
    Map<String, dynamic> json,
    QuakeSourceType source,
  ) {
    final Data = json['Data'];
    List<dynamic> items;
    if (Data is List) {
      items = Data;
    } else if (Data is Map) {
      final eventId = Data['id']?.toString();
      if (eventId != null) {
        items = [Data];
      } else {
        items = [];
      }
    } else {
      items = [];
    }

    final List<QuakeMessage> messages = [];
    for (final item in items) {
      if (item is! Map) continue;
      final parsed = _parseFanEvent(Map<String, dynamic>.from(item), source, isInitialLoad: true);
      if (parsed != null) {
        // CWA/JMA/CENC 使用原始地名，其他数据源使用 getFEName 作为备用
        final String finalLocation;
        if (source == QuakeSourceType.cwa || source == QuakeSourceType.cwa_eew ||
            source == QuakeSourceType.jma_fan || source == QuakeSourceType.cenc) {
          finalLocation = parsed.location;
        } else {
          final String cnLocation = getFEName(parsed.latitude, parsed.longitude);
          finalLocation = cnLocation.isNotEmpty ? cnLocation : parsed.location;
        }

        // CWA/JMA 使用原始震度，不进行回退计算
        final int maxIntensity;
        if (source == QuakeSourceType.cwa || source == QuakeSourceType.cwa_eew ||
            source == QuakeSourceType.jma_fan) {
          maxIntensity = parsed.maxIntensity ?? 0;
        } else {
          maxIntensity = parsed.maxIntensity ??
              IntensityCalculator.calcCsisLevel(
                parsed.magnitude,
                parsed.depth,
                0,
              );
        }
        messages.add(
          QuakeMessage(
            source: source,
            eventId: parsed.eventId,
            location: finalLocation,
            magnitude: parsed.magnitude,
            latitude: parsed.latitude,
            longitude: parsed.longitude,
            depth: parsed.depth,
            originTime: parsed.originTime,
            maxIntensity: maxIntensity,
            jmaShindo: parsed.jmaShindo,
            isHistory: true,
            infoTypeName: parsed.infoTypeName,
            reviewType: parsed.reviewType,
            verify: parsed.verify,
            isInfoEvent: true,
          ),
        );
      }
    }

    if (messages.isEmpty) return;

    switch (source) {
      case QuakeSourceType.fssn:
        onFssnListUpdated?.call(messages);
        break;
      case QuakeSourceType.cwa:
        onCwaListUpdated?.call(messages);
        break;
      case QuakeSourceType.cenc:
        onCencListUpdated?.call(messages);
        break;
      default:
        break;
    }
  }

  /// 解析数据负载
  ///
  /// 从消息中提取地震事件数据并处理。
  ///
  /// 参数：
  /// - [payload]: JSON 格式的数据负载
  /// - [sourceHint]: 数据源提示（可选）
  /// - [isInitialLoad]: 是否为初始全量加载（不触发预警/情报UI）
  void _parsePayload(Map<String, dynamic> payload, {String? sourceHint, bool isInitialLoad = false}) {
    // 提取内部 Data 字段
    final innerData = payload['Data'];
    Map<String, dynamic> event;
    if (innerData is Map) {
      event = Map<String, dynamic>.from(innerData);
    } else {
      event = payload;
    }

    // 检查是否为 CENC 烈度速报数据
    if (event.containsKey('uniEventId') &&
        (event.containsKey('contour_geojson') ||
            event.containsKey('instrument_intensity_json'))) {
      _handleCencIrData(event);
      return;
    }

    // 气象预警走独立处理（有 sourceHint 或 有 headline 字段均可识别）
    if (sourceHint == 'weatheralarm' || event.containsKey('headline')) {
      _handleWeatherAlarm(event);
      return;
    }

    // NMEFC 海啸预警走独立处理
    if (event.containsKey('warningInfo') && event.containsKey('forecasts')) {
      _handleNmefcTsunami(event, isInitialLoad: isInitialLoad);
      return;
    }

    // 解析数据源并处理事件
    final QuakeSourceType source = _resolveSource(event, sourceHint);
    final result = _parseFanEvent(event, source, isInitialLoad: isInitialLoad);
    if (result != null) {
      debugPrint('FAN _parsePayload source=$source eventId=${result.eventId} isInfoEvent=${result.isInfoEvent} isHistory=$isInitialLoad');
      if (isInitialLoad) {
        // kanameishi: query_response / initial_all 包含当前活跃的 EEW 事件
        // 对 EEW 事件，检查是否仍然活跃（根据 reportTime 和 timeoutSeconds）
        // 如果仍然活跃，则 emit 让 QuakeProvider 正常显示预警卡片
        final bool isEew = !result.isInfoEvent;
        if (isEew) {
          final int timeoutSec = QuakeTime.eewTimeoutSeconds(result);
          final int elapsedSec = QuakeTime.calcPassedSeconds(result);
          if (elapsedSec < timeoutSec) {
            debugPrint('FAN initial EEW still active: ${result.eventId} elapsed=${elapsedSec}s timeout=${timeoutSec}s');
            emit(result);
          } else {
            debugPrint('FAN initial EEW expired: ${result.eventId} elapsed=${elapsedSec}s timeout=${timeoutSec}s');
          }
        }
        // 信息事件：历史数据已通过 cenclist_response / cwalist_response 等专门路径入桶
      } else {
        emit(result);
      }
    }
  }

  /// 映射 CENC IR 列表字段到标准字段名
  ///
  /// cencirlist_response 返回的字段名与常规事件不同：
  /// oriTime→shockTime, epiLat→latitude, epiLon→longitude, locName→placeName
  Map<String, dynamic> _mapCencIrFields(Map<String, dynamic> item) {
    final mapped = <String, dynamic>{};
    mapped['id'] = item['id']?.toString() ?? '';
    mapped['uniEventId'] = item['uniEventId']?.toString() ?? '';
    mapped['shockTime'] = item['oriTime']?.toString() ?? item['shockTime']?.toString() ?? '';
    mapped['latitude'] = double.tryParse(item['epiLat']?.toString() ?? '') ?? item['latitude'];
    mapped['longitude'] = double.tryParse(item['epiLon']?.toString() ?? '') ?? item['longitude'];
    mapped['placeName'] = item['locName']?.toString() ?? item['placeName']?.toString() ?? '';
    mapped['magnitude'] = double.tryParse(item['magnitude']?.toString() ?? '') ?? item['magnitude'];
    mapped['depth'] = double.tryParse(item['focDepth']?.toString() ?? '') ?? item['depth'];
    mapped['infoTypeName'] = item['infoTypeName']?.toString() ?? '';
    mapped['nameByInfo'] = item['nameByInfo']?.toString() ?? '';
    return mapped;
  }

  /// 处理 CENC 烈度速报数据
  ///
  /// 解析包含等震线图的详细烈度数据。
  ///
  /// 参数：
  /// - [json]: JSON 格式的烈度速报数据
  void _handleCencIrData(Map<String, dynamic> json) {
    try {
      final irData = CencIrData.fromJson(json);
      onCencIrData?.call(irData);
    } catch (e) {
      debugPrint('FAN CENC-IR 解析异常: $e');
    }
  }

  /// 处理气象预警数据
  void _handleWeatherAlarm(Map<String, dynamic> json) {
    try {
      final alarm = WeatherAlarm.fromJson(json);
      onWeatherAlarm?.call(alarm);
    } catch (e) {
      debugPrint('FAN WeatherAlarm 解析异常: $e');
    }
  }

  /// 处理 NMEFC 海啸预警数据
  void _handleNmefcTsunami(Map<String, dynamic> json, {bool isInitialLoad = false}) {
    try {
      final tsunami = TsunamiMessage.parseNmefcTsunami(json);
      debugPrint('FAN NMEFC海啸: ${tsunami.title} (${tsunami.areas.length}区域)');
      if (!isInitialLoad) {
        emitTsunami(tsunami);
      }
    } catch (e) {
      debugPrint('FAN NMEFC海啸解析异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 数据源识别
  // ═══════════════════════════════════════════════════════════════════════════

  /// 解析数据源类型
  ///
  /// 优先使用 sourceHint，其次通过特征检测，最后默认为 CENC。
  ///
  /// 参数：
  /// - [json]: JSON 格式的事件数据
  /// - [sourceHint]: 数据源提示
  ///
  /// 返回：
  /// - 识别出的数据源类型
  QuakeSourceType _resolveSource(
    Map<String, dynamic> json,
    String? sourceHint,
  ) {
    if (sourceHint != null && sourceHint.isNotEmpty) {
      final fromHint = _sourceNameToType(sourceHint);
      if (fromHint != null) return fromHint;
    }
    return _detectSource(json) ?? QuakeSourceType.cenc;
  }

  /// FAN source 字段名转换为 QuakeSourceType
  ///
  /// 参数：
  /// - [name]: FAN 数据源名称
  ///
  /// 返回：
  /// - 对应的 QuakeSourceType，如果不识别则返回 null
  QuakeSourceType? _sourceNameToType(String name) {
    switch (name) {
      case 'cenc':
        return QuakeSourceType.cenc;
      case 'cea':
        return QuakeSourceType.cea;
      case 'cea-pr':
        return QuakeSourceType.cea_pr;
      case 'jma':
        return QuakeSourceType.jma_fan;
      case 'cwa':
        return QuakeSourceType.cwa;
      case 'cwa-eew':
        return QuakeSourceType.cwa_eew;
      case 'hko':
        return QuakeSourceType.hko;
      case 'kma':
        return QuakeSourceType.kma_eq;
      case 'kma-eew':
        return QuakeSourceType.kma_eew_fan;
      case 'sa':
        return QuakeSourceType.sa;
      case 'fssn':
        return QuakeSourceType.fssn;
      case 'emsc':
        return QuakeSourceType.emsc;
      case 'bcsf':
        return QuakeSourceType.bcsf;
      case 'gfz':
        return QuakeSourceType.gfz;
      case 'usp':
        return QuakeSourceType.usp;
      case 'usgs':
        return QuakeSourceType.usgs;
      case 'ningxia':
        return QuakeSourceType.ningxia;
      case 'guangxi':
        return QuakeSourceType.guangxi;
      case 'shanxi':
        return QuakeSourceType.shanxi;
      case 'beijing':
        return QuakeSourceType.beijing;
      case 'yunnan':
        return QuakeSourceType.yunnan;
      case 'fssn-cmt':
        return QuakeSourceType.fssnCmt;
      default:
        return null;
    }
  }

  /// 从数据字段特征推断数据源类型
  ///
  /// 根据消息中包含的特有字段来判断数据来源。
  ///
  /// 参数：
  /// - [json]: JSON 格式的事件数据
  ///
  /// 返回：
  /// - 推断出的数据源类型，如果无法确定则返回 null
  QuakeSourceType? _detectSource(Map<String, dynamic> json) {
    // CENC-IR: uniEventId, contour_geojson, instrument_intensity_json
    if (json.containsKey('uniEventId')) return QuakeSourceType.cenc;
    if (json.containsKey('contour_geojson') ||
        json.containsKey('instrument_intensity_json'))
      return null;

    // CEA: epiIntensity + updates (数值型烈度)
    if (json.containsKey('updates') &&
        json.containsKey('epiIntensity') &&
        !json.containsKey('affectedAreas')) {
      return QuakeSourceType.cea;
    }

    // CEA-PR: 有 province 字段
    if (json.containsKey('province')) return QuakeSourceType.cea_pr;

    // CWA: maxIntensity(字符串型震度) + imageURI
    if (json.containsKey('imageURI')) return QuakeSourceType.cwa;

    // CWA-EEW: locationDesc + updates + 无 epiIntensity
    if (json.containsKey('locationDesc') &&
        json.containsKey('updates') &&
        !json.containsKey('epiIntensity')) {
      return QuakeSourceType.cwa_eew;
    }

    // JMA: epiIntensity(string) + final/cancel 布尔标志
    if (json.containsKey('final') || json.containsKey('cancel'))
      return QuakeSourceType.jma_fan;

    // HKO: citystring + region + verify
    if (json.containsKey('citystring') || json.containsKey('verify'))
      return QuakeSourceType.hko;

    // KMA-EEW: epiIntensity + affectedAreas
    if (json.containsKey('affectedAreas')) return QuakeSourceType.kma_eew_fan;

    // KMA: epiIntensity(数值) + createTime(UTC+9)
    if (json.containsKey('createTime') && json.containsKey('epiIntensity'))
      return QuakeSourceType.kma_eq;

    // 宁夏: title字段
    if (json.containsKey('title') && json.containsKey('epiIntensity'))
      return QuakeSourceType.ningxia;

    // FSSN-CMT: nodalPlane1 + allMagnitudes（震源机制解）
    if (json.containsKey('nodalPlane1') && json.containsKey('allMagnitudes'))
      return QuakeSourceType.fssnCmt;

    // weatheralarm 拦截防御
    if (json.containsKey('headline')) return null;

    // FSSN: infoTypeName = "已确认" etc + 通常有 updates
    if (json.containsKey('infoTypeName') &&
        !json.containsKey('url') &&
        !json.containsKey('title')) {
      return QuakeSourceType.fssn;
    }

    // USGS: 有 url 指向 usgs.gov + title + infoTypeName
    if (json.containsKey('url') &&
        json.containsKey('title') &&
        json.containsKey('infoTypeName')) {
      return QuakeSourceType.usgs;
    }

    // SA (ShakeAlert): 无中文字段特征, id 为网络代码+数字 (ci/ew/nc/uw/uu/nm等)
    if (json.containsKey('id') &&
        !json.containsKey('epiIntensity') &&
        !json.containsKey('maxIntensity') &&
        !json.containsKey('infoTypeName') &&
        !json.containsKey('title') &&
        !json.containsKey('updates') &&
        !json.containsKey('createTime') &&
        !json.containsKey('url')) {
      final idStr = json['id']?.toString() ?? '';
      if (RegExp(r'^[a-z]{2,4}\d+$').hasMatch(idStr)) {
        return QuakeSourceType.sa;
      }
    }

    // EMSC: id 格式 YYYYMMDD_NNNNNNN (如 20260510_0000248)
    if (json.containsKey('id') &&
        RegExp(r'^\d{8}_\d+$').hasMatch(json['id']?.toString() ?? '')) {
      return QuakeSourceType.emsc;
    }

    // GFZ / USP / BCSF: id 格式 机构前缀+数字+字母 (如 gfz2026jbxg, usp2026izja, fr2026trrfdj)
    if (json.containsKey('id')) {
      final idStr = json['id']?.toString() ?? '';
      if (RegExp(r'^(gfz|usp)\d+[a-z]+$').hasMatch(idStr)) {
        if (idStr.startsWith('gfz')) return QuakeSourceType.gfz;
        if (idStr.startsWith('usp')) return QuakeSourceType.usp;
      }
      if (RegExp(r'^fr\d+[a-z]+$').hasMatch(idStr)) {
        return QuakeSourceType.bcsf;
      }
    }

    // 默认：有 eventId 或 id + shockTime 的地震信息
    if (json.containsKey('shockTime') || json.containsKey('originTime')) {
      return QuakeSourceType.cenc;
    }

    return QuakeSourceType.cenc;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 事件解析
  // ═══════════════════════════════════════════════════════════════════════════

  /// 解析 FAN 地震事件
  ///
  /// 从 JSON 数据中提取地震信息并转换为 QuakeMessage。
  ///
  /// FAN 统一字段名：
  /// - `id`/`eventId`: 事件标识
  /// - `shockTime`: 发震时间
  /// - `placeName`/`locationDesc`/`title`: 地点名称
  /// - `latitude`/`longitude`: 震中坐标
  /// - `magnitude`: 震级
  /// - `depth`: 震源深度
  /// - `epiIntensity`/`maxIntensity`: 震度/烈度
  /// - `updates`: 更新次数
  /// - `infoTypeName`: 信息类型
  /// - `type`: 测定类型（automatic/reviewed）
  ///
  /// 参数：
  /// - [json]: JSON 格式的事件数据
  /// - [source]: 数据源类型
  ///
  /// 返回：
  /// - 解析后的 QuakeMessage，如果解析失败则返回 null
  QuakeMessage? _parseFanEvent(
    Map<String, dynamic> json,
    QuakeSourceType source, {
    bool isInitialLoad = false,
  }) {
    try {
      // ─── 基础字段 ───
      final String id = json['id']?.toString() ?? '';
      final String eventId = json['eventId']?.toString() ?? '';

      final String shockTimeStr = json['shockTime']?.toString() ?? '';
      final DateTime originTime =
          DateTime.tryParse(shockTimeStr) ?? DateTime.now();

      // ─── 地点信息 ───
      final String placeName = json['placeName']?.toString() ?? '';
      final String locationDesc = json['locationDesc']?.toString() ?? '';

      // ─── 震源参数 ───
      final double latitude =
          double.tryParse(json['latitude']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(json['longitude']?.toString() ?? '') ?? 0.0;

      double magnitude = 0.0;
      if (source == QuakeSourceType.fssnCmt) {
        final allMags = json['allMagnitudes'];
        if (allMags is Map) {
          magnitude = double.tryParse(allMags['Mw']?.toString() ?? '') ??
              double.tryParse(allMags['Mww']?.toString() ?? '') ??
              double.tryParse(allMags['M']?.toString() ?? '') ?? 0.0;
        }
      } else {
        magnitude = double.tryParse(json['magnitude']?.toString() ?? '') ?? 0.0;
      }

      final double magnitudel =
          double.tryParse(json['magnitudel']?.toString() ?? '') ?? 0.0;
      final String infoTypeName = source == QuakeSourceType.fssnCmt
          ? '震源机制解'
          : json['infoTypeName']?.toString() ?? '';
      final String title = json['title']?.toString() ?? '';

      // depth 可能为 null，CMT 优先用 centroidDepth
      double depth = 0.0;
      if (source == QuakeSourceType.fssnCmt) {
        final cd = json['centroidDepth'];
        if (cd != null) {
          depth = double.tryParse(cd.toString()) ?? 0.0;
        }
      }
      if (depth == 0.0) {
        final depthRaw = json['depth'];
        if (depthRaw != null) {
          final ds = depthRaw.toString();
          // 解析 "137(+/- 10)" 格式取第一部分
          final numPart = ds.split('(').first.trim();
          depth = double.tryParse(numPart) ?? 0.0;
        }
      }

      // CMT 特有字段
      final String? nodalPlane1 = source == QuakeSourceType.fssnCmt
          ? json['nodalPlane1']?.toString()
          : null;
      final String? nodalPlane2 = source == QuakeSourceType.fssnCmt
          ? json['nodalPlane2']?.toString()
          : null;

      // ─── 震度/烈度（多路径差异） ───
      // JMA 震度可能是数字或字符串 (如 "5弱", "5強")
      final String epiIntensityStr = json['epiIntensity']?.toString() ?? '';
      final double? epiIntensityRaw = double.tryParse(epiIntensityStr);
      String maxIntensityStr = json['maxIntensity']?.toString() ?? '';
      final int? maxIntensityParsed = int.tryParse(maxIntensityStr);
      
      // JMA 震度字符串转换
      String? jmaShindo;
      int? intensity;
      
      if (source == QuakeSourceType.jma_fan) {
        // JMA 数据源：仅设置 jmaShindo 震度徽章字符串，不转为数值型 maxIntensity
        if (epiIntensityStr.isNotEmpty) {
          jmaShindo = _normalizeJmaShindo(epiIntensityStr);
        } else if (maxIntensityStr.isNotEmpty) {
          jmaShindo = _normalizeJmaShindo(maxIntensityStr);
        }
      } else if (source == QuakeSourceType.cwa || source == QuakeSourceType.cwa_eew) {
        // CWA 数据源：仅设置 jmaShindo 震度徽章字符串
        if (maxIntensityStr.isNotEmpty) {
          jmaShindo = _formatShindo(maxIntensityStr);
        }
      } else {
        // 其他数据源：使用 API 原始数值型烈度
        intensity = maxIntensityParsed ??
            (epiIntensityRaw != null ? epiIntensityRaw.round() : null);
      }

      // ─── 其他注册字段 ───
      final int updates = int.tryParse(json['updates']?.toString() ?? '') ?? 0;
      final String createTime = json['createTime']?.toString() ?? '';
      final String updateTime = json['updateTime']?.toString() ?? '';
      final String province = json['province']?.toString() ?? '';
      final String md5 = json['md5']?.toString() ?? '';
      final String url = json['url']?.toString() ?? '';
      final String imageURI = json['imageURI']?.toString() ?? '';
      final String citystring = json['citystring']?.toString() ?? '';
      final String region = json['region']?.toString() ?? '';
      final String verify = json['verify']?.toString() ?? '';
      final String typeField = json['type']?.toString() ?? json['infoTypeName']?.toString() ?? '';

      // ─── 布尔标志（JMA 路径） ───
      final bool isFinal = json['final'] == true;
      final bool isCancel = json['cancel'] == true;
      final bool isTraining = json['isTraining'] == true;

      // 跳过取消报
      if (isCancel) {
        debugPrint('FAN $source: 取消报 已跳过');
        return null;
      }

      // ─── 组装地点名称 ───
      final String feName = (source == QuakeSourceType.cenc)
          ? ''
          : getFEName(latitude, longitude);
      String locationBase;
      
      // HKO: 优先使用 placeName，citystring 作为补充描述
      if (source == QuakeSourceType.hko) {
        locationBase = placeName.isNotEmpty
            ? (region.isNotEmpty ? '$placeName ($region)' : placeName)
            : citystring.isNotEmpty
            ? citystring
            : region.isNotEmpty
            ? region
            : feName.isNotEmpty
            ? feName
            : '未知地点';
      } else {
        // 国际数据源优先使用 FE 区域中文名
        final bool useFeName = source == QuakeSourceType.usgs ||
            source == QuakeSourceType.sa ||
            source == QuakeSourceType.emsc ||
            source == QuakeSourceType.bcsf ||
            source == QuakeSourceType.gfz ||
            source == QuakeSourceType.usp ||
            source == QuakeSourceType.fssn ||
            source == QuakeSourceType.kma_eq;
        
        if (useFeName && feName.isNotEmpty) {
          locationBase = feName;
        } else {
          locationBase = placeName.isNotEmpty
              ? placeName
              : locationDesc.isNotEmpty
              ? locationDesc
              : title.isNotEmpty
              ? title
              : region.isNotEmpty
              ? region
              : feName.isNotEmpty
              ? feName
              : '未知地点';
        }
      }
      
      // CWA 数据源：提取 "(位於...)" 部分
      if (source == QuakeSourceType.cwa || source == QuakeSourceType.cwa_eew) {
        locationBase = _extractCwaLocation(locationBase);
      }
      
      final String location = locationBase;

      // ─── 测定类型 ───
      String? reviewType;
      if (source == QuakeSourceType.cenc) {
        final clean = typeField.replaceAll('[', '').replaceAll(']', '');
        if (clean == '正式测定') {
          reviewType = 'reviewed';
        } else if (clean == '自动测定') {
          reviewType = 'automatic';
        }
      } else if (typeField == 'automatic') {
        reviewType = '自动测定';
      } else if (typeField == 'reviewed') {
        reviewType = '正式测定';
      }
      
      // HKO: verify=Y/N -> 已核实/待核实
      if (source == QuakeSourceType.hko && verify.isNotEmpty) {
        reviewType = verify == 'Y' ? '已核实' : '待核实';
      }

      final String reportTimeStr = createTime.isNotEmpty
          ? createTime
          : updateTime.isNotEmpty
              ? updateTime
              : '';
      final DateTime? parsedReportTime =
          reportTimeStr.isNotEmpty ? DateTime.tryParse(reportTimeStr) : null;

      // ─── 烈度计算 ───
      // JMA 和 CWA 使用原始烈度值，其他数据源需要转换
      final bool shouldFallbackConvert =
          source != QuakeSourceType.jma_fan &&
          source != QuakeSourceType.cwa &&
          source != QuakeSourceType.cwa_eew;
      final int? finalIntensity =
          intensity ??
          (shouldFallbackConvert
              ? IntensityCalculator.calcCsisLevel(
                  magnitude > 0 ? magnitude : magnitudel,
                  depth,
                  0,
                )
              : null);

      // kanameishi: 初始加载时，EEW 事件需要检查是否仍然活跃
      // 过期的 EEW 不发射统一事件，避免在打开应用时显示已过期的预警
      final bool isInfoEventSource = source != QuakeSourceType.cea &&
          source != QuakeSourceType.cea_pr &&
          source != QuakeSourceType.kma_eew_fan &&
          source != QuakeSourceType.sa &&
          source != QuakeSourceType.cwa_eew &&
          source != QuakeSourceType.jma_fan &&
          source != QuakeSourceType.wolfx &&
          source != QuakeSourceType.sc_eew &&
          source != QuakeSourceType.fj_eew &&
          source != QuakeSourceType.cq_eew;
      final bool shouldEmitUnified;
      if (!isInitialLoad) {
        shouldEmitUnified = true;
      } else if (isInfoEventSource) {
        // 信息事件：不发射统一事件（历史数据已通过列表响应路径入桶）
        shouldEmitUnified = false;
      } else {
        // EEW 事件：检查是否仍然活跃
        // 需要先构造一个临时的 QuakeMessage 来计算过期时间
        final int timeoutSec = _eewTimeoutForSource(source, magnitude, magnitudel, isCancel, isWarn: source == QuakeSourceType.jma_fan && infoTypeName == '警報');
        final int elapsedSec = _calcPassedSecondsForSource(
          source,
          createTime.isNotEmpty ? createTime : shockTimeStr,
          shockTimeStr,
        );
        shouldEmitUnified = elapsedSec < timeoutSec;
        if (!shouldEmitUnified) {
          debugPrint('FAN initial EEW expired (unified): source=$source eventId=$eventId elapsed=${elapsedSec}s timeout=${timeoutSec}s');
        }
      }
      if (shouldEmitUnified) {
        _emitFanUnified(
        source,
        <String, dynamic>{
          'eventId': eventId.isNotEmpty ? eventId : id.isNotEmpty ? id : md5,
          'location': location,
          'magnitude': magnitude > 0 ? magnitude : magnitudel,
          'depth': depth,
          'latitude': latitude,
          'longitude': longitude,
          'originTime': json['shockTime']?.toString() ?? '',
          'maxIntensity': finalIntensity,
          'jmaShindo': jmaShindo,
          'infoTypeName': infoTypeName,
          'reviewType': reviewType ?? '',
          'type': reviewType ?? '',
          'updates': updates,
          'isWarn': source == QuakeSourceType.jma_fan && infoTypeName == '警報',
          'isFinal': isFinal,
          'isCancel': isCancel,
          'isAssumption': false,
          'isTraining': isTraining,
          'placeName': location,
          'createTime': json['createTime']?.toString() ?? '',
          'updateTime': updateTime,
          'shockTime': json['shockTime']?.toString() ?? '',
        },
        );
      }

      return QuakeMessage(
        source: source,
        eventId: eventId.isNotEmpty
            ? eventId
            : id.isNotEmpty
            ? id
            : md5.isNotEmpty
            ? md5
            : DateTime.now().millisecondsSinceEpoch.toString(),
        location: location,
        magnitude: magnitude > 0 ? magnitude : magnitudel,
        latitude: latitude,
        longitude: longitude,
        depth: depth,
        originTime: originTime,
        maxIntensity: finalIntensity,
        jmaShindo: jmaShindo,
        isTest: isTraining,
        isFinal: isFinal,
        isCanceled: isCancel,
        isTsunamiWarning: typeField == 'tsunami',
        tsunamiWarning: typeField == 'tsunami' ? '自然资源部海啸预警' : null,
        reviewType: reviewType,
        infoTypeName: infoTypeName.isNotEmpty ? infoTypeName : null,
        verify: verify.isNotEmpty ? verify : null,
        isInfoEvent: source != QuakeSourceType.cea &&
            source != QuakeSourceType.cea_pr &&
            source != QuakeSourceType.kma_eew_fan &&
            source != QuakeSourceType.sa &&
            source != QuakeSourceType.cwa_eew &&
            source != QuakeSourceType.jma_fan &&
            source != QuakeSourceType.wolfx &&
            source != QuakeSourceType.sc_eew &&
            source != QuakeSourceType.fj_eew &&
            source != QuakeSourceType.cq_eew,
        reportNumber: updates > 0 ? updates : null,
        reportTime: parsedReportTime,
        province: province.isNotEmpty ? province : null,
        nodalPlane1: nodalPlane1,
        nodalPlane2: nodalPlane2,
      );
    } catch (e) {
      debugPrint('FAN 事件解析异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 错误处理与重连
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理连接失败
  ///
  /// 参考 kanameishi 的 WebSocketObj.onclose 逻辑：
  /// - 线性退避：每次 +1s，初始 3s，上限 10s
  /// - 达到上限后切换到下一个 URL
  void _handleFailure() {
    _keepaliveTimer?.cancel();
    onStatusChanged?.call(SourceStatus.error);
    if (!_isManualClose) {
      _scheduleReconnect();
    }
  }

  /// 安排延迟重连
  ///
  /// 参考 kanameishi 的线性退避策略。
  void _scheduleReconnect() {
    if (_isManualClose) return;
    if (_reconnectTimer?.isActive ?? false) return;

    // 重试间隔达到上限时切换到下一个 URL
    if (_retryInterval >= 10) {
      _currentUrlIndex = (_currentUrlIndex + 1) % _wsUrls.length;
    }

    final delay = _retryInterval;
    debugPrint('FAN: $delay 秒后重连 (urlIndex=$_currentUrlIndex)');
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _cleanup();
      _doConnect(_currentUrlIndex);
    });

    // 线性递增退避：+1s，上限 10s
    _retryInterval = (_retryInterval + 1).clamp(3, 10);
  }

  /// 清理资源
  ///
  /// 关闭 WebSocket 连接并释放相关资源。
  void _cleanup() {
    _keepaliveTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _connectedInitDone = false;
    _seenCencIrIds.clear();
    try {
      _channel?.sink.close();
    } catch (_) {}
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
    _keepaliveTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _cleanup();
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  /// 调试打印
  ///
  /// 封装 print 方法，便于统一管理日志输出。
  void debugPrint(String message) {
    // ignore: avoid_print
    print(message);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JMA 震度辅助方法
  // ═══════════════════════════════════════════════════════════════════════════

  /// 规范化 JMA 震度字符串
  ///
  /// 将各种格式的震度字符串转换为标准格式。
  /// 例如: "5弱" -> "5-", "5強" -> "5+", "5" -> "5"
  String _normalizeJmaShindo(String shindo) {
    final s = shindo.trim();
    if (s.isEmpty) return '';
    
    // 处理 "5弱", "5強" 等格式
    if (s.contains('弱') || s.toLowerCase().contains('low')) {
      final num = RegExp(r'\d+').firstMatch(s);
      return num != null ? '${num.group(0)}-' : s;
    }
    if (s.contains('強') || s.toLowerCase().contains('high')) {
      final num = RegExp(r'\d+').firstMatch(s);
      return num != null ? '${num.group(0)}+' : s;
    }
    
    // 处理 "5-", "5+" 格式
    if (s.contains('-') && !s.startsWith('-')) return s;
    if (s.contains('+') && !s.startsWith('+')) return s;
    
    // 纯数字
    final num = RegExp(r'\d+').firstMatch(s);
    if (num != null) {
      final val = int.tryParse(num.group(0) ?? '');
      if (val != null && val >= 1 && val <= 7) {
        return val.toString();
      }
    }
    
    return s;
  }

  /// 计算 EEW 超时时间（秒）
  ///
  /// 对齐 kanameishi-dev 的过期策略，直接用原始字段计算
  static int _eewTimeoutForSource(
    QuakeSourceType source,
    double magnitude,
    double magnitudel,
    bool isCancel, {
    bool isWarn = false,
  }) {
    if (isCancel) return 20;
    final mag = magnitude > 0 ? magnitude : magnitudel;
    if (isWarn) return ((mag > 6 ? mag : 6) * 60).ceil();
    return ((mag > 3 ? mag : 3) * 60).ceil();
  }

  /// 计算从报告时间到当前的已过去秒数
  ///
  /// 对齐 kanameishi-dev 的 calcPassedTime(reportTime, timeZone) 逻辑：
  /// 1. 时间字符串是数据源本地时间
  /// 2. 减去时区偏移转为 UTC 时间戳
  /// 3. 与当前 UTC 时间比较
  static int _calcPassedSecondsForSource(
    QuakeSourceType source,
    String reportTimeStr,
    String originTimeStr,
  ) {
    // 选择可用的时间字符串
    String timeStr = reportTimeStr.isNotEmpty ? reportTimeStr : originTimeStr;
    if (timeStr.isEmpty) return 0;

    // 解析时间字符串
    final parsed = DateTime.tryParse(timeStr);
    if (parsed == null) return 0;

    // 确定时区偏移（对齐 kanameishi 的 timeZone 字段）
    final int tzOffsetHours = QuakeTime.isJapanSource(source) ? 9 : 8;

    // kanameishi: dayjs.utc(time).subtract(timeZone, "hours")
    // 将本地时间字符串视为 UTC，减去时区偏移得到真正的 UTC 时间戳
    final utcInstant = DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).subtract(Duration(hours: tzOffsetHours));

    final elapsed = DateTime.now().toUtc().difference(utcInstant);
    return elapsed.inSeconds.clamp(0, 999999);
  }

  /// 格式化震度字符串
  ///
  /// 参考 kanameishi 的 formatShindo 函数
  /// 将震度转换为符号格式：
  /// - "5強" -> "5+"
  /// - "5弱" -> "5-"
  /// - "6強" -> "6+"
  /// - "6弱" -> "6-"
  /// - 移除 "級" 字符
  ///
  /// 参数：
  /// - [intensity]: 原始震度字符串
  ///
  /// 返回：
  /// - 格式化后的震度字符串
  String _formatShindo(String intensity) {
    if (intensity.isEmpty) return intensity;
    
    return intensity
        .replaceAll('強', '+')
        .replaceAll('弱', '-')
        .replaceAll('級', '')
        .trim();
  }

  /// 提取 CWA 地点名称
  ///
  /// CWA 地点格式: "花蓮縣政府南偏西方 25.0 公里 (位於花蓮縣秀林鄉)"
  /// 提取后: "花蓮縣秀林鄉"
  ///
  /// 参数：
  /// - [loc]: 原始地点字符串
  ///
  /// 返回：
  /// - 提取后的地点名称
  String _extractCwaLocation(String loc) {
    if (loc.isEmpty) return loc;
    
    final start = loc.indexOf('(位於');
    final end = loc.indexOf(')');
    
    if (start == -1 || end == -1 || start + 3 >= end) {
      return loc;
    }
    
    return loc.substring(start + 3, end);
  }

  /// 映射 QuakeSourceType → 适配器 source 字符串
  /// 并通过适配器转换并发射统一事件
  void _emitFanUnified(QuakeSourceType source, Map<String, dynamic> data) {
    final adapterSource = _sourceToAdapterSource(source);
    if (adapterSource == null) return;
    final result = QuakeEventAdapter.convert(adapterSource, data, 1);
    if (result != null) emitUnified(result);
  }

  String? _sourceToAdapterSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.jma_fan:
        return 'jmaEew';
      case QuakeSourceType.cenc:
        return 'cencEqlist';
      case QuakeSourceType.cwa:
        return 'cwaEqlist';
      case QuakeSourceType.cwa_eew:
        return 'cwaEew';
      case QuakeSourceType.cea:
        return 'ceaEew';
      case QuakeSourceType.cea_pr:
        return 'ceaEew';
      case QuakeSourceType.sc_eew:
        return 'scEew';
      case QuakeSourceType.fj_eew:
        return 'fjEew';
      case QuakeSourceType.kma_eq:
        return 'kmaEqlist';
      case QuakeSourceType.kma_eew_fan:
        return 'kmaEew';
      case QuakeSourceType.hko:
        return 'hko';
      case QuakeSourceType.sa:
        return 'sa';
      case QuakeSourceType.emsc:
        return 'emsc';
      case QuakeSourceType.bcsf:
        return 'bcsf';
      case QuakeSourceType.gfz:
        return 'gfz';
      case QuakeSourceType.usp:
        return 'usp';
      case QuakeSourceType.usgs:
        return 'usgsEqlist';
      case QuakeSourceType.fssn:
        return 'fssnEqlist';
      case QuakeSourceType.ningxia:
        return 'ningxia';
      case QuakeSourceType.guangxi:
        return 'guangxi';
      case QuakeSourceType.shanxi:
        return 'shanxi';
      case QuakeSourceType.beijing:
        return 'beijing';
      case QuakeSourceType.yunnan:
        return 'yunnan';
      case QuakeSourceType.fssnCmt:
        return 'fssnCmt';
      default:
        return null;
    }
  }
}
