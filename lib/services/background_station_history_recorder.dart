import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/eew_event_group.dart';
import '../models/station_history_frame.dart';
import '../models/unified_quake_data.dart';
import 'eew_history_store.dart';

/// Background-isolate owner of EEW station-history recording (workflow E).
///
/// While a recording window is active, this recorder is the single writer of
/// station frame files, event manifests and the history index. The UI isolate
/// forwards its capture frames here and suspends its own writes; if the UI
/// engine dies, this recorder keeps recording from the background station
/// payloads (snapshot fidelity degrades for UI-derived fields such as the
/// NIED detection overlay, but the recording itself survives).
class BackgroundStationHistoryRecorder {
  BackgroundStationHistoryRecorder({
    required this.preferenceKey,
    required void Function(List<Map<String, dynamic>> records) onRecordingEnded,
    EewHistoryStore? store,
    DateTime Function()? clock,
  }) : _store = store ?? EewHistoryStore(preferenceKey: preferenceKey),
       _onRecordingEnded = onRecordingEnded,
       _clock = clock;

  final String preferenceKey;
  final EewHistoryStore _store;
  final void Function(List<Map<String, dynamic>> records) _onRecordingEnded;
  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  final Map<String, EewEventGroup> _recordingGroups = {};
  List<EewEventGroup> _existingGroups = const [];
  final Set<String> _enabledKinds = Set.of(StationHistoryFrame.kinds);
  final Map<String, DateTime> _lastUiFrameAt = {};
  bool _recording = false;
  bool _finalizing = false;
  DateTime _lastEewEventAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _persistTimer;
  Timer? _safetyTimer;
  Future<void>? _restoring;
  SharedPreferences? _preferences;
  Future<void> _saveChain = Future<void>.value();

  /// UI forwarding is considered dead after this gap; background payloads
  /// then feed the recorder directly so a killed UI engine cannot stall EEW
  /// recording.
  static const Duration _uiFrameStaleAfter = Duration(seconds: 4);

  /// Safety valve for a dead UI engine: without EEW updates the recording
  /// window is finalized after this silence.
  static const Duration _eewSilenceTimeout = Duration(minutes: 10);

  static const Duration _windowBeforeFirstArrival = Duration(minutes: 3);

  bool get recording => _recording;

  /// UI-provided canonical group identities plus the user's per-kind capture
  /// toggles. Seeds win over provisional background-derived groups because
  /// they carry the exact [EewEventGroup.firstArrivedAt] the UI used.
  Future<void> setRecording(
    bool recording, {
    List<Map<String, dynamic>> groups = const [],
    List<String>? enabledKinds,
    SharedPreferences? preferences,
  }) async {
    if (preferences != null) _preferences = preferences;
    if (enabledKinds != null && enabledKinds.isNotEmpty) {
      _enabledKinds
        ..clear()
        ..addAll(enabledKinds.where(StationHistoryFrame.kinds.contains));
    }
    if (!recording) {
      if (!_recording) return;
      await _finalize();
      return;
    }
    if (!_recording) {
      _recording = true;
      _lastEewEventAt = _now;
      _armSafetyTimer();
    }
    await _ensureRestored();
    for (final seed in groups) {
      final key = seed['recordKey']?.toString();
      if (key == null || key.isEmpty) continue;
      final latestMap = seed['latest'];
      if (latestMap is! Map) continue;
      final latest = UnifiedQuakeData.fromMap(
        Map<String, dynamic>.from(latestMap),
      );
      final firstArrivedAt = DateTime.tryParse(
        seed['firstArrivedAt']?.toString() ?? '',
      )?.toUtc();
      final existing = _recordingGroups[key];
      if (existing == null) {
        final baseIndex = _existingGroups.indexWhere(
          (group) => _recordKey(group) == key,
        );
        var base = baseIndex >= 0
            ? _existingGroups.removeAt(baseIndex)
            : EewEventGroup(
                eventId: latest.eventId,
                reports: [latest],
                firstArrivedAt: firstArrivedAt ?? DateTime.now().toUtc(),
              );
        base = base.addReport(latest);
        if (firstArrivedAt != null) {
          base = base.copyWith(firstArrivedAt: firstArrivedAt);
        }
        _recordingGroups[key] = base;
      } else if (firstArrivedAt != null) {
        _recordingGroups[key] = existing.copyWith(
          firstArrivedAt: firstArrivedAt,
        );
      }
    }
    _scheduleSave();
  }

