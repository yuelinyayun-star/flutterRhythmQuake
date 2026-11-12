import 'dart:async';
import 'dart:isolate';

import '../../models/snet_station.dart';
import '../../services/debug/ui_peak_profiler.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/kma_monitor.dart';
import '../../services/sources/lpgm_monitor_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/palert_service.dart';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/shake_detection_service.dart';
import '../ui/station_dashboard.dart';
import 'station_summary_projection.dart';

class StationSummaryRequest {
  const StationSummaryRequest({
    required this.nied,
    required this.kma,
    required this.cwa,
    required this.palert,
    required this.seisjs,
    required this.snet,
    required this.detection,
    required this.lpgm,
    required this.windowEnd,
    this.changed,
    this.seisjsSummary,
    this.palertSummary,
  });
  final List<NiedStation> nied;
  final List<KmaStation> kma;
  final List<CwaStation> cwa;
  final List<PAlertStation> palert;
  final List<SeisJsStation> seisjs;
  final List<SnetStation> snet;
  final ShakeDetectionSnapshot detection;
  final LpgmSnapshot? lpgm;
  final DateTime windowEnd;
  final Set<String>? changed;
  final SeisJsPreparedSummary? seisjsSummary;
  final PAlertPreparedSummary? palertSummary;
}

/// Full summary owner: native buffers/catalogues, maxima, regions, rankings,
/// selected station views and display change signatures never run in the UI.
class StationSummaryWorker {
  StationSummaryWorker() {
    _start();
  }
  Isolate? _isolate;
  SendPort? _commands;
  late final ReceivePort _responses, _errors, _exits, _staging;
  final _pending = <int, Completer<StationSummaryData?>>{};
  final _startupQueue = <(int, StationSummaryRequest)>[];
  int _nextId = 0;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  Future<StationSummaryData?> project(StationSummaryRequest request) {
    if (_disposed) return Future.value(null);
    final id = _nextId++;
    final done = Completer<StationSummaryData?>();
    _pending[id] = done;
    // SendPort snapshots before returning. Only startup needs an owned staging
    // copy; input objects cannot change while the worker's ready port arrives.
    final message = (id, request);
    if (_commands case final commands?) {
      commands.send(message);
    } else {
      _staging.sendPort.send(message);
    }
    return done.future;
  }

