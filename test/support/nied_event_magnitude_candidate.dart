import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';
import 'nied_station_paired_candidate.dart';

/// Offline event-level magnitude candidate. It never feeds production estimates.
class NiedEventMagnitudeCandidate {
  String? _eventId;
  DateTime? _lastFrameTime;
  Map<String, _GroupFrame> _previousGroups = <String, _GroupFrame>{};
  Map<String, _GroupFrame> _currentGroups = <String, _GroupFrame>{};
  Map<String, _GroupPeakState> _states = <String, _GroupPeakState>{};
  List<Map<String, Object?>> _migrationDecisions = <Map<String, Object?>>[];
  Set<String> _duplicateCurrentKeys = <String>{};
  String? _frameResetReason;

  /// Begins a frame, migrating only when membership gives unique evidence.
  void beginFrame({
    required String eventId,
    required DateTime time,
    required List<Map> groups,
  }) {
    final resetForEvent = _eventId != null && _eventId != eventId;
    final resetForClock =
        _lastFrameTime != null && time.isBefore(_lastFrameTime!);
    _frameResetReason = resetForEvent
        ? 'event_id_changed'
        : resetForClock
        ? 'clock_moved_backwards'
        : null;
    if (resetForEvent || resetForClock) _clearState();

    _eventId = eventId;
    _lastFrameTime = time;
    final previousDuplicateKeys = _duplicateCurrentKeys;
    final nextGroups = <String, _GroupFrame>{};
    final duplicateKeys = <String>{};
    for (final group in groups) {
      final key = _eventKey(eventId, group);
      final frameGroup = _GroupFrame.fromMap(key, group);
      if (nextGroups.containsKey(key)) {
        duplicateKeys.add(key);
      } else {
        nextGroups[key] = frameGroup;
      }
    }
    _duplicateCurrentKeys = duplicateKeys;
    _migrationDecisions = <Map<String, Object?>>[];

    // Compare only the immediately preceding frame with this frame. The
    // older frame remains diagnostic history, never migration evidence.
    for (final predecessor in _currentGroups.values) {
      final successors = nextGroups.values
          .where(
            (candidate) =>
                candidate.key != predecessor.key &&
                predecessor.hasCompleteMembership &&
                candidate.hasCompleteMembership &&
                candidate.assignedStationCodes.containsAll(
                  predecessor.assignedStationCodes,
                ),
          )
          .toList(growable: false);

      if (nextGroups.containsKey(predecessor.key)) {
        if (successors.isNotEmpty) {
          _migrationDecisions.add(
            _decision(
              predecessor,
              reason: 'simultaneous_groups_no_transfer',
              successors: successors,
            ),
          );
        }
        continue;
      }
      if (!predecessor.hasCompleteMembership) {
        _migrationDecisions.add(
          _decision(
            predecessor,
            reason: 'missing_or_empty_predecessor_membership',
          ),
        );
        continue;
      }
      if (successors.isEmpty) {
        _migrationDecisions.add(
          _decision(predecessor, reason: 'no_full_membership_containment'),
        );
        continue;
      }
      if (successors.length != 1) {
        _migrationDecisions.add(
          _decision(
            predecessor,
            reason: 'ambiguous_multiple_successors',
            successors: successors,
          ),
        );
        continue;
      }

      final successor = successors.single;
      if (_currentGroups.containsKey(successor.key)) {
        _migrationDecisions.add(
          _decision(
            predecessor,
            reason: 'simultaneous_groups_no_transfer',
            successors: successors,
          ),
        );
        continue;
      }
      if (previousDuplicateKeys.contains(predecessor.key) ||
          _duplicateCurrentKeys.contains(predecessor.key) ||
          _duplicateCurrentKeys.contains(successor.key)) {
        _migrationDecisions.add(
          _decision(
            predecessor,
            reason: 'duplicate_event_key_no_transfer',
            successors: successors,
          ),
        );
        continue;
      }

      final oldState = _states[predecessor.key];
      var transferredCount = 0;
      if (oldState != null) {
        final newState = _states.putIfAbsent(
          successor.key,
          _GroupPeakState.new,
        );
        for (final entry in oldState.peaksByStation.entries) {
          final existing = newState.peaksByStation[entry.key];
          if (existing == null || entry.value > existing) {
            newState.peaksByStation[entry.key] = entry.value;
          }
          transferredCount++;
        }
      }
      _migrationDecisions.add(
        _decision(
          predecessor,
          reason: 'unique_membership_containment',
          successors: successors,
          transferredStationPeakCount: transferredCount,
        ),
      );
    }

    final liveKeys = nextGroups.keys.toSet();
    _states.removeWhere((key, _) => !liveKeys.contains(key));
    for (final key in liveKeys) {
      _states.putIfAbsent(key, _GroupPeakState.new);
    }
    _previousGroups = _currentGroups;
    _currentGroups = nextGroups;
  }

