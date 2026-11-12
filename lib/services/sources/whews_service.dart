import 'dart:async';
import 'dart:collection';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter/foundation.dart' show visibleForTesting, debugPrint;

import '../../models/weather_alarm.dart';
import '../../models/unified_quake_data.dart';
import '../../models/whews_catalog.dart';
import '../../models/volcano_event_data.dart';
import '../../models/source_status.dart';
import '../../models/tsunami_message.dart';
import '../quake_event_adapter.dart';
import '../native_jma_tsunami.dart';
import 'base_source.dart';
import 'jma_ashfall_forecast_service.dart';
import 'noaa_tsunami_area_service.dart';
import 'incois_tsunami_detail_service.dart';
import 'tsunami_bulletin_service.dart';
import 'whews_socket_client.dart';

class WhewsService extends BaseSourceService {
  WhewsService({
    required String apiToken,
    JmaAshfallForecastService? ashfallForecastService,
    NoaaTsunamiAreaService? noaaTsunamiAreaService,
    IncoisTsunamiDetailService? incoisTsunamiDetailService,
    TsunamiBulletinService? tsunamiBulletinService,
    DateTime Function()? now,
    WebSocketChannel Function(Uri)? socketFactory,
  }) : _now = now ?? DateTime.now,
       _apiToken = apiToken.trim(),
       _socketFactory = socketFactory,
       _ashfallForecastService =
           ashfallForecastService ?? JmaAshfallForecastService(),
       _noaaTsunamiAreaService =
           noaaTsunamiAreaService ?? NoaaTsunamiAreaService(),
       _incoisTsunamiDetailService =
           incoisTsunamiDetailService ?? IncoisTsunamiDetailService(),
       _tsunamiBulletinService =
           tsunamiBulletinService ?? TsunamiBulletinService();

  static const String enabledPreferenceKey = 'api_source_whews_enabled';
  static const String apiAuthorizedPreferenceKey =
      'api_source_whews_authorized';
  static const String aggregateUrl = 'wss://api.beecld.com/ws/all';
  // CEA/CEA-PR are not included in the overseas /ws/all aggregate; connect
  // the domestic node separately per https://api.beecld.com/#overview.
  static const String ceaAggregateUrl = 'wss://api.2v8.cn/ws/cea_all';
  static const int adapterOrigin = 3;
  static const Set<String> tsunamiSources = {
    'tsunami',
    'jma_tsunami',
    'ptwc',
    'ntwc',
    'incois',
    'cat_tsunami',
    'cwa_tsunami',
  };

  String _apiToken;
  final DateTime Function() _now;
  final WebSocketChannel Function(Uri)? _socketFactory;
  WhewsSocketClient? _aggregateClient;
  WhewsSocketClient? _ceaClient;
  final LinkedHashSet<String> _seenFrames = LinkedHashSet<String>();
  final Map<String, WhewsSocketState> _states = {};
  final JmaAshfallForecastService _ashfallForecastService;
  final NoaaTsunamiAreaService _noaaTsunamiAreaService;
  final IncoisTsunamiDetailService _incoisTsunamiDetailService;
  final TsunamiBulletinService _tsunamiBulletinService;
  final Map<String, Future<void>> _officialDetailFetches = {};
  final Map<TsunamiSource, Object> _officialDetailRevisions = {};
  final Map<TsunamiSource, TsunamiMessage> _officialDetailReports = {};
  final LinkedHashMap<String, List<VolcanoAshfallWindow>>
  _ashfallWindowsByRevision = LinkedHashMap();
  final Map<String, Future<void>> _ashfallFetches = {};
  bool _connectionRequested = false;
  bool _running = false;
  int _connectionGeneration = 0;

  void Function(WeatherAlarm alarm)? onWeatherAlarm;

  @override
  String get name => 'WHEWS';

