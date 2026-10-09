import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/unified_quake_data.dart';

/// Local sequence for a source which supplies event IDs and revisions, but no
/// report number. The original source payload is only read, never changed.
class SasmexReportSequence {
  final Map<String, _ReportState> _events = {};
  static const _maxEvents = 64;
  static const _maxBodies = 128;

  UnifiedQuakeData? accept(UnifiedQuakeData event) {
    final body = event.sourcePayload;
    if (body == null) return null;
    // updated is a revision timestamp, not an earthquake parameter. Keep every
    // other raw field (including sent/epochMs, coordinates and description).
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode(
              _ordered({
                for (final entry in body.entries)
                  if (entry.key != 'updated') entry.key: entry.value,
              }),
            ),
          ),
        )
        .toString();
    final time = event.reportTime?.millisecondsSinceEpoch;
    var state = _events[event.eventId];
    if (state == null) {
      state = _ReportState(1, fingerprint, time, [fingerprint]);
      _events[event.eventId] = state;
      while (_events.length > _maxEvents) {
        _events.remove(_events.keys.first);
      }
    } else {
      final newer = time != null && (state.time == null || time > state.time!);
      if (time != null && state.time != null && time < state.time!) {
        return null;
      }
      if (fingerprint != state.body) {
        // An old body with no newer source timestamp cannot displace a later
        // report. A changed reconnect snapshot needs explicit chronology too.
        if (!newer &&
            (event.isSnapshot || state.seenBodies.contains(fingerprint))) {
          return null;
        }
        state.number++;
        state.body = fingerprint;
        state.seenBodies.remove(fingerprint);
        state.seenBodies.add(fingerprint);
        if (state.seenBodies.length > _maxBodies) {
          state.seenBodies.removeAt(0);
        }
      }
      if (newer) state.time = time;
    }
    return event.copyWith(
      reportNumText: '第${state.number}報',
      hasReportSequence: true,
    );
  }

  String encode() => jsonEncode({
    for (final entry in _events.entries)
      entry.key: {
        'number': entry.value.number,
        'body': entry.value.body,
        'time': entry.value.time,
        'seenBodies': entry.value.seenBodies,
      },
  });

  void restore(String encoded) {
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final restored = <String, _ReportState>{};
    for (final entry in decoded.entries) {
      final value = entry.value as Map<String, dynamic>;
      final number = value['number'] as int;
      final body = value['body'] as String;
      if (number < 1 || body.isEmpty) continue;
      final seen = (value['seenBodies'] as List).cast<String>().toList();
      if (seen.length > _maxBodies) {
        seen.removeRange(0, seen.length - _maxBodies);
      }
      restored[entry.key] = _ReportState(
        number,
        body,
        value['time'] as int?,
        seen,
      );
    }
    while (restored.length > _maxEvents) {
      restored.remove(restored.keys.first);
    }
    _events.addAll(restored);
  }

  static dynamic _ordered(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _ordered(value[key])};
    }
    if (value is List) return value.map(_ordered).toList();
    return value;
  }
}

class _ReportState {
  _ReportState(this.number, this.body, this.time, this.seenBodies);
  int number;
  String body;
  int? time;
  final List<String> seenBodies;
}
