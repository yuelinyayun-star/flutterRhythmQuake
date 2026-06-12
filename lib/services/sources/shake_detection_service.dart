import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/source_estimation/station_event_tracker.dart';
import '../../../core/nied_replay_logger.dart';
import 'jp_shindo_scale.dart';
import 'nied_monitor.dart';

enum ShakeDetectStage { idle, weak, detected, strong }

class DetectedStationEntry {
  final String code;
  final String prefecture;
  final int level;
  final int jmaShindo;
  final int detectState;
  final String detectReason;

  const DetectedStationEntry({
    required this.code,
    required this.prefecture,
    required this.level,
    required this.jmaShindo,
    required this.detectState,
    required this.detectReason,
  });
}

class NiedDetectionGridCell {
  final LatLng center;
  final int level;
  final double shindo;

  const NiedDetectionGridCell({
    required this.center,
    required this.level,
    required this.shindo,
  });
}

class ShakeDetectionSnapshot {
  final ShakeDetectStage stage;
  final int weakCount;
  final int detectedCount;
  final int strongCount;
  final int maxShindo;
  final List<DetectedStationEntry> detectedStations;
  final double? hypoLat;
  final double? hypoLng;
  final double? hypoDepth;
  final double? hypoConfidence;

  /// 1-based sub-area index -> max shindo. Kept for UI compatibility.
  final Map<int, double> subAreaShindo;

  /// Kanameishi-style 1-degree detection grid cells.
  final Map<String, NiedDetectionGridCell> gridCells;

  const ShakeDetectionSnapshot({
    required this.stage,
    required this.weakCount,
    required this.detectedCount,
    required this.strongCount,
    required this.maxShindo,
    this.detectedStations = const [],
    this.hypoLat,
    this.hypoLng,
    this.hypoDepth,
    this.hypoConfidence,
    this.subAreaShindo = const {},
    this.gridCells = const {},
  });
}

class ShakeDetectionService {
  static final ShakeDetectionService _instance =
      ShakeDetectionService._internal();
  factory ShakeDetectionService() => _instance;
  ShakeDetectionService._internal();

  static const int nearbyLength = 6;
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

  List<NiedStation>? _stations;
  List<List<int>> _adjStationIds = [];
  List<List<double>> _distMatrix = [];
  List<double> _gridDecimal = const [0.0, 0.0];
  final Map<String, NiedDetectionGridCell> _gridCells = {};

  int _sensitivity = 2;
  int _prevMaxShindo = -1;
  String _lastStationSignature = '';
  String _lastSnapshotKey = '';
  bool _shake1Notified = false;
  bool _shake2Notified = false;
  bool _focused = false;
  Timer? _expireCheckTimer;

  void Function(int shindo)? onShakeDetected;
  void Function()? onShakeExpired;
  void Function(String title, String body)? onNotification;
  void Function()? onFocusWindow;
  void Function(ShakeDetectionSnapshot snapshot)? onDetectionSnapshotChanged;

  void setStations(List<NiedStation> stations) {
    _stations = stations;
    final signature = stations
        .map(
          (s) =>
              '${s.id}:${s.code}:${s.coordinate.latitude.toStringAsFixed(3)},'
              '${s.coordinate.longitude.toStringAsFixed(3)}',
        )
        .join('|');
    if (signature != _lastStationSignature) {
      _lastStationSignature = signature;
      _buildAdjacency();
      _gridCells.clear();
      _gridDecimal = const [0.0, 0.0];
      _prevMaxShindo = -1;
      _lastSnapshotKey = '';
      _shake1Notified = false;
      _shake2Notified = false;
      _focused = false;
    }
    _startExpireCheck();
  }

  void setSensitivity(int level) {
    _sensitivity = level.clamp(1, 3);
  }

