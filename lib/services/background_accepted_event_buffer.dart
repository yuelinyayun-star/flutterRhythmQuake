import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/unified_quake_data.dart';

/// Keeps accepted source reports available when the UI isolate is suspended.
class BackgroundAcceptedEventBuffer {
  BackgroundAcceptedEventBuffer(this._preferences, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _rows.addAll(_preferences.getStringList(preferenceKey) ?? const []);
    _prune();
  }

  static const preferenceKey = 'background_accepted_event_buffer';
  static const _maxEntries = 40;
  static const _maxBytes = 2 * 1024 * 1024;
  static const _maxAge = Duration(hours: 24);

  final SharedPreferences _preferences;
  final DateTime Function() _now;
  final List<String> _rows = [];
  Future<void> _pendingSave = Future.value();

  void add(UnifiedQuakeData event) {
    if (event.isHistory || event.isSnapshot) return;
    final row = jsonEncode({
      'receivedAt': _now().toUtc().millisecondsSinceEpoch,
      'event': event.toMap(),
    });
    if (utf8.encode(row).length > _maxBytes) return;
    _rows.add(row);
    _prune();
    final snapshot = List<String>.of(_rows);
    _pendingSave = _pendingSave.then((_) async {
      try {
        await _preferences.setStringList(preferenceKey, snapshot);
      } catch (error) {
        debugPrint('[BackgroundEvent] buffer save failed: $error');
      }
    });
  }

  List<UnifiedQuakeData> snapshot() {
    _prune();
    final events = <UnifiedQuakeData>[];
    for (final row in _rows) {
      try {
        final entry = jsonDecode(row) as Map<String, dynamic>;
        events.add(
          UnifiedQuakeData.fromMap(
            Map<String, dynamic>.from(entry['event'] as Map),
          ),
        );
      } catch (_) {
        // One damaged stored row must not hide the other received reports.
      }
    }
    return events;
  }

  Future<void> flush() => _pendingSave;

  void _prune() {
    final oldest = _now().toUtc().subtract(_maxAge).millisecondsSinceEpoch;
    _rows.removeWhere((row) {
      try {
        final entry = jsonDecode(row) as Map<String, dynamic>;
        return (entry['receivedAt'] as int) < oldest;
      } catch (_) {
        return true;
      }
    });
    while (_rows.length > _maxEntries ||
        _rows.fold<int>(0, (size, row) => size + utf8.encode(row).length) >
            _maxBytes) {
      _rows.removeAt(0);
    }
  }
}
