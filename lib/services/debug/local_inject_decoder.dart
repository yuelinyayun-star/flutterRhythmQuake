import '../../models/jian_sources.dart';
import '../../models/source_payload.dart';
import '../../models/tsunami_message.dart';
import '../../models/unified_quake_data.dart';
import '../../models/weather_alarm.dart';
import '../quake_event_adapter.dart';
import '../sources/fan_service.dart';
import '../sources/nowquake_cenc_intensity_service.dart';

const localInjectApiName = '本地注入';

class LocalInjectBatch {
  final events = <UnifiedQuakeData>[];
  final tsunamis = <TsunamiMessage>[];
  final weatherAlarms = <WeatherAlarm>[];
  int get count => events.length + tsunamis.length + weatherAlarms.length;
}

/// Decodes only: no connections, clock rewriting, UI calls or event emission.
class LocalInjectDecoder {
  static const formats = [
    'auto',
    'wolfx',
    'fan',
    'p2p',
    'whews',
    'wauth',
    'jian',
    'nowquake',
    'nied',
    'adapter',
    'unified',
  ];
  static const adapterSources = {
    'jmaEew',
    'cwaEew',
    'ceaEew',
    'scEew',
    'cqEew',
    'fjEew',
    'kmaEew',
    'sa',
    'jmaEqlist',
    'cwaEqlist',
    'cencEqlist',
    'kmaEqlist',
    'usgsEqlist',
    'fssnEqlist',
    'hko',
    'emsc',
    'bcsf',
    'gfz',
    'usp',
    'geonet',
    'ningxia',
    'guangxi',
    'shanxi',
    'beijing',
    'yunnan',
    'fssnCmt',
    'cencCmt',
    'usgsCmt',
    'jmaCmt',
    'fnetCmt',
    'hinetAquaCmt',
  };
  static const _wolfxSources = {
    'jma_eew': 'jmaEew',
    'cenc_eew': 'ceaEew',
    'cwa_eew': 'cwaEew',
    'sc_eew': 'scEew',
    'fj_eew': 'fjEew',
    'cq_eew': 'cqEew',
  };

  static LocalInjectBatch decode(
    Object? input, {
    String format = 'auto',
    String? source,
  }) {
    if (!formats.contains(format)) {
      throw FormatException('不支持的报文格式：$format');
    }
    final batch = LocalInjectBatch();
    _decode(input, batch, format: format, source: source);
    if (batch.count == 0) throw const FormatException('报文中没有可注入的事件');
    return batch;
  }

