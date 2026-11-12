import 'dart:async';
import 'api_json_decoder.dart';
import 'dart:convert';
import 'dart:isolate';
import '../station_history_capture.dart';
import '../foreground_station_payload.dart';
import '../../models/source_payload.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/source_estimation/palert_source_profile.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import 'palert_detection.dart';
import 'palert_http_client.dart';
import 'palert_intensity.dart';
import 'palert_level_history.dart';
import 'palert_wire_values.dart';
import 'station_json_decoder.dart';
import 'shake_detection_service.dart';
import 'native_station_runtime.dart';
import 'native_station_display.dart';
import '../obs_automation_input_service.dart';

part 'palert_data_worker.dart';
part 'palert_native_runtime.dart';

class PAlertStation {
  final String id;
  final String network;
  final String name;
  final String area;
  final LatLng coordinate;
  final double? pgaGal;
  final double? pgvCms;
  final int? cwaIntensityIndex;
  final int? heldCwaIntensityIndex;
  final int? heldLevel;
  final DateTime? dataTime;
  final DateTime? receivedAt;
  final int? _sampledLevel;

  const PAlertStation({
    required this.id,
    required this.network,
    required this.name,
    required this.area,
    required this.coordinate,
    this.pgaGal,
    this.pgvCms,
    this.cwaIntensityIndex,
    this.heldCwaIntensityIndex,
    this.heldLevel,
    this.dataTime,
    this.receivedAt,
    int? sampledLevel,
    this.preparedMapRecent,
  }) : _sampledLevel = sampledLevel;
  final bool? preparedMapRecent;

  int? get displayCwaIntensityIndex {
    if (preparedMapRecent != null) {
      return heldCwaIntensityIndex ?? cwaIntensityIndex;
    }
    final level = gridLevel;
    return level < 0
        ? null
        : PAlertSourceProfile.intensityIndexFromLevel(level);
  }

  /// Original sampled result for native consumers; no threshold recalculation.
  int? get sampledLevel => _sampledLevel;

  bool get hasRealtime => gridLevel >= 0 && dataTime != null;

  int get gridLevel => heldLevel ?? currentGridLevel;

  int get currentGridLevel =>
      _sampledLevel ?? PAlertSourceProfile.level(pgaGal, pgvCms);

  double? get estimatedContinuousShindo =>
      PAlertIntensity.estimateFromPga(pgaGal);

  int get detectionLevel => currentGridLevel;

  // Kept as an index-shaped compatibility getter for existing callers.
  int get jmaIndex => displayCwaIntensityIndex ?? -1;

  int get shindoClass {
    final index = PAlertSourceProfile.intensityIndexFromLevel(gridLevel);
    if (index < 0) return -1;
    if (index <= 4) return index;
    if (index <= 6) return 5;
    if (index <= 8) return 6;
    return 7;
  }

  String get shindoLabel =>
      PAlertSourceProfile.intensityLabelFromLevel(gridLevel);

  PAlertStation copyWith({
    double? pgaGal,
    double? pgvCms,
    int? cwaIntensityIndex,
    int? heldCwaIntensityIndex,
    int? heldLevel,
    DateTime? dataTime,
    DateTime? receivedAt,
  }) {
    return PAlertStation(
      id: id,
      network: network,
      name: name,
      area: area,
      coordinate: coordinate,
      pgaGal: pgaGal ?? this.pgaGal,
      pgvCms: pgvCms ?? this.pgvCms,
      cwaIntensityIndex: cwaIntensityIndex ?? this.cwaIntensityIndex,
      heldCwaIntensityIndex:
          heldCwaIntensityIndex ?? this.heldCwaIntensityIndex,
      heldLevel: heldLevel ?? this.heldLevel,
      dataTime: dataTime ?? this.dataTime,
      receivedAt: receivedAt ?? this.receivedAt,
      sampledLevel: pgaGal == null && pgvCms == null ? _sampledLevel : null,
      preparedMapRecent: pgaGal == null && pgvCms == null && receivedAt == null
          ? preparedMapRecent
          : null,
    );
  }
}

enum PAlertDetectionSignal { none, detected, expired }

/// Sound tiers consume only the joint detector's confirmed intensity.
/// A session plays once at shindo 1-3 and once again when it reaches 4+.
class PAlertDetectionGate {
  int _previousMaxShindo = -1;
  bool _lowIntensityNotified = false;
  bool _strongIntensityNotified = false;

