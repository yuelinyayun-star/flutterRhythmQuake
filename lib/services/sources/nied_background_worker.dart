import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

import 'shindo_color_util.dart';

class NiedScanConfig {
  final int pixelX;
  final int pixelY;

  const NiedScanConfig({
    required this.pixelX,
    required this.pixelY,
  });
}

class NiedPixelSample {
  final int surfaceRawLevel;
  final double? surfacePosition;

  const NiedPixelSample({
    required this.surfaceRawLevel,
    required this.surfacePosition,
  });
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
  final int detectLevel;
  final double activity;
  final int ascend;
  final bool isActive;
  final double continuousShindo;

  const NiedDetectionInput({
    required this.detectLevel,
    required this.activity,
    required this.ascend,
    required this.isActive,
    this.continuousShindo = 0,
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
            for (final config in configs)
              [config.pixelX, config.pixelY],
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
      if (values.length != configs.length * 2) return null;
      final samples = <NiedPixelSample>[];
      for (var i = 0; i < configs.length; i++) {
        final offset = i * 2;
        samples.add(
          NiedPixelSample(
            surfaceRawLevel: values[offset].round(),
            surfacePosition: _finitePosition(values[offset + 1]),
          ),
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
              station.detectLevel,
              station.activity,
              station.ascend,
              station.isActive,
              station.continuousShindo,
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
  static const int _nearbyLength = 6;
  static const double _denseNearbyKm = 30.0;
  static const double _sparseFallbackNearbyKm = 40.0;
  static const List<double> _activityThresholds = [
    double.infinity,
    9,
    12,
    14,
    15,
    16,
    16,
  ];

  List<List<Object?>> _scanConfigs = const [];
  List<_DetectorStationConfig> _detectorConfigs = const [];
  List<List<int>> _adjacentStationIds = const [];
  List<List<double>> _distanceMatrix = const [];

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

    final values = Float64List(_scanConfigs.length * 2);
    for (var i = 0; i < _scanConfigs.length; i++) {
      final config = _scanConfigs[i];
      final x = config[0] as int;
      final y = config[1] as int;
      final surfaceSample = _sample(surface, x, y);
      final offset = i * 2;
      values[offset] = surfaceSample.rawLevel.toDouble();
      values[offset + 1] = surfaceSample.position ?? double.nan;
    }
    return {
      'width': surface.width,
      'height': surface.height,
      'samples': TransferableTypedData.fromList([values.buffer.asUint8List()]),
    };
  }

  _PixelSample _sample(image_lib.Image image, int x, int y) {
    if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
      return const _PixelSample(-1, null);
    }
    final pixel = image.getPixel(x, y);
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final shindo = ShindoColorUtil.rgbaToShindo(r, g, b);
    if (shindo == null) return const _PixelSample(-1, null);
    return _PixelSample(
      ShindoColorUtil.shindoToRawLevel(shindo),
      ShindoColorUtil.rgbaToPosition(r, g, b),
    );
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
    return [
      for (var i = 0; i < _adjacentStationIds.length; i++)
        math
            .max(
              (_adjacentStationIds[i].isEmpty
                      ? 0
                      : _adjacentStationIds[i]
                            .map((id) => _distanceMatrix[i][id])
                            .reduce(math.max)) /
                  3.5,
              5,
            )
            .round(),
    ];
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
            detectLevel: row[0] as int,
            activity: (row[1] as num).toDouble(),
            ascend: row[2] as int,
            isActive: row[3] as bool,
            continuousShindo: (row[4] as num).toDouble(),
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

    for (final index in dedupedPossibleStations) {
      final station = states[index];
      if (checkedStations.contains(index)) continue;
      if (station.isActive && station.ascend > 0) {
        _chainActivate(index, states, activeStations, checkedStations);
        continue;
      }

      final nearbyStationIds = _dedupe(
        _adjacentStationIds[index]
            .where((id) => states[id].detectLevel > -1)
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
      final numThreshold = switch (sensitivity) {
        1 => 3.0,
        2 => nearbyCount <= 2 ? (nearbyCount + 1) / 2.0 : nearbyCount / 2.0,
        3 => nearbyCount / 2.0,
        _ => double.infinity,
      };
      final baseActivityThreshold = _activityThresholds[nearbyCount];
      final activityThreshold = switch (sensitivity) {
        1 => baseActivityThreshold + 2,
        2 => baseActivityThreshold,
        3 => baseActivityThreshold - 2,
        _ => double.infinity,
      };
      if (nearbyActiveNum < numThreshold) continue;

      var nearbyActivity = nearbyActiveNum * (nearbyActiveNum + 1) / 2.0;
      for (var i = 0; i < nearbyStationIds.length; i++) {
        final nearbyId = nearbyStationIds[i];
        final distance = _distanceMatrix[index][nearbyId];
        nearbyActivity += i >= 3 && distance > 15
            ? states[nearbyId].activity / 2.0
            : states[nearbyId].activity;
      }
      if (nearbyActivity >= activityThreshold) {
        _chainActivate(index, states, activeStations, checkedStations);
      }
    }

    int? strongestIndex;
    if (message['hadActiveGrid'] != true && activeStations.isNotEmpty) {
      strongestIndex = activeStations.reduce(
        (a, b) => states[a].detectLevel >= states[b].detectLevel ? a : b,
      );
    }
    final sorted = activeStations.toList()..sort();
    return {'activeIndices': sorted, 'strongestIndex': strongestIndex};
  }

  void _buildAdjacency() {
    final count = _detectorConfigs.length;
    _adjacentStationIds = List.generate(count, (_) => <int>[]);
    _distanceMatrix = List.generate(count, (_) => List.filled(count, 0.0));
    for (var i = 0; i < count; i++) {
      final distances = <({int id, double distance})>[];
      ({int id, double distance})? fallback;
      for (var j = 0; j < count; j++) {
        final distance = j < i
            ? _distanceMatrix[j][i]
            : j == i
            ? 0.0
            : _haversine(_detectorConfigs[i], _detectorConfigs[j]);
        _distanceMatrix[i][j] = distance;
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
    if (candidate.detectLevel != current.detectLevel) {
      return candidate.detectLevel > current.detectLevel
          ? candidateId
          : currentId;
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

class _PixelSample {
  final int rawLevel;
  final double? position;

  const _PixelSample(this.rawLevel, this.position);
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
  final int detectLevel;
  final double activity;
  final int ascend;
  final bool isActive;
  final double continuousShindo;

  const _DetectorStationState({
    required this.detectLevel,
    required this.activity,
    required this.ascend,
    required this.isActive,
    required this.continuousShindo,
  });
}
