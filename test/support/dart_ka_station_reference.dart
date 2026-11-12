// Frozen pre-migration KA station reference. Do not update with the native implementation.
import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

class DartKaStationReference {
  final int id;
  final String code;
  final String name;
  final LatLng coordinate;
  final String network;
  final String prefecture;

  /// KA level in the -1..20 domain used by detection, display, and estimation.
  int level;
  final Map<NiedGifLayer, NiedGifObservation> gifObservations;
  final Map<NiedGifLayer, Set<String>> gifLayerQualityFlags;
  NiedGifObservation? get gifObservation =>
      gifObservations[NiedGifLayer.realtimeShindo];
  NiedGifObservation? get pgaObservation =>
      gifObservations[NiedGifLayer.peakAcceleration];
  NiedGifObservation? get pgvObservation =>
      gifObservations[NiedGifLayer.peakVelocity];
  NiedGifObservation? get pgdObservation =>
      gifObservations[NiedGifLayer.peakDisplacement];
  double calibrationFactor;
  int thresholdCode;
  int ascend;
  int triggerStamp;
  double activity;
  bool isActive;
  int? abnormalUpdateCount;
  int? _detectState;
  String? _detectReason;
  int get detectState => _detectState ?? 0;
  set detectState(int value) => _detectState = value;
  String get detectReason => _detectReason ?? '';
  set detectReason(String value) => _detectReason = value;
  List<int> recentLevel;

  int expireSeconds;
  int defaultExpireSeconds;
  static const int kaExpireSeconds = 10;
  static const int maxExpireSeconds = 60;
  DateTime? lastUpdate;
  DateTime? lastDataTime;
  DateTime? lastReceivedAt;
  int pixelX;
  int pixelY;
  final bool scanReliable;
  final String? pixelClusterId;
  Timer? activeTimer;
  DateTime? _activeUntil;

  DartKaStationReference({
    required this.id,
    required this.code,
    required this.name,
    required this.coordinate,
    required this.network,
    required this.prefecture,
    required this.expireSeconds,
    this.pixelX = 0,
    this.pixelY = 0,
    this.scanReliable = true,
    this.pixelClusterId,
    this.level = -1,
  }) : defaultExpireSeconds = expireSeconds,
       gifObservations = <NiedGifLayer, NiedGifObservation>{},
       gifLayerQualityFlags = <NiedGifLayer, Set<String>>{},
       calibrationFactor = 1.0,
       thresholdCode = 320,
       ascend = 0,
       triggerStamp = 0,
       activity = 0.0,
       isActive = false,
       abnormalUpdateCount = null,
       _detectState = 0,
       _detectReason = '',
       recentLevel = [];

  /// Capture mutable observations without copying timers or allocating defaults
  /// that would immediately be replaced by the captured values.
  DartKaStationReference.detachedSnapshot(DartKaStationReference source)
    : id = source.id,
      code = source.code,
      name = source.name,
      coordinate = source.coordinate,
      network = source.network,
      prefecture = source.prefecture,
      expireSeconds = source.expireSeconds,
      defaultExpireSeconds = source.defaultExpireSeconds,
      pixelX = source.pixelX,
      pixelY = source.pixelY,
      scanReliable = source.scanReliable,
      pixelClusterId = source.pixelClusterId,
      level = source.level,
      calibrationFactor = source.calibrationFactor,
      thresholdCode = source.thresholdCode,
      ascend = source.ascend,
      triggerStamp = source.triggerStamp,
      activity = source.activity,
      isActive = source.isActive,
      abnormalUpdateCount = source.abnormalUpdateCount,
      _detectState = source.detectState,
      _detectReason = source.detectReason,
      recentLevel = List.of(source.recentLevel),
      lastUpdate = source.lastUpdate,
      lastDataTime = source.lastDataTime,
      lastReceivedAt = source.lastReceivedAt,
      gifObservations = Map.of(source.gifObservations),
      gifLayerQualityFlags = {
        for (final entry in source.gifLayerQualityFlags.entries)
          entry.key: Set.of(entry.value),
      };

  double get continuousShindo => gifObservation?.shindo ?? 0.0;
  int get kaLevel => level;
  List<int> get recentKaLevel => recentLevel;

