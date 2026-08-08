import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

import 'shindo_color_util.dart';
import 'nied_detection_rules.dart';

class NiedScanConfig {
  final int pixelX;
  final int pixelY;

  const NiedScanConfig({required this.pixelX, required this.pixelY});
}

class NiedPixelSample {
  final double? surfacePosition;

  const NiedPixelSample({required this.surfacePosition});
}

class NiedFrameScanResult {
  final int width;
  final int height;
  final List<NiedPixelSample> samples;

  const NiedFrameScanResult({
    required this.width,
    required this.height,
    required this.samples,
  });
}

class NiedDetectionInput {
  final int kaLevel;
  final double activity;
  final int ascend;
  final bool isActive;
  final double continuousShindo;
  final int triggerStamp;

  const NiedDetectionInput({
    required this.kaLevel,
    required this.activity,
    required this.ascend,
    required this.isActive,
    this.continuousShindo = 0,
    this.triggerStamp = 0,
  });
}

class NiedDetectionResult {
  final List<int> activeIndices;
  final int? strongestIndex;

  const NiedDetectionResult({
    required this.activeIndices,
    required this.strongestIndex,
  });
}

class NiedBackgroundWorker {
  NiedBackgroundWorker._();

  static final NiedBackgroundWorker instance = NiedBackgroundWorker._();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Future<void>? _starting;
  int _nextRequestId = 1;
  final Map<int, Completer<Object?>> _pending = {};
  String _scanConfigSignature = '';
  String _detectorConfigSignature = '';

  bool get supported => !kIsWeb;

  /// 释放后台 isolate 及其台站配置缓存；下次请求时会按需重建。
  void stop() {
    _reset();
  }

  Future<NiedFrameScanResult?> scanFrame({
    required Uint8List surfaceBytes,
    required List<NiedScanConfig> configs,
    required String configSignature,
  }) async {
    if (!supported) return null;
    try {
      await _ensureStarted();
      if (_scanConfigSignature != configSignature) {
        await _request('configureScan', {
          'configs': [
            for (final config in configs) [config.pixelX, config.pixelY],
          ],
        });
        _scanConfigSignature = configSignature;
      }
      final response = await _request('scanFrame', {
        'surface': TransferableTypedData.fromList([surfaceBytes]),
      });
      if (response is! Map) return null;
      final packed = response['samples'];
      if (packed is! TransferableTypedData) return null;
      final values = packed.materialize().asFloat64List();
      if (values.length != configs.length) return null;
      final samples = <NiedPixelSample>[];
      for (var i = 0; i < configs.length; i++) {
        samples.add(
          NiedPixelSample(surfacePosition: _finitePosition(values[i])),
        );
      }
      return NiedFrameScanResult(
        width: response['width'] as int? ?? 0,
        height: response['height'] as int? ?? 0,
        samples: samples,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<int>?> configureDetector({
    required String signature,
    required List<List<Object?>> stations,
  }) async {
    if (!supported) return null;
    try {
      await _ensureStarted();
      if (_detectorConfigSignature == signature) return const [];
      final response = await _request('configureDetector', {
        'stations': stations,
      });
      if (response is! List) return null;
      _detectorConfigSignature = signature;
      return response.cast<int>();
    } catch (_) {
      return null;
    }
  }

  Future<NiedDetectionResult?> detect({
    required List<NiedDetectionInput> stations,
    required int sensitivity,
    required bool hadActiveGrid,
  }) async {
    if (!supported) return null;
    try {
      await _ensureStarted();
      final response = await _request('detect', {
        'stations': [
          for (final station in stations)
            [
              station.kaLevel,
              station.activity,
              station.ascend,
              station.isActive,
              station.continuousShindo,
              station.triggerStamp,
            ],
        ],
        'sensitivity': sensitivity,
        'hadActiveGrid': hadActiveGrid,
      });
      if (response is! Map) return null;
      return NiedDetectionResult(
        activeIndices:
            (response['activeIndices'] as List?)?.cast<int>() ?? const [],
        strongestIndex: response['strongestIndex'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureStarted() async {
    if (_sendPort != null) return;
    final starting = _starting;
    if (starting != null) return starting;
    final completer = Completer<void>();
    _starting = completer.future;
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen(_handleMessage);
    try {
      _isolate = await Isolate.spawn(_niedWorkerMain, receivePort.sendPort);
      await _waitForSendPort();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      _reset();
      rethrow;
    } finally {
      _starting = null;
    }
  }

  Future<void> _waitForSendPort() async {
    if (_sendPort != null) return;
    final completer = Completer<void>();
    late StreamSubscription<dynamic> subscription;
    final port = ReceivePort();
    subscription = port.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete();
        subscription.cancel();
        port.close();
      }
    });
    _sendPort ??= await _firstSendPortMessage();
    if (!completer.isCompleted) {
      completer.complete();
      await subscription.cancel();
      port.close();
    }
  }

  Future<SendPort> _firstSendPortMessage() {
    final completer = Completer<SendPort>();
    void poll() {
      final port = _sendPort;
      if (port != null) {
        completer.complete(port);
      } else {
        Timer(const Duration(milliseconds: 1), poll);
      }
    }

    poll();
    return completer.future;
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      return;
    }
    if (message is! Map) return;
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = message['error'];
    if (error != null) {
      completer.completeError(StateError(error.toString()));
    } else {
      completer.complete(message['result']);
    }
  }

  Future<Object?> _request(String command, Map<String, Object?> payload) {
    final sendPort = _sendPort;
    if (sendPort == null) {
      return Future<Object?>.error(StateError('NIED worker is not ready'));
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    sendPort.send({'id': id, 'command': command, ...payload});
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('NIED worker request timed out: $command');
      },
    );
  }

  void _reset() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('NIED worker stopped'));
      }
    }
    _pending.clear();
    _scanConfigSignature = '';
    _detectorConfigSignature = '';
  }

  static double? _finitePosition(double value) =>
      value.isFinite && value >= 0 ? value : null;
}

