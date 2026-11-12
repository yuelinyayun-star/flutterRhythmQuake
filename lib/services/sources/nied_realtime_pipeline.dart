import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import '../../core/event_detection/event_detection_models.dart';
import '../../core/nied_replay_logger.dart';
import '../../models/source_payload.dart';
import '../foreground_station_payload.dart';
import '../ntp_service.dart';
import '../station_history_capture.dart';
import '../obs_automation_input_service.dart';
import 'jp_shindo_scale.dart';
import 'jian_station_service.dart';
import 'lmoni_image_service.dart';
import 'native_ka_history.dart';
import 'nied_array_observation_processor.dart';
import 'nied_background_worker.dart';
import 'nied_monitor.dart';
import 'nied_source_estimation_worker.dart';
import 'nied_source_station_frame.dart';
import 'nied_yahoo_service.dart';
import 'shake_detection_service.dart';
import 'station_image_decoder.dart';
import 'whews_nied_station_metadata.dart';
import 'whews_socket_client.dart';
import 'whews_station_service.dart';
import 'data_owner_asset.dart';
import 'source_connection_lifecycle.dart';

class NiedPipelineFrame {
  NiedPipelineFrame(
    this.source,
    this._stationFrame,
    this.detection,
    this.eventDetection,
    this._preparedHistory,
    this.original,
    this.dataTime,
    this.receivedAt,
    this.signals,
    this.processingIsolate,
    this.layerSignature,
    this.automationSamples, [
    this.inferenceDiagnostics = const {},
  ]);
  final String source;
  // Timer-free, native-owner-free display views, prepared by the data owner.
  final NiedSourceStationFrame _stationFrame;
  // Send compact original values once. Display objects are created only in
  // the receiving isolate, without sending thousands of duplicated maps.
  late final List<NiedStation> stations = NiedSourceStationDecoder().apply(
    _stationFrame,
  );
  final ShakeDetectionSnapshot detection;
  final EventDetection? eventDetection;
  final Map<String, dynamic>? _preparedHistory;
  // Keep the latest frame available for an EEW starting between updates.
  // Its input is independently owned; a later frame cannot change it.
  late final Map<String, dynamic> history =
      _preparedHistory ?? _niedFrameHistory(stations, source, detection);
  @visibleForTesting
  bool get historyPreparedByOwner => _preparedHistory != null;
  final Map<String, dynamic>? original;
  final DateTime? dataTime;
  final DateTime receivedAt;
  final List<int?> signals;
  final String? processingIsolate;
  final String layerSignature;
  final List<ObsStationInputSample> automationSamples;
  final Map<String, Object?> inferenceDiagnostics;
}

/// One owner from live HTTP/WS ingress through KA, detection, inference input,
/// timers and archive projection. The host only forwards display/effect output.
class NiedRealtimePipeline {
  static NiedRealtimePipeline? active;
  bool get acceptsGifInjection => _source == 'lmoni' || _source == 'kmoni';
  static bool get supported => !kIsWeb && NativeKaHistorySession.supported;
  void Function(NiedPipelineFrame)? onFrame;
  void Function(NiedSourceEstimationResult)? onEstimate;
  void Function(WhewsSocketState)? onStatus;
  void Function(Object)? onError;
  Isolate? _isolate;
  static final _previousOwner = SourceConnectionBarrier();
  Completer<void>? _exitDone;
  SendPort? _commands;
  ReceivePort? _responses, _errors, _exits;
  Completer<SendPort?>? _ready;
  final _pending = <int, Completer<void>>{};
  int _generation = 0, _nextId = 0;
  String? _source;
  String _token = '';
  bool _estimate = false;
  int _sensitivity = 2;
  bool _disposed = false;
  Timer? _restartTimer;
  int _frameCount = 0;
  DateTime? _lastDataTime;
  int _stationCount = 0;
  Map<String, Object?> _inferenceDiagnostics = const {};
  Map<String, Object?> get diagnostics => {
    'source': _source,
    'running': isRunning,
    'frames': _frameCount,
    'stations': _stationCount,
    'dataTime': _lastDataTime?.toIso8601String(),
    'estimateEnabled': _estimate,
    'inference': _inferenceDiagnostics,
    'pendingRequests': _pending.length,
  };
  NiedReplayConfig _replay = const NiedReplayConfig.disabled();
  final bool testMode;
  final String? testPrefecturesJson;
  NiedRealtimePipeline({this.testMode = false, this.testPrefecturesJson});

