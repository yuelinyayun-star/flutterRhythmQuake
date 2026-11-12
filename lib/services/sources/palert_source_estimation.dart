import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/source_estimator.dart';
import '../../core/source_estimation/palert_magnitude.dart';
import 'palert_service.dart';
import 'palert_station_layout.dart';
import 'native_palert_topology.dart';

/// Raw P-Alert episode picks. The display peak hold is never an input.
class PAlertSourcePick {
  final List<({DateTime time, double pga, int level})> _history = [];
  DateTime? triggerAt;
  DateTime? nonQuietBoundary;
  int maxLevel = -1;
  int secondMaxLevel = -1;
  double? _peak;
  double? _secondPeak;
  DateTime? _lastPeakChange;
  DateTime? get updatedAt => _history.isEmpty ? null : _history.last.time;
  double? get peakPga => _peak;

  void update(PAlertStation station) {
    final time = station.dataTime;
    if (time == null || (updatedAt != null && !time.isAfter(updatedAt!))) {
      return;
    }
    final level = station.currentGridLevel;
    if (level < 0) {
      clear();
      return;
    }
    if (updatedAt != null &&
        time.difference(updatedAt!) > PAlertService.frameStaleAfter) {
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
      if (oldPeak != _peak || oldSecond != _secondPeak) _lastPeakChange = time;
      if (_lastPeakChange != null &&
          time.difference(_lastPeakChange!) >= const Duration(seconds: 8)) {
        _clearTrigger();
      }
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
    _lastPeakChange = null;
  }

  void clear() {
    _history.clear();
    nonQuietBoundary = null;
    _clearTrigger();
  }
}

/// Uses an independent instance of the existing four-stage HYP search, with
/// P-Alert pick weights. Magnitude uses the APP's Taiwan PGA model only.
class PAlertSourceEstimation {
  final Map<String, PAlertSourcePick> _picks = {};
  Map<String, List<String>> _adjacency = {};
  final _layout = PAlertStationLayout();
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
    if (!_layout.matches(stations)) {
      _picks.clear();
      _estimator = _newEstimator();
      _eventId = null;
      _layout.replace(stations);
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
        'level': station.currentGridLevel,
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
        if (isPublishable(estimate)) {
          sources.add(_withMagnitude(estimate, metadata, stations));
        }
      }
    } else if (primary != null && isPublishable(primary)) {
      sources.add(
        _withMagnitude(
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
          metadata,
          stations,
        ),
      );
    }
    return sources;
  }

  SourceEstimate _withMagnitude(
    SourceEstimate estimate,
    Map<String, Object?> metadata,
    List<PAlertStation> stations,
  ) {
    final assignments = metadata['nied_dart_hyp_station_detection_ids'];
    final detectionId = estimate.diagnostics['selected_detection_id'];
    final result = palertMagnitude(
      lat: estimate.latitude,
      lng: estimate.longitude,
      depth: estimate.depthKm!,
      samples: [
        for (final station in stations)
          if (assignments is Map &&
              assignments[station.id] == detectionId &&
              _picks[station.id]?.peakPga != null)
            (
              id: station.id,
              pga: _picks[station.id]!.peakPga!,
              lat: station.coordinate.latitude,
              lng: station.coordinate.longitude,
            ),
      ],
    );
    return SourceEstimate(
      latitude: estimate.latitude,
      longitude: estimate.longitude,
      depthKm: estimate.depthKm,
      magnitude: result?.magnitude,
      originTime: estimate.originTime,
      confidence: estimate.confidence,
      method: estimate.method,
      supportingStationCount: estimate.supportingStationCount,
      diagnostics: {
        ...estimate.diagnostics,
        if (result != null) ...result.diagnostics,
      },
    );
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
    if (NativePAlertTopology.supported) {
      final neighbors = NativePAlertTopology.build([
        for (final station in stations) ...[
          station.coordinate.latitude, station.coordinate.longitude,
        ],
      ]);
      return {
        for (var i = 0; i < stations.length; i++)
          stations[i].id: [for (final index in neighbors[i]) stations[index].id],
      };
    }
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
