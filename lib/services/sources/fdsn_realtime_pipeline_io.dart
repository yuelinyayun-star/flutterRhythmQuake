import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../widgets/map/fdsn_map_station_store.dart';
import '../obs_automation_input_service.dart';
import 'fdsn_motion_service_io.dart';
import 'fdsn_station_service.dart';
import 'native_seedlink_codec.dart';
import 'fdsn_display_frame.dart';

/// Connection, catalogues, original packet processing, native waveform kernels,
/// late/calibrated sample merge and display retention have a single data owner.
class FdsnRealtimePipeline {
  FdsnRealtimePipeline({this.testMode = false});
  static bool get supported => !kIsWeb && NativeSeedLinkCodec.supported;
  static FdsnRealtimePipeline? active;
  final bool testMode;
  void Function(FdsnDisplayFrame)? onFrame;
  void Function(Object)? onError;
  FdsnDisplayFrame? lastFrame;
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _responses, _errors, _exits;
  Completer<SendPort?>? _ready;
  int _generation = 0, _revision = 0, _limit = 300;
  Set<String> _sources = const {};
  Timer? _retry;
  bool _disposed = false, _running = false;
  final _pending = <int, Completer<void>>{};
  int _requestId = 0;

  Future<void> connect({
    required int stationLimit,
    required Set<String> sources,
  }) async {
    if (_disposed) return;
    if (_running && _limit == stationLimit && setEquals(_sources, sources)) {
      return;
    }
    _retry?.cancel();
    _running = true;
    active = this;
    _limit = stationLimit;
    _sources = Set.unmodifiable(sources);
    final revision = ++_revision;
    final generation = _generation;
    final port = await _ensureStarted();
    if (port != null &&
        _running &&
        generation == _generation &&
        revision == _revision) {
      port.send(('configure', (revision, stationLimit, _sources)));
    }
  }

  @visibleForTesting
  Future<void> injectOriginal({
    List<FdsnStation>? metadata,
    FdsnMotionSample? sample,
    DateTime? displayClock,
  }) async {
    if (!testMode) {
      throw StateError('Original fixture injection requires testMode');
    }
    final port = await _ensureStarted();
    if (port == null) return;
    final id = _requestId++;
    final done = Completer<void>();
    _pending[id] = done;
    port.send((id, metadata, sample, displayClock));
    await done.future;
  }

  Future<SendPort?> _ensureStarted() {
    if (_ready != null) return _ready!.future;
    if (!_running || _disposed) return Future.value(null);
    final ready = _ready = Completer<SendPort?>();
    final generation = _generation;
    final output = _responses = ReceivePort();
    final errors = _errors = ReceivePort();
    final exits = _exits = ReceivePort();
    SendPort? readyPort;
    output.listen((dynamic value) {
      if (generation != _generation) return;
      if (value is SendPort) {
        _commands = readyPort = value;
        if (!ready.isCompleted) ready.complete(value);
      } else if (value is FdsnDisplayFrame) {
        if (value.revision != _revision) return;
        lastFrame = value;
        onFrame?.call(value);
      } else if (value is int) {
        _pending.remove(value)?.complete();
      } else if (value is (int, String)) {
        _pending.remove(value.$1)?.completeError(StateError(value.$2));
      }
    });
    void failed(Object error) {
      if (generation != _generation) return;
      final sources = _sources, limit = _limit;
      onError?.call(error);
      stop();
      if (!_disposed && !testMode) {
        _retry = Timer(const Duration(seconds: 2), () {
          unawaited(connect(stationLimit: limit, sources: sources));
        });
      }
    }

    errors.listen(
      (dynamic error) => failed(StateError('FDSN data owner: $error')),
    );
    exits.listen((_) => failed(StateError('FDSN data owner exited')));
    unawaited(
      Isolate.spawn(
        _fdsnMain,
        (output.sendPort, testMode),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: 'fdsn-realtime-data-owner',
      ).then((isolate) {
        if (generation != _generation) {
          if (readyPort != null) {
            readyPort!.send('close');
          } else {
            isolate.kill(priority: Isolate.immediate);
          }
        } else {
          _isolate = isolate;
        }
      }, onError: (Object error) => failed(error)),
    );
    return ready.future;
  }

