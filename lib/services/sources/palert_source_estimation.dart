import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/source_estimation/palert_source_profile.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/source_estimator.dart';
import 'palert_service.dart';

/// Raw P-Alert episode picks. The display peak hold is never an input.
class PAlertSourcePick {
  final List<({DateTime time, double pga, int level})> _history = [];
  DateTime? triggerAt;
  DateTime? nonQuietBoundary;
  int maxLevel = -1;
  int secondMaxLevel = -1;
  double? _peak;
  double? _secondPeak;
  int _unchangedSeconds = 0;
  DateTime? get updatedAt => _history.isEmpty ? null : _history.last.time;

  void update(PAlertStation station) {
    final time = station.dataTime;
    if (time == null || (updatedAt != null && !time.isAfter(updatedAt!))) {
      return;
    }
    // A null current category includes high PGA with no current PGV. The
    // service may retain the last PGV for display, which is not a new sample.
    final level =
        (station.pgaGal ?? -1) >= 80 && station.cwaIntensityIndex == null
        ? -1
        : PAlertSourceProfile.level(station.pgaGal, station.pgvCms);
    if (level < 0) {
      clear();
      return;
    }
    if (updatedAt != null &&
        time.difference(updatedAt!).inMilliseconds != 1000) {
      clear();
    }
    final pga = station.pgaGal!;
    if (level >= 6 || nonQuietBoundary == null) nonQuietBoundary = time;
    if (triggerAt == null && _history.length >= 8) {
      final previous = _history.last;
      final background = _history
          .take(_history.length - 1)
          .map((v) => v.pga)
          .reduce(math.max);
      if ((level >= 6 || previous.level >= 6) &&
          previous.pga > 0 &&
          _atLeast(pga, background * 1.5) &&
          _atLeast(previous.pga, background * 1.5)) {
        triggerAt = previous.time;
        maxLevel = previous.level;
        _peak = previous.pga;
      } else if (level >= 6 &&
          pga > 0 &&
          _atLeast(pga, math.max(background, previous.pga) * 2)) {
        triggerAt = time;
      }
    }
    if (triggerAt != null) {
      final oldPeak = _peak;
      final oldSecond = _secondPeak;
      if (level >= maxLevel) {
        secondMaxLevel = maxLevel;
        maxLevel = level;
      } else if (level > secondMaxLevel) {
        secondMaxLevel = level;
      }
      if (_peak == null || pga >= _peak!) {
        _secondPeak = _peak;
        _peak = pga;
      } else if (_secondPeak == null || pga > _secondPeak!) {
        _secondPeak = pga;
      }
      _unchangedSeconds = oldPeak != _peak || oldSecond != _secondPeak
          ? 0
          : _unchangedSeconds + 1;
      if (_unchangedSeconds >= 8) _clearTrigger();
    }
    _history.add((time: time, pga: pga, level: level));
    if (_history.length > 8) _history.removeAt(0);
  }

  bool get hasQuietHistory =>
      _history.length == 8 && _history.every((sample) => sample.level < 6);

  static bool _atLeast(double a, double b) =>
      double.parse(a.toStringAsFixed(10)) >=
      double.parse(b.toStringAsFixed(10));

  void _clearTrigger() {
    triggerAt = null;
    maxLevel = secondMaxLevel = -1;
    _peak = _secondPeak = null;
    _unchangedSeconds = 0;
  }

  void clear() {
    _history.clear();
    nonQuietBoundary = null;
    _clearTrigger();
  }
}

/// Uses an independent instance of the existing four-stage HYP search, with
/// P-Alert pick weights. No Japan-only magnitude estimate is published.
class PAlertSourceEstimation {
  final Map<String, PAlertSourcePick> _picks = {};
  Map<String, List<String>> _adjacency = {};
  String _layout = '';
  String? _eventId;
  String? get eventId => _eventId;
  NiedDartHypSourceEstimator _estimator = _newEstimator();

  static NiedDartHypSourceEstimator _newEstimator() =>
      NiedDartHypSourceEstimator(
        searchSchedule: NiedHypSearchSchedule.referenceBroadFourStage,
        writebackPolicy: NiedHypWritebackPolicy.nonIncreasingCurrent,
      );