  bool get isRunning => _source != null;

  Future<void> start({
    required String source,
    required NiedReplayConfig replay,
    required int sensitivity,
    required bool estimate,
  }) async {
    if (_disposed) return;
    _restartTimer?.cancel();
    _restartTimer = null;
    final same =
        _source == source &&
        _replay.enabled == replay.enabled &&
        _replay.startJst == replay.startJst &&
        _replay.stepSeconds == replay.stepSeconds;
    if (!same) stop();
    _source = source;
    active = this;
    _replay = replay;
    _sensitivity = sensitivity;
    _estimate = estimate;
    await _ensureStarted();
    if (_source == source) _sendSettings();
  }

  void setApiToken(String value) {
    _token = value;
    _commands?.send(('token', value));
  }

  void setSensitivity(int value) {
    _sensitivity = value;
    _sendSettings();
  }

  void setEstimateEnabled(bool value) {
    if (_estimate == value) return;
    _estimate = value;
    _sendSettings();
  }

  void _sendSettings() => _commands?.send((
    'settings',
    (
      _sensitivity,
      _estimate,
      NiedReplayLogger.instance.isEnabled,
      StationHistoryCapture.instance.recording,
    ),
  ));
  void _sendClock() {
    final clock = NtpService();
    _commands?.send((
      'clock',
      (clock.deviceOffset, clock.lastSyncedAt, clock.isSynced),
    ));
  }

  @visibleForTesting
  Future<void> injectArray(WhewsStationFrame frame, DateTime receivedAt) =>
      _request('array', (frame, receivedAt));
  // Original-GIF debugging uses the same data owner as live ingress.
  Future<void> injectGif(
    Uint8List bytes,
    DateTime dataTime,
    DateTime receivedAt,
  ) => _request('gif', (
    TransferableTypedData.fromList([bytes]),
    dataTime,
    receivedAt,
  ));

  Future<void> beginGifInjection() => _request('beginInjection', true);
  Future<void> endGifInjection() => _request('endInjection', true);
  Future<void> importStations(Map<String, dynamic> originalSnapshot) =>
      _request('import', snapshotSourcePayload(originalSnapshot));

  Future<void> _request(String kind, Object payload) async {
    final generation = _generation;
    final port = await _ensureStarted();
    if (port == null || generation != _generation) return;
    final id = _nextId++;
    final done = Completer<void>();
    _pending[id] = done;
    port.send((id, kind, payload));
    return done.future;
  }