  set continuousShindo(double value) {
    if (!value.isFinite) return;
    final current =
        gifObservation ??
        const NiedGifObservation(layer: NiedGifLayer.realtimeShindo);
    if (identical(current.shindo, value)) return;
    gifObservations[NiedGifLayer.realtimeShindo] = current.copyWith(
      layer: NiedGifLayer.realtimeShindo,
      shindo: value,
    );
  }

  void updateGifObservation(NiedGifObservation? observation) {
    if (observation == null) return;
    gifObservations[observation.layer] = observation;
    gifLayerQualityFlags.remove(observation.layer);
  }

  void clearGifObservation(NiedGifLayer layer, {required String qualityFlag}) {
    gifObservations.remove(layer);
    gifLayerQualityFlags[layer] = {qualityFlag};
  }

  void update(int newLevel, {bool render = true}) {
    final originLevel = newLevel.clamp(-1, 20).toInt();
    final effectiveLevel = _effectiveLevel(originLevel, recentLevel);

    level = effectiveLevel;

    // Push before detection, matching KA's unshift-before-calc order.
    recentLevel.insert(0, originLevel);
    if (recentLevel.length > maxExpireSeconds) {
      recentLevel = recentLevel.sublist(0, maxExpireSeconds);
    }

    var newAscend = 0;
    var newTriggerStamp = 0;
    if (_isAbnormalStation(recentKaLevel)) {
      abnormalUpdateCount = 0;
    } else if (abnormalUpdateCount != null) {
      final nextCount = abnormalUpdateCount! + 1;
      abnormalUpdateCount = nextCount >= 600 ? null : nextCount;
    } else {
      final ascendResult = _calcAscend(
        recentKaLevel,
        expireSeconds,
        currentLevel: kaLevel,
      );
      newAscend = ascendResult.$1;
      newTriggerStamp = ascendResult.$2;
    }
    ascend = newAscend;
    triggerStamp = newAscend > 0 ? newTriggerStamp : 0;
    activity = _calcActivity(kaLevel, ascend);
  }

  void updateFromContinuousShindo(
    double? newContinuousShindo, {
    bool render = true,
  }) {
    if (newContinuousShindo != null && newContinuousShindo.isFinite) {
      continuousShindo = newContinuousShindo;
    }
    final level = newContinuousShindo == null || !newContinuousShindo.isFinite
        ? -1
        : JpShindoScale.kanameishiLevelFromShindo(newContinuousShindo);
    update(level, render: render);
  }

  int _effectiveLevel(int originLevel, List<int> recentLevels) {
    if (originLevel != -1) return originLevel;
    final count = recentLevels.length < 4 ? recentLevels.length : 4;
    for (var index = 0; index < count; index++) {
      if (recentLevels[index] != -1) return recentLevels[index];
    }
    return -1;
  }

  /// Matches KA calcAscend: fills short -1 gaps, then scans backwards until
  /// the first level rebound to find the latest minimum.
  (int, int) _calcAscend(
    List<int> recentLevels,
    int expireSeconds, {
    required int currentLevel,
  }) {
    if (recentLevels.isEmpty) return (0, 0);

    // Fill short missing runs with the next valid value. Long or trailing
    // missing runs end the usable history, exactly as in KA.
    final firstMissing = recentLevels.indexOf(-1);
    final arr = firstMissing >= 0 ? List<int>.from(recentLevels) : recentLevels;
    var index = firstMissing >= 0 ? firstMissing : arr.length;
    while (index < arr.length) {
      if (arr[index] != -1) {
        index++;
        continue;
      }
      var missingCount = 1;
      var nextValidIndex = index + 1;
      while (nextValidIndex < arr.length && arr[nextValidIndex] == -1) {
        missingCount++;
        if (missingCount > expireSeconds) {
          arr.removeRange(index, arr.length);
          break;
        }
        nextValidIndex++;
      }
      if (index >= arr.length) break;
      if (nextValidIndex < arr.length) {
        arr[index] = arr[nextValidIndex];
        index++;
      } else {
        arr.removeRange(index, arr.length);
        break;
      }
    }
    if (arr.isEmpty) return (0, 0);

    var latestMinVal = arr[0];
    var latestMinIndex = 0;
    var identicalCount = 1;
    for (var i = 0; i < arr.length - 1; i++) {
      final current = arr[i];
      final next = arr[i + 1];
      if (next < current) {
        latestMinVal = next;
        latestMinIndex = i + 1;
        identicalCount = 1;
      } else if (next > current) {
        break;
      } else {
        identicalCount++;
        if (identicalCount > expireSeconds) {
          break;
        }
      }
    }

    final ascend = currentLevel - latestMinVal;
    final triggerStamp = ascend > 0 && recentLevels[latestMinIndex] != -1
        ? (lastDataTime?.millisecondsSinceEpoch ??
                  lastUpdate?.millisecondsSinceEpoch ??
                  0) -
              latestMinIndex * 1000
        : 0;
    return (ascend, triggerStamp);
  }