  void processUpdate() {
    final stations = _stations;
    if (stations == null || stations.isEmpty) return;
    if (_adjStationIds.length != stations.length) {
      _buildAdjacency();
    }

    for (final station in stations) {
      if (!station.isActive) {
        station.detectState = 0;
        station.detectReason = '';
      }
    }

    final hadActiveGrid = _gridCells.isNotEmpty;
    final possibleStations = <int>[];
    for (var i = 0; i < stations.length; i++) {
      if (stations[i].activity > 0) possibleStations.add(i);
    }
    final dedupedPossibleStations = _dedupeStationIds(
      possibleStations,
      stations,
    );

    final activeStations = <int>{};
    final checkedStations = <int>{};
    for (final index in dedupedPossibleStations) {
      final station = stations[index];
      if (checkedStations.contains(index)) {
        continue;
      }

      if (station.isActive && station.ascend > 0) {
        _chainActivate(index, activeStations, checkedStations);
        continue;
      }

      final nearbyStationIds = _dedupeStationIds(
        _adjStationIds[index]
            .where((id) => id >= 0 && id < stations.length)
            .where((id) => stations[id].detectLevel > -1)
            .toList(growable: false),
        stations,
      );
      if (nearbyStationIds.isEmpty) continue;

      final possibleNearbyStationIds = _dedupeStationIds(
        nearbyStationIds
            .where((id) => stations[id].activity > 0)
            .toList(growable: false),
        stations,
      );
      final weakRiseCount = possibleNearbyStationIds
          .where((id) => stations[id].ascend <= 1 && !stations[id].isActive)
          .length;
      final nearbyActiveNum =
          possibleNearbyStationIds.length - weakRiseCount / 2.0;

      final nearbyCount = nearbyStationIds.length.clamp(0, nearbyLength);
      final numThres = switch (_sensitivity) {
        1 => 3.0,
        2 => nearbyCount <= 2 ? (nearbyCount + 1) / 2.0 : nearbyCount / 2.0,
        3 => nearbyCount / 2.0,
        _ => double.infinity,
      };
      final baseActivityThres = _activityThresholds[nearbyCount];
      final activityThres = switch (_sensitivity) {
        1 => baseActivityThres + 2,
        2 => baseActivityThres,
        3 => baseActivityThres - 2,
        _ => double.infinity,
      };

      if (nearbyActiveNum >= numThres) {
        final numActivity = nearbyActiveNum * (nearbyActiveNum + 1) / 2.0;
        var nearbyActivity = numActivity;
        for (var i = 0; i < nearbyStationIds.length; i++) {
          final nearbyId = nearbyStationIds[i];
          final nearbyStation = stations[nearbyId];
          final distance = _distMatrix[index][nearbyId];
          nearbyActivity += i >= 3 && distance > 15
              ? nearbyStation.activity / 2.0
              : nearbyStation.activity;
        }
        if (nearbyActivity >= activityThres) {
          _chainActivate(index, activeStations, checkedStations);
        }
      }
    }

    if (!hadActiveGrid && activeStations.isNotEmpty) {
      final strongest = activeStations
          .map((id) => stations[id])
          .reduce((a, b) => a.detectLevel >= b.detectLevel ? a : b);
      _gridDecimal = [
        _gridDecimalPart(strongest.coordinate.latitude),
        _gridDecimalPart(strongest.coordinate.longitude),
      ];
    }

    for (final index in activeStations) {
      final station = stations[index];
      final jmaShindo = station.detectLevel >= 0
          ? JpShindoScale.jmaNumberFromKanameishiLevel(station.detectLevel)
          : -1;
      station.detectState = jmaShindo >= 4
          ? 6
          : jmaShindo >= 1
          ? 5
          : jmaShindo >= 0
          ? 1
          : 0;
      station.detectReason = 'kanameishi-chain';
      station.setActive(_handleStationExpired);
    }

    _refreshDetectionGrids();
    _checkShakeNotification();
  }