  Future<SendPort?> _ensureStarted() {
    if (_ready != null) return _ready!.future;
    final source = _source;
    if (source == null) return Future.value(null);
    final ready = _ready = Completer<SendPort?>();
    final generation = _generation;
    final responses = _responses = ReceivePort();
    final errors = _errors = ReceivePort();
    final exits = _exits = ReceivePort();
    final exitDone = Completer<void>();
    SendPort? generationPort;
    responses.listen((dynamic message) {
      if (_generation != generation) return;
      if (message is SendPort) {
        _commands = generationPort = message;
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is NiedPipelineFrame) {
        _frameCount++;
        _lastDataTime = message.dataTime;
        _stationCount = message.stations.length;
        _inferenceDiagnostics = message.inferenceDiagnostics;
        final capture = StationHistoryCapture.instance;
        if (message.original != null) {
          capture.restoreOriginal('${message.source}.nied', message.original!);
        }
        final frame = message;
        LmoniImageService().acceptPreparedStations(frame.stations);
        capture.publish(
          'nied',
          () => frame.history,
          originalJson: frame.original,
          receivedAt: frame.receivedAt,
        );
        onFrame?.call(frame);
      } else if (message is NiedSourceEstimationResult) {
        if (_estimate) onEstimate?.call(message);
      } else if (message is NiedGifFrame) {
        LmoniImageService().acceptPreparedGif(message);
      } else if (message is WhewsSocketState) {
        onStatus?.call(message);
      } else if (message is (int, String?)) {
        final done = _pending.remove(message.$1);
        if (message.$2 == null) {
          done?.complete();
        } else {
          done?.completeError(StateError(message.$2!));
        }
      } else if (message is (String, Object)) {
        if (message.$1 == 'error') {
          onError?.call(StateError(message.$2.toString()));
        }
      } else if (message is (int, Map<String, dynamic>)) {
        NiedReplayLogger.instance.acceptPreparedRecord(message.$1, message.$2);
      } else if (message is (DateTime, String, Uint8List, String)) {
        NiedReplayLogger.instance.recordGifBytes(
          jstTime: message.$1,
          gifUrl: message.$2,
          bytes: message.$3,
          layerKey: message.$4,
        );
      }
    });
    void failed(Object error) {
      if (generation != _generation) return;
      final restartSource = _source;
      onError?.call(error);
      onStatus?.call(WhewsSocketState.error);
      stop();
      if (!_disposed && !testMode && restartSource != null) {
        _restartTimer = Timer(const Duration(seconds: 2), () {
          unawaited(
            start(
              source: restartSource,
              replay: _replay,
              sensitivity: _sensitivity,
              estimate: _estimate,
            ),
          );
        });
      }
    }

    errors.listen(
      (dynamic error) => failed(StateError('NIED data owner: $error')),
    );
    exits.listen((_) {
      if (!exitDone.isCompleted) exitDone.complete();
      exits.close();
      failed(StateError('NIED data owner exited'));
    });
    final ntp = NtpService();
    unawaited(() async {
      try {
        await _previousOwner.wait();
        if (generation != _generation) {
          exits.close();
          return;
        }
        _exitDone = exitDone;
        await Isolate.spawn(
          _niedPipelineMain,
          (
            responses.sendPort,
            source,
            _token,
            _replay,
            _sensitivity,
            _estimate,
            (ntp.deviceOffset, ntp.lastSyncedAt, ntp.isSynced),
            testMode,
            testPrefecturesJson,
            NiedReplayLogger.instance.isEnabled,
            StationHistoryCapture.instance.recording,
          ),
          onError: errors.sendPort,
          onExit: exits.sendPort,
          debugName: 'nied-realtime-data-owner',
        ).then((isolate) {
          if (generation != _generation) {
            if (generationPort != null) {
              generationPort!.send('close');
            } else {
              isolate.kill(priority: Isolate.immediate);
            }
          } else {
            _isolate = isolate;
          }
        });
      } catch (error) {
        if (!exitDone.isCompleted) exitDone.complete();
        exits.close();
        failed(error);
      }
    }());
    NiedReplayLogger.instance.revision.addListener(_sendSettings);
    StationHistoryCapture.instance.addRecordingListener(_sendSettings);
    NtpService().clockRevision.addListener(_sendClock);
    return ready.future;
  }