  /// Equivalent to reference isAbnormalStation: detects 3+ peaks with
  /// amplitude >= 3 in KA level history.
  bool _isAbnormalStation(List<int> recentLevels) {
    // Read valid levels in order without allocating a filtered history.
    // Phases match the reference's search, ascent, and descent loops.
    var phase = 0;
    var hasPrevious = false;
    var previous = 0;
    var leftBottom = 0;
    var top = 0;
    var rightBottom = 0;
    var peakCount = 0;
    for (var index = 0; index < recentLevels.length; index++) {
      final current = recentLevels[index];
      if (current == -1) continue;
      if (!hasPrevious) {
        previous = current;
        hasPrevious = true;
        continue;
      }
      if (phase == 1) {
        if (current >= previous) {
          top = current;
        } else {
          rightBottom = current;
          phase = 2;
        }
      } else if (current <= previous) {
        if (phase == 2) rightBottom = current;
      } else {
        if (phase == 2 && top - leftBottom >= 3 && top - rightBottom >= 3) {
          peakCount++;
          if (peakCount >= 3) return true;
        }
        leftBottom = previous;
        top = current;
        phase = 1;
      }
      previous = current;
    }
    if (phase == 2 && top - leftBottom >= 3 && top - rightBottom >= 3) {
      peakCount++;
    }
    return peakCount >= 3;
  }

  double _calcActivity(int level, int ascend) {
    double levelActivity;
    if (ascend > 0 || isActive) {
      if (level <= 5) {
        levelActivity = 0;
      } else if (level <= 7) {
        levelActivity = isActive ? 0.5 * (level - 5) : 0.25 * (level - 5);
      } else if (level <= 11) {
        levelActivity = 2.0 * (level - 7);
      } else {
        levelActivity = 6.0 * (level - 10);
      }
    } else {
      levelActivity = 0;
    }

    double ascendActivity;
    if (ascend <= 0) {
      ascendActivity = 0;
    } else if (ascend <= 1) {
      ascendActivity = isActive ? 0.5 : 0.25;
    } else if (ascend <= 6) {
      ascendActivity = 2.0 * (ascend - 2) + 1;
    } else {
      ascendActivity = 6.0 * (ascend - 5);
    }

    return levelActivity + ascendActivity;
  }

  void setActive([void Function()? onExpired]) {
    _holdActive(const Duration(milliseconds: 10500), onExpired);
  }

  /// Transfer only UI detection state when Android replaces a frame's objects.
  /// Keep the original deadline so incoming frames cannot extend a detection.
  void adoptDetectionHold(DartKaStationReference previous, void Function() onExpired) {
    final deadline = previous._activeUntil;
    final wasHeld =
        previous.isActive && (previous.activeTimer?.isActive ?? false);
    previous.activeTimer?.cancel();
    if (!wasHeld || deadline == null) return;
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    detectState = previous.detectState;
    detectReason = previous.detectReason;
    _holdActive(remaining, onExpired);
  }

  void _holdActive(Duration remaining, void Function()? onExpired) {
    isActive = true;
    activeTimer?.cancel();
    _activeUntil = DateTime.now().add(remaining);
    // KA keeps an activated NIED station for 10.5 seconds so the hold spans
    // the boundary before the next one-second frame arrives.
    activeTimer = Timer(remaining, () {
      isActive = false;
      _activeUntil = null;
      onExpired?.call();
    });
  }

  void terminate() {
    activeTimer?.cancel();
  }
}