  /// Every live EEW report forwarded through the background engine refreshes
  /// the window and the provisional groups (used when the UI cannot seed).
  Future<void> observeEewEvent(UnifiedQuakeData event) async {
    if (!event.isEew || event.isReplay || event.isHistory || event.isSnapshot) {
      return;
    }
    _lastEewEventAt = _now;
    if (!_recording) return;
    await _ensureRestored();
    final key = _keyFor(event.source, event.eventId);
    if (!_recordingGroups.containsKey(key)) {
      final baseIndex = _existingGroups.indexWhere(
        (group) => _recordKey(group) == key,
      );
      final base = baseIndex >= 0
          ? _existingGroups.removeAt(baseIndex)
          : EewEventGroup(
              eventId: event.eventId,
              reports: [event],
              firstArrivedAt: DateTime.now().toUtc(),
            );
      _recordingGroups[key] = base.addReport(event);
    } else {
      _recordingGroups[key] = _recordingGroups[key]!.addReport(event);
    }
    _armSafetyTimer();
    _scheduleSave();
  }

  /// Frames forwarded by the UI capture listener (authoritative content).
  Future<void> acceptUiFrame(Map<String, dynamic> frameMap) async {
    if (!_recording) return;
    final StationHistoryFrame frame;
    try {
      frame = StationHistoryFrame.fromMap(frameMap);
    } on Object catch (error) {
      debugPrint('[BackgroundStationHistory] invalid UI frame: $error');
      return;
    }
    _lastUiFrameAt[frame.kind] = _now;
    await _recordFrame(frame);
  }

  /// Fallback frames built from background bridge payloads. Only used while
  /// the UI engine stopped forwarding (killed or suspended) for this kind.
  void observeStationPayload(Map<String, dynamic> payload) {
    if (!_recording) return;
    final kind = payload['kind']?.toString();
    if (kind == null || !_enabledKinds.contains(kind)) return;
    final now = _now;
    final lastUi = _lastUiFrameAt[kind];
    if (lastUi != null && now.difference(lastUi) < _uiFrameStaleAfter) {
      return;
    }
    final original = payload['originalJson'];
    try {
      _recordFrame(
        StationHistoryFrame(
          receivedAt: now,
          snapshot: Map<String, dynamic>.of(payload)..remove('originalJson'),
          originalJson: original is Map
              ? Map<String, dynamic>.from(original)
              : null,
        ),
      );
    } on Object catch (error) {
      debugPrint('[BackgroundStationHistory] invalid payload frame: $error');
    }
  }

  Future<void> _recordFrame(StationHistoryFrame frame) async {
    await _ensureRestored();
    var changed = false;
    for (final key in List.of(_recordingGroups.keys)) {
      final group = _recordingGroups[key]!;
      if (frame.receivedAt.isBefore(
        group.firstArrivedAt.toUtc().subtract(_windowBeforeFirstArrival),
      )) {
        continue;
      }
      _recordingGroups[key] = _store.acceptFrame(group, frame);
      changed = true;
    }
    if (changed) _scheduleSave();
  }

  void _scheduleSave() {
    _persistTimer ??= Timer(const Duration(seconds: 2), () {
      _persistTimer = null;
      _saveChain = _saveChain.then(
        (_) => _save(),
        onError: (Object error, StackTrace stack) {
          debugPrint('[BackgroundStationHistory] save failed: $error\n$stack');
        },
      );
    });
  }

  Future<void> _save() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await _store.save(preferences, [
      ..._existingGroups,
      ..._recordingGroups.values,
    ]);
  }

  Future<void> _ensureRestored() {
    return _restoring ??= () async {
      final preferences = _preferences;
      if (preferences == null) return;
      _existingGroups = await _store.restoreForStartup(
        preferences,
        lazyReports: true,
        migrateLegacy: false,
      );
    }();
  }

  Future<void> _finalize() async {
    if (_finalizing) return;
    _finalizing = true;
    _recording = false;
    _safetyTimer?.cancel();
    _safetyTimer = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    try {
      await _ensureRestored();
      await _saveChain;
      await _save();
      final records = [
        for (final entry in _recordingGroups.entries)
          {
            'key': entry.key,
            'frameKeys': [...?entry.value.storedStations?.frameKeys],
          },
      ];
      await _store.flushFiles();
      _onRecordingEnded(records);
      _existingGroups = [..._existingGroups, ..._recordingGroups.values];
      _recordingGroups.clear();
    } finally {
      _finalizing = false;
    }
  }

  void _armSafetyTimer() {
    _safetyTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_recording) return;
      if (_now.difference(_lastEewEventAt) >= _eewSilenceTimeout) {
        unawaited(_finalize());
      }
    });
  }

  String _recordKey(EewEventGroup group) =>
      _keyFor(group.latest.source, group.eventId);

  String _keyFor(String source, String eventId) =>
      EewHistoryStore.recordKeyFor(preferenceKey, source, eventId);
}
