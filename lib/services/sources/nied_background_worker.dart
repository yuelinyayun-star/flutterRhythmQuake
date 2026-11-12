import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

import 'shindo_color_util.dart';
import 'nied_detection_rules.dart';
import 'native_station_image_decoder.dart';
import 'native_ka_detector.dart';
import 'lpgm_monitor_service.dart';

class NiedScanConfig {
  final int pixelX;
  final int pixelY;

  const NiedScanConfig({required this.pixelX, required this.pixelY});
}

class NiedPixelSample {
  final double? surfacePosition;
  // The original palette lookup can provide shindo without a color position.
  final double? surfaceShindo;
  final String? missingReason;

  const NiedPixelSample({
    required this.surfacePosition,
    this.surfaceShindo,
    this.missingReason,
  });
}

class NiedFrameScanResult {
  final int width;
  final int height;
  final List<NiedPixelSample> samples;
  final String backend;

  const NiedFrameScanResult({
    required this.width,
    required this.height,
    required this.samples,
    this.backend = 'dart',
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

/// The full NIED data owner calls the already verified Rust detector directly.
/// Its catalogue/buffers stay in that isolate, without another async hop or a
/// duplicate Dart distance matrix. Policy matches the existing NIED worker.
class NiedLocalDetectionSession {
  NiedLocalDetectionSession(List<List<Object?>> stations) {
    if (!NativeKaDetector.supported) {
      throw UnsupportedError(
        'NIED local detection requires the native backend',
      );
    }
    expireSeconds = _state._configureDetector({'stations': stations});
  }
  final _state = _NiedWorkerState();
  late final List<int> expireSeconds;
  NiedDetectionResult detect(
    List<NiedDetectionInput> stations, {
    required int sensitivity,
    required bool hadActiveGrid,
  }) {
    final result = _state._detect({
      'stations': [
        for (final s in stations)
          [
            s.kaLevel,
            s.activity,
            s.ascend,
            s.isActive,
            s.continuousShindo,
            s.triggerStamp,
          ],
      ],
      'sensitivity': sensitivity,
      'hadActiveGrid': hadActiveGrid,
    });
    return NiedDetectionResult(
      activeIndices: (result['activeIndices'] as List).cast<int>(),
      strongestIndex: result['strongestIndex'] as int?,
    );
  }

  void dispose() => _state.dispose();
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

  Future<LpgmSnapshot?> processLpgmFrame({
    required Uint8List imageBytes,
    required DateTime dataTime,
  }) async {
    await _ensureStarted();
    return await _request('lpgmFrame', {
          'image': TransferableTypedData.fromList([imageBytes]),
          'time': dataTime,
        })
        as LpgmSnapshot?;
  }

  Future<void> resetLpgm() async {
    if (_sendPort == null && _starting == null) return;
    try {
      await _ensureStarted();
      await _request('resetLpgm', const {});
    } on StateError {
      // A shared-worker shutdown already disposes the LPGM state. Its pending
      // reset is an expected cancellation, not an unhandled async exception.
      if (_sendPort != null) rethrow;
    }
  }

  @visibleForTesting
  Future<Map<String, Object?>> imageDecoderDiagnostics() async {
    if (_sendPort == null) return const {'backend': 'not-started'};
    return Map<String, Object?>.from(
      (await _request('imageDiagnostics', const {})) as Map,
    );
  }

  @visibleForTesting
  Future<Map<String, Object?>> detectorDiagnostics() async {
    if (_sendPort == null) return const {'backend': 'not-started'};
    return Map<String, Object?>.from(
      (await _request('detectorDiagnostics', const {})) as Map,
    );
  }

  /// 释放后台 isolate 及其台站配置缓存；下次请求时会按需重建。
  void stop() {
    _reset();
  }

  Future<NiedFrameScanResult?> scanFrame({
    required Uint8List surfaceBytes,
    required List<NiedScanConfig> configs,
    required String configSignature,
    bool physicalValues = false,
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
        'physicalValues': physicalValues,
      });
      if (response is! Map) return null;
      final packed = response['samples'];
      if (packed is! TransferableTypedData) return null;
      final values = packed.materialize().asFloat64List();
      if (values.length != configs.length) return null;
      final samples = <NiedPixelSample>[];
      final fallback = response['shindoFallback'] as Map?;
      final quality = (response['quality'] as TransferableTypedData?)
          ?.materialize()
          .asUint8List();
      for (var i = 0; i < configs.length; i++) {
        samples.add(
          NiedPixelSample(
            surfacePosition: _finitePosition(values[i]),
            surfaceShindo: (fallback?[i] as num?)?.toDouble(),
            missingReason: switch (quality?[i]) {
              1 => 'pixel_transparent',
              2 => 'pixel_undecodable',
              3 => 'pixel_out_of_bounds',
              _ => null,
            },
          ),
        );
      }
      return NiedFrameScanResult(
        width: response['width'] as int? ?? 0,
        height: response['height'] as int? ?? 0,
        samples: samples,
        backend: response['backend'] as String? ?? 'dart',
      );
    } catch (error) {
      debugPrint('[NIED] Background image scan failed: $error');
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
    } catch (error) {
      debugPrint('[NIED] Background detector configuration failed: $error');
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
      final packed = Int64List(stations.length * 6);
      final floating = Float64List.view(packed.buffer);
      for (var index = 0; index < stations.length; index++) {
        final station = stations[index], offset = index * 6;
        packed[offset] = station.kaLevel;
        floating[offset + 1] = station.activity;
        packed[offset + 2] = station.ascend;
        packed[offset + 3] = station.isActive ? 1 : 0;
        floating[offset + 4] = station.continuousShindo;
        packed[offset + 5] = station.triggerStamp;
      }
      final response = await _request('detect', {
        'packedStations': TransferableTypedData.fromList([
          packed.buffer.asUint8List(),
        ]),
        'sensitivity': sensitivity,
        'hadActiveGrid': hadActiveGrid,
      });
      if (response is! Map) return null;
      return NiedDetectionResult(
        activeIndices:
            (response['activeIndices'] as List?)?.cast<int>() ?? const [],
        strongestIndex: response['strongestIndex'] as int?,
      );
    } catch (error) {
      debugPrint('[NIED] Background KA detection failed: $error');
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
    // Finish the current synchronous call, explicitly free FFI buffers, then
    // exit. Never abandon a native allocation by killing a configured worker.
    if (_sendPort != null) {
      _sendPort!.send({'command': 'close'});
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
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
    if (message['command'] == 'close') {
      state.dispose();
      receivePort.close();
      Isolate.exit();
    }
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
  NativeStationImageDecoder? _nativeDecoder;
  List<_DetectorStationConfig> _detectorConfigs = const [];
  List<List<int>> _adjacentStationIds = const [];
  NativeKaDetector? _nativeKaDetector;
  LpgmFrameProcessor? _lpgmProcessor;

  void dispose() {
    _lpgmProcessor?.dispose();
    _lpgmProcessor = null;
    _nativeKaDetector?.dispose();
    _nativeKaDetector = null;
    _nativeDecoder?.dispose();
    _nativeDecoder = null;
  }

  Object? handle(Map<dynamic, dynamic> message) {
    switch (message['command']) {
      case 'lpgmFrame':
        final bytes = (message['image'] as TransferableTypedData)
            .materialize()
            .asUint8List();
        return (_lpgmProcessor ??= LpgmFrameProcessor()).process(
          bytes,
          message['time'] as DateTime,
        );
      case 'resetLpgm':
        _lpgmProcessor?.dispose();
        _lpgmProcessor = null;
        return true;
      case 'configureScan':
        _scanConfigs =
            (message['configs'] as List?)?.cast<List<Object?>>() ?? const [];
        _nativeDecoder?.dispose();
        _nativeDecoder = NativeStationImageDecoder.supported
            ? NativeStationImageDecoder([
                for (final config in _scanConfigs) ...[
                  config[0] as int,
                  config[1] as int,
                ],
              ])
            : null;
        return true;
      case 'scanFrame':
        return _scanFrame(message);
      case 'imageDiagnostics':
        return {
          'backend': _nativeDecoder == null ? 'dart' : 'rust-abi-1',
          'bufferCapacityBytes': _nativeDecoder?.bufferCapacityBytes ?? 0,
          if (_nativeDecoder != null) ...NativeStationImageDecoder.memoryStats,
        };
      case 'detectorDiagnostics':
        return {
          'backend': _nativeKaDetector == null ? 'dart' : 'rust-abi-1',
          if (_nativeKaDetector != null) ...NativeKaDetector.diagnostics,
        };
      case 'configureDetector':
        return _configureDetector(message);
      case 'detect':
        return _detect(message);
      default:
        throw StateError('Unknown NIED worker command: ${message['command']}');
    }
  }

  Map<String, Object?> _scanFrame(Map<dynamic, dynamic> message) {
    final physical = message['physicalValues'] == true;
    final surfaceBytes = (message['surface'] as TransferableTypedData)
        .materialize()
        .asUint8List();
    final native = _nativeDecoder;
    final fallback = <int, double>{};
    if (native != null) {
      final frame = native.sampleNied(surfaceBytes, physical: physical);
      final values = Float64List(_scanConfigs.length);
      final quality = Uint8List(_scanConfigs.length);
      for (var i = 0; i < values.length; i++) {
        final offset = i * 3;
        values[i] = frame.values[offset];
        quality[i] = frame.values[offset + 2].toInt();
        if (!physical &&
            values[i].isNaN &&
            frame.values[offset + 1].isFinite &&
            quality[i] == 0) {
          fallback[i] = frame.values[offset + 1];
        }
      }
      return {
        'width': frame.width,
        'height': frame.height,
        'backend': 'rust-abi-1',
        'shindoFallback': fallback,
        'quality': TransferableTypedData.fromList([quality]),
        'samples': TransferableTypedData.fromList([
          values.buffer.asUint8List(),
        ]),
      };
    }
    final surface = image_lib.decodeImage(surfaceBytes);
    if (surface == null) throw StateError('Unable to decode NIED surface GIF');

    final values = Float64List(_scanConfigs.length);
    final quality = Uint8List(_scanConfigs.length);
    for (var i = 0; i < _scanConfigs.length; i++) {
      final config = _scanConfigs[i];
      final x = config[0] as int;
      final y = config[1] as int;
      if (x < 0 ||
          x >= surface.width ||
          y < 0 ||
          y >= surface.height ||
          surface.getPixel(x, y).a == 0) {
        values[i] = double.nan;
        quality[i] = x < 0 || x >= surface.width || y < 0 || y >= surface.height
            ? 3
            : 1;
        continue;
      }
      values[i] =
          _samplePosition(surface, x, y, physical: physical) ?? double.nan;
      if (!physical &&
          values[i].isNaN &&
          x >= 0 &&
          x < surface.width &&
          y >= 0 &&
          y < surface.height) {
        final p = surface.getPixel(x, y);
        final a = p.a.toInt();
        final shindo = ShindoColorUtil.rgbaToShindo(
          (p.r.toInt() * a + 127) ~/ 255,
          (p.g.toInt() * a + 127) ~/ 255,
          (p.b.toInt() * a + 127) ~/ 255,
        );
        if (shindo != null) fallback[i] = shindo;
      }
      if (values[i].isNaN && !fallback.containsKey(i)) quality[i] = 2;
    }
    return {
      'width': surface.width,
      'height': surface.height,
      'shindoFallback': fallback,
      'quality': TransferableTypedData.fromList([quality]),
      'samples': TransferableTypedData.fromList([values.buffer.asUint8List()]),
    };
  }

  double? _samplePosition(
    image_lib.Image image,
    int x,
    int y, {
    bool physical = false,
  }) {
    if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
      return null;
    }
    final pixel = image.getPixel(x, y);
    final alpha = pixel.a.toInt();
    final r = (pixel.r.toInt() * alpha + 127) ~/ 255;
    final g = (pixel.g.toInt() * alpha + 127) ~/ 255;
    final b = (pixel.b.toInt() * alpha + 127) ~/ 255;
    final shindo = ShindoColorUtil.rgbaToShindo(r, g, b);
    if (!physical && shindo == null) return null;
    return ShindoColorUtil.rgbaToPosition(r, g, b);
  }

  List<int> _configureDetector(Map<dynamic, dynamic> message) {
    _nativeKaDetector?.dispose();
    _nativeKaDetector = null;
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
    if (NativeKaDetector.supported) {
      _nativeKaDetector = NativeKaDetector.niedCoordinates([
        for (final station in _detectorConfigs) ...[
          station.latitude,
          station.longitude,
        ],
      ]);
      // The native session is the sole owner of adjacency and working sets.
      _adjacentStationIds = const [];
    } else {
      _buildAdjacency();
    }
    return List<int>.filled(_detectorConfigs.length, 10);
  }

  Map<String, Object?> _detect(Map<dynamic, dynamic> message) {
    final rows = (message['stations'] as List?) ?? const [];
    final packed = message['packedStations'] as TransferableTypedData?;
    final words = packed?.materialize().asInt64List();
    if (words != null && words.length % 6 != 0)
      throw StateError('Invalid KA frame size');
    final count = words == null ? rows.length : words.length ~/ 6;
    if (count != _detectorConfigs.length) {
      throw StateError('NIED detector station count changed');
    }
    final native = _nativeKaDetector;
    if (native != null) {
      if (words != null) {
        native.writePacked(words);
      } else {
        for (var index = 0; index < rows.length; index++) {
          final row = rows[index] as List;
          native.writeInput(
            index,
            kaLevel: row[0] as int,
            activity: (row[1] as num).toDouble(),
            ascend: row[2] as int,
            isActive: row[3] as bool,
            triggerStamp: row[5] as int,
            continuousShindo: (row[4] as num).toDouble(),
          );
        }
      }
      final result = native.process(
        sensitivity: message['sensitivity'] as int? ?? 2,
        hadActiveGrid: message['hadActiveGrid'] == true,
      );
      return {
        'activeIndices': result.activeIndices,
        'strongestIndex': result.strongestIndex,
      };
    }
    final floating = words == null
        ? null
        : Float64List.view(words.buffer, words.offsetInBytes);
    final states = [
      if (words != null)
        for (var index = 0; index < count; index++)
          _DetectorStationState(
            kaLevel: words[index * 6],
            activity: floating![index * 6 + 1],
            ascend: words[index * 6 + 2],
            isActive: words[index * 6 + 3] == 1,
            continuousShindo: floating[index * 6 + 4],
            triggerStamp: words[index * 6 + 5],
          ),
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
    // Keep one detector result per station, matching KA's station list. The
    // GIF pixel-cluster key is retained only as provenance metadata.
    return stationIds;
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
