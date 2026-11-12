part of 'palert_service.dart';

/// Owns HTTP, original JSON, native decoding/history and the joint detector.
/// There is one persistent owner per connection, never one isolate per frame.
class _PAlertDataWorker {
  _PAlertDataWorker(this.owner);
  final PAlertService owner;
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _messages;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Timer? _restart;
  int _generation = 0;

  void setSensitivity(int value) => _commands?.send(('sensitivity', value));

  void start() {
    stop();
    final generation = _generation;
    final messages = _messages = ReceivePort();
    final errors = _errors = ReceivePort();
    final exits = _exits = ReceivePort();
    messages.listen((dynamic message) {
      if (generation != _generation || !owner._running) return;
      if (message is SendPort) {
        _commands = message;
        setSensitivity(owner._sensitivity);
      } else if (message is _PAlertDataFrame) {
        _accept(message);
      } else if (message is bool) {
        owner._isConnected = message;
        owner.onStatusChanged?.call(message);
      }
    });
    errors.listen((dynamic error) {
      if (generation == _generation) _failed(error);
    });
    exits.listen((_) {
      if (generation == _generation) _failed('processing isolate exited');
    });
    unawaited(_spawn(generation, messages, errors, exits));
  }

  Future<void> _spawn(
    int generation,
    ReceivePort messages,
    ReceivePort errors,
    ReceivePort exits,
  ) async {
    try {
      // Asset loading requires the root messenger; no HTTP/JSON runs here.
      List<int>? root;
      try {
        final asset = await rootBundle.load(
          'assets/certificates/TWCA_Global_Root_CA.der',
        );
        root = asset.buffer.asUint8List(
          asset.offsetInBytes,
          asset.lengthInBytes,
        );
      } catch (_) {
        // Same asset-free headless behavior as createPAlertHttpClient.
      }
      if (generation != _generation || !owner._running) return;
      final isolate = await Isolate.spawn(
        _pAlertDataMain,
        (
          messages.sendPort,
          owner._endpoint,
          owner._pollInterval,
          owner._sensitivity,
          root,
        ),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: 'palert-data-processing',
      );
      if (generation != _generation || !owner._running) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error) {
      if (generation == _generation) _failed(error);
    }
  }

  void _accept(_PAlertDataFrame frame) {
    final capture = StationHistoryCapture.instance;
    // Both parts were frozen by their processing owner; do not decode them.
    if (frame.originalMetadata != null) {
      capture.retainOriginal('palert', 'metadata', frame.originalMetadata!);
    }
    if (frame.originalData != null) {
      capture.retainOriginal('palert', 'data', frame.originalData!);
    }
    owner._stations = frame.stations;
    owner._workerDetection = frame.detection;
    owner._preparedHistory = frame.history;
    owner.processingIsolateName = frame.isolateName;
    owner.dataTimeNotifier.value = frame.dataTime;
    owner.receivedTimeNotifier.value = frame.receivedTime;
    // Capture the exact immutable frame, not a closure reading the next frame.
    capture.publish('palert', () => frame.history, source: 'palert');
    if (frame.detectionChanged) {
      owner.onDetectionChanged?.call(frame.detection);
    }
    for (final signal in frame.signals) {
      if (signal == null) {
        owner.onShakeExpired?.call();
      } else {
        owner.onShakeDetected?.call(signal);
      }
    }
    if (frame.stationsChanged) owner._stationController.add(frame.stations);
  }

  void _failed(Object error) {
    debugPrint('[P-Alert] data worker stopped: $error');
    stop();
    if (!owner._running) return;
    owner._isConnected = false;
    owner._workerDetection = ShakeDetectionService.idleSnapshot;
    owner._preparedHistory = null;
    owner.onDetectionChanged?.call(owner._workerDetection);
    owner.onShakeExpired?.call();
    owner.onStatusChanged?.call(false);
    _restart = Timer(const Duration(seconds: 3), () {
      if (owner._running) start();
    });
  }