  /// Adds this frame's associated raw station values and recalculates magnitude.
  Map<String, Object?> observe({
    required String eventKey,
    required Map<String, double> associated,
    required double latitude,
    required double longitude,
    required bool multipleSources,
  }) {
    final frameGroup = _currentGroups[eventKey];
    final migration = _migrationDecisions
        .where((decision) => decision['successorEventKey'] == eventKey)
        .toList(growable: false);
    final base = <String, Object?>{
      'candidateOnly': true,
      'feedsProduction': false,
      'modelChanged': false,
      'eventKey': eventKey,
      'eventId': _eventId,
      'observedAtUtc': _lastFrameTime?.toUtc().toIso8601String(),
      'inheritancePolicy': 'membership_containment_evidence',
      'inheritanceEvidenceIsOfficialMergeProof': false,
      'inheritanceDecisions': migration,
      'frameMigrationDecisions': _migrationDecisions,
      'migrationCoverage': _migrationCoverage(),
      if (_frameResetReason != null) 'frameResetReason': _frameResetReason,
    };
    if (frameGroup == null || _duplicateCurrentKeys.contains(eventKey)) {
      return <String, Object?>{
        ...base,
        'supported': false,
        'reason': frameGroup == null
            ? 'event_key_not_in_current_frame'
            : 'duplicate_event_key_in_current_frame',
        'magnitude': null,
        'peakIntensity': null,
        'stationPeakCount': 0,
      };
    }

    final state = _states.putIfAbsent(eventKey, _GroupPeakState.new);
    var acceptedCount = 0;
    var invalidCount = 0;
    for (final entry in associated.entries) {
      if (!entry.value.isFinite) {
        invalidCount++;
        continue;
      }
      acceptedCount++;
      final previousPeak = state.peaksByStation[entry.key];
      if (previousPeak == null || entry.value > previousPeak) {
        state.peaksByStation[entry.key] = entry.value;
      }
    }

    double? peakIntensity;
    final peakStationCodes = <String>[];
    for (final entry in state.peaksByStation.entries) {
      if (peakIntensity == null || entry.value > peakIntensity) {
        peakIntensity = entry.value;
        peakStationCodes
          ..clear()
          ..add(entry.key);
      } else if (entry.value == peakIntensity) {
        peakStationCodes.add(entry.key);
      }
    }
    peakStationCodes.sort();

    final result = peakIntensity == null
        ? null
        : calculateSrevKaizouMagnitude(
            sourceLatitude: latitude,
            sourceLongitude: longitude,
            inputIntensity: peakIntensity,
            multipleSources: multipleSources,
          );
    final sortedStationPeaks = state.peaksByStation.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String, Object?>{
      ...base,
      'supported': result != null,
      if (result == null) 'reason': 'no_finite_peak_or_magnitude_result',
      'latitude': latitude,
      'longitude': longitude,
      'multipleSources': multipleSources,
      'inputStationCount': associated.length,
      'acceptedInputStationCount': acceptedCount,
      'invalidInputStationCount': invalidCount,
      'stationPeakCount': state.peaksByStation.length,
      'stationPeaks': <String, double>{
        for (final entry in sortedStationPeaks) entry.key: entry.value,
      },
      'peakIntensity': peakIntensity,
      'peakStationCodes': peakStationCodes,
      'magnitude': result?.magnitude,
      'magnitudeDiagnostics': result?.toDiagnostics(),
      'stationPairedCandidate': calculateNiedStationPairedCandidate(
        latitude: latitude,
        longitude: longitude,
        intensity: peakIntensity,
        strongestCodes: peakStationCodes,
        multipleSources: multipleSources,
      ),
    };
  }