  void stop() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _generation++;
    _source = null;
    if (identical(active, this)) active = null;
    NiedReplayLogger.instance.revision.removeListener(_sendSettings);
    StationHistoryCapture.instance.removeRecordingListener(_sendSettings);
    NtpService().clockRevision.removeListener(_sendClock);
    if (_ready case final ready? when !ready.isCompleted) ready.complete(null);
    final exitDone = _exitDone;
    final isolate = _isolate;
    _exitDone = null;
    if (exitDone != null) {
      _previousOwner.close(() async {
        try {
          await exitDone.future.timeout(const Duration(seconds: 10));
        } on TimeoutException {
          // Drain an exit notification queued behind a local host stall first.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (exitDone.isCompleted) return;
          isolate?.kill(priority: Isolate.immediate);
          throw StateError('NIED owner shutdown was not confirmed');
        }
      });
    }
    if (_commands != null) {
      _commands!.send('close');
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
    _ready = null;
    _commands = null;
    _isolate = null;
    _responses?.close();
    _errors?.close();
    if (exitDone == null) _exits?.close();
    _responses = _errors = _exits = null;
    for (final pending in _pending.values) {
      pending.complete();
    }
    _pending.clear();
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}

typedef _Configuration = (
  SendPort,
  String,
  String,
  NiedReplayConfig,
  int,
  bool,
  (int, DateTime?, bool),
  bool,
  String?,
  bool,
  bool,
);

void _niedPipelineMain(_Configuration config) {
  final (
    output,
    source,
    token,
    replay,
    sensitivity,
    estimate,
    clock,
    testMode,
    prefecturesJson,
    logging,
    recording,
  ) = config;
  NtpService().restoreClockSample(clock.$1, clock.$2, clock.$3);
  StationImageDecoder.cpuOnly = true;
  final logger = NiedReplayLogger.instance;
  logger.externalRecordSink = (type, record) => output.send((type, record));
  logger.externalGifSink = (time, url, bytes, layer) =>
      output.send((time, url, bytes, layer));
  logger.setExternalRecordingEnabled(logging);
  final owner = _NiedPipelineOwner(
    output,
    source,
    estimate,
    sensitivity,
    recording,
    prefecturesJson: prefecturesJson,
  );
  final input = ReceivePort();
  Future<void> commands = Future.value();
  input.listen((dynamic message) {
    if (message == 'close') {
      unawaited(
        owner.close().then(
          (_) {
            input.close();
            Isolate.exit();
          },
          onError: (Object error, StackTrace stack) {
            output.send(('error', 'NIED shutdown failed'));
          },
        ),
      );
      return;
    }
    if (message is (String, dynamic)) {
      switch (message.$1) {
        case 'clock':
          final (offset, stamp, synced) = message.$2 as (int, DateTime?, bool);
          NtpService().restoreClockSample(offset, stamp, synced);
        case 'token':
          owner.whews.setApiToken(message.$2 as String);
        case 'settings':
          final (value, enabled, logging, recording) =
              message.$2 as (int, bool, bool, bool);
          owner.configure(value, enabled);
          owner.recording = recording;
          logger.setExternalRecordingEnabled(logging);
      }
      return;
    }
    final (id, kind, payload) = message as (int, String, Object);
    commands = commands.then((_) async {
      try {
        if (kind == 'array') {
          final (frame, received) = payload as (WhewsStationFrame, DateTime);
          await owner.processArray(frame, received);
        } else if (kind == 'gif') {
          final (bytes, time, received) =
              payload as (TransferableTypedData, DateTime, DateTime);
          await owner.processGif(
            bytes.materialize().asUint8List(),
            time,
            received,
          );
        }
        if (kind == 'beginInjection') {
          owner.resetForInjection();
        } else if (kind == 'endInjection') {
          owner.resetForInjection();
          if (!testMode) {
            owner.monitor.configureEndpoint(source);
            owner.monitor.configureReplay(replay);
            owner.monitor.start();
          }
        } else if (kind == 'import') {
          final raw = payload as Map<String, dynamic>;
          owner.accept(ForegroundStationPayload.decodeNied(raw['stations']));
        }
        output.send((id, null));
      } catch (error) {
        output.send((id, error.toString()));
      }
    });
  });
  output.send(input.sendPort);
  owner.start(token, replay, testMode: testMode);
}

class _NiedPipelineOwner {
  _NiedPipelineOwner(
    this.output,
    this.source,
    this.estimateEnabled,
    int sensitivity,
    this.recording, {
    this.prefecturesJson,
  }) {
    configure(sensitivity, estimateEnabled);
    detector.onDetectionSnapshotChanged = (snapshot) {
      detection = snapshot;
      if (!processing) emit();
    };
    detector.onEventDetectionChanged = (event) {
      eventDetection = event;
    };
    detector.onShakeDetected = (value) {
      signals.add(value);
      if (!processing) emit();
    };
    detector.onShakeExpired = () {
      signals.add(null);
      if (!processing) emit();
    };
  }
  final SendPort output;
  final String source;
  final String? prefecturesJson;
  final image = LmoniImageService();
  final monitor = NiedMonitorService();
  final yahoo = NiedYahooService();
  final whews = WhewsStationService(kind: WhewsStationKind.nied, apiToken: '');
  final jian = JianStationService(kind: WhewsStationKind.nied);
  final detector = ShakeDetectionService.forSource('nied', nativeOwner: true);
  final inference = NiedSourceEstimationWorker(
    includeObservationHistory: false,
  );
  final array = NiedArrayObservationProcessor();
  final encoder = NiedSourceStationEncoder();
  final subscriptions = <StreamSubscription<dynamic>>[];
  ShakeDetectionSnapshot detection = ShakeDetectionService.idleSnapshot;
  EventDetection? eventDetection;
  List<NiedStation> stations = const [];
  final signals = <int?>[];
  bool recording;
  bool estimateEnabled, processing = false, closed = false;
  int estimateGeneration = 0;
  Future<void>? lastInference;
  Future<void> arrayFrames = Future.value();

  void configure(int sensitivity, bool estimate) {
    detector.setSensitivity(sensitivity);
    inference.setSensitivity(sensitivity);
    if (estimateEnabled && !estimate) {
      inference.reset();
      estimateGeneration++;
    }
    estimateEnabled = estimate;
    if (!estimate) monitor.setPhysicalLayersEnabled(false);
  }

