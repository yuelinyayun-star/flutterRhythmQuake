import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import '../../models/station_history_frame.dart';
import '../../models/snet_station.dart';
import '../foreground_station_payload.dart';
import '../sources/nied_monitor.dart';
import '../sources/kma_monitor.dart';
import '../sources/cwa_station_service.dart';
import '../sources/palert_service.dart';
import '../sources/palert_detection_grid.dart';
import '../sources/seisjs_service.dart';
import '../sources/lpgm_monitor_service.dart';
import '../sources/shake_detection_service.dart';
import 'package:latlong2/latlong.dart';

/// Playback-only objects, never fed to live detectors, sockets or automation.
class ReplayStationDisplay {
  final _niedDecoder = _ReplayNiedDisplayDecoder();
  final _frames = <String, StationHistoryFrame>{};
  List<NiedStation> nied = const [];
  List<KmaStation> kma = const [];
  List<CwaStation> cwa = const [];
  List<SnetStation> snet = const [];
  List<SeisJsStation> seisjs = const [];
  List<PAlertStation> palert = const [];
  List<PAlertDetectionGridCell> palertGrid = const [];
  LpgmSnapshot? lpgm;
  ShakeDetectionSnapshot niedDetection = _idleDetection;
  static const _idleDetection = ShakeDetectionSnapshot(
    stage: ShakeDetectStage.idle,
    weakCount: 0,
    detectedCount: 0,
    strongCount: 0,
    maxShindo: -1,
  );

  Set<String> update(
    Map<String, StationHistoryFrame> frames, {
    bool decodeNied = true,
  }) {
    if (frames.isEmpty) {
      final changed = _frames.keys.toSet();
      _frames.clear();
      nied = const [];
      kma = const [];
      cwa = const [];
      snet = const [];
      seisjs = const [];
      palert = const [];
      palertGrid = const [];
      lpgm = null;
      niedDetection = _idleDetection;
      return changed;
    }
    final changed = <String>{};
    for (final entry in frames.entries) {
      if (identical(_frames[entry.key], entry.value)) continue;
      changed.add(entry.key);
      if (entry.key == 'nied' && !decodeNied) continue;
      _frames[entry.key] = entry.value;
      final snapshot = entry.value.snapshot;
      final stations = snapshot['stations'];
      switch (entry.key) {
        case 'nied':
          nied = ForegroundStationPayload.decodeNied(stations);
          final detection = snapshot['detection'];
          if (detection is Map) {
            final cells = detection['gridCells'] as Map? ?? const {};
            niedDetection = ShakeDetectionSnapshot(
              stage: ShakeDetectStage.values.firstWhere(
                (s) => s.name == detection['stage'],
                orElse: () => ShakeDetectStage.idle,
              ),
              weakCount: detection['weakCount'] as int,
              detectedCount: detection['detectedCount'] as int,
              strongCount: detection['strongCount'] as int,
              maxShindo: detection['maxShindo'] as int,
              gridCells: {
                for (final entry in cells.entries)
                  entry.key as String: NiedDetectionGridCell(
                    center: LatLng(
                      (entry.value['lat'] as num).toDouble(),
                      (entry.value['lng'] as num).toDouble(),
                    ),
                    level: entry.value['level'] as int,
                    shindo: (entry.value['shindo'] as num).toDouble(),
                  ),
              },
              detectedStations: [
                for (final station in detection['detectedStations'] as List)
                  DetectedStationEntry(
                    code: station['code'] as String,
                    prefecture: station['prefecture'] as String,
                    level: station['level'] as int,
                    jmaShindo: station['jmaShindo'] as int,
                    detectState: station['detectState'] as int,
                    detectReason: station['detectReason'] as String,
                  ),
              ],
            );
          } else {
            niedDetection = _idleDetection;
          }
        case 'kma':
          kma = ForegroundStationPayload.decodeKma(stations);
        case 'cwa':
          cwa = ForegroundStationPayload.decodeCwa(stations);
        case 'snet':
          snet = ForegroundStationPayload.decodeSnet(stations);
        case 'seisjs':
          seisjs = ForegroundStationPayload.decodeSeisJs(stations);
        case 'palert':
          palert = ForegroundStationPayload.decodePAlert(stations);
          palertGrid = ForegroundStationPayload.decodePAlertDetection(
            snapshot,
            now: entry.value.receivedAt,
          );
        case 'lpgm':
          lpgm = ForegroundStationPayload.decodeLpgm(snapshot);
      }
    }
    return changed;
  }

  Future<ReplayNiedDisplayFrame> decodeNied(StationHistoryFrame frame) =>
      _niedDecoder.decode(frame);

  void applyNied(StationHistoryFrame frame, ReplayNiedDisplayFrame decoded) {
    _frames['nied'] = frame;
    nied = decoded.stations;
    niedDetection = decoded.detection;
  }