  PAlertDetectionSignal update(int currentMaxShindo) {
    if (currentMaxShindo < 0) {
      final hadRealtime = reset();
      return hadRealtime
          ? PAlertDetectionSignal.expired
          : PAlertDetectionSignal.none;
    }

    final rising = currentMaxShindo > _previousMaxShindo;
    _previousMaxShindo = currentMaxShindo;
    if (!rising) return PAlertDetectionSignal.none;
    if (currentMaxShindo >= 4 && !_strongIntensityNotified) {
      _lowIntensityNotified = true;
      _strongIntensityNotified = true;
      return PAlertDetectionSignal.detected;
    }
    if (currentMaxShindo >= 1 && !_lowIntensityNotified) {
      _lowIntensityNotified = true;
      return PAlertDetectionSignal.detected;
    }
    return PAlertDetectionSignal.none;
  }

  bool reset() {
    final hadRealtime = _previousMaxShindo >= 0;
    _previousMaxShindo = -1;
    _lowIntensityNotified = false;
    _strongIntensityNotified = false;
    return hadRealtime;
  }
}

class PAlertService {
  static final PAlertService _instance = PAlertService._();
  factory PAlertService() => _instance;
  PAlertService._({
    Future<http.Client> Function()? clientFactory,
    bool useWorker = !kIsWeb,
    bool useNative = true,
    Map<String, Object?> nativeSettings = const {},
    Uri? endpoint,
    Duration pollInterval = realtimePollInterval,
  }) : _clientFactory = clientFactory ?? createPAlertHttpClient,
       _useWorker = useWorker,
       _useNative = useNative && useWorker,
       _nativeSettings = nativeSettings,
       _endpoint = endpoint,
       _pollInterval = pollInterval {
    if (_useWorker) return;
    _detector.onSnapshot = (snapshot) {
      onDetectionChanged?.call(snapshot);
    };
    _detector.onCwaIntensityChanged = (maxShindo) {
      final signal = _detectionGate.update(maxShindo);
      if (signal == PAlertDetectionSignal.detected) {
        onShakeDetected?.call(maxShindo);
      } else if (signal == PAlertDetectionSignal.expired) {
        onShakeExpired?.call();
      }
    };
  }

  @visibleForTesting
  PAlertService.forTesting({
    required Future<http.Client> Function() clientFactory,
    Duration pollInterval = realtimePollInterval,
    Uri? endpoint,
  }) : this._(
         clientFactory: clientFactory,
         useWorker: false,
         pollInterval: pollInterval,
         endpoint: endpoint,
       );

  @visibleForTesting
  PAlertService.workerForTesting({
    required Uri endpoint,
    Duration pollInterval = realtimePollInterval,
  }) : this._(endpoint: endpoint, pollInterval: pollInterval, useNative: false);

  @visibleForTesting
  PAlertService.nativeForTesting({
    Uri? endpoint,
    Duration pollInterval = realtimePollInterval,
    Map<String, Object?> settings = const {},
  }) : this._(
         endpoint: endpoint,
         pollInterval: pollInterval,
         nativeSettings: settings,
       );

  final Future<http.Client> Function() _clientFactory;
  final bool _useWorker;
  final bool _useNative;
  final Map<String, Object?> _nativeSettings;
  late final _PAlertNativeRuntime _nativeRuntime = _PAlertNativeRuntime(this);
  bool get nativeActive => _nativeRuntime.active;
  String get nativeLayerSignature => _nativeRuntime.signature;
  String get nativeStatus => _nativeRuntime.status;
  String? get nativeError => _nativeRuntime.error;
  int get nativeFrameCount => _nativeRuntime.frames;
  List<NativeStationGrid> get nativeGrids => _nativeRuntime.grids;
  List<ObsStationInputSample> get nativeAutomationSamples =>
      _nativeRuntime.automation;
  PAlertPreparedSummary? get nativeSummary => _nativeRuntime.summary;
  List<SeismicActiveEvent> get nativeSourceEvents => _nativeRuntime.events;
  bool _nativeInferenceEnabled = false;
  void setInferenceEnabled(bool enabled) {
    if (_nativeInferenceEnabled == enabled) return;
    _nativeInferenceEnabled = enabled;
    if (nativeActive) _nativeRuntime.setInferenceEnabled(enabled);
  }