  void setApiToken(String apiToken, {bool retryRejected = false}) {
    final next = apiToken.trim();
    if (next == _apiToken) {
      if (retryRejected && _connectionRequested && next.isNotEmpty) {
        _closeClients();
        _openClients();
      }
      return;
    }
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
    _connectionGeneration++;
    _states
      ..clear()
      ..[aggregateUrl] = WhewsSocketState.connecting
      ..[ceaAggregateUrl] = WhewsSocketState.connecting;
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
      socketFactory: _socketFactory,
      onMessage: _handleMessage,
      onStateChanged: (state) => _handleState(url, state),
    );
  }

  void _handleState(String url, WhewsSocketState state) {
    _states[url] = state;
    if (!_running) return;
    onStatusChanged?.call(whewsAggregateStatus(_states.values));
  }

  void _handleMessage(dynamic message, {bool isInitialSnapshot = false}) {
    if (message is List) {
      _handleInitialAggregate(message);
      return;
    }
    if (message is! Map) return;
    final frame = Map<String, dynamic>.from(message);
    final key = _frameKey(frame);
    if (key != null && _seenFrames.contains(key)) return;
    _rememberFrame(frame);
    _dispatchFrame(frame, isInitialSnapshot: isInitialSnapshot);
  }

  void _handleInitialAggregate(List<dynamic> message) {
    final jmaIndices = NativeJmaTsunami.supported
        ? (NativeJmaTsunami.prepare({
                    'op': 'snapshot',
                    'frames': message,
                  })['indices']
                  as List)
              .cast<int>()
              .toSet()
        : null;
    final latestTsunamiFrames = <String, Map<String, dynamic>>{};
    final allTsunamiFrames = <Map<String, dynamic>>[];
    for (var index = 0; index < message.length; index++) {
      final item = message[index];
      if (item is! Map) continue;
      final frame = Map<String, dynamic>.from(item);
      final source = frame['source']?.toString().trim() ?? '';
      if (source == 'jma_tsunami' && jmaIndices != null) {
        if (jmaIndices.contains(index)) {
          _handleMessage(frame, isInitialSnapshot: true);
        } else {
          _rememberFrame(frame);
        }
        continue;
      }
      if (!tsunamiSources.contains(source)) {
        _handleMessage(frame, isInitialSnapshot: true);
        continue;
      }
      allTsunamiFrames.add(frame);
      final current = latestTsunamiFrames[source];
      if (current == null || _isLaterTsunamiFrame(frame, current)) {
        latestTsunamiFrames[source] = frame;
      }
    }

    final selectedKeys = latestTsunamiFrames.values
        .map(_frameKey)
        .whereType<String>()
        .toSet();
    final alreadySeenSelectedKeys = selectedKeys
        .where(_seenFrames.contains)
        .toSet();
    for (final frame in allTsunamiFrames) {
      _rememberFrame(frame);
    }
    for (final frame in latestTsunamiFrames.values) {
      final key = _frameKey(frame);
      if (key != null && alreadySeenSelectedKeys.contains(key)) continue;
      _dispatchFrame(frame, isInitialSnapshot: true);
    }
  }

  bool _isLaterTsunamiFrame(
    Map<String, dynamic> candidate,
    Map<String, dynamic> current,
  ) {
    if (candidate['source'] == 'tsunami' &&
        NativeJmaTsunami.supported &&
        candidate['Data'] is Map &&
        current['Data'] is Map) {
      final next = TsunamiMessage.parseNmefcTsunami(
        Map<String, dynamic>.from(candidate['Data'] as Map),
      );
      final previous = TsunamiMessage.parseNmefcTsunami(
        Map<String, dynamic>.from(current['Data'] as Map),
      );
      return NativeJmaTsunami.prepare({
            'op': 'nmefcAccept',
            'previous': previous.toMap(),
            'incoming': next.toMap(),
          })['accepted'] ==
          true;
    }
    final bulletinSource = switch (candidate['source']) {
      'cat_tsunami' => TsunamiSource.cat,
      'cwa_tsunami' => TsunamiSource.cwa,
      _ => null,
    };
    if (bulletinSource != null &&
        candidate['Data'] is Map &&
        current['Data'] is Map) {
      final next = TsunamiMessage.parseInternationalTsunami(
        bulletinSource,
        Map<String, dynamic>.from(candidate['Data'] as Map),
      );
      final previous = TsunamiMessage.parseInternationalTsunami(
        bulletinSource,
        Map<String, dynamic>.from(current['Data'] as Map),
      );
      final order = next.reportOrderComparedTo(previous);
      if (order != null) return order >= 0;
    }
    final candidateTime = _tsunamiFrameInstant(candidate);
    final currentTime = _tsunamiFrameInstant(current);
    if (candidateTime != null && currentTime != null) {
      return !candidateTime.isBefore(currentTime);
    }
    if (candidateTime != null) return true;
    return currentTime == null;
  }

  DateTime? _tsunamiFrameInstant(Map<String, dynamic> frame) {
    final source = frame['source']?.toString().trim() ?? '';
    final rawData = frame['Data'];
    if (rawData is! Map) return null;
    final data = Map<String, dynamic>.from(rawData);
    try {
      return switch (source) {
        'tsunami' => TsunamiMessage.parseNmefcTsunami(data).reportInstantUtc,
        'jma_tsunami' => TsunamiMessage.parseWhewsJmaTsunami(
          data,
        ).reportInstantUtc,
        'ptwc' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.ptwc,
          data,
        ).reportInstantUtc,
        'ntwc' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.ntwc,
          data,
        ).reportInstantUtc,
        'incois' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.incois,
          data,
        ).reportInstantUtc,
        'cat_tsunami' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.cat,
          data,
        ).reportInstantUtc,
        'cwa_tsunami' => TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.cwa,
          data,
        ).reportInstantUtc,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  void _dispatchFrame(
    Map<String, dynamic> frame, {
    required bool isInitialSnapshot,
  }) {
    final source = frame['source']?.toString().trim() ?? '';
    final rawData = frame['Data'];
    if (source.isEmpty || rawData is! Map) return;
    final data = Map<String, dynamic>.from(rawData);
    if (source == 'weatheralarm') {
      try {
        final alarm = WeatherAlarm.fromFanJson(
          data,
          source: WeatherAlarmSource.whews,
        );
        if (!alarm.isExpired()) onWeatherAlarm?.call(alarm);
      } catch (_) {
        // Keep malformed weather frames out of the existing alarm pipeline.
      }
      return;
    }
    if (source == 'tsunami') {
      final generation = _connectionGeneration;
      unawaited(
        TsunamiMessage.parseNmefcTsunamiAsync(data)
            .then((message) {
              if (generation == _connectionGeneration) {
                final event = message.copyWith(
                  isInitialSnapshot: isInitialSnapshot,
                );
                final previous = _officialDetailReports[event.source];
                if (previous != null &&
                    NativeJmaTsunami.supported &&
                    NativeJmaTsunami.prepare({
                          'op': 'nmefcAccept',
                          'previous': previous.toMap(),
                          'incoming': event.toMap(),
                        })['accepted'] !=
                        true) {
                  return;
                }
                final revision = Object();
                _officialDetailRevisions[event.source] = revision;
                _officialDetailReports[event.source] = event;
                emitTsunami(event);
                if (NativeJmaTsunami.supported &&
                    event.isDisplayableAt(_now())) {
                  _enrichOfficialTsunamiDetail(event, event.htmlUrl, revision);
                }
              }
            })
            .catchError((Object error) {
              debugPrint('WHEWS NMEFC 海啸解析失败: $error');
            }),
      );
      return;
    }
    if (source == 'jma_tsunami') {
      final generation = _connectionGeneration;
      unawaited(
        TsunamiMessage.parseJmaSourceAsync('whews', data)
            .then((message) {
              if (generation == _connectionGeneration) {
                emitTsunami(
                  message.copyWith(isInitialSnapshot: isInitialSnapshot),
                );
              }
            })
            .catchError((Object error) {
              debugPrint('WHEWS JMA 海啸解析失败: $error');
            }),
      );
      return;
    }
    final internationalSource = switch (source) {
      'ptwc' => TsunamiSource.ptwc,
      'ntwc' => TsunamiSource.ntwc,
      'incois' => TsunamiSource.incois,
      'cat_tsunami' => TsunamiSource.cat,
      'cwa_tsunami' => TsunamiSource.cwa,
      _ => null,
    };
    if (internationalSource != null) {
      try {
        final event = TsunamiMessage.parseInternationalTsunami(
          internationalSource,
          data,
        ).copyWith(isInitialSnapshot: isInitialSnapshot);
        final isNoaa =
            internationalSource == TsunamiSource.ptwc ||
            internationalSource == TsunamiSource.ntwc;
        final hasOfficialDetail =
            isNoaa || internationalSource == TsunamiSource.incois;
        if (hasOfficialDetail &&
            NativeJmaTsunami.supported &&
            NativeJmaTsunami.prepare({
                  'op': 'noaaIsCurrent',
                  'previous': _officialDetailReports[internationalSource]
                      ?.toMap(),
                  'incoming': event.toMap(),
                })['current'] !=
                true) {
          return;
        }
        final revision = Object();
        if (hasOfficialDetail) {
          _officialDetailRevisions[internationalSource] = revision;
          _officialDetailReports[internationalSource] = event;
        }
        emitTsunami(event);
        if (event.isDisplayableAt(_now()) && hasOfficialDetail) {
          _enrichOfficialTsunamiDetail(
            event,
            data[isNoaa ? 'jsonUrl' : 'detailUrl']?.toString() ?? '',
            revision,
          );
        }
      } catch (_) {
        // Keep malformed international tsunami frames out of the pipeline.
      }
      return;
    }
    final event = QuakeEventAdapter.convertWhews(source, data);
    if (event == null) return;
    _emitUnifiedWithAshfallEnrichment(
      unifiedCatalogSources.containsKey(event.source)
          ? event.copyWith(isSnapshot: isInitialSnapshot)
          : event,
    );
  }

  void _enrichOfficialTsunamiDetail(
    TsunamiMessage event,
    String jsonUrl,
    Object revision,
  ) {
    if (jsonUrl.isEmpty) return;
    final key =
        '${event.source.name}|${event.id}|${event.reportTime}|${identityHashCode(revision)}';
    if (_officialDetailFetches.containsKey(key)) return;
    final generation = _connectionGeneration;
    final fetch = _fetchOfficialTsunamiDetail(
      event,
      jsonUrl,
      generation,
      revision,
    );
    _officialDetailFetches[key] = fetch;
    unawaited(
      fetch.whenComplete(() {
        if (identical(_officialDetailFetches[key], fetch)) {
          _officialDetailFetches.remove(key);
        }
      }),
    );
  }

  Future<void> _fetchOfficialTsunamiDetail(
    TsunamiMessage event,
    String jsonUrl,
    int generation,
    Object revision,
  ) async {
    final isIncois = event.source == TsunamiSource.incois;
    final isNoaa =
        event.source == TsunamiSource.ptwc ||
        event.source == TsunamiSource.ntwc;
    final bulletinFuture = _tsunamiBulletinService.fetch(event);
    final detail = isNoaa
        ? await _noaaTsunamiAreaService.fetchDetail(jsonUrl)
        : null;
    final raw = isIncois
        ? await _incoisTsunamiDetailService.fetch(jsonUrl)
        : detail?.raw;
    final bulletin = await bulletinFuture;
    if ((raw == null && bulletin == null) ||
        generation != _connectionGeneration ||
        !identical(_officialDetailRevisions[event.source], revision)) {
      return;
    }
    emitTsunami(
      event.copyWith(
        areas: detail == null || detail.areas.isEmpty
            ? event.areas
            : detail.areas,
        officialDetail: {...?raw, ...?bulletin},
      ),
    );
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
    final generation = _connectionGeneration;
    final fetch = _enrichAshfall(event, revisionKey, generation);
    _ashfallFetches[revisionKey] = fetch;
    unawaited(
      fetch.whenComplete(() {
        if (identical(_ashfallFetches[revisionKey], fetch)) {
          _ashfallFetches.remove(revisionKey);
        }
      }),
    );
  }

  Future<void> _enrichAshfall(
    UnifiedQuakeData event,
    String revisionKey,
    int generation,
  ) async {
    final volcano = event.volcanoEvent;
    if (volcano == null) return;
    final windows = await _ashfallForecastService.fetchFor(volcano);
    if (windows.isEmpty || generation != _connectionGeneration) return;
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
    if (source == 'jma_tsunami' && NativeJmaTsunami.supported) {
      return NativeJmaTsunami.prepare({'op': 'frameKey', 'frame': frame})['key']
          as String?;
    }
    final rawData = frame['Data'];
    final cancellation =
        source == 'jma_eew' &&
        rawData is Map &&
        (rawData['isCancel'] == true || rawData['cancel'] == true);
    final statusKey = source == 'jma_eew' ? '|cancel=$cancellation' : '';
    final md5 = frame['md5']?.toString().trim() ?? '';
    if (md5.isNotEmpty) return '$source|$md5$statusKey';
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
    return '$source|$id|$updates|$updateTime$statusKey';
  }

  @override
  void disconnect() {
    _connectionRequested = false;
    _closeClients();
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  void _closeClients() {
    _connectionGeneration++;
    _running = false;
    _aggregateClient?.dispose();
    _ceaClient?.dispose();
    _aggregateClient = null;
    _ceaClient = null;
    _states.clear();
    _seenFrames.clear();
    _ashfallFetches.clear();
    _ashfallWindowsByRevision.clear();
    _officialDetailFetches.clear();
    _officialDetailRevisions.clear();
    _officialDetailReports.clear();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

@visibleForTesting
SourceStatus whewsAggregateStatus(Iterable<WhewsSocketState> states) {
  final values = states.toList(growable: false);
  if (values.isEmpty) return SourceStatus.disconnected;
  if (values.every((item) => item == WhewsSocketState.connected)) {
    return SourceStatus.connected;
  }
  final hasLiveSocket = values.any(
    (item) => item == WhewsSocketState.connected,
  );
  final hasFailedSocket = values.any(
    (item) =>
        item == WhewsSocketState.error ||
        item == WhewsSocketState.disconnected ||
        item == WhewsSocketState.unauthorized,
  );
  // One endpoint confirmed while a sibling failed: degraded but still usable.
  if (hasLiveSocket && hasFailedSocket) {
    return SourceStatus.connecting;
  }
  // A slow sibling still handshaking must not flash yellow once the other
  // socket is already heartbeat-confirmed.
  if (hasLiveSocket) {
    return SourceStatus.connected;
  }
  if (values.any((item) => item == WhewsSocketState.connecting)) {
    return SourceStatus.connecting;
  }
  return SourceStatus.error;
}
