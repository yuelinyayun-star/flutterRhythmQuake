import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:latlong2/latlong.dart';
import 'base_source.dart';
import '../../models/quake_message.dart';
import '../../models/tsunami_message.dart';
import '../../models/source_status.dart';
import '../../services/quake_event_adapter.dart';
import '../../models/unified_quake_data.dart';
import 'nied_monitor.dart';
import '../../models/nied_calibration.dart';
import '../../core/source_estimation/kotoho7_js_receiver_bridge.dart';
import 'shake_detection_service.dart';
import 'jp_shindo_scale.dart';
import 'lmoni_image_service.dart';

/// 模拟输入服务
///
/// 该类提供手动注入地震数据的功能。
/// 用于测试和调试，支持多种数据格式的解析。
///
/// 主要功能：
/// - 解析JSON/JS格式的地震数据
/// - 支持Wolfx、P2P、FAN等多种数据格式
/// - 自动识别数据格式类型
/// - 提取嵌套的JSON数据块
///
/// 支持的数据格式：
/// - Wolfx格式: JMA/CENC/CWA等预警格式
/// - P2P格式: P2PQuake地震信息格式
/// - FAN格式: FanStudio聚合数据格式
class MockInputService extends BaseSourceService {
  bool _niedGifInjectionRunning = false;

  @override
  String get name => 'Mock';

  @override
  void connect() {
    onStatusChanged?.call(SourceStatus.connected);
  }

