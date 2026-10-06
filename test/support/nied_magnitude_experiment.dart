import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';
import 'nied_event_magnitude_candidate.dart';

/// Offline shadow calculations only. Never returns an application estimate.
class NiedMagnitudeExperiment {
  final _states = <String, _EventState>{};
  final _eventCandidate = NiedEventMagnitudeCandidate();
  DateTime? _previousTime;

  Map<String, Object?> observe(
    SourceEstimationRequest request,
    SourceEstimate? output,
    List<Map> snapshots,
  ) {
    final time = request.observedAt;
    if (_previousTime != null && time.isBefore(_previousTime!)) {
      _states.clear();
    }
    _previousTime = time;
    final groups =
        (request.metadata['nied_dart_hyp_detection_ids'] as List?)
            ?.whereType<Map>()
            .where((g) => g['active'] == true)
            .toList() ??
        <Map>[];
    _eventCandidate.beginFrame(
      eventId: request.eventId,
      time: time,
      groups: groups,
    );
    String identity(Map group) =>
        '${request.eventId}:${group['id']}:${group['serial']}:${group['created_at']}';
    final liveKeys = groups.map(identity).toSet();
    _states.removeWhere((key, _) => !liveKeys.contains(key));
    if (output == null) {
      return {'supported': false, 'reason': 'no_source_output'};
    }
    final selectedId = output.diagnostics['selected_detection_id'];
    final selected = groups.where((g) => g['id'] == selectedId).firstOrNull;
    if (selected == null) {
      return {'supported': false, 'reason': 'selected_source_not_active'};
    }
    final stations = <String, Map>{
      for (final station in snapshots) station['code'].toString(): station,
    };
    // Use post-merge group diagnostics, not the pre-merge station-owner cache.
    final owners = <String, Set<Object>>{};
    for (final group in groups) {
      final id = group['id'];
      if (id == null) continue;
      for (final code in (group['assigned_station_codes'] as List? ?? [])) {
        if (stations.containsKey(code)) {
          owners.putIfAbsent(code.toString(), () => {}).add(id);
        }
      }
    }
    final adjacency =
        request.metadata['nied_detection_adj_station_codes'] as Map?;
    final reachable = <String, Set<Object>>{};
    for (final group in groups) {
      final id = group['id'];
      if (id == null) continue;
      final pending = owners.entries
          .where((e) => e.value.length == 1 && e.value.contains(id))
          .map((e) => e.key)
          .toList();
      final visited = <String>{};
      for (var i = 0; i < pending.length; i++) {
        final code = pending[i];
        if (!visited.add(code)) continue;
        final assigned = owners[code];
        if (assigned != null &&
            (assigned.length != 1 || !assigned.contains(id))) {
          continue;
        }
        reachable.putIfAbsent(code, () => {}).add(id);
        for (final neighbor in (adjacency?[code] as Iterable? ?? const [])) {
          final next = neighbor.toString();
          if (stations.containsKey(next) && !visited.contains(next)) {
            pending.add(next);
          }
        }
      }
    }
    final key = identity(selected);
    final state = _states.putIfAbsent(key, _EventState.new);
    final associated = <String, double>{};
    final reasons = <String, int>{};
    for (final entry in stations.entries) {
      final candidates = reachable[entry.key];
      final directOwners = owners[entry.key];
      final reason = directOwners != null && directOwners.length > 1
          ? 'ambiguous_direct_owner'
          : candidates == null || candidates.isEmpty
          ? 'no_active_owner_path'
          : candidates.length > 1
          ? 'ambiguous_owner_path'
          : !candidates.contains(selectedId)
          ? 'other_event'
          : null;
      if (reason != null) {
        reasons[reason] = (reasons[reason] ?? 0) + 1;
        continue;
      }
      final value = entry.value['shindo'];
      if (value is! num || !value.isFinite) continue;
      associated[entry.key] = value.toDouble();
    }
    final rawMaximum = state.rawHold.update(associated, time);
    state.quantizedHold.updateFrame(associated, observedAt: time);
    final quantizedMaximum = state.quantizedHold.maximumFor(associated.keys);
    final multiple = groups.length > 1;
    SrevKaizouMagnitudeResult? calculate(double? value) => value == null
        ? null
        : calculateSrevKaizouMagnitude(
            sourceLatitude: output.latitude,
            sourceLongitude: output.longitude,
            inputIntensity: value,
            multipleSources: multiple,
          );
    final reportNumber = (selected['report_num'] as num?)?.toInt() ?? 0;
    final stable = selected['stable'] == true;
    final quantizedLocked = state.quantizedPublication.update(
      reportNumber: reportNumber,
      stable: stable,
      calculate: () => calculate(quantizedMaximum),
    );
    // Preserve the existing multiple-source conversion in this experiment.
    final continuousInput = multiple ? quantizedMaximum : rawMaximum;
    final continuousLocked = state.continuousPublication.update(
      reportNumber: reportNumber,
      stable: stable,
      calculate: () => calculate(continuousInput),
    );
    final refreshed = calculate(continuousInput);
    if (refreshed != null &&
        (state.peak == null || refreshed.magnitude > state.peak!)) {
      state.peak = refreshed.magnitude;
      state.peakAt = time;
    }
    var untimedCount = 0;
    String? strongestCode;
    for (final entry in associated.entries) {
      if (stations[entry.key]?['triggerStamp'] == null) untimedCount++;
      if (strongestCode == null || entry.value > associated[strongestCode]!) {
        strongestCode = entry.key;
      }
    }
    return {
      'supported': refreshed != null,
      'eventKey': key,
      'multipleSources': multiple,
      'selectedDetectionId': selectedId,
      'associatedStationCount': associated.length,
      'associatedUntimedCount': untimedCount,
      'associatedCodes': associated.keys.toList()..sort(),
      'rejectedCounts': reasons,
      'strongestCode': strongestCode,
      'strongestRawIntensity': associated[strongestCode],
      'heldContinuousIntensity': rawMaximum,
      'heldQuantizedIntensity': quantizedMaximum,
      'associatedQuantizedLockedMagnitude': quantizedLocked?.magnitude,
      'associatedContinuousLockedMagnitude': continuousLocked?.magnitude,
      'associatedContinuousRefreshedMagnitude': refreshed?.magnitude,
      'associatedContinuousPeakMagnitude': state.peak,
      'peakObservedAtUtc': state.peakAt?.toUtc().toIso8601String(),
      'publicationState': state.continuousPublication.toDiagnostics(),
      'refreshedDiagnostics': refreshed?.toDiagnostics(),
      'eventPeakCandidate': _eventCandidate.observe(
        eventKey: key,
        associated: associated,
        latitude: output.latitude,
        longitude: output.longitude,
        multipleSources: multiple,
      ),
      'modelChanged': false,
      'feedsProduction': false,
    };
  }
}

class _EventState {
  final rawHold = _ContinuousHold();
  final quantizedHold = SrevKaizouMagnitudeIntensityState();
  final quantizedPublication = SrevKaizouMagnitudePublicationState();
  final continuousPublication = SrevKaizouMagnitudePublicationState();
  double? peak;
  DateTime? peakAt;
}

class _ContinuousHold {
  final _values = <String, ({double value, DateTime time})>{};

  double? update(Map<String, double> current, DateTime time) {
    _values.removeWhere(
      (_, held) =>
          time.difference(held.time) > srevKaizouMaximumShindoHoldDuration,
    );
    for (final entry in current.entries) {
      final previous = _values[entry.key];
      if (previous == null || entry.value > previous.value) {
        _values[entry.key] = (value: entry.value, time: time);
      }
    }
    double? maximum;
    for (final code in current.keys) {
      final value = _values[code]?.value;
      if (value != null && (maximum == null || value > maximum)) {
        maximum = value;
      }
    }
    return maximum;
  }
}
