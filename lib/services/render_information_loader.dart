import 'package:http/http.dart' as http;

import '../models/cenc_ir_data.dart';
import '../models/unified_quake_data.dart';
import '../models/quake_message.dart';
import '../models/usgs_shakemap.dart';
import 'quake_event_adapter.dart';
import 'sources/api_json_decoder.dart';
import 'sources/nowquake_cenc_intensity_service.dart';
import 'sources/source_http_client.dart';
import 'sources/usgs_shakemap_service.dart';

typedef RenderEventMatcher = bool Function(UnifiedQuakeData, UnifiedQuakeData);
typedef RenderIrMatcher =
    Map<String, dynamic>? Function(
      UnifiedQuakeData,
      List<Map<String, dynamic>>,
    );

class RenderCencIrProduct {
  const RenderCencIrProduct({required this.data, required this.event});
  final CencIrData data;
  final UnifiedQuakeData event;
}

/// Owns only the renderer's HTTP requests. No feed callbacks, selection or
/// admission. Original source bodies go through the existing source adapters.
class RenderInformationLoader {
  RenderInformationLoader({http.Client? client})
    : _client = client ?? createSourceHttpClient();
  final http.Client _client;
  UsgsShakeMapService? _shakeMap;
  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    if (_shakeMap case final reader?) {
      reader.dispose();
    } else {
      _client.close();
    }
  }

  /// A private product reader: never selects or subscribes on the main map's
  /// service. Reuses its identity checks, preferred version and original MMI.
  Future<UsgsShakeMapFrame?> shakeMap(QuakeMessage event) async {
    if (_closed || event.source != QuakeSourceType.usgs) return null;
    final reader = _shakeMap ??= UsgsShakeMapService(client: _client);
    await reader.select(event);
    if (_closed) return null;
    final frame = reader.frame;
    if (frame == null && reader.status?.contains('失败') == true) {
      throw StateError(reader.status!);
    }
    return frame;
  }

  Future<dynamic> _get(Uri uri) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (_closed) return null;
    if (response.statusCode != 200)
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    return decodeApiJsonBytes(response.bodyBytes);
  }

  Future<UnifiedQuakeData?> observed(
    UnifiedQuakeData target,
    RenderEventMatcher matches,
  ) async {
    if (target.warnArea.isNotEmpty || target.isJmaLpgm) return null;
    if (target.source == 'jmaEqlist' || target.source == 'p2pJmaEqlist') {
      final rows = await _get(
        Uri.https('api.p2pquake.net', '/v2/history', {
          'codes': '551',
          'limit': '100',
        }),
      );
      if (rows is! List) return null;
      for (final row in rows.whereType<Map>()) {
        final event = QuakeEventAdapter.convert(
          'jmaEqlist',
          Map<String, dynamic>.from(row),
          2,
        );
        if (event != null &&
            event.warnArea.isNotEmpty &&
            matches(target, event))
          return event;
      }
    } else if (target.source == 'cwaEqlist') {
      final raw = await _get(
        Uri.https(
          'api.core.exptech.dev',
          '/api/v2/eq/report/${target.eventId}',
        ),
      );
      if (raw is Map) {
        final event = QuakeEventAdapter.convert(
          'cwaEqlist',
          Map<String, dynamic>.from(raw),
          0,
        );
        if (event != null &&
            event.warnArea.isNotEmpty &&
            matches(target, event))
          return event;
      }
    }
    return null;
  }

  Future<RenderCencIrProduct?> cencIr(
    UnifiedQuakeData target,
    RenderIrMatcher binding,
  ) async {
    if (target.source != 'cencEqlist') return null;
    final rows = await _get(
      Uri.https('api-cencint-public.nowquake.cn', '/list', {
        'pageNo': '0',
        'pageSize': '20',
      }),
    );
    if (rows is! List) return null;
    final summaries = rows
        .whereType<Map>()
        .map(
          (row) => NowQuakeCencIntensityService.summaryFromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
    final match = binding(target, summaries);
    if (match == null) return null;
    final raw = await _get(
      Uri.https('api-cencint-public.nowquake.cn', '/event/${match['id']}'),
    );
    if (raw is! Map) return null;
    final original = Map<String, dynamic>.from(raw);
    final detailSummary = NowQuakeCencIntensityService.summaryFromJson(
      original,
    );
    if (binding(target, [detailSummary]) == null) {
      throw StateError('烈度速报详情与所选事件不匹配');
    }
    final data = CencIrData.fromNowQuakeJson(original);
    return RenderCencIrProduct(
      data: data,
      event: target.copyWith(
        source: 'nowQuakeCencIr',
        titleText: '中国地震台网烈度速报',
        reportNumText: '',
        maxIntensity: '${original['maxintensity'] ?? '-'}',
        hypocenter: data.locName,
        lat: data.epiLat,
        lng: data.epiLon,
      ),
    );
  }
}