  @override
  void disconnect() {
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  /// 从原始字符串注入地震数据
  ///
  /// 支持多种输入格式：
  /// - 纯JSON字符串
  /// - JavaScript对象字面量
  /// - Markdown代码块包裹的JSON
  ///
  /// [raw] 原始输入字符串
  /// 返回成功解析的地震事件数量
  int injectFromJs(String raw) {
    final normalized = _extractJsonBlob(raw);
    if (normalized == null || normalized.trim().isEmpty) {
      throw FormatException('未识别到可解析的 JSON/JS 数据块');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(normalized);
    } catch (_) {
      final converted = _tryConvertJsObject(normalized);
      decoded = jsonDecode(converted);
    }

    int count = 0;
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          if (_tryInjectTsunami(item)) {
            count++;
            continue;
          }
          final q = _parseAny(item);
          if (q != null) {
            emit(q);
            _emitUnifiedFromQuakeMessage(q, item);
            count++;
          }
        }
      }
    } else if (decoded is Map<String, dynamic>) {
      if (_tryInjectTsunami(decoded)) {
        count = 1;
      } else {
        final q = _parseAny(decoded);
        if (q != null) {
          emit(q);
          _emitUnifiedFromQuakeMessage(q, decoded);
          count = 1;
        }
      }
    }

    if (count == 0) {
      throw FormatException('已解析输入，但未匹配 Wolfx/FAN/P2P 可用地震结构');
    }
    return count;
  }

  void _emitUnifiedFromQuakeMessage(QuakeMessage q, Map<String, dynamic> json) {
    try {
      final adapterSource = _quakeSourceToAdapterSource(q.source);
      if (adapterSource == null) {
        debugPrint('_emitUnified: no adapter for source=${q.source}');
        return;
      }
      final origin = _getOrigin(q.source);

      final result = QuakeEventAdapter.convert(adapterSource, json, origin);
      if (result != null) {
        if (result.magnitude < 0 && q.magnitude > 0) {
          final fixed = UnifiedQuakeData(
            source: result.source,
            origin: result.origin,
            eventId: q.eventId.isNotEmpty ? q.eventId : result.eventId,
            isEew: result.isEew,
            timeZone: result.timeZone,
            titleText: result.titleText,
            reportNumText: result.reportNumText,
            useShindo: result.useShindo,
            maxIntensity: result.maxIntensity,
            className: result.className,
            hypocenter: result.hypocenter,
            originTime: result.originTime,
            magnitude: q.magnitude,
            depth: q.depth,
            depthText: result.depthText,
            lat: q.latitude,
            lng: q.longitude,
            isWarn: result.isWarn,
            isFinal: result.isFinal,
            isCanceled: result.isCanceled,
            isAssumption: result.isAssumption,
            warnArea: result.warnArea,
            rawEvent: result.rawEvent,
            arrivedAt: result.arrivedAt,
          );
          debugPrint(
            '_emitUnified: fixed from QuakeMessage mag=${q.magnitude}, depth=${q.depth}, lat=${q.latitude}, lng=${q.longitude}',
          );
          emitUnified(fixed);
        } else {
          debugPrint(
            '_emitUnified: OK eventId=${result.eventId}, isEew=${result.isEew}, mag=${result.magnitude}',
          );
          emitUnified(result);
        }
      } else {
        final fallback = _buildUnifiedFromQuakeMessage(q);
        if (fallback != null) {
          debugPrint(
            '_emitUnified: fallback from QuakeMessage mag=${q.magnitude}',
          );
          emitUnified(fallback);
        } else {
          debugPrint('_emitUnified: adapter returned null, fallback also null');
        }
      }
    } catch (e, stack) {
      debugPrint('_emitUnified ERROR: $e');
      debugPrint(stack.toString().split('\n').take(3).join('\n'));
    }
  }

  UnifiedQuakeData? _buildUnifiedFromQuakeMessage(QuakeMessage q) {
    final isEew = _isEewSource(q.source);
    final useShindo = _isJmaOrCwaSource(q.source);
    final timeZone = _getTimeZone(q.source);
    final className = _setClassNameFromQuakeMessage(q);
    final adapterSource = _quakeSourceToAdapterSource(q.source);

    return UnifiedQuakeData(
      source: adapterSource ?? q.source.name,
      origin: _getOrigin(q.source),
      eventId: q.eventId,
      isEew: isEew,
      timeZone: timeZone,
      titleText: isEew ? '地震预警' : '地震信息',
      reportNumText: q.reportNumText ?? '',
      useShindo: useShindo,
      maxIntensity: _formatMaxIntensity(q),
      className: className,
      hypocenter: q.location,
      originTime: q.originTime,
      magnitude: q.magnitude,
      depth: q.depth,
      depthText: '震源深度 ${q.depth > 0 ? q.depth.round() : "?"}km',
      lat: q.latitude,
      lng: q.longitude,
      isWarn: q.isWarn,
      isFinal: q.isFinal,
      isCanceled: q.isCanceled,
      isAssumption: q.isAssumption,
      arrivedAt: DateTime.now(),
    );
  }

  bool _isEewSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
      case QuakeSourceType.cwa_eew:
      case QuakeSourceType.cea:
      case QuakeSourceType.cea_pr:
      case QuakeSourceType.sc_eew:
      case QuakeSourceType.fj_eew:
      case QuakeSourceType.cq_eew:
      case QuakeSourceType.kma_eew_fan:
        return true;
      default:
        return false;
    }
  }

  bool _isJmaOrCwaSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
      case QuakeSourceType.jma_fan:
      case QuakeSourceType.p2p:
      case QuakeSourceType.cwa_eew:
      case QuakeSourceType.cwa:
      case QuakeSourceType.kma_eew_fan:
      case QuakeSourceType.kma_eq:
        return true;
      default:
        return false;
    }
  }

  int _getTimeZone(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
      case QuakeSourceType.jma_fan:
      case QuakeSourceType.p2p:
      case QuakeSourceType.kma_eew_fan:
      case QuakeSourceType.kma_eq:
        return 9;
      case QuakeSourceType.cwa_eew:
      case QuakeSourceType.cwa:
        return 8;
      default:
        return 8;
    }
  }

  String _formatMaxIntensity(QuakeMessage q) {
    if (q.jmaShindo != null) return q.jmaShindo!;
    if (q.maxIntensity != null) return '${q.maxIntensity}';
    return '-';
  }

  String _setClassNameFromQuakeMessage(QuakeMessage q) {
    if (q.isCanceled) return 'dark-gray';
    if (q.jmaShindo != null) {
      final map = {
        '0': 'gray',
        '1': 'blue',
        '2': 'green',
        '3': 'yellow',
        '4': 'orange',
        '5-': 'dark-orange',
        '5弱': 'dark-orange',
        '5+': 'red',
        '5強': 'red',
        '6-': 'dark-red',
        '6弱': 'dark-red',
        '6+': 'purple',
        '6強': 'purple',
        '7': 'purple',
      };
      return map[q.jmaShindo] ?? 'gray';
    }
    if (q.maxIntensity != null) {
      final i = q.maxIntensity!;
      if (i <= 0) return 'gray';
      if (i <= 2) return 'sky-blue';
      if (i <= 4) return 'blue';
      if (i <= 5) return 'green';
      if (i <= 6) return 'yellow';
      if (i <= 7) return 'orange';
      if (i <= 8) return 'dark-orange';
      if (i <= 9) return 'red';
      return 'purple';
    }
    return 'gray';
  }

  String? _quakeSourceToAdapterSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
        return 'jmaEew';
      case QuakeSourceType.jma_fan:
        return 'jmaEew';
      case QuakeSourceType.cwa_eew:
        return 'cwaEew';
      case QuakeSourceType.cwa:
        return 'cwaEqlist';
      case QuakeSourceType.cea:
        return 'ceaEew';
      case QuakeSourceType.cea_pr:
        return 'ceaEew';
      case QuakeSourceType.sc_eew:
        return 'scEew';
      case QuakeSourceType.fj_eew:
        return 'fjEew';
      case QuakeSourceType.cq_eew:
        return 'cqEew';
      case QuakeSourceType.kma_eew_fan:
        return 'kmaEew';
      case QuakeSourceType.kma_eq:
        return 'kmaEqlist';
      case QuakeSourceType.p2p:
        return 'jmaEqlist';
      case QuakeSourceType.cenc:
        return 'cencEqlist';
      case QuakeSourceType.usgs:
        return 'usgsEqlist';
      case QuakeSourceType.fssn:
        return 'fssnEqlist';
      case QuakeSourceType.fssnCmt:
        return 'fssnCmt';
      case QuakeSourceType.cencCmt:
        return 'cencCmt';
      case QuakeSourceType.hko:
        return 'hko';
      case QuakeSourceType.emsc:
        return 'emsc';
      case QuakeSourceType.bcsf:
        return 'bcsf';
      case QuakeSourceType.gfz:
        return 'gfz';
      case QuakeSourceType.usp:
        return 'usp';
      case QuakeSourceType.sa:
        return 'sa';
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
      default:
        return null;
    }
  }

  int _getOrigin(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
        return 0;
      case QuakeSourceType.p2p:
        return 2;
      default:
        return 1;
    }
  }

  /// 尝试解析任意格式的地震数据
  ///
  /// 自动识别数据格式并调用对应的解析器
  /// 尝试注入海啸数据 (code 552)
  /// 返回 true 表示已处理
  bool _tryInjectTsunami(Map<String, dynamic> json) {
    final code = int.tryParse(json['code']?.toString() ?? '');
    if (code != 552) return false;
    try {
      final tsunami = TsunamiMessage.parseJmaTsunami(json);
      emitTsunami(tsunami);
      debugPrint(
        'Inject tsunami: ${tsunami.title} (${tsunami.areas.length} areas)',
      );
      return true;
    } catch (e) {
      debugPrint('Inject tsunami failed: $e');
      return false;
    }
  }

  QuakeMessage? _parseAny(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? '';
    final code = int.tryParse(json['code']?.toString() ?? '');

    if (type == 'jma_eew' ||
        type == 'cenc_eew' ||
        type == 'fj_eew' ||
        type == 'cq_eew' ||
        type == 'sc_eew' ||
        type == 'cwa_eew') {
      return _parseWolfx(json);
    }

    if (code == 551 ||
        code == 552 ||
        (json.containsKey('issue') && json.containsKey('earthquake'))) {
      return _parseP2P(json);
    }

    if (json.containsKey('shockTime') ||
        json.containsKey('eventId') ||
        json.containsKey('placeName')) {
      return _parseFan(json);
    }

    if ((json.containsKey('EventID') || json.containsKey('ID')) &&
        (json.containsKey('OriginTime') || json.containsKey('ReportTime')) &&
        (json.containsKey('HypoCenter') ||
            json.containsKey('Hypocenter') ||
            json.containsKey('Latitude'))) {
      final guessed = Map<String, dynamic>.from(json);
      guessed.putIfAbsent('type', () {
        if (guessed.containsKey('Serial') ||
            guessed.containsKey('AnnouncedTime')) {
          return 'jma_eew';
        }
        if (guessed.containsKey('MaxIntensity') &&
            guessed.containsKey('HypoCenter')) {
          return 'cenc_eew';
        }
        return 'cenc_eew';
      });
      return _parseWolfx(guessed);
    }

    for (final key in const ['data', 'Data', 'payload', 'message']) {
      final wrapped = json[key];
      if (wrapped is Map<String, dynamic>) {
        final parsed = _parseAny(wrapped);
        if (parsed != null) return parsed;
      }
      if (wrapped is List) {
        for (final item in wrapped) {
          if (item is Map<String, dynamic>) {
            final parsed = _parseAny(item);
            if (parsed != null) return parsed;
          }
        }
      }
    }

    return null;
  }

  /// 解析Wolfx格式的地震数据
  ///
  /// Wolfx格式支持多种预警类型：
  /// - jma_eew: 日本气象厅预警
  /// - cenc_eew: 中国地震台网中心预警
  /// - fj_eew/cq_eew/sc_eew: 省级地震局预警
  /// - cwa_eew: 台湾中央气象署预警
  QuakeMessage _parseWolfx(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? 'jma_eew';
    if (type == 'jma_eew') {
      final eventId =
          _pick(json, ['EventID', 'eventId', 'ID']) ?? _newId('wolfx_jma');
      final origin =
          _parseDate(_pick(json, ['OriginTime', 'originTime'])) ??
          DateTime.now();
      final announced = _parseDate(
        _pick(json, ['AnnouncedTime', 'ReportTime']),
      );
      final serial = _toInt(_pick(json, ['Serial', 'ReportNum']));
      return QuakeMessage(
        source: QuakeSourceType.wolfx,
        eventId: eventId,
        location: _pick(json, ['Hypocenter', 'placeName']) ?? '未知地点',
        magnitude:
            _toDouble(_pick(json, ['Magunitude', 'Magnitude', 'magnitude'])) ??
            0.0,
        latitude: _toDouble(_pick(json, ['Latitude', 'latitude'])) ?? 0.0,
        longitude: _toDouble(_pick(json, ['Longitude', 'longitude'])) ?? 0.0,
        depth: _toDouble(_pick(json, ['Depth', 'depth'])) ?? 0.0,
        originTime: origin,
        reportNumber: serial != null && serial > 0 ? serial : null,
        reportTime: announced,
      );
    }

    final source = switch (type) {
      'cenc_eew' => QuakeSourceType.cenc,
      'fj_eew' => QuakeSourceType.fj_eew,
      'cq_eew' => QuakeSourceType.cq_eew,
      'sc_eew' => QuakeSourceType.sc_eew,
      'cwa_eew' => QuakeSourceType.cwa_eew,
      _ => QuakeSourceType.cenc,
    };

    final eventId =
        _pick(json, ['EventID', 'eventId', 'ID']) ??
        _newId('wolfx_${source.name}');
    final origin =
        _parseDate(_pick(json, ['OriginTime', 'originTime'])) ?? DateTime.now();
    final report = _parseDate(_pick(json, ['ReportTime', 'AnnouncedTime']));
    final reportNum = _toInt(_pick(json, ['ReportNum', 'Serial']));
    return QuakeMessage(
      source: source,
      eventId: eventId,
      location:
          _pick(json, ['HypoCenter', 'Hypocenter', 'placeName']) ?? '未知地点',
      magnitude:
          _toDouble(_pick(json, ['Magnitude', 'Magunitude', 'magnitude'])) ??
          0.0,
      latitude: _toDouble(_pick(json, ['Latitude', 'latitude'])) ?? 0.0,
      longitude: _toDouble(_pick(json, ['Longitude', 'longitude'])) ?? 0.0,
      depth: _toDouble(_pick(json, ['Depth', 'depth'])) ?? 0.0,
      originTime: origin,
      maxIntensity: _toInt(_pick(json, ['MaxIntensity', 'maxIntensity'])),
      reportNumber: reportNum != null && reportNum > 0 ? reportNum : null,
      reportTime: report,
    );
  }

  /// 解析P2PQuake格式的地震数据
  ///
  /// P2PQuake格式包含issue和earthquake两个主要字段
  QuakeMessage? _parseP2P(Map<String, dynamic> json) {
    final issue = json['issue'];
    final eq = json['earthquake'];
    if (issue is! Map<String, dynamic> || eq is! Map<String, dynamic>) {
      return null;
    }

    final hypo = eq['hypocenter'];
    final location =
        (hypo is Map<String, dynamic> ? hypo['name'] : null)?.toString() ??
        '未知地点';
    final magnitude =
        _toDouble(hypo is Map<String, dynamic> ? hypo['magnitude'] : null) ??
        0.0;
    final lat = _parseCoord(
      hypo is Map<String, dynamic> ? hypo['latitude'] : null,
    );
    final lng = _parseCoord(
      hypo is Map<String, dynamic> ? hypo['longitude'] : null,
    );
    final depth = _parseDepth(
      hypo is Map<String, dynamic> ? hypo['depth'] : null,
    );

    return QuakeMessage(
      source: QuakeSourceType.p2p,
      eventId: _makeP2PEventId(json),
      location: location,
      magnitude: magnitude,
      latitude: lat,
      longitude: lng,
      depth: depth,
      originTime: _parseDate(issue['time']?.toString()) ?? DateTime.now(),
      maxIntensity: _parseP2PMaxIntensity(eq['maxScale']),
      reportNumber: _toInt(issue['correct']),
      reportTime: _parseDate(issue['time']?.toString()),
    );
  }

  /// 解析FanStudio格式的地震数据
  ///
  /// FAN格式是FanStudio聚合平台的数据格式
  QuakeMessage _parseFan(Map<String, dynamic> json) {
    final source = _resolveFanSource(json);
    final eventId =
        _pick(json, ['eventId', 'id', 'md5']) ?? _newId('fan_${source.name}');
    final origin =
        _parseDate(_pick(json, ['shockTime', 'OriginTime'])) ?? DateTime.now();
    final reportTime = _parseDate(_pick(json, ['createTime', 'ReportTime']));
    final updates = _toInt(_pick(json, ['updates', 'ReportNum']));
    return QuakeMessage(
      source: source,
      eventId: eventId,
      location:
          _pick(json, ['placeName', 'locationDesc', 'title', 'HypoCenter']) ??
          '未知地点',
      magnitude:
          _toDouble(_pick(json, ['magnitude', 'Magnitude', 'Magunitude'])) ??
          0.0,
      latitude: _toDouble(_pick(json, ['latitude', 'Latitude'])) ?? 0.0,
      longitude: _toDouble(_pick(json, ['longitude', 'Longitude'])) ?? 0.0,
      depth: _toDouble(_pick(json, ['depth', 'Depth'])) ?? 0.0,
      originTime: origin,
      maxIntensity: _toInt(
        _pick(json, ['epiIntensity', 'maxIntensity', 'MaxIntensity']),
      ),
      infoTypeName: _pick(json, ['infoTypeName']),
      verify: _pick(json, ['verify']),
      reportNumber: updates != null && updates > 0 ? updates : null,
      reportTime: reportTime,
    );
  }

  /// 解析FAN数据源类型
  ///
  /// 根据数据特征判断具体的数据源
  QuakeSourceType _resolveFanSource(Map<String, dynamic> json) {
    final sourceHint = json['source']?.toString();
    if (sourceHint != null && sourceHint.isNotEmpty) {
      switch (sourceHint) {
        case 'jma':
          return QuakeSourceType.jma_fan;
        case 'cenc':
          return QuakeSourceType.cenc;
        case 'cea':
          return QuakeSourceType.cea;
        case 'cea-pr':
          return QuakeSourceType.cea_pr;
        case 'cwa':
          return QuakeSourceType.cwa;
        case 'cwa-eew':
          return QuakeSourceType.cwa_eew;
        case 'kma':
          return QuakeSourceType.kma_eq;
        case 'kma-eew':
          return QuakeSourceType.kma_eew_fan;
      }
    }

    if (json.containsKey('final') || json.containsKey('cancel')) {
      return QuakeSourceType.jma_fan;
    }
    if (json.containsKey('affectedAreas')) return QuakeSourceType.kma_eew_fan;
    if (json.containsKey('province')) return QuakeSourceType.cea_pr;
    if (json.containsKey('epiIntensity')) return QuakeSourceType.cea;
    return QuakeSourceType.cenc;
  }

  /// 从原始字符串中提取JSON数据块
  ///
  /// 支持多种格式：
  /// - 纯JSON对象/数组
  /// - Markdown代码块包裹的JSON
  /// - 嵌套在文本中的JSON
  String? _extractJsonBlob(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    text = text.replaceAllMapped(
      RegExp(r'^```[a-zA-Z0-9_-]*\s*|\s*```$'),
      (_) => '',
    );

    if ((text.startsWith('{') && text.endsWith('}')) ||
        (text.startsWith('[') && text.endsWith(']'))) {
      return text;
    }

    final startObj = text.indexOf('{');
    final startArr = text.indexOf('[');
    int start = -1;
    if (startObj >= 0 && startArr >= 0) {
      start = startObj < startArr ? startObj : startArr;
    } else if (startObj >= 0) {
      start = startObj;
    } else if (startArr >= 0) {
      start = startArr;
    }
    if (start < 0) return null;

    final open = text[start];
    final close = open == '{' ? '}' : ']';
    int depth = 0;
    bool inString = false;
    String quote = '"';
    bool escape = false;

    for (int i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escape) {
          escape = false;
          continue;
        }
        if (ch == r'\') {
          escape = true;
          continue;
        }
        if (ch == quote) {
          inString = false;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        inString = true;
        quote = ch;
        continue;
      }
      if (ch == open) depth++;
      if (ch == close) {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  /// 尝试将JavaScript对象字面量转换为JSON
  ///
  /// 处理JS特有的语法：
  /// - 无引号的属性名
  /// - 单引号字符串
  /// - 尾随逗号
  String _tryConvertJsObject(String src) {
    var s = src.trim();
    s = s.replaceAll(RegExp(r'^\s*(const|let|var)\s+\w+\s*=\s*'), '');
    s = s.replaceAll(RegExp(r';\s*$'), '');
    s = s.replaceAllMapped(RegExp(r'([{\[,]\s*)([A-Za-z_]\w*)(\s*:)'), (m) {
      return '${m[1]}"${m[2]}"${m[3]}';
    });
    s = s.replaceAll("'", '"');
    s = s.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);
    return s;
  }

  /// 从多个可能的键中选取值
  String? _pick(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      if (map.containsKey(k) && map[k] != null) {
        final v = map[k].toString();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  double? _toDouble(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());
  int? _toInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text.replaceAll('/', '-').replaceFirst(' ', 'T'));
  }

  /// 解析坐标值
  ///
  /// 支持数字和带方向前缀的格式 (如 "N35.5", "S35.5")
  double _parseCoord(dynamic value) {
    if (value == null) return 0.0;
    final v = value.toString().trim();
    if (v.isEmpty) return 0.0;
    final p = v[0].toUpperCase();
    if (p == 'N' || p == 'S' || p == 'E' || p == 'W') {
      final n = double.tryParse(v.substring(1)) ?? 0.0;
      return (p == 'S' || p == 'W') ? -n : n;
    }
    return double.tryParse(v) ?? 0.0;
  }

  /// 解析深度值
  ///
  /// 支持带"km"后缀的格式
  double _parseDepth(dynamic value) {
    if (value == null) return 0.0;
    return double.tryParse(value.toString().replaceAll('km', '').trim()) ?? 0.0;
  }

  /// 解析P2P最大烈度
  ///
  /// P2P使用10倍烈度值存储
  int? _parseP2PMaxIntensity(dynamic maxScale) {
    final n = _toInt(maxScale);
    if (n == null || n <= 0) return null;
    return (n / 10).round();
  }

  /// 生成P2P事件ID
  String _makeP2PEventId(Map<String, dynamic> json) {
    final id = json['_id'];
    if (id is Map && id['\$oid'] != null) return id['\$oid'].toString();
    return _newId('p2p');
  }

  /// 生成新的事件ID
  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}';

  /// 从 K-NET ASCII zip 文件注入测站数据
  ///
  /// 解析 zip 中的 .NS/.EW/.UD 文件，提取各站 PGA，
  /// 转换为 scratch level，灌入 ShakeDetectionService。
  ///
  /// [zipPath] K-NET ASCII zip 文件路径
  /// 返回注入的测站数量
  int injectFromKnetZip(String zipPath) {
    final file = File(zipPath);
    if (!file.existsSync()) {
      throw FormatException('文件不存在: $zipPath');
    }

    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    final stations = <String, _KnetStationAcc>{};

    for (final entry in archive.files) {
      if (entry.isFile != true) continue;
      final name = entry.name;
      if (!name.endsWith('.NS') &&
          !name.endsWith('.EW') &&
          !name.endsWith('.UD')) {
        continue;
      }

      final comp = name.substring(name.length - 2);
      final fname = name.split('/').last;
      final codeIdx = fname.indexOf('2606');
      if (codeIdx < 0) continue;
      final code = fname.substring(0, codeIdx);

      final content = utf8.decode(entry.content as List<int>);
      final lines = content.split('\n');
      double? pga;
      double? lat;
      double? lng;

      for (final line in lines) {
        if (line.startsWith('Max. Acc. (gal)')) {
          final m = RegExp(r'([\d.]+)\s*$').firstMatch(line);
          if (m != null) pga = double.tryParse(m.group(1)!);
        } else if (line.startsWith('Station Lat.')) {
          final m = RegExp(r'([\d.]+)\s*$').firstMatch(line);
          if (m != null) lat = double.tryParse(m.group(1)!);
        } else if (line.startsWith('Station Long.')) {
          final m = RegExp(r'([\d.]+)\s*$').firstMatch(line);
          if (m != null) lng = double.tryParse(m.group(1)!);
        }
      }

      if (pga == null || lat == null || lng == null) continue;
      final l = lat;
      final ln = lng;
      stations.putIfAbsent(code, () => _KnetStationAcc(code, l, ln));
      final s = stations[code]!;
      if (pga > s.maxPga) s.maxPga = pga;
      s.comps[comp] = pga;
    }

    if (stations.isEmpty) {
      throw FormatException('未从 zip 中找到有效的 K-NET 测站数据');
    }

    // Convert to NiedStation list
    final niedStations = <NiedStation>[];
    double avgLat = 0, avgLng = 0;

    for (final ks in stations.values) {
      // PGA → shindo
      final pga = ks.maxPga;
      double shindo;
      if (pga > 0.001) {
        shindo = 2.68 + 1.72 * _log10(pga);
      } else {
        shindo = -3.0;
      }
      final level = JpShindoScale.kanameishiLevelFromShindo(shindo);
      if (level < 0) continue;

      final ns = NiedStation(
        id: ks.code.hashCode,
        code: ks.code,
        name: ks.code,
        coordinate: LatLng(ks.lat, ks.lng),
        network: 'K-NET',
        prefecture: _guessPref(ks.lat, ks.lng),
        expireSeconds: 5,
        level: level,
      );
      ns.recentLevel = List.filled(5, level);
      ns.lastUpdate = DateTime.now();
      ns.calibrationFactor =
          NiedCalibration.factors[ks.code] ?? NiedCalibration.defaultFactor;
      ns.thresholdCode =
          NiedCalibration.thresholdCodes[ks.code] ??
          NiedCalibration.defaultThresholdCode;
      niedStations.add(ns);
      avgLat += ks.lat;
      avgLng += ks.lng;
    }

    avgLat /= niedStations.length;
    avgLng /= niedStations.length;

    // Feed to ShakeDetectionService
    final detection = ShakeDetectionService();
    detection.setSensitivity(2);
    detection.setStations(niedStations);

    // Broadcast to map via LmoniImageService stream
    LmoniImageService().broadcastStations(niedStations);

    // Run multiple frames for detection
    for (int f = 0; f < 3; f++) {
      for (final s in niedStations) {
        s.lastUpdate = DateTime.now();
      }
      detection.processUpdate();
    }

    debugPrint(
      '[KNET] Injected ${niedStations.length} stations'
      ' (${stations.length} raw) from $zipPath'
      ', avg epicenter=(${avgLat.toStringAsFixed(3)}, ${avgLng.toStringAsFixed(3)})',
    );

    return niedStations.length;
  }

  /// 直接从 NIED GIF 文件或目录注入。
  ///
  /// 目录输入会优先选择 `*.jma_s.gif`，避免把井下/物理量图层当成实时震度图。
  /// 每张 GIF 对应一个秒级时刻，直接进入 `LmoniImageService.processPixels()`，后续测站更新、检测、
  /// 震源推算都走应用现有实时链路。
  Future<int> injectFromNiedGifPath(String path) async {
    if (_niedGifInjectionRunning) {
      throw StateError('NIED GIF 注入正在进行中');
    }
    final target = FileSystemEntity.typeSync(path);
    if (target == FileSystemEntityType.notFound) {
      throw FormatException('路径不存在: $path');
    }

    final files = target == FileSystemEntityType.directory
        ? _niedGifFilesInDirectory(Directory(path))
        : [File(path)];
    if (files.isEmpty) {
      throw FormatException('未找到可注入的 NIED GIF: $path');
    }

    _niedGifInjectionRunning = true;
    final imageService = LmoniImageService()..start();
    var injected = 0;
    DateTime? fallbackTime;
    DateTime? firstDataTime;
    final playbackClock = Stopwatch()..start();
    try {
      for (final file in files) {
        final dataTime =
            _niedGifTimestampFromName(file) ??
            (fallbackTime = (fallbackTime ?? DateTime.now()).add(
              const Duration(seconds: 1),
            ));
        firstDataTime ??= dataTime;
        final targetElapsed = dataTime.difference(firstDataTime);
        if (targetElapsed > Duration.zero) {
          final remaining = targetElapsed - playbackClock.elapsed;
          if (remaining > Duration.zero) {
            await Future<void>.delayed(remaining);
          }
        }

        final bytes = await file.readAsBytes();
        final decoded = image_lib.decodeImage(bytes);
        if (decoded == null) continue;
        if (decoded.width != 352 || decoded.height != 400) {
          debugPrint(
            '[NIED GIF Inject] skip ${file.path}: '
            'unexpected size ${decoded.width}x${decoded.height}',
          );
          continue;
        }
        final packedRgb = _packedRgbFromImage(decoded);
        imageService.processPixels(
          packedRgb,
          surfaceGifBytes: Uint8List.fromList(bytes),
          dataTime: dataTime,
          receivedAt: DateTime.now(),
        );
        await _waitForNiedSourceBridgePlaybackBackpressure();
        injected++;
      }
    } finally {
      _niedGifInjectionRunning = false;
    }
    debugPrint('[NIED GIF Inject] Injected $injected GIF seconds from $path');
    return injected;
  }

  Future<void> _waitForNiedSourceBridgePlaybackBackpressure() async {
    // StreamController.add() delivers the map listener on a later microtask.
    // Yield once so the NIED source-estimation driver can enqueue the JS frame
    // before we inspect bridge pressure.
    await Future<void>.delayed(Duration.zero);
    const maxWait = Duration(milliseconds: 1200);
    final stopwatch = Stopwatch()..start();
    var lastLogged = '';
    while (stopwatch.elapsed < maxWait) {
      final status = Kotoho7JsReceiverBridge.queueStatus();
      if (!status.hasWork) return;
      final signature =
          '${status.pendingFrameCount}/${status.inFlightSessionCount}';
      if (kDebugMode && signature != lastLogged) {
        lastLogged = signature;
        debugPrint(
          '[NIED GIF Inject] wait JS bridge '
          'pending=${status.pendingFrameCount} '
          'inFlight=${status.inFlightSessionCount}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  List<File> _niedGifFilesInDirectory(Directory directory) {
    if (!directory.existsSync()) return const [];
    final allGifFiles = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.gif'))
        .toList(growable: false);
    final surfaceGifFiles = allGifFiles
        .where((file) => file.path.toLowerCase().endsWith('.jma_s.gif'))
        .toList(growable: false);
    final selected = surfaceGifFiles.isNotEmpty ? surfaceGifFiles : allGifFiles;
    return selected.toList(growable: false)..sort(_compareNiedGifFiles);
  }

  int _compareNiedGifFiles(File left, File right) {
    final leftTime = _niedGifTimestampFromName(left);
    final rightTime = _niedGifTimestampFromName(right);
    if (leftTime != null && rightTime != null) {
      final timeCompare = leftTime.compareTo(rightTime);
      if (timeCompare != 0) return timeCompare;
    } else if (leftTime != null) {
      return -1;
    } else if (rightTime != null) {
      return 1;
    }
    return left.path.compareTo(right.path);
  }

  DateTime? _niedGifTimestampFromName(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final match = RegExp(r'(20\d{12})').firstMatch(name);
    if (match == null) return null;
    final stamp = match.group(1)!;
    return DateTime(
      int.parse(stamp.substring(0, 4)),
      int.parse(stamp.substring(4, 6)),
      int.parse(stamp.substring(6, 8)),
      int.parse(stamp.substring(8, 10)),
      int.parse(stamp.substring(10, 12)),
      int.parse(stamp.substring(12, 14)),
    );
  }

  List<int> _packedRgbFromImage(image_lib.Image image) {
    final pixels = List<int>.filled(image.width * image.height, 0);
    var index = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixels[index++] =
            (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
      }
    }
    return pixels;
  }

  double _log10(double x) => x <= 0 ? 0 : (math.log(x) / 2.302585092994046);

  String _guessPref(double lat, double lng) {
    const prefs = [
      (35.0, 139.5, '東京都'),
      (34.7, 135.5, '大阪府'),
      (35.2, 136.9, '愛知県'),
      (38.3, 140.9, '宮城県'),
      (43.1, 141.4, '北海道'),
      (37.9, 139.0, '新潟県'),
      (34.4, 132.5, '広島県'),
      (33.6, 130.4, '福岡県'),
      (36.6, 136.7, '石川県'),
      (36.4, 139.0, '群馬県'),
      (35.6, 140.1, '千葉県'),
      (37.5, 138.1, '新潟県'),
    ];
    double best = double.infinity;
    String bestPref = '日本';
    for (final (pLat, pLng, name) in prefs) {
      final d = (lat - pLat) * (lat - pLat) + (lng - pLng) * (lng - pLng);
      if (d < best) {
        best = d;
        bestPref = name;
      }
    }
    return bestPref;
  }
}

/// K-NET 测站累计 PGA 数据
class _KnetStationAcc {
  final String code;
  final double lat;
  final double lng;
  double maxPga = 0;
  final Map<String, double> comps = {};

  _KnetStationAcc(this.code, this.lat, this.lng);
}