  void _buildAdjacency() {
    final stations = _stations;
    if (stations == null || stations.isEmpty) return;

    final n = stations.length;
    _adjStationIds = List.generate(n, (_) => <int>[]);
    _distMatrix = List.generate(n, (_) => List.filled(n, 0.0));
    final latLngs = stations.map((s) => s.coordinate).toList(growable: false);

    for (var i = 0; i < n; i++) {
      final distances = <({int id, double distance})>[];
      ({int id, double distance})? candidate;

      for (var j = 0; j < n; j++) {
        final distance = j < i
            ? _distMatrix[j][i]
            : j == i
            ? 0.0
            : _haversine(latLngs[i], latLngs[j]);
        _distMatrix[i][j] = distance;

        if (distance <= _denseNearbyKm) {
          distances.add((id: j, distance: distance));
        } else if (distance <= _sparseFallbackNearbyKm &&
            (candidate == null || distance <= candidate.distance)) {
          candidate = (id: j, distance: distance);
        }
      }

      if (distances.length <= 1 && candidate != null) {
        distances.add(candidate);
      }
      distances.sort((a, b) => a.distance.compareTo(b.distance));
      if (distances.length > nearbyLength) {
        distances.removeRange(nearbyLength, distances.length);
      }

      _adjStationIds[i] = distances.map((d) => d.id).toList(growable: false);
      if (distances.isNotEmpty) {
        final maxDist = distances.last.distance;
        final expire = math.max((maxDist / 3.5).round(), 5);
        stations[i].defaultExpireSeconds = expire;
        stations[i].expireSeconds = expire;
      }
    }
  }

  void _chainActivate(
    int startIndex,
    Set<int> activeStations,
    Set<int> checkedStations,
  ) {
    final stations = _stations;
    if (stations == null) return;

    final pendingStations = <int>{startIndex};
    while (pendingStations.isNotEmpty) {
      final currentIndex = pendingStations.first;
      pendingStations.remove(currentIndex);
      checkedStations.add(currentIndex);

      final currentStation = stations[currentIndex];
      if (currentStation.activity > 0) {
        activeStations.add(currentIndex);
        final neighborIds = _dedupeStationIds(
          _adjStationIds[currentIndex]
              .where((id) => id >= 0 && id < stations.length)
              .toList(growable: false),
          stations,
        );
        for (final neighborIndex in neighborIds) {
          if (!checkedStations.contains(neighborIndex)) {
            pendingStations.add(neighborIndex);
          }
        }
      }
    }
  }

  void _refreshDetectionGrids() {
    final stations = _stations;
    if (stations == null) return;

    final next = <String, NiedDetectionGridCell>{};
    for (final station in stations.where((s) => s.isActive)) {
      // kanameishi-dev builds grids from every active station and then maps the
      // resulting max level to JMA shindo, so level<=7 must remain as a real
      // "震度0" detect grid instead of being dropped here.
      if (station.detectLevel < 0) continue;
      final lat = _roundCoord(station.coordinate.latitude, _gridDecimal[0]);
      final lng = _roundCoord(station.coordinate.longitude, _gridDecimal[1]);
      final key = '$lat,$lng';
      final existing = next[key];
      final level = existing == null || station.detectLevel > existing.level
          ? station.detectLevel
          : existing.level;
      next[key] = NiedDetectionGridCell(
        center: LatLng(lat, lng),
        level: level,
        shindo: (level + 0.5 - 7) / 2,
      );
    }

    _gridCells
      ..clear()
      ..addAll(next);
    if (_gridCells.isEmpty) {
      _gridDecimal = const [0.0, 0.0];
    }
  }