  static void _decode(
    Object? input,
    LocalInjectBatch batch, {
    required String format,
    String? source,
    bool history = false,
    bool snapshot = false,
    int depth = 0,
  }) {
    if (depth > 16) throw const FormatException('报文嵌套过深');
    void next(
      Object? value, {
      String? fmt,
      String? src,
      bool? hist,
      bool? snap,
    }) {
      _decode(
        value,
        batch,
        format: fmt ?? format,
        source: src ?? source,
        history: hist ?? history,
        snapshot: snap ?? snapshot,
        depth: depth + 1,
      );
    }

    if (input is List) {
      for (final item in input) {
        next(item);
      }
      return;
    }
    if (input is! Map || input.keys.any((key) => key is! String)) {
      throw const FormatException('报文必须是 JSON 对象或数组');
    }
    final data = Map<String, dynamic>.from(input);
    if (data['meta'] is Map && data['reports'] is List) {
      next(data['reports']);
      return;
    }
    // Our envelope is distinct from upstream data/Data envelopes.
    if (data.containsKey('format') && data.containsKey('payload')) {
      final fmt = data['format'].toString().toLowerCase();
      if (!formats.contains(fmt)) throw FormatException('不支持的报文格式：$fmt');
      next(data['payload'], fmt: fmt, src: data['source']?.toString());
      return;
    }
    final type = data['type']?.toString() ?? '';
    if (const {
      'heartbeat',
      'pong',
      'auth_success',
      'auth_fail',
      'auth_error',
    }.contains(type)) {
      return;
    }
    final code = data['code']?.toString();
    var resolved = format;
    if (resolved == 'auto') {
      resolved = code == '551' || code == '552'
          ? 'p2p'
          : _wolfxSources.containsKey(type) || type.endsWith('_eqlist')
          ? 'wolfx'
          : data['eq_id'] != null && data['stations'] is List
          ? 'nowquake'
          : type == 'all' ||
                (jianEarthquakeSources.containsKey(type) &&
                    data['Data'] != null)
          ? 'jian'
          : data['source'] != null && data['Data'] != null
          ? (type == 'update' || type == 'initial' ? 'fan' : 'whews')
          : data.containsKey('EventID')
          ? 'wolfx'
          : 'fan';
    }
    UnifiedQuakeData? event;
    if (resolved == 'p2p') {
      if (code == '552') {
        batch.tsunamis.add(TsunamiMessage.parseJmaTsunami(data));
        return;
      }
      if (code != '551') throw const FormatException('P2P 仅支持 551/552 事件报文');
      event = QuakeEventAdapter.convert('jmaEqlist', data, 2);
    } else if (resolved == 'nied') {
      event = QuakeEventAdapter.convert('jmaEew', data, 2);
    } else if (resolved == 'wolfx') {
      if (type == 'cenc_eqlist' || type == 'jma_eqlist') {
        for (final entry in data.entries) {
          if (RegExp(r'^No\d+$').hasMatch(entry.key) && entry.value is Map) {
            final item = Map<String, dynamic>.from(entry.value as Map);
            final converted = QuakeEventAdapter.convert(
              type == 'jma_eqlist' ? 'jmaEqlist' : 'cencEqlist',
              item,
              0,
            );
            if (converted != null) {
              batch.events.add(
                _local(converted.copyWith(isHistory: true), item),
              );
            }
          }
        }
        return;
      }
      final key =
          source ?? _wolfxSources[type] ?? (type.isEmpty ? 'jmaEew' : type);
      if (!adapterSources.contains(key)) {
        throw FormatException('不支持的 Wolfx 类型：$key');
      }
      event = QuakeEventAdapter.convert(key, data, 0);
    } else if (resolved == 'jian') {
      if (type == 'all') {
        for (final entry in data.entries) {
          final match = RegExp(r'^source[:：](.+)$').firstMatch(entry.key);
          if (match != null && entry.value is Map) {
            final key = match.group(1)!;
            if (!jianEarthquakeSources.containsKey(key) ||
                (entry.value as Map)['Data'] is! Map) {
              continue;
            }
            next(
              (entry.value as Map)['Data'],
              fmt: 'jian',
              src: key,
              hist: !jianEewTypes.contains(key),
              snap: true,
            );
          }
        }
        return;
      }
      if (type.endsWith('list_response')) {
        next(
          data['Data'],
          fmt: 'jian',
          src: type.substring(0, type.length - 'list_response'.length),
          hist: true,
        );
        return;
      }
      final key = source ?? type;
      if (!jianEarthquakeSources.containsKey(key)) {
        throw FormatException('不支持的 Jian 类型：$key');
      }
      final body = data['Data'] is Map
          ? Map<String, dynamic>.from(data['Data'] as Map)
          : data;
      event = QuakeEventAdapter.convertJian(
        key,
        body,
        isHistory: history,
        isSnapshot: snapshot,
      );
    } else if (resolved == 'fan' ||
        resolved == 'whews' ||
        resolved == 'wauth') {
      if (type == 'initial_all' ||
          type == 'query_response' ||
          (type == 'initial' && data['Data'] == null)) {
        for (final entry in data.entries) {
          if (entry.value is Map || entry.value is List) {
            next(entry.value, fmt: resolved, src: entry.key, snap: true);
          }
        }
        return;
      }
      if (type.endsWith('list_response')) {
        final key = type.substring(0, type.length - 'list_response'.length);
        next(data['Data'], fmt: resolved, src: key, hist: true);
        return;
      }
      final key = source ?? data['source']?.toString();
      final wrapped = data['Data'] ?? data['data'];
      if (wrapped is List) {
        next(wrapped, fmt: resolved, src: key);
        return;
      }
      final body = wrapped is Map ? Map<String, dynamic>.from(wrapped) : data;
      if (type == 'initial') snapshot = true;
      if (key == 'weatheralarm') {
        batch.weatherAlarms.add(
          WeatherAlarm.fromFanJson(
            body,
            source: resolved == 'fan'
                ? WeatherAlarmSource.fan
                : WeatherAlarmSource.whews,
            apiTypeLabel: localInjectApiName,
          ),
        );
        return;
      }
      if (!const [
        'id',
        'eventId',
        'md5',
        'shockTime',
        'originTime',
        'warningInfo',
        'reportTime',
        'createTime',
      ].any(body.containsKey)) {
        throw const FormatException('缺少事件标识或时间字段');
      }
      final tsunami = switch (key) {
        'tsunami' => TsunamiMessage.parseNmefcTsunami(body),
        'jma_tsunami' => TsunamiMessage.parseWhewsJmaTsunami(body),
        'ptwc' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.ptwc,
          body,
        ),
        'ntwc' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.ntwc,
          body,
        ),
        'incois' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.incois,
          body,
        ),
        _ => null,
      };
      if (tsunami != null) {
        batch.tsunamis.add(tsunami.copyWith(isInitialSnapshot: snapshot));
        return;
      }
      if (resolved == 'fan') {
        event = FanService.decodeEventPayload(body, sourceHint: key);
      } else {
        if (key == null || key.isEmpty) {
          throw const FormatException('WHEWS/ WAuth 缺少 source');
        }
        event = QuakeEventAdapter.convertWhews(key, body);
      }
    } else if (resolved == 'nowquake') {
      event = NowQuakeCencIntensityService.unifiedInfoFromJson(data);
    } else if (resolved == 'adapter') {
      if (!adapterSources.contains(source)) {
        throw FormatException('未知适配器：$source');
      }
      event = QuakeEventAdapter.convert(source!, data, 1);
    } else if (resolved == 'unified') {
      event = UnifiedQuakeData.fromMap(data);
    }
    if (event == null || event.isEmpty || event.eventId.trim().isEmpty) {
      throw const FormatException('没有匹配到有效事件，请明确选择 format 和 source');
    }
    batch.events.add(
      _local(
        event.copyWith(
          isHistory: event.isHistory || history || (snapshot && !event.isEew),
          isSnapshot: event.isSnapshot || snapshot,
        ),
        resolved == 'unified' ? (event.sourcePayload ?? data) : data,
      ),
    );
  }

  static UnifiedQuakeData _local(
    UnifiedQuakeData event,
    Map<String, dynamic> raw,
  ) => event.copyWith(
    apiTypeLabel: localInjectApiName,
    rawEvent: event.rawEvent?.copyWith(apiTypeLabel: localInjectApiName),
    sourcePayload: snapshotSourcePayload(raw),
  );
}