  void stop() {
    _retry?.cancel();
    _retry = null;
    _running = false;
    _generation++;
    if (identical(active, this)) active = null;
    if (_commands != null) {
      _commands!.send('close');
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
    if (_ready case final ready? when !ready.isCompleted) ready.complete(null);
    _responses?.close();
    _errors?.close();
    _exits?.close();
    _commands = null;
    _isolate = null;
    _ready = null;
    _responses = _errors = _exits = null;
    for (final pending in _pending.values) {
      pending.complete();
    }
    _pending.clear();
    lastFrame = null;
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}

void _fdsnMain((SendPort, bool) config) {
  final (output, testing) = config;
  final input = ReceivePort();
  final owner = _FdsnDataOwner(output);
  input.listen((dynamic message) {
    if (message == 'close') {
      owner.close();
      input.close();
      Isolate.exit();
    }
    if (message is (String, (int, int, Set<String>))) {
      final (revision, limit, sources) = message.$2;
      owner.configure(revision, limit, sources, testing: testing);
    } else if (message
        is (int, List<FdsnStation>?, FdsnMotionSample?, DateTime?)) {
      try {
        if (!testing) throw StateError('Fixture input in a live owner');
        owner.displayClock = message.$4;
        if (message.$2 case final metadata? when metadata.isNotEmpty) {
          owner.setStations(metadata.first.source, metadata);
        }
        if (message.$3 case final sample?) owner.accept(sample);
        owner.flush();
        output.send(message.$1);
      } catch (error) {
        output.send((message.$1, error.toString()));
      }
    }
  });
  output.send(input.sendPort);
}

class _FdsnDataOwner {
  _FdsnDataOwner(this.output) {
    motion.onStatusChanged = (value) => connected = value;
    samples = motion.sampleStream.listen(accept);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => flush());
  }
  final SendPort output;
  final motion = FdsnMotionService();
  DateTime? displayClock;
  late final store = FdsnMapStationStore(
    clock: () => displayClock ?? DateTime.now(),
  );
  final subscriptions = <String, StreamSubscription<List<FdsnStation>>>{};
  late final StreamSubscription<FdsnMotionSample> samples;
  late final Timer timer;
  final latest = <String, FdsnMotionSample>{};
  final pending = <String, FdsnMotionSample>{};
  final measured = <String, FdsnMotionSample>{};
  final received = <String, DateTime>{};
  final lastUiUpdate = <String, DateTime>{};
  Set<String> sources = const {};
  List<FdsnStation>? previousViews;
  int revision = 0, limit = 300;
  bool connected = false;

  void configure(
    int version,
    int count,
    Set<String> enabled, {
    required bool testing,
  }) {
    revision = version;
    limit = count;
    sources = enabled;
    previousViews = null;
    for (final entry in FdsnStationService.sources.entries) {
      if (sources.contains(entry.key)) {
        if (!testing && !subscriptions.containsKey(entry.key)) {
          subscriptions[entry.key] = entry.value.stationStream.listen(
            (stations) => setStations(entry.key, stations),
          );
          unawaited(entry.value.start());
        }
      } else {
        unawaited(subscriptions.remove(entry.key)?.cancel());
        entry.value.stop();
        store.removeSource(entry.key);
      }
    }
    if (!testing) motion.connect(stationLimit: limit, enabledSources: sources);
    flush();
  }

  void setStations(String source, List<FdsnStation> stations) {
    if (!sources.contains(source)) return;
    store.setSource(source, [
      for (final station in stations)
        if (latest['$source:${station.code}'] case final sample?)
          station.copyWith(
            pga: sample.pga,
            pgv: sample.pgv,
            intensity: sample.intensity,
            lastMotionUpdate: sample.timestamp,
            sensorType: sample.hasMeasurement ? sample.sensorType : null,
            activity: sample.activity,
          )
        else
          station,
    ]);
  }

  void accept(FdsnMotionSample sample) {
    if (!sources.contains(sample.source) ||
        (!sample.hasMeasurement && !sample.active)) {
      return;
    }
    final key = '${sample.source}:${sample.code}';
    final previous = latest[key];
    if (previous != null && sample.timestamp.isBefore(previous.timestamp)) {
      return;
    }
    if (!sample.hasMeasurement &&
        sample.activity == null &&
        previous?.hasMeasurement == true) {
      return;
    }
    if (sample.hasMeasurement) measured[key] = sample;
    if (!sample.hasMeasurement && previous?.hasMeasurement == true) {
      sample = FdsnMotionSample(
        source: sample.source,
        network: sample.network,
        station: sample.station,
        channel: sample.channel,
        timestamp: sample.timestamp,
        active: sample.active,
        activity: sample.activity,
        pga: previous!.pga,
        pgv: previous.pgv,
        intensity: previous.intensity,
        sensorType: previous.sensorType,
      );
    }
    latest[key] = pending[key] = sample;
    received[key] = DateTime.now();
  }

  void flush() {
    final automation = <ObsStationInputSample>[
      for (final sample in measured.values)
        ObsStationInputSample(
          stationId: sample.code,
          stationName: sample.code,
          active: sample.active,
          intensityLevel: sample.intensity?.floor() ?? -1,
          intensity: sample.intensity,
          observedAt: sample.timestamp,
          strong: (sample.intensity?.floor() ?? -1) >= 5,
        ),
    ];
    measured.clear();
    for (final entry in pending.entries) {
      final sample = entry.value;
      final station = store.find(sample.source, sample.code);
      if (station == null) continue;
      final now = received[entry.key]!;
      final same =
          station.pga == (sample.pga ?? station.pga) &&
          station.pgv == (sample.pgv ?? station.pgv) &&
          station.intensity == (sample.intensity ?? station.intensity) &&
          (!sample.hasMeasurement || station.sensorType == sample.sensorType) &&
          station.activity == (sample.activity ?? station.activity);
      final last = lastUiUpdate[entry.key];
      if (same &&
          station.lastMotionUpdate != null &&
          last != null &&
          now.difference(last) < const Duration(seconds: 10)) {
        continue;
      }
      lastUiUpdate[entry.key] = now;
      store.update(
        station.copyWith(
          pga: sample.pga,
          pgv: sample.pgv,
          intensity: sample.intensity,
          lastMotionUpdate: sample.timestamp,
          sensorType: sample.hasMeasurement ? sample.sensorType : null,
          activity: sample.activity,
        ),
      );
    }
    pending.clear();
    final views = store.displayStations(sources);
    output.send(
      FdsnDisplayFrame(
        revision: revision,
        stations: identical(views, previousViews) ? null : views,
        automation: automation,
        statuses: motion.sourceStatusesNotifier.value,
        linked: motion.linkedStationCountNotifier.value,
        limit: limit,
        dataTime: motion.dataTimeNotifier.value,
        connected: connected,
        connections: motion.connectionSnapshot,
        processingIsolate: Isolate.current.debugName,
      ),
    );
    previousViews = views;
  }

  void close() {
    timer.cancel();
    unawaited(samples.cancel());
    for (final subscription in subscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final service in FdsnStationService.sources.values) {
      service.stop();
    }
    motion.dispose();
    store.clear();
  }
}