  void start(String token, NiedReplayConfig replay, {required bool testMode}) {
    whews.setApiToken(token);
    void status(bool value) => output.send(
      value ? WhewsSocketState.connected : WhewsSocketState.error,
    );
    image.onStatusChanged = status;
    yahoo.onStatusChanged = status;
    subscriptions.add(
      image.stationStream.listen((value) {
        if (value != null && source != 'yahoo') accept(value);
      }),
    );
    subscriptions.add(image.gifFrameStream.listen(output.send));
    subscriptions.add(
      yahoo.stationStream.listen((value) {
        if (value != null && source == 'yahoo') accept(value);
      }),
    );
    void queueArray(WhewsStationFrame frame) {
      final receivedAt = DateTime.now();
      arrayFrames = arrayFrames
          .then((_) => processArray(frame, receivedAt))
          .catchError((Object error) {
            if (!closed) output.send(('error', error.toString()));
          });
    }

    subscriptions.add(whews.frameStream.listen(queueArray));
    subscriptions.add(jian.frameStream.listen(queueArray));
    whews.stateNotifier.addListener(
      () => output.send(whews.stateNotifier.value),
    );
    jian.stateNotifier.addListener(() => output.send(jian.stateNotifier.value));
    if (testMode) {
      if (source == 'lmoni' || source == 'kmoni') image.start();
      return;
    }
    switch (source) {
      case 'whews':
        whews.start();
      case 'jian':
        jian.start();
      case 'yahoo':
        yahoo.configureReplay(replay);
        yahoo.start();
      default:
        image.start();
        monitor.configureEndpoint(source);
        monitor.configureReplay(replay);
        monitor.start();
    }
  }

  Future<String> loadAsset(String key) async {
    if (prefecturesJson != null) return prefecturesJson!;
    // Windows packages keep unchanged assets beside the executable. The engine
    // asset channel does not provide background-isolate responses on this host.
    // Read and decode the original file here, without a UI messenger roundtrip.
    return readPackagedDataOwnerAsset(key);
  }

  Future<void> processArray(WhewsStationFrame frame, DateTime received) async {
    if (closed || frame.source != source) return;
    if (frame.coordinates.isEmpty) {
      stations = const [];
      detector.reset(detachStations: true);
      emit();
      return;
    }
    if (frame.values.length != frame.coordinates.length ||
        (source == 'jian' &&
            (frame.codes.length != frame.coordinates.length ||
                frame.names.length != frame.coordinates.length ||
                frame.regions.length != frame.coordinates.length ||
                frame.stationTypes.length != frame.coordinates.length ||
                frame.codes.any((code) => code.trim().isEmpty)))) {
      return;
    }
    var same = array.stations.length == frame.coordinates.length;
    if (same) {
      for (var i = 0; i < frame.coordinates.length; i++) {
        if (array.stations[i].coordinate != frame.coordinates[i]) {
          same = false;
          break;
        }
      }
    }
    if (!same) {
      await loadWhewsNiedPrefectures(loadString: loadAsset);
      if (closed) return;
      processing = true;
      detector.reset(detachStations: true, emitSnapshot: false);
      inference.reset();
      estimateGeneration++;
      encoder.reset();
      array.configure(
        buildWhewsNiedStations(
          frame.coordinates,
          source: source,
          codes: frame.codes,
          names: frame.names,
          regions: frame.regions,
          stationTypes: frame.stationTypes,
        ),
      );
      processing = false;
    }
    array.apply(frame, receivedAt: received);
    if (frame.originalJson != null) {
      StationHistoryCapture.instance.restoreOriginal(
        '$source.nied',
        frame.originalJson!,
      );
    }
    accept(array.stations);
  }

  Future<void> processGif(
    Uint8List bytes,
    DateTime time,
    DateTime received,
  ) async {
    final scanned = await NiedBackgroundWorker.instance.scanFrame(
      surfaceBytes: bytes,
      configs: image.backgroundScanConfigs,
      configSignature: image.backgroundScanConfigSignature,
    );
    if (scanned == null) throw StateError('NIED GIF decode failed');
    image.processSampledFrame(
      scanned,
      surfaceGifBytes: bytes,
      dataTime: time,
      receivedAt: received,
      publish: false,
    );
    image.publishStations();
    await Future<void>.delayed(Duration.zero);
    await lastInference;
  }