  final Uri? _endpoint;
  final Duration _pollInterval;
  late final _PAlertDataWorker _dataWorker = _PAlertDataWorker(this);
  ShakeDetectionSnapshot _workerDetection = ShakeDetectionService.idleSnapshot;
  Map<String, dynamic>? _preparedHistory;
  int _sensitivity = 2;
  String? processingIsolateName;
  bool get processingInBackground => _useWorker;

  /// Already frozen in the processing owner; callers only display/forward it.
  Map<String, dynamic> historySnapshot({bool includeOriginalJson = false}) {
    if (nativeActive) return _nativeRuntime.history(includeOriginalJson);
    final snapshot =
        _preparedHistory ??
        ForegroundStationPayload.palert(
          _stations,
          dataTime: dataTimeNotifier.value,
          receivedTime: receivedTimeNotifier.value,
          detection: detectionSnapshot,
        );
    final original = StationHistoryCapture.instance.original('palert');
    return includeOriginalJson && original != null
        ? {...snapshot, 'originalJson': original}
        : snapshot;
  }

  static Uri get _graphqlUri => kIsWeb
      ? Uri.base.resolve('/api/palert/graphql/')
      : Uri.parse('https://palert.earth.sinica.edu.tw/graphql/');
  static const String _stationFilter = 'onlineAll';
  static const Duration intensityHoldDuration = PAlertLevelHistory.holdDuration;
  static const Duration realtimePollInterval = Duration(seconds: 1);
  static const Duration frameStaleAfter = Duration(seconds: 6);
  static const Duration _frameWatchdogInterval = Duration(seconds: 1);
  static const int maxConsecutiveFailures = 3;

  static const String _stationListQuery = '''
query (\$staFilter: staList_filter_choices) {
  stationList(staFilter: \$staFilter) {
    staInfos
    timestamp
  }
}
''';

  static const String _realtimeQuery = '''
query (\$recordTime: Float!, \$token: String!) {
  pga: realtimePGA(recordTime: \$recordTime, token: \$token, type: 0) {
    timestamp
    dataVals
  }
  pgv: realtimePGA(recordTime: \$recordTime, token: \$token, type: 1) {
    timestamp
    dataVals
  }
}
''';

  final _stationController = StreamController<List<PAlertStation>>.broadcast();
  Stream<List<PAlertStation>> get stationStream => _stationController.stream;
  final ValueNotifier<DateTime?> dataTimeNotifier = ValueNotifier(null);
  final ValueNotifier<DateTime?> receivedTimeNotifier = ValueNotifier(null);
  void Function(bool connected)? onStatusChanged;
  void Function(int maxShindo)? onShakeDetected;
  void Function()? onShakeExpired;
  void Function(ShakeDetectionSnapshot)? onDetectionChanged;
  late final PAlertDetector _detector = PAlertDetector();
  ShakeDetectionSnapshot get detectionSnapshot =>
      _useWorker ? _workerDetection : _detector.snapshot;
  void setSensitivity(int value) {
    _sensitivity = value;
    if (nativeActive) {
      _nativeRuntime.setSensitivity(value);
    } else if (_useWorker) {
      _dataWorker.setSensitivity(value);
    } else {
      _detector.setSensitivity(value);
    }
  }

  final Map<String, PAlertStation> _stationMap = {};
  late final PAlertLevelHistory _levelHistory = PAlertLevelHistory();
  late final StationJsonDecoder _wireDecoder = StationJsonDecoder(
    prepareStationNumbers: false,
  );
  final PAlertDetectionGate _detectionGate = PAlertDetectionGate();
  List<PAlertStation> _stations = const [];
  List<PAlertStation> get stations => _stations;