  List<SourceEstimate> update(
    List<PAlertStation> stations,
    Set<String> confirmedIds,
    DateTime now,
  ) {
    final layout = stations.map((s) => '${s.id}:${s.coordinate}').join('|');
    if (layout != _layout) {
      _picks.clear();
      _estimator = _newEstimator();
      _eventId = null;
      _layout = layout;
      _adjacency = _neighbors(stations);
    }
    final active = <Map<String, Object?>>[];
    final inactive = <Map<String, Object?>>[];
    DateTime? observedAt;
    for (final station in stations) {
      final pick = _picks.putIfAbsent(station.id, PAlertSourcePick.new);
      if (station.receivedAt == null ||
          station.dataTime == null ||
          now.difference(station.receivedAt!) > PAlertService.frameStaleAfter) {
        pick.clear();
        continue;
      }
      pick.update(station);
      if (pick.updatedAt == null) continue;
      if (observedAt == null || station.dataTime!.isAfter(observedAt)) {
        observedAt = station.dataTime;
      }
      final snapshot = <String, Object?>{
        'id': station.id,
        'code': station.id,
        'latLng': [station.coordinate.latitude, station.coordinate.longitude],
        'updateStamp': station.dataTime!.millisecondsSinceEpoch,
        'triggerStamp': pick.triggerAt?.millisecondsSinceEpoch,
        'level': PAlertSourceProfile.level(station.pgaGal, station.pgvCms),
        'maxLevel': pick.maxLevel,
        'secondMaxLevel': pick.secondMaxLevel,
        'nonQuietBoundaryStamp': pick.nonQuietBoundary?.millisecondsSinceEpoch,
      };
      if (confirmedIds.contains(station.id) && pick.triggerAt != null) {
        active.add(snapshot);
      } else if (pick.hasQuietHistory && !confirmedIds.contains(station.id)) {
        inactive.add(snapshot);
      }
    }
    if (active.isEmpty || observedAt == null) {
      _estimator = _newEstimator();
      _eventId = null;
      return const [];
    }
    _eventId ??= 'palert-${observedAt.millisecondsSinceEpoch}';
    final metadata = <String, Object?>{
      'activeStations': active,
      'inactiveStations': inactive,
      'adjStationIds': _adjacency,
      'detectionAdjStationCodes': _adjacency,
    };
    final request = SourceEstimationRequest(
      sourceId: 'palert',
      eventId: _eventId!,
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 0,
      stations: const [],
      metadata: metadata,
    );
    final primary = _estimator.supports(request)
        ? _estimator.estimate(request)
        : null;
    final sources = <SourceEstimate>[];
    final rawSources = metadata['nied_dart_hyp_sources'];
    if (rawSources is Iterable) {
      for (final raw in rawSources.whereType<Map>()) {
        final diagnostics = raw['diagnostics'];
        if (raw['latitude'] is! num ||
            raw['longitude'] is! num ||
            diagnostics is! Map) {
          continue;
        }
        final estimate = SourceEstimate(
          latitude: (raw['latitude'] as num).toDouble(),
          longitude: (raw['longitude'] as num).toDouble(),
          depthKm: (raw['depth_km'] as num?)?.toDouble(),
          originTime: DateTime.tryParse(raw['origin_time']?.toString() ?? ''),
          confidence: (raw['confidence'] as num?)?.toDouble() ?? 0,
          method: 'palert_hyp_v1',
          supportingStationCount:
              (raw['supporting_station_count'] as num?)?.toInt() ?? 0,
          diagnostics: diagnostics.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        if (isPublishable(estimate)) sources.add(estimate);
      }
    } else if (primary != null && isPublishable(primary)) {
      sources.add(
        SourceEstimate(
          latitude: primary.latitude,
          longitude: primary.longitude,
          depthKm: primary.depthKm,
          originTime: primary.originTime,
          confidence: primary.confidence,
          method: 'palert_hyp_v1',
          supportingStationCount: primary.supportingStationCount,
          diagnostics: primary.diagnostics,
        ),
      );
    }
    return sources;
  }

  static bool isPublishable(SourceEstimate estimate) {
    final quality = estimate.diagnostics['quality_score'];
    final score = estimate.diagnostics['score'];
    return estimate.supportingStationCount >= 5 &&
        estimate.latitude.isFinite &&
        estimate.longitude.isFinite &&
        estimate.latitude.abs() <= 90 &&
        estimate.longitude.abs() <= 180 &&
        estimate.depthKm != null &&
        estimate.depthKm!.isFinite &&
        estimate.depthKm! >= 0 &&
        estimate.originTime != null &&
        quality is num &&
        quality.isFinite &&
        quality >= -3 &&
        (score == null || (score is num && score.isFinite && score < 1e12));
  }

  Map<String, List<String>> _neighbors(List<PAlertStation> stations) {
    const distance = Distance();
    return {
      for (final station in stations)
        station.id: (() {
          final candidates = stations.where((s) => s.id != station.id).toList()
            ..sort(
              (a, b) => distance(
                station.coordinate,
                a.coordinate,
              ).compareTo(distance(station.coordinate, b.coordinate)),
            );
          final selected = <String>{};
          final counts = List.filled(4, 0);
          for (final other in candidates) {
            final bearing =
                (distance.bearing(station.coordinate, other.coordinate) + 360) %
                360;
            final direction = ((bearing + 45) / 90).floor() % 4;
            if (counts[direction] >= 3) continue;
            selected.add(other.id);
            counts[direction]++;
          }
          return selected.toList();
        })(),
    };
  }
}