  void accept(List<NiedStation> value) {
    if (closed) return;
    stations = value;
    processing = true;
    try {
      if (value.isEmpty) {
        detector.reset(detachStations: true);
      } else {
        // The data owner commits holds and detection before making UI views or
        // taking HYP input. No async detector result can modify an older frame.
        detector.setStations(value);
        detector.processUpdate();
      }
    } finally {
      processing = false;
    }
    emit();
    if (estimateEnabled && value.isNotEmpty) {
      final generation = estimateGeneration;
      // All inference transport preparation executes here, off the UI isolate.
      unawaited(
        lastInference = inference
            .processStations(value)
            .then(
              (result) {
                if (closed ||
                    !estimateEnabled ||
                    generation != estimateGeneration ||
                    result == null) {
                  return;
                }
                monitor.setPhysicalLayersEnabled(
                  result.detection.hasActiveEvent,
                );
                output.send(result);
              },
              onError: (Object error) {
                if (!closed) output.send(('error', error.toString()));
              },
            ),
      );
    }
  }

  void resetForInjection() {
    processing = true;
    monitor.stop();
    image.stop();
    image.start();
    detector.reset(detachStations: true);
    inference.reset();
    estimateGeneration++;
    encoder.reset();
    stations = const [];
    processing = false;
    emit();
  }

  void emit() {
    if (closed) return;
    final frame = encoder.capture(stations, includeCatalogue: true);
    final history = recording
        ? _niedFrameHistory(stations, source, detection)
        : null;
    DateTime? time;
    final automation = <ObsStationInputSample>[];
    for (final station in stations) {
      final stamp = station.lastDataTime;
      if (stamp != null && (time == null || stamp.isAfter(time))) time = stamp;
      if (station.isActive) {
        automation.add(
          ObsStationInputSample(
            stationId: station.code,
            stationName: station.name,
            active: true,
            intensityLevel: JpShindoScale.jmaIndexFromKanameishiLevel(
              station.kaLevel,
            ),
            intensity: JpShindoScale.rawShindoFromKanameishiLevel(
              station.kaLevel,
            ),
            latitude: station.coordinate.latitude,
            longitude: station.coordinate.longitude,
            observedAt:
                station.lastDataTime ?? station.lastUpdate ?? DateTime.now(),
            rising: station.detectState == 1,
            strong: station.detectState >= 6,
          ),
        );
      }
    }
    output.send(
      NiedPipelineFrame(
        source,
        frame,
        detection,
        eventDetection,
        history,
        StationHistoryCapture.instance.original('$source.nied'),
        time,
        DateTime.now(),
        List.of(signals),
        Isolate.current.debugName,
        _layerSignature(),
        automation,
        inference.diagnostics,
      ),
    );
    signals.clear();
  }

  String _layerSignature() {
    if (stations.isEmpty) return '0|idle:0:0:0:-1';
    final signature = detector.preparedLayerSignature;
    if (signature == null) {
      throw StateError('Native NIED layer projection missing');
    }
    return signature;
  }

  Future<void> close() async {
    closed = true;
    monitor.stop();
    image.stop();
    yahoo.stop();
    whews.dispose();
    jian.dispose();
    detector.reset(detachStations: true, emitSnapshot: false);
    inference.dispose();
    array.dispose();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    NiedBackgroundWorker.instance.stop();
    await Future.wait([whews.closed, jian.closed]);
  }
}

Map<String, dynamic> _niedFrameHistory(
  List<NiedStation> stations,
  String source,
  ShakeDetectionSnapshot detection,
) {
  return snapshotSourcePayload({
    ...ForegroundStationPayload.nied(
      stations,
      source: source,
      includeTrackingHistory: false,
    ),
    'detection': {
      'stage': detection.stage.name,
      'weakCount': detection.weakCount,
      'detectedCount': detection.detectedCount,
      'strongCount': detection.strongCount,
      'maxShindo': detection.maxShindo,
      'gridCells': {
        for (final entry in detection.gridCells.entries)
          entry.key: {
            'lat': entry.value.center.latitude,
            'lng': entry.value.center.longitude,
            'level': entry.value.level,
            'shindo': entry.value.shindo,
          },
      },
      'detectedStations': [
        for (final s in detection.detectedStations)
          {
            'code': s.code,
            'prefecture': s.prefecture,
            'level': s.level,
            'jmaShindo': s.jmaShindo,
            'detectState': s.detectState,
            'detectReason': s.detectReason,
          },
      ],
    },
  });
}