  void _start() {
    _responses = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    _staging = ReceivePort();
    _staging.listen((dynamic message) {
      if (_disposed) return;
      if (_commands case final commands?) {
        commands.send(message);
      } else {
        _startupQueue.add(message as (int, StationSummaryRequest));
      }
    });
    _responses.listen((dynamic message) {
      if (_disposed) return;
      if (message is SendPort) {
        _commands = message;
        for (final request in _startupQueue) {
          message.send(request);
        }
        _startupQueue.clear();
      } else if (message is (int, StationSummaryData)) {
        _pending.remove(message.$1)?.complete(message.$2);
      } else if (message is (int, String)) {
        _pending.remove(message.$1)?.completeError(StateError(message.$2));
      }
    });
    void failed(Object error) {
      if (_disposed) return;
      for (final pending in _pending.values) {
        pending.completeError(error);
      }
      _pending.clear();
      dispose();
    }

    _errors.listen(
      (dynamic error) => failed(StateError('Station summary owner: $error')),
    );
    _exits.listen((_) => failed(StateError('Station summary owner exited')));
    unawaited(
      Isolate.spawn(
        _summaryMain,
        _responses.sendPort,
        onError: _errors.sendPort,
        onExit: _exits.sendPort,
        debugName: 'station-summary-data-owner',
      ).then((isolate) {
        if (_disposed) {
          isolate.kill(priority: Isolate.immediate);
        } else {
          _isolate = isolate;
        }
      }, onError: (Object error) => failed(error)),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_commands != null) {
      _commands!.send('close');
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
    _responses.close();
    _errors.close();
    _exits.close();
    _staging.close();
    _startupQueue.clear();
    for (final pending in _pending.values) {
      pending.complete(null);
    }
    _pending.clear();
    _commands = null;
    _isolate = null;
  }
}

void _summaryMain(SendPort output) {
  final input = ReceivePort();
  final projection = StationSummaryProjection();
  List<NiedStation> nied = const [];
  List<KmaStation> kma = const [];
  List<CwaStation> cwa = const [];
  List<PAlertStation> palert = const [];
  List<SeisJsStation> seisjs = const [];
  SeisJsPreparedSummary? seisjsSummary;
  PAlertPreparedSummary? palertSummary;
  List<SnetStation> snet = const [];
  LpgmSnapshot? lpgm;
  StationSummaryData timedProject(StationSummaryRequest r) {
    UiPeakProfiler.begin('worker.project');
    try {
      return projection.project(
        nied: nied,
        kma: kma,
        cwa: cwa,
        palert: palert,
        palertSummary: palertSummary,
        seisjs: seisjs,
        seisjsSummary: seisjsSummary,
        snet: snet,
        detection: r.detection,
        lpgm: lpgm,
        windowEnd: r.windowEnd,
        changed: r.changed,
      );
    } finally {
      UiPeakProfiler.end('worker.project');
    }
  }

  input.listen((dynamic message) {
    if (message == 'close') {
      projection.dispose();
      input.close();
      Isolate.exit();
    }
    final (id, r) = message as (int, StationSummaryRequest);
    try {
      bool update(String source) =>
          r.changed == null || r.changed!.contains(source);
      if (update('nied')) nied = r.nied;
      if (update('kma')) kma = r.kma;
      if (update('cwa')) cwa = r.cwa;
      if (update('palert')) {
        palert = r.palert;
        palertSummary = r.palertSummary;
      }
      if (update('seisjs')) {
        seisjs = r.seisjs;
        seisjsSummary = r.seisjsSummary;
      }
      if (update('snet')) snet = r.snet;
      if (update('lpgm')) lpgm = r.lpgm;
      final result = timedProject(r);
      result.processingIsolate = Isolate.current.debugName;
      result.preparedDetectUiSignature = _detectSignature(result.niedDetect);
      result.preparedUiSignature = _uiSignature(result);
      output.send((id, result));
    } catch (error) {
      output.send((id, error.toString()));
    }
  });
  output.send(input.sendPort);
}

String _detectSignature(NiedDetectSummary? detect) {
  if (detect == null) return '-';
  final prefs = <String, int>{};
  final areas = detect.visualAreas;
  if (areas.isNotEmpty) {
    for (final area in areas) {
      if (area.jmaShindo > (prefs[area.name] ?? -1)) {
        prefs[area.name] = area.jmaShindo;
      }
    }
  } else {
    for (final station in detect.detectedStations) {
      final name = station.prefecture.isEmpty
          ? station.code
          : station.prefecture;
      if (station.jmaShindo > (prefs[name] ?? -1)) {
        prefs[name] = station.jmaShindo;
      }
    }
  }
  final signature =
      (prefs.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((entry) => '${entry.key}:${entry.value}')
          .join(',');
  return [
    detect.stage,
    detect.weakCount,
    detect.detectedCount,
    detect.strongCount,
    detect.maxShindo,
    detect.visualGridCount,
    areas.isEmpty ? prefs.length : areas.length,
    signature,
  ].join(',');
}

String _uiSignature(StationSummaryData data) {
  String hm(DateTime? time) => time == null
      ? '-'
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  final top = data.snetTopStations
      .map((s) => '${s.code}:${s.jmaIndex}:${s.shindo.toStringAsFixed(3)}')
      .join(',');
  final snet = [
    hm(data.snetWindowStart),
    hm(data.snetWindowEnd),
    top,
  ].join(',');
  return [
    data.seisJsStation?.shindo ?? -1,
    data.seisJsStation?.maxIntensity.toStringAsFixed(2) ?? '-',
    data.seisJsStation?.pga.toStringAsFixed(1) ?? '-',
    data.seisJsMaxStation?.intensity.toStringAsFixed(2) ?? '-',
    data.niedMaxStation?.level ?? -1,
    data.treaMaxStation?.currentIntensity.toStringAsFixed(1) ?? '-',
    data.kmaMaxStation?.intensity ?? -3,
    data.snetTopStations.isEmpty ? -1 : data.snetTopStations.first.jmaIndex,
    data.pAlertMaxStation?.shindoClass ?? -1,
    data.preparedDetectUiSignature,
    snet,
    data.lpgmMaxSva?.toStringAsFixed(3) ?? '-',
    data.lpgmMaxClass ?? -1,
  ].join('|');
}