void _niedWorkerMain(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);
  final state = _NiedWorkerState();
  receivePort.listen((dynamic message) {
    if (message is! Map) return;
    final id = message['id'];
    if (id is! int) return;
    try {
      final result = state.handle(message);
      mainPort.send({'id': id, 'result': result});
    } catch (error) {
      mainPort.send({'id': id, 'error': error.toString()});
    }
  });
}

class _NiedWorkerState {
  static const int _nearbyLength = niedNearbyStationLimit;
  static const double _denseNearbyKm = 30.0;
  static const double _sparseFallbackNearbyKm = 40.0;
  List<List<Object?>> _scanConfigs = const [];
  List<_DetectorStationConfig> _detectorConfigs = const [];
  List<List<int>> _adjacentStationIds = const [];

  Object? handle(Map<dynamic, dynamic> message) {
    switch (message['command']) {
      case 'configureScan':
        _scanConfigs =
            (message['configs'] as List?)?.cast<List<Object?>>() ?? const [];
        return true;
      case 'scanFrame':
        return _scanFrame(message);
      case 'configureDetector':
        return _configureDetector(message);
      case 'detect':
        return _detect(message);
      default:
        throw StateError('Unknown NIED worker command: ${message['command']}');
    }
  }

  Map<String, Object?> _scanFrame(Map<dynamic, dynamic> message) {
    final surfaceBytes = (message['surface'] as TransferableTypedData)
        .materialize()
        .asUint8List();
    final surface = image_lib.decodeImage(surfaceBytes);
    if (surface == null) throw StateError('Unable to decode NIED surface GIF');

    final values = Float64List(_scanConfigs.length);
    for (var i = 0; i < _scanConfigs.length; i++) {
      final config = _scanConfigs[i];
      final x = config[0] as int;
      final y = config[1] as int;
      values[i] = _samplePosition(surface, x, y) ?? double.nan;
    }
    return {
      'width': surface.width,
      'height': surface.height,
      'samples': TransferableTypedData.fromList([values.buffer.asUint8List()]),
    };
  }

