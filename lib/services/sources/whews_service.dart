import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/weather_alarm.dart';
import '../../models/unified_quake_data.dart';
import '../../models/volcano_event_data.dart';
import '../../models/source_status.dart';
import '../../models/tsunami_message.dart';
import '../quake_event_adapter.dart';
import 'base_source.dart';
import 'jma_ashfall_forecast_service.dart';
import 'whews_socket_client.dart';

class WhewsService extends BaseSourceService {
  WhewsService({
    required String apiToken,
    JmaAshfallForecastService? ashfallForecastService,
  }) : _apiToken = apiToken.trim(),
       _ashfallForecastService =
           ashfallForecastService ?? JmaAshfallForecastService();

  static const String enabledPreferenceKey = 'api_source_whews_enabled';
  static const String apiAuthorizedPreferenceKey =
      'api_source_whews_authorized';
  static const String aggregateUrl = 'wss://api.beecld.com/ws/all';
  static const String ceaAggregateUrl = 'wss://api.2v8.cn/ws/cea_all';
  static const int adapterOrigin = 3;

  String _apiToken;
  WhewsSocketClient? _aggregateClient;
  WhewsSocketClient? _ceaClient;
  final LinkedHashSet<String> _seenFrames = LinkedHashSet<String>();
  final Map<String, WhewsSocketState> _states = {};
  final JmaAshfallForecastService _ashfallForecastService;
  final LinkedHashMap<String, List<VolcanoAshfallWindow>>
  _ashfallWindowsByRevision = LinkedHashMap();
  final Map<String, Future<void>> _ashfallFetches = {};
  bool _connectionRequested = false;
  bool _running = false;

  void Function(WeatherAlarm alarm)? onWeatherAlarm;

  @override
  String get name => 'WHEWS';

  void setApiToken(String apiToken) {
    final next = apiToken.trim();
    if (next == _apiToken) return;
    _apiToken = next;
    if (next.isEmpty) {
      _closeClients();
      if (_connectionRequested) {
        onStatusChanged?.call(SourceStatus.error);
      }
      return;
    }
    _aggregateClient?.setApiToken(next);
    _ceaClient?.setApiToken(next);
    if (_connectionRequested && !_running) {
      _openClients();
    }
  }

  @override
  void connect() {
    _connectionRequested = true;
    if (_running) return;
    if (_apiToken.isEmpty) {
      onStatusChanged?.call(SourceStatus.error);
      return;
    }
    _openClients();
  }

  void _openClients() {
    if (_running || _apiToken.isEmpty) return;
    _running = true;
    onStatusChanged?.call(SourceStatus.connecting);
    _aggregateClient = _createClient(aggregateUrl);
    _ceaClient = _createClient(ceaAggregateUrl);
    _aggregateClient!.start();
    _ceaClient!.start();
  }

  WhewsSocketClient _createClient(String url) {
    return WhewsSocketClient(
      url: url,
      apiToken: _apiToken,
      onMessage: _handleMessage,
      onStateChanged: (state) => _handleState(url, state),
    );
  }

  void _handleState(String url, WhewsSocketState state) {
    _states[url] = state;
    if (!_running) return;
    if (_states.values.any((item) => item == WhewsSocketState.connected)) {
      onStatusChanged?.call(SourceStatus.connected);
    } else if (_states.values.any(
      (item) => item == WhewsSocketState.connecting,
    )) {
      onStatusChanged?.call(SourceStatus.connecting);
    } else {
      onStatusChanged?.call(SourceStatus.error);
    }
  }

  void _handleMessage(dynamic message) {
    if (message is List) {
      for (final item in message) {
        if (item is Map) {
          _rememberFrame(Map<String, dynamic>.from(item));
        }
      }
      return;
    }
    if (message is! Map) return;
    final frame = Map<String, dynamic>.from(message);
    final key = _frameKey(frame);
    if (key != null && _seenFrames.contains(key)) return;
    _rememberFrame(frame);
    final source = frame['source']?.toString().trim() ?? '';
    final rawData = frame['Data'];
    if (source.isEmpty || rawData is! Map) return;
    final data = Map<String, dynamic>.from(rawData);
    if (source == 'weatheralarm') {
      try {
        onWeatherAlarm?.call(WeatherAlarm.fromFanJson(data));
      } catch (_) {
        // Keep malformed weather frames out of the existing alarm pipeline.
      }
      return;
    }
    if (source == 'tsunami') {
      try {
        emitTsunami(TsunamiMessage.parseNmefcTsunami(data));
      } catch (_) {
        // Keep malformed tsunami frames out of the existing tsunami pipeline.
      }
      return;
    }
    if (source == 'jma_tsunami') {
      try {
        emitTsunami(TsunamiMessage.parseWhewsJmaTsunami(data));
      } catch (_) {
        // Keep malformed JMA tsunami frames out of the existing pipeline.
      }
      return;
    }
    final event = QuakeEventAdapter.convertWhews(source, data);
    if (event == null) return;
    _emitUnifiedWithAshfallEnrichment(event);
  }