  void dispose() => _niedDecoder.dispose();
}

class ReplayNiedDisplayFrame {
  final List<NiedStation> stations;
  final ShakeDetectionSnapshot detection;

  const ReplayNiedDisplayFrame({
    required this.stations,
    required this.detection,
  });
}

ReplayNiedDisplayFrame _decodeReplayNiedFrame(StationHistoryFrame frame) {
  final snapshot = frame.snapshot;
  final stations = ForegroundStationPayload.decodeNied(snapshot['stations']);
  final detection = snapshot['detection'];
  if (detection is! Map) {
    return ReplayNiedDisplayFrame(
      stations: stations,
      detection: ReplayStationDisplay._idleDetection,
    );
  }
  final cells = detection['gridCells'] as Map? ?? const {};
  return ReplayNiedDisplayFrame(
    stations: stations,
    detection: ShakeDetectionSnapshot(
      stage: ShakeDetectStage.values.firstWhere(
        (stage) => stage.name == detection['stage'],
        orElse: () => ShakeDetectStage.idle,
      ),
      weakCount: detection['weakCount'] as int,
      detectedCount: detection['detectedCount'] as int,
      strongCount: detection['strongCount'] as int,
      maxShindo: detection['maxShindo'] as int,
      gridCells: {
        for (final entry in cells.entries)
          entry.key as String: NiedDetectionGridCell(
            center: LatLng(
              (entry.value['lat'] as num).toDouble(),
              (entry.value['lng'] as num).toDouble(),
            ),
            level: entry.value['level'] as int,
            shindo: (entry.value['shindo'] as num).toDouble(),
          ),
      },
      detectedStations: [
        for (final station in detection['detectedStations'] as List)
          DetectedStationEntry(
            code: station['code'] as String,
            prefecture: station['prefecture'] as String,
            level: station['level'] as int,
            jmaShindo: station['jmaShindo'] as int,
            detectState: station['detectState'] as int,
            detectReason: station['detectReason'] as String,
          ),
      ],
    ),
  );
}

class _ReplayNiedDisplayDecoder {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Completer<SendPort>? _starting;
  final _pending = <int, Completer<ReplayNiedDisplayFrame>>{};
  var _nextId = 0;
  var _disposed = false;

  Future<ReplayNiedDisplayFrame> decode(StationHistoryFrame frame) async {
    if (_disposed) throw StateError('Replay NIED decoder disposed');
    if (kIsWeb) return _decodeReplayNiedFrame(frame);
    final port = await _ensureStarted();
    if (_disposed) throw StateError('Replay NIED decoder disposed');
    final id = _nextId++;
    final completer = Completer<ReplayNiedDisplayFrame>();
    _pending[id] = completer;
    port.send({'id': id, 'frame': frame});
    return completer.future;
  }

  Future<SendPort> _ensureStarted() async {
    final current = _sendPort;
    if (current != null) return current;
    final pendingStart = _starting;
    if (pendingStart != null) return pendingStart.future;
    final start = Completer<SendPort>();
    _starting = start;
    final receive = ReceivePort();
    _receivePort = receive;
    receive.listen(_handleMessage);
    try {
      _isolate = await Isolate.spawn(
        _replayNiedDisplayWorker,
        receive.sendPort,
      );
      return await start.future;
    } catch (error, stackTrace) {
      if (!start.isCompleted) start.completeError(error, stackTrace);
      _starting = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      receive.close();
      _receivePort = null;
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      final start = _starting;
      _starting = null;
      if (start != null && !start.isCompleted) start.complete(message);
      return;
    }
    if (message is! Map) return;
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final result = message['result'];
    if (result is ReplayNiedDisplayFrame) {
      completer.complete(result);
    } else {
      completer.completeError(
        StateError('${message['error'] ?? 'Decode failed'}'),
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sendPort?.send(const {'command': 'close'});
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    final error = StateError('Replay NIED decoder disposed');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    final start = _starting;
    _starting = null;
    if (start != null && !start.isCompleted) start.completeError(error);
  }
}

void _replayNiedDisplayWorker(SendPort mainPort) {
  final receive = ReceivePort();
  mainPort.send(receive.sendPort);
  receive.listen((dynamic message) {
    if (message is! Map) return;
    if (message['command'] == 'close') {
      receive.close();
      Isolate.exit();
    }
    final id = message['id'];
    final frame = message['frame'];
    if (id is! int || frame is! StationHistoryFrame) return;
    try {
      mainPort.send({'id': id, 'result': _decodeReplayNiedFrame(frame)});
    } catch (error, stackTrace) {
      mainPort.send({'id': id, 'error': '$error\n$stackTrace'});
    }
  });
}