  Map<String, Object?> _decision(
    _GroupFrame predecessor, {
    required String reason,
    List<_GroupFrame> successors = const <_GroupFrame>[],
    int transferredStationPeakCount = 0,
  }) {
    final successor = successors.length == 1 ? successors.single : null;
    final matchedCount = successor == null
        ? null
        : predecessor.assignedStationCodes
              .where(successor.assignedStationCodes.contains)
              .length;
    return <String, Object?>{
      'predecessorEventKey': predecessor.key,
      'successorEventKey': reason == 'unique_membership_containment'
          ? successor?.key
          : null,
      'candidateSuccessorEventKeys':
          successors.map((group) => group.key).toList()..sort(),
      'reason': reason,
      'predecessorMembershipComplete': predecessor.hasCompleteMembership,
      'predecessorAssignedStationCodeCount':
          predecessor.assignedStationCodes.length,
      'matchedAssignedStationCodeCount': matchedCount,
      'completeAssignedStationCodeCount':
          reason == 'unique_membership_containment'
          ? predecessor.assignedStationCodes.length
          : 0,
      'transferredStationPeakCount': transferredStationPeakCount,
      'inheritanceEvidence':
          'assigned_station_codes membership containment only; not official merged-group proof',
    };
  }

  Map<String, Object?> _migrationCoverage() {
    final reasons = _migrationDecisions.map((d) => d['reason'] as String);
    int count(String reason) =>
        reasons.where((value) => value == reason).length;
    return <String, Object?>{
      'predecessorsConsidered': _migrationDecisions.length,
      'transferred': count('unique_membership_containment'),
      'ambiguous': count('ambiguous_multiple_successors'),
      'coexistenceBlocked': count('simultaneous_groups_no_transfer'),
      'unmatched': count('no_full_membership_containment'),
      'membershipUnavailable': count('missing_or_empty_predecessor_membership'),
      'duplicateKeys': count('duplicate_event_key_no_transfer'),
      'noPriorGroupHistory': _previousGroups.isEmpty,
    };
  }

  void _clearState() {
    _previousGroups = <String, _GroupFrame>{};
    _currentGroups = <String, _GroupFrame>{};
    _states = <String, _GroupPeakState>{};
    _migrationDecisions = <Map<String, Object?>>[];
    _duplicateCurrentKeys = <String>{};
  }

  static String _eventKey(String eventId, Map group) =>
      '$eventId:${group['id']}:${group['serial']}:${group['created_at']}';
}

class _GroupFrame {
  const _GroupFrame({
    required this.key,
    required this.assignedStationCodes,
    required this.hasCompleteMembership,
  });

  final String key;
  final Set<String> assignedStationCodes;
  final bool hasCompleteMembership;

  factory _GroupFrame.fromMap(String key, Map group) {
    final raw = group['assigned_station_codes'];
    if (raw is! List || raw.isEmpty) {
      return _GroupFrame(
        key: key,
        assignedStationCodes: <String>{},
        hasCompleteMembership: false,
      );
    }
    final codes = <String>{};
    var complete = true;
    for (final value in raw) {
      if (value is! String || value.isEmpty) {
        complete = false;
      } else {
        codes.add(value);
      }
    }
    return _GroupFrame(
      key: key,
      assignedStationCodes: codes,
      hasCompleteMembership: complete && codes.isNotEmpty,
    );
  }
}

class _GroupPeakState {
  final peaksByStation = <String, double>{};
}