  void _emitDetectionSnapshot() {
    final stations = _stations;
    if (stations == null) return;

    final activeStations = stations.where((s) => s.isActive).toList();
    var maxDetectLevel = -1;
    var strong = 0;
    var weak = 0;
    var detected = 0;
    final entries = <DetectedStationEntry>[];

    for (final station in activeStations) {
      if (station.detectLevel > maxDetectLevel) {
        maxDetectLevel = station.detectLevel;
      }
      final jmaShindo = station.detectLevel >= 0
          ? JpShindoScale.jmaNumberFromKanameishiLevel(station.detectLevel)
          : -1;
      if (jmaShindo >= 4) strong++;
      if (jmaShindo >= 1 && jmaShindo <= 3) {
        detected++;
      } else if (jmaShindo == 0) {
        weak++;
      }
      entries.add(
        DetectedStationEntry(
          code: station.code,
          prefecture: station.prefecture,
          level: station.level,
          jmaShindo: jmaShindo,
          detectState: station.detectState,
          detectReason: station.detectReason,
        ),
      );
    }

    entries.sort((a, b) {
      final levelCmp = b.level.compareTo(a.level);
      if (levelCmp != 0) return levelCmp;
      return a.code.compareTo(b.code);
    });

    final maxShindo = maxDetectLevel >= 0
        ? JpShindoScale.jmaNumberFromKanameishiLevel(maxDetectLevel)
        : -1;
    // Formal detection should be governed by the detector itself rather than
    // by post-mapping display shindo thresholds.
    final stage = activeStations.isEmpty
        ? ShakeDetectStage.idle
        : strong > 0
        ? ShakeDetectStage.strong
        : detected > 0
        ? ShakeDetectStage.detected
        : ShakeDetectStage.weak;
    final observedAt =
        stations
            .map((s) => s.lastDataTime ?? s.lastUpdate)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (latest, value) {
              if (latest == null || value.isAfter(latest)) {
                return value;
              }
              return latest;
            }) ??
        DateTime.now();
    StationEventTracker.instance.ingestNiedFrame(
      stations: stations,
      observedAt: observedAt,
      stageName: stage.name,
      maxShindo: maxShindo,
      metadata: {
        'weak_count': weak,
        'detected_count': detected,
        'strong_count': strong,
        'grid_cell_count': _gridCells.length,
      },
    );
    final estimate =
        StationEventTracker.instance.currentNiedEvent.value?.estimate;

    final gridKey = _gridCells.entries
        .map((e) => '${e.key}:${e.value.level}')
        .join(',');
    final stationKey = entries
        .map((e) => '${e.code}:${e.level}:${e.jmaShindo}:${e.detectState}')
        .join(',');
    final estimateKey = estimate == null
        ? 'none'
        : '${estimate.latitude.toStringAsFixed(3)},'
              '${estimate.longitude.toStringAsFixed(3)},'
              '${(estimate.depthKm ?? -1).toStringAsFixed(1)},'
              '${estimate.confidence.toStringAsFixed(2)},'
              '${estimate.method}';
    final key =
        '${stage.name}|${entries.length}|$strong|$maxShindo|$gridKey|$stationKey|$estimateKey';
    if (key == _lastSnapshotKey) return;
    _lastSnapshotKey = key;