  Timer? _realtimeTimer;
  Timer? _frameWatchdogTimer;
  bool _running = false;
  bool _fetchingStations = false;
  bool _fetchingRealtime = false;
  void Function()? _onRealtimeSettled;
  bool _isConnected = false;
  bool _failureReported = false;
  int _consecutiveFailures = 0;
  int _runGeneration = 0;
  DateTime? _lastRealtimeTimestamp;
  DateTime? _lastFrameReceivedAt;
  http.Client? _client;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_runGeneration;
    _consecutiveFailures = 0;
    _isConnected = false;
    _failureReported = false;
    _lastFrameReceivedAt = null;
    if (_useNative && NativeStationRuntime.supported) {
      _nativeRuntime.start();
      return;
    }
    if (_useWorker) {
      _dataWorker.start();
      return;
    }
    unawaited(_bootstrap(generation));
    _realtimeTimer = Timer.periodic(
      _pollInterval,
      (_) => _fetchRealtime(generation),
    );
    _frameWatchdogTimer = Timer.periodic(
      _frameWatchdogInterval,
      (_) => _checkFrameFreshness(generation),
    );
  }

  void stop({bool clear = true}) {
    if (nativeActive) _nativeRuntime.stop();
    if (_useWorker) {
      _dataWorker.stop();
      final wasDetected = _workerDetection.stage != ShakeDetectStage.idle;
      _workerDetection = ShakeDetectionService.idleSnapshot;
      _preparedHistory = null;
      onDetectionChanged?.call(_workerDetection);
      if (wasDetected) onShakeExpired?.call();
    } else {
      _endShakeDetection();
    }
    _running = false;
    _runGeneration++;
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
    _frameWatchdogTimer?.cancel();
    _frameWatchdogTimer = null;
    _fetchingStations = false;
    _fetchingRealtime = false;
    _isConnected = false;
    _failureReported = false;
    _consecutiveFailures = 0;
    _lastRealtimeTimestamp = null;
    _lastFrameReceivedAt = null;
    if (!_useWorker) {
      _levelHistory.clear();
      _wireDecoder.dispose();
    }
    dataTimeNotifier.value = null;
    receivedTimeNotifier.value = null;
    _client?.close();
    _client = null;
    onStatusChanged?.call(false);
    if (clear) {
      _stationMap.clear();
      _stations = const [];
      _stationController.add(_stations);
    }
  }

  @visibleForTesting
  void handleOriginalForTesting(List<int> bytes, DateTime clock) =>
      _nativeRuntime.inject(bytes, clock);

  bool _isCurrentRun(int generation) =>
      _running && generation == _runGeneration;

  Future<void> _bootstrap(int generation) async {
    try {
      final client = await _clientFactory();
      if (!_isCurrentRun(generation)) {
        client.close();
        return;
      }
      _client = client;
    } catch (e) {
      if (_isCurrentRun(generation)) {
        debugPrint('[P-Alert] HTTP client initialization failed: $e');
        _markDisconnected();
      }
      return;
    }
    await _fetchStationList(generation);
    if (_isCurrentRun(generation)) await _fetchRealtime(generation);
  }

  Future<void> _fetchStationList(int generation) async {
    if (!_isCurrentRun(generation) || _client == null || _fetchingStations) {
      return;
    }
    _fetchingStations = true;
    try {
      final json = await _postGraphql(
        _stationListQuery,
        generation: generation,
        variables: const {'staFilter': _stationFilter},
      );
      if (!_isCurrentRun(generation)) return;
      final data = json['data'] as Map<String, dynamic>?;
      final stationList = data?['stationList'] as Map<String, dynamic>?;
      StationHistoryCapture.instance.retainOriginal('palert', 'metadata', json);
      final infos = stationList?['staInfos'];
      if (infos is! List || infos.isEmpty) {
        if (_stationMap.isEmpty) _handleFailure();
        return;
      }

      final nextStations = <String, PAlertStation>{};
      for (final item in infos) {
        if (item is! Map<String, dynamic>) continue;
        final id = _asString(item['station']);
        final lat = _asDouble(item['lat']);
        final lon = _asDouble(item['lon']);
        if (id.isEmpty || lat == null || lon == null) continue;

        final existing = _stationMap[id];
        nextStations[id] = PAlertStation(
          id: id,
          network: _asString(item['network']),
          name: _asString(item['locname']).isNotEmpty
              ? _asString(item['locname'])
              : id,
          area: _asString(item['area']),
          coordinate: LatLng(lat, lon),
          pgaGal: existing?.pgaGal,
          pgvCms: existing?.pgvCms,
          cwaIntensityIndex: existing?.cwaIntensityIndex,
          heldCwaIntensityIndex: existing?.heldCwaIntensityIndex,
          heldLevel: existing?.heldLevel,
          dataTime: existing?.dataTime,
          receivedAt: existing?.receivedAt,
          sampledLevel: existing?._sampledLevel,
        );
      }
      if (!_isCurrentRun(generation)) return;
      if (nextStations.isEmpty) {
        if (_stationMap.isEmpty) _handleFailure();
        return;
      }
      _stationMap
        ..clear()
        ..addAll(nextStations);
      _levelHistory.setStations(nextStations.keys);
      _wireDecoder.setPAlertStations(nextStations.keys);
      _emitStations();
    } catch (e) {
      if (_isCurrentRun(generation)) {
        debugPrint('[P-Alert] station list fetch failed: $e');
        if (_stationMap.isEmpty) _handleFailure();
      }
    } finally {
      if (generation == _runGeneration) {
        _fetchingStations = false;
      }
    }
  }

  Future<void> _fetchRealtime(int generation) async {
    if (!_isCurrentRun(generation) || _client == null || _fetchingRealtime) {
      return;
    }
    if (_stationMap.isEmpty) {
      return;
    }
    _fetchingRealtime = true;
    try {
      late PAlertWireResponse wire;
      final json = await _postGraphql(
        _realtimeQuery,
        generation: generation,
        variables: const {'recordTime': 0, 'token': ''},
        decoder: (bytes) {
          wire = _wireDecoder.decodePAlertUtf8(
            bytes,
            shouldExtract: _shouldExtractRealtimeValues,
          );
          return wire.raw;
        },
      );
      if (!_isCurrentRun(generation)) return;
      final data = json['data'] as Map<String, dynamic>?;
      final pga = data?['pga'] as Map<String, dynamic>?;
      StationHistoryCapture.instance.retainOriginal('palert', 'data', json);
      final pgv = data?['pgv'] as Map<String, dynamic>?;
      final pgaTimestamp = parseTimestamp(pga?['timestamp'] as String?);
      final pgvTimestamp = parseTimestamp(pgv?['timestamp'] as String?);
      if (!_isCurrentRun(generation)) return;
      if (pgaTimestamp == null) {
        _handleFailure();
        return;
      }
      if (!isNewerFrameTime(_lastRealtimeTimestamp, pgaTimestamp)) return;

      final values = wire.values;
      if (values.validPgaCount == 0) {
        _handleFailure();
        return;
      }
      final includePgv = pgvTimestamp == pgaTimestamp;
      final receivedAt = DateTime.now().toUtc();
      final levels = _levelHistory.processWireValues(
        pgaTimestamp,
        values,
        includePgv: includePgv,
      );
      var changed = false;
      var index = 0;
      for (final id in _stationMap.keys.toList(growable: false)) {
        final row = index * 2;
        final pgaGal = values.pga(index);
        final pgvCms = includePgv ? values.pgv(index) : null;
        index++;
        if (pgaGal == null && pgvCms == null) continue;
        final station = _stationMap[id]!;
        final hasCurrentPga = pgaGal != null;
        final level = levels[row];
        final heldLevel = hasCurrentPga ? levels[row + 1] : station.heldLevel;
        _stationMap[id] = PAlertStation(
          id: station.id,
          network: station.network,
          name: station.name,
          area: station.area,
          coordinate: station.coordinate,
          pgaGal: pgaGal ?? station.pgaGal,
          pgvCms: hasCurrentPga ? pgvCms : station.pgvCms,
          cwaIntensityIndex: level < 0
              ? null
              : PAlertSourceProfile.intensityIndexFromLevel(level),
          heldCwaIntensityIndex: heldLevel == null || heldLevel < 0
              ? null
              : PAlertSourceProfile.intensityIndexFromLevel(heldLevel),
          heldLevel: heldLevel,
          dataTime: hasCurrentPga ? pgaTimestamp : station.dataTime,
          receivedAt: hasCurrentPga ? receivedAt : station.receivedAt,
          sampledLevel: hasCurrentPga ? level : station.currentGridLevel,
        );
        changed = true;
      }
      if (!changed) {
        _handleFailure();
        return;
      }

      _lastRealtimeTimestamp = pgaTimestamp;
      _lastFrameReceivedAt = receivedAt;
      dataTimeNotifier.value = pgaTimestamp;
      receivedTimeNotifier.value = receivedAt;
      _emitStations();
      _checkShakeDetection();
      _handleSuccess();
    } catch (e) {
      if (_isCurrentRun(generation)) {
        debugPrint('[P-Alert] realtime fetch failed: $e');
        _handleFailure();
      }
    } finally {
      if (generation == _runGeneration) {
        _fetchingRealtime = false;
        _onRealtimeSettled?.call();
      }
    }
  }

  void _checkFrameFreshness(int generation) {
    if (_isCurrentRun(generation)) {
      _detector.expireStale(DateTime.now().toUtc());
    }
    if (!_isCurrentRun(generation) ||
        !isFrameStale(_lastFrameReceivedAt, DateTime.now().toUtc())) {
      return;
    }
    _markDisconnected();
  }

  bool _shouldExtractRealtimeValues(dynamic raw) {
    if (raw is! Map || raw['errors'] != null) return false;
    final data = raw['data'];
    final pga = data is Map ? data['pga'] : null;
    final timestamp = pga is Map ? pga['timestamp'] : null;
    if (timestamp is! String) return false;
    final time = parseTimestamp(timestamp);
    return time != null && isNewerFrameTime(_lastRealtimeTimestamp, time);
  }

  void _handleSuccess() {
    _consecutiveFailures = 0;
    _failureReported = false;
    if (_isConnected) return;
    _isConnected = true;
    onStatusChanged?.call(true);
  }

  void _handleFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures < maxConsecutiveFailures || _failureReported) {
      return;
    }
    _isConnected = false;
    _failureReported = true;
    _endShakeDetection();
    onStatusChanged?.call(false);
  }

  void _markDisconnected() {
    _consecutiveFailures = maxConsecutiveFailures;
    if (_failureReported) return;
    _isConnected = false;
    _failureReported = true;
    _endShakeDetection();
    onStatusChanged?.call(false);
  }

  Future<Map<String, dynamic>> _postGraphql(
    String query, {
    required int generation,
    required Map<String, dynamic> variables,
    dynamic Function(List<int>) decoder = decodeApiJsonBytes,
  }) async {
    final client = _client;
    if (client == null) throw StateError('P-Alert client is not running');
    final response = await client
        .post(
          _endpoint ?? _graphqlUri,
          headers: const {
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json;charset=UTF-8',
            if (!kIsWeb) ...{
              'Origin': 'https://palert.earth.sinica.edu.tw',
              'Referer': 'https://palert.earth.sinica.edu.tw/realtime',
              'User-Agent': 'FlutterRhythmQuake/1.0',
            },
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 12));
    if (!_isCurrentRun(generation)) {
      throw StateError('P-Alert connection stopped');
    }
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final json = decoder(response.bodyBytes);
    if (json is! Map<String, dynamic>) {
      throw StateError('invalid JSON');
    }
    if (json['errors'] != null) {
      throw StateError('GraphQL errors: ${json['errors']}');
    }
    return json;
  }

  void _emitStations() {
    final next = _stationMap.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    _stations = next;
    StationHistoryCapture.instance.publish(
      'palert',
      () => ForegroundStationPayload.palert(
        _stations,
        dataTime: dataTimeNotifier.value,
        receivedTime: receivedTimeNotifier.value,
        detection: detectionSnapshot,
      ),
      source: 'palert',
    );
    _stationController.add(next);
  }

  void _checkShakeDetection() {
    _detector.update(_stations, now: DateTime.now().toUtc());
  }

  void _endShakeDetection() {
    _detector.reset();
  }

  static int? cwaIntensityIndexFromPgaPgv({double? pgaGal, double? pgvCms}) {
    final level = PAlertSourceProfile.level(pgaGal, pgvCms);
    return level < 0
        ? null
        : PAlertSourceProfile.intensityIndexFromLevel(level);
  }

  static DateTime? parseTimestamp(String? value) {
    if (value == null || value.isEmpty) return null;
    final trimmed = value.trim();
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;
    final match = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2}):(\d{2})$',
    ).firstMatch(trimmed);
    if (match == null) return null;
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  @visibleForTesting
  static bool isNewerFrameTime(DateTime? previous, DateTime candidate) {
    return previous == null || candidate.isAfter(previous);
  }

  static bool isFrameStale(
    DateTime? receivedAt,
    DateTime now, {
    Duration staleAfter = frameStaleAfter,
  }) {
    return receivedAt != null && now.difference(receivedAt) > staleAfter;
  }

  static String _asString(dynamic value) => value?.toString().trim() ?? '';

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}