  void stop() {
    _generation++;
    _restart?.cancel();
    _restart = null;
    final isolate = _isolate;
    _commands?.send(('stop', null));
    _commands = null;
    _isolate = null;
    _messages?.close();
    _errors?.close();
    _exits?.close();
    _messages = _errors = _exits = null;
    // Give the owner time to close HTTP and native sessions before termination.
    if (isolate != null) {
      Timer(const Duration(seconds: 1), () {
        isolate.kill(priority: Isolate.immediate);
      });
    }
  }
}

class _PAlertDataFrame {
  const _PAlertDataFrame({
    required this.stations,
    required this.detection,
    required this.history,
    required this.dataTime,
    required this.receivedTime,
    required this.originalMetadata,
    required this.originalData,
    required this.signals,
    required this.stationsChanged,
    required this.detectionChanged,
    required this.isolateName,
  });
  final List<PAlertStation> stations;
  final ShakeDetectionSnapshot detection;
  final Map<String, dynamic> history;
  final DateTime? dataTime;
  final DateTime? receivedTime;
  final Map<String, dynamic>? originalMetadata;
  final Map<String, dynamic>? originalData;
  final List<int?> signals;
  final bool stationsChanged;
  final bool detectionChanged;
  final String? isolateName;
}

void _pAlertDataMain((SendPort, Uri?, Duration, int, List<int>?) config) {
  final (output, endpoint, interval, sensitivity, root) = config;
  final input = ReceivePort();
  final engine = PAlertService._(
    useWorker: false,
    endpoint: endpoint,
    pollInterval: interval,
    clientFactory: () => createPAlertHttpClientWithRoot(root),
  );
  final signals = <int?>[];
  bool detectionChanged = false;
  Map<String, dynamic>? lastMetadata;
  Map<String, dynamic>? lastData;

  void publish({required bool stationsChanged}) {
    final original = StationHistoryCapture.instance.original('palert');
    final metadata = original?['metadata'] as Map<String, dynamic>?;
    final data = original?['data'] as Map<String, dynamic>?;
    final snapshot = snapshotSourcePayload(engine.historySnapshot());
    output.send(
      _PAlertDataFrame(
        stations: engine.stations,
        detection: engine.detectionSnapshot,
        history: snapshot,
        dataTime: engine.dataTimeNotifier.value,
        receivedTime: engine.receivedTimeNotifier.value,
        originalMetadata: identical(metadata, lastMetadata) ? null : metadata,
        originalData: identical(data, lastData) ? null : data,
        signals: List.of(signals),
        stationsChanged: stationsChanged,
        detectionChanged: detectionChanged,
        isolateName: Isolate.current.debugName,
      ),
    );
    signals.clear();
    detectionChanged = false;
    lastMetadata = metadata;
    lastData = data;
  }

  // Detector callbacks inside a fetch are committed with that frame, so UI,
  // archive and inference always see matching observations and confirmed IDs.
  void publishDetection() {
    if (!engine._fetchingRealtime) publish(stationsChanged: false);
  }

  engine.onStatusChanged = output.send;
  engine.onDetectionChanged = (_) {
    detectionChanged = true;
    publishDetection();
  };
  engine.onShakeDetected = (value) {
    signals.add(value);
    publishDetection();
  };
  engine.onShakeExpired = () {
    signals.add(null);
    publishDetection();
  };
  engine._onRealtimeSettled = () {
    // The async station stream commits successful frames first. A failed
    // request can still reset a detection and must publish that cancellation.
    scheduleMicrotask(() {
      if (engine._running && (detectionChanged || signals.isNotEmpty)) {
        publish(stationsChanged: false);
      }
    });
  };
  final subscription = engine.stationStream.listen((_) {
    publish(stationsChanged: true);
  });
  engine.setSensitivity(sensitivity);
  input.listen((dynamic message) async {
    if (message is! (String, dynamic)) return;
    switch (message.$1) {
      case 'sensitivity':
        engine.setSensitivity(message.$2 as int);
      case 'stop':
        engine.onStatusChanged = null;
        engine.onDetectionChanged = null;
        engine.onShakeDetected = null;
        engine.onShakeExpired = null;
        engine.stop();
        await subscription.cancel();
        input.close();
        Isolate.exit();
    }
  });
  output.send(input.sendPort);
  engine.start();
}