    final snapshot = ShakeDetectionSnapshot(
      stage: stage,
      weakCount: weak,
      detectedCount: detected,
      strongCount: strong,
      maxShindo: maxShindo,
      detectedStations: entries,
      hypoLat: estimate?.latitude,
      hypoLng: estimate?.longitude,
      hypoDepth: estimate?.depthKm,
      hypoConfidence: estimate?.confidence,
      gridCells: Map<String, NiedDetectionGridCell>.from(_gridCells),
    );
    NiedReplayLogger.instance.logDetection(snapshot);
    onDetectionSnapshotChanged?.call(snapshot);
  }

  void _checkShakeNotification() {
    _refreshDetectionGrids();
    final currentMaxShindo = _currentMaxShindo();

    if (currentMaxShindo > _prevMaxShindo) {
      onShakeDetected?.call(currentMaxShindo);

      if (currentMaxShindo >= 1 && currentMaxShindo <= 3 && !_shake1Notified) {
        onNotification?.call('揺れを検出', '揺れに注意してください。');
        _shake1Notified = true;
      } else if (currentMaxShindo >= 4 && !_shake2Notified) {
        onNotification?.call('強い揺れを検出', '強い揺れに警戒してください。');
        _shake1Notified = true;
        _shake2Notified = true;
      }

      if (currentMaxShindo >= 1 && !_focused) {
        onFocusWindow?.call();
        _focused = true;
      }
    } else if (currentMaxShindo == -1 && _prevMaxShindo >= 0) {
      onShakeExpired?.call();
      _shake1Notified = false;
      _shake2Notified = false;
      _focused = false;
    } else if (currentMaxShindo <= _prevMaxShindo) {
      _shake1Notified = false;
      _shake2Notified = false;
      _focused = false;
    }

    _prevMaxShindo = currentMaxShindo;
    _emitDetectionSnapshot();
  }

  int _currentMaxShindo() {
    final maxLevel = _gridCells.values.fold<int>(
      -1,
      (maxLevel, cell) => cell.level > maxLevel ? cell.level : maxLevel,
    );
    return maxLevel >= 0
        ? JpShindoScale.jmaNumberFromKanameishiLevel(maxLevel)
        : -1;
  }

  void _handleStationExpired() {
    _checkShakeNotification();
  }

  void _startExpireCheck() {
    if (_expireCheckTimer != null) return;
    _expireCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_prevMaxShindo >= 0) {
        _checkShakeNotification();
      }
    });
  }

  double _roundCoord(double val, double decimal) {
    return (val - decimal).roundToDouble() + decimal;
  }

  List<int> _dedupeStationIds(
    List<int> stationIds,
    List<NiedStation> stations,
  ) {
    if (stationIds.length <= 1) return stationIds;

    final bestByCluster = <String, int>{};
    final orderedClusterKeys = <String>[];

    for (final stationId in stationIds) {
      final key = _clusterKey(stations[stationId]);
      final currentBest = bestByCluster[key];
      if (currentBest == null) {
        bestByCluster[key] = stationId;
        orderedClusterKeys.add(key);
        continue;
      }
      bestByCluster[key] = _preferClusterRepresentative(
        currentBest,
        stationId,
        stations,
      );
    }

    return orderedClusterKeys
        .map((key) => bestByCluster[key]!)
        .toList(growable: false);
  }

  String _clusterKey(NiedStation station) {
    final clusterId = station.pixelClusterId;
    if (clusterId != null && clusterId.isNotEmpty) {
      return 'pixel:$clusterId';
    }
    return 'station:${station.code}';
  }

  int _preferClusterRepresentative(
    int currentId,
    int candidateId,
    List<NiedStation> stations,
  ) {
    final current = stations[currentId];
    final candidate = stations[candidateId];

    int cmp(double a, double b) => a.compareTo(b);

    final detectCmp = cmp(
      candidate.detectLevel.toDouble(),
      current.detectLevel.toDouble(),
    );
    if (detectCmp != 0) return detectCmp > 0 ? candidateId : currentId;

    final activityCmp = cmp(candidate.activity, current.activity);
    if (activityCmp != 0) return activityCmp > 0 ? candidateId : currentId;

    final ascendCmp = cmp(
      candidate.ascend.toDouble(),
      current.ascend.toDouble(),
    );
    if (ascendCmp != 0) return ascendCmp > 0 ? candidateId : currentId;

    final shindoCmp = cmp(candidate.continuousShindo, current.continuousShindo);
    if (shindoCmp != 0) return shindoCmp > 0 ? candidateId : currentId;

    return candidate.id < current.id ? candidateId : currentId;
  }

  static double _gridDecimalPart(double val) {
    final fraction = (val + 180) % 1;
    return (fraction * 10).roundToDouble() / 10;
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final lat1Rad = _toRad(a.latitude);
    final lat2Rad = _toRad(b.latitude);
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final h =
        sinDLat * sinDLat +
        sinDLng * sinDLng * math.cos(lat1Rad) * math.cos(lat2Rad);
    return 2 * r * math.asin(math.sqrt(h));
  }

  double _toRad(double deg) => deg * 0.017453292519943295;
}