  double? _samplePosition(image_lib.Image image, int x, int y) {
    if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
      return null;
    }
    final pixel = image.getPixel(x, y);
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final shindo = ShindoColorUtil.rgbaToShindo(r, g, b);
    if (shindo == null) return null;
    return ShindoColorUtil.rgbaToPosition(r, g, b);
  }

  List<int> _configureDetector(Map<dynamic, dynamic> message) {
    final source = (message['stations'] as List?) ?? const [];
    _detectorConfigs = [
      for (final row in source)
        if (row is List)
          _DetectorStationConfig(
            id: row[0] as int,
            latitude: (row[1] as num).toDouble(),
            longitude: (row[2] as num).toDouble(),
            clusterKey: row[3] as String,
          ),
    ];
    _buildAdjacency();
    return List<int>.filled(_adjacentStationIds.length, 10);
  }

  Map<String, Object?> _detect(Map<dynamic, dynamic> message) {
    final rows = (message['stations'] as List?) ?? const [];
    if (rows.length != _detectorConfigs.length) {
      throw StateError('NIED detector station count changed');
    }
    final states = [
      for (final row in rows)
        if (row is List)
          _DetectorStationState(
            kaLevel: row[0] as int,
            activity: (row[1] as num).toDouble(),
            ascend: row[2] as int,
            isActive: row[3] as bool,
            continuousShindo: (row[4] as num).toDouble(),
            triggerStamp: row[5] as int,
          ),
    ];
    final sensitivity = message['sensitivity'] as int? ?? 2;
    final possibleStations = <int>[
      for (var i = 0; i < states.length; i++)
        if (states[i].activity > 0) i,
    ];
    final dedupedPossibleStations = _dedupe(possibleStations, states);
    final activeStations = <int>{};
    final checkedStations = <int>{};
    final stationPairAbnormalCache = <String, bool>{};

    bool hasAbnormalStationPair(List<int> stationIds) {
      for (var i = 0; i < stationIds.length - 1; i++) {
        for (var j = i + 1; j < stationIds.length; j++) {
          final firstId = stationIds[i];
          final secondId = stationIds[j];
          final lowId = math.min(firstId, secondId);
          final highId = math.max(firstId, secondId);
          final key = '$lowId-$highId';
          final isAbnormal = stationPairAbnormalCache.putIfAbsent(
            key,
            () => isNiedAbnormalStationPair(
              firstTriggerStamp: states[firstId].triggerStamp,
              secondTriggerStamp: states[secondId].triggerStamp,
              distanceKm: _haversine(
                _detectorConfigs[firstId],
                _detectorConfigs[secondId],
              ),
            ),
          );
          if (isAbnormal) return true;
        }
      }
      return false;
    }

    for (final index in dedupedPossibleStations) {
      final station = states[index];
      if (checkedStations.contains(index)) continue;
      if (station.isActive && station.ascend > 0) {
        _chainActivate(index, states, activeStations, checkedStations);
        continue;
      }

      final nearbyStationIds = _dedupe(
        _adjacentStationIds[index]
            .where((id) => states[id].kaLevel > -1)
            .toList(growable: false),
        states,
      );
      if (nearbyStationIds.isEmpty) continue;
      final possibleNearbyStationIds = _dedupe(
        nearbyStationIds
            .where((id) => states[id].activity > 0)
            .toList(growable: false),
        states,
      );
      final weakRiseCount = possibleNearbyStationIds
          .where((id) => states[id].ascend <= 1 && !states[id].isActive)
          .length;
      final nearbyActiveNum =
          possibleNearbyStationIds.length - weakRiseCount / 2.0;
      final nearbyCount = nearbyStationIds.length.clamp(0, _nearbyLength);
      final numThreshold = niedStationCountThreshold(sensitivity, nearbyCount);
      var activityThreshold = niedActivityThreshold(sensitivity, nearbyCount);
      if (nearbyActiveNum < numThreshold) continue;

      final abnormalCandidates = nearbyStationIds
          .where((id) => !states[id].isActive && states[id].ascend > 2)
          .toList(growable: false);
      if (hasAbnormalStationPair(abnormalCandidates)) {
        activityThreshold *= 2;
      }
      var nearbyActivity = nearbyActiveNum * (nearbyActiveNum + 1) / 2.0;
      for (final nearbyId in nearbyStationIds) {
        nearbyActivity += states[nearbyId].activity;
      }
      if (nearbyActivity >= activityThreshold) {
        _chainActivate(index, states, activeStations, checkedStations);
      }
    }

    int? strongestIndex;
    if (message['hadActiveGrid'] != true && activeStations.isNotEmpty) {
      strongestIndex = activeStations.reduce(
        (a, b) => states[a].kaLevel >= states[b].kaLevel ? a : b,
      );
    }
    final sorted = activeStations.toList()..sort();
    return {'activeIndices': sorted, 'strongestIndex': strongestIndex};
  }

  void _buildAdjacency() {
    final count = _detectorConfigs.length;
    _adjacentStationIds = List.generate(count, (_) => <int>[]);
    for (var i = 0; i < count; i++) {
      final distances = <({int id, double distance})>[];
      ({int id, double distance})? fallback;
      for (var j = 0; j < count; j++) {
        final distance = i == j
            ? 0.0
            : _haversine(_detectorConfigs[i], _detectorConfigs[j]);
        if (distance <= _denseNearbyKm) {
          distances.add((id: j, distance: distance));
        } else if (distance <= _sparseFallbackNearbyKm &&
            (fallback == null || distance <= fallback.distance)) {
          fallback = (id: j, distance: distance);
        }
      }
      if (distances.length <= 1 && fallback != null) distances.add(fallback);
      distances.sort((a, b) => a.distance.compareTo(b.distance));
      if (distances.length > _nearbyLength) {
        distances.removeRange(_nearbyLength, distances.length);
      }
      _adjacentStationIds[i] = [for (final distance in distances) distance.id];
    }
  }

  void _chainActivate(
    int startIndex,
    List<_DetectorStationState> states,
    Set<int> activeStations,
    Set<int> checkedStations,
  ) {
    final pending = <int>{startIndex};
    while (pending.isNotEmpty) {
      final current = pending.first;
      pending.remove(current);
      checkedStations.add(current);
      if (states[current].activity <= 0) continue;
      activeStations.add(current);
      final neighbors = _dedupe(_adjacentStationIds[current], states);
      for (final neighbor in neighbors) {
        if (!checkedStations.contains(neighbor)) pending.add(neighbor);
      }
    }
  }

  List<int> _dedupe(List<int> stationIds, List<_DetectorStationState> states) {
    if (stationIds.length <= 1) return stationIds;
    final bestByCluster = <String, int>{};
    final order = <String>[];
    for (final id in stationIds) {
      final key = _detectorConfigs[id].clusterKey;
      final current = bestByCluster[key];
      if (current == null) {
        bestByCluster[key] = id;
        order.add(key);
      } else {
        bestByCluster[key] = _prefer(current, id, states);
      }
    }
    return [for (final key in order) bestByCluster[key]!];
  }

  int _prefer(
    int currentId,
    int candidateId,
    List<_DetectorStationState> states,
  ) {
    final current = states[currentId];
    final candidate = states[candidateId];
    if (candidate.kaLevel != current.kaLevel) {
      return candidate.kaLevel > current.kaLevel ? candidateId : currentId;
    }
    if (candidate.activity != current.activity) {
      return candidate.activity > current.activity ? candidateId : currentId;
    }
    if (candidate.ascend != current.ascend) {
      return candidate.ascend > current.ascend ? candidateId : currentId;
    }
    if (candidate.continuousShindo != current.continuousShindo) {
      return candidate.continuousShindo > current.continuousShindo
          ? candidateId
          : currentId;
    }
    return _detectorConfigs[candidateId].id < _detectorConfigs[currentId].id
        ? candidateId
        : currentId;
  }

  double _haversine(_DetectorStationConfig a, _DetectorStationConfig b) {
    const radius = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h =
        sinLat * sinLat + sinLng * sinLng * math.cos(lat1) * math.cos(lat2);
    return 2 * radius * math.asin(math.sqrt(h));
  }

  double _toRad(double degrees) => degrees * 0.017453292519943295;
}

class _DetectorStationConfig {
  final int id;
  final double latitude;
  final double longitude;
  final String clusterKey;

  const _DetectorStationConfig({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.clusterKey,
  });
}

class _DetectorStationState {
  final int kaLevel;
  final double activity;
  final int ascend;
  final bool isActive;
  final double continuousShindo;
  final int triggerStamp;

  const _DetectorStationState({
    required this.kaLevel,
    required this.activity,
    required this.ascend,
    required this.isActive,
    required this.continuousShindo,
    required this.triggerStamp,
  });
}