  void _emitUnifiedWithAshfallEnrichment(UnifiedQuakeData event) {
    final volcano = event.volcanoEvent;
    if (volcano == null || !volcano.isAshfallForecast || volcano.isCanceled) {
      emitUnified(event);
      return;
    }

    final revisionKey = '${event.eventId}|${volcano.updates}';
    final cached = _ashfallWindowsByRevision[revisionKey];
    if (cached != null) {
      emitUnified(
        event.copyWith(volcanoEvent: volcano.copyWith(ashfallWindows: cached)),
      );
      return;
    }

    // The WHEWS frame must remain responsive while the official JMA document
    // is fetched. A same-report correction below is deliberately side-effect
    // free in QuakeProvider.
    emitUnified(event);
    if (_ashfallFetches.containsKey(revisionKey)) return;
    final fetch = _enrichAshfall(event, revisionKey);
    _ashfallFetches[revisionKey] = fetch;
    unawaited(fetch.whenComplete(() => _ashfallFetches.remove(revisionKey)));
  }

  Future<void> _enrichAshfall(
    UnifiedQuakeData event,
    String revisionKey,
  ) async {
    final volcano = event.volcanoEvent;
    if (volcano == null) return;
    final windows = await _ashfallForecastService.fetchFor(volcano);
    if (windows.isEmpty) return;
    _rememberAshfallWindows(revisionKey, windows);
    emitUnified(
      event.copyWith(volcanoEvent: volcano.copyWith(ashfallWindows: windows)),
    );
  }

  void _rememberAshfallWindows(
    String revisionKey,
    List<VolcanoAshfallWindow> windows,
  ) {
    _ashfallWindowsByRevision.remove(revisionKey);
    _ashfallWindowsByRevision[revisionKey] = List.unmodifiable(windows);
    while (_ashfallWindowsByRevision.length > 128) {
      _ashfallWindowsByRevision.remove(_ashfallWindowsByRevision.keys.first);
    }
  }

  @visibleForTesting
  void handleMessageForTesting(dynamic message) => _handleMessage(message);

  void _rememberFrame(Map<String, dynamic> frame) {
    final key = _frameKey(frame);
    if (key == null) return;
    _seenFrames.add(key);
    while (_seenFrames.length > 1024) {
      _seenFrames.remove(_seenFrames.first);
    }
  }

  String? _frameKey(Map<String, dynamic> frame) {
    final source =
        frame['source']?.toString().trim().toLowerCase().replaceAll('-', '_') ??
        '';
    if (source.isEmpty) return null;
    final md5 = frame['md5']?.toString().trim() ?? '';
    if (md5.isNotEmpty) return '$source|$md5';
    final data = frame['Data'];
    if (data is! Map) return null;
    final id =
        (data['id'] ?? data['eventId'] ?? data['EventID'] ?? data['ID'])
            ?.toString()
            .trim() ??
        '';
    if (id.isEmpty) return null;
    final updates =
        (data['updates'] ??
                data['serial'] ??
                data['Serial'] ??
                data['ReportNum'] ??
                data['reportNumber'])
            ?.toString() ??
        '';
    final updateTime =
        (data['updateTime'] ??
                data['createTime'] ??
                data['reportTime'] ??
                data['ReportTime'])
            ?.toString() ??
        '';
    return '$source|$id|$updates|$updateTime';
  }

  @override
  void disconnect() {
    _connectionRequested = false;
    _closeClients();
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  void _closeClients() {
    _running = false;
    _aggregateClient?.dispose();
    _ceaClient?.dispose();
    _aggregateClient = null;
    _ceaClient = null;
    _states.clear();
    _ashfallFetches.clear();
    _ashfallWindowsByRevision.clear();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
