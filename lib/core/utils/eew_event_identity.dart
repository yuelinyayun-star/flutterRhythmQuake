import '../../models/unified_quake_data.dart';
import 'quake_time.dart';

/// Stable identity of aliases already verified by the event matcher. Reusing
/// its first accepted key keeps UI/history, speech and old-report state aligned
/// when a transport switches between an agency ID and an opaque delivery ID.
/// This does not widen the matcher's time or coordinate tolerances.
class EewEventIdentityRegistry {
  static const maxAliases = 256;
  final Map<String, String> _aliases = {};

  String _scope(UnifiedQuakeData event) =>
      '${event.replaySessionId ?? ''}|${event.source}|';

  String resolve(UnifiedQuakeData event) {
    final id = canonicalEewEventId(event);
    return _aliases['${_scope(event)}$id'] ?? id;
  }

  /// Keep a new alias only with matching origin/parameters, or an already saved
  /// group. Mere proximity can still use the existing temporary match rules but
  /// cannot permanently associate two different IDs.
  void rememberMatch(
    UnifiedQuakeData previous,
    UnifiedQuakeData incoming, {
    bool fromSavedGroup = false,
  }) {
    if (!previous.isEew ||
        !incoming.isEew ||
        previous.source != incoming.source ||
        previous.replaySessionId != incoming.replaySessionId) {
      return;
    }
    if (!fromSavedGroup &&
        (previous.originTime == null ||
            incoming.originTime == null ||
            QuakeTime.unifiedInstantUtc(previous) !=
                QuakeTime.unifiedInstantUtc(incoming) ||
            previous.lat == null ||
            previous.lng == null ||
            previous.lat != incoming.lat ||
            previous.lng != incoming.lng ||
            !previous.magnitude.isFinite ||
            previous.magnitude <= 0 ||
            previous.magnitude != incoming.magnitude ||
            (previous.depth >= 0 &&
                incoming.depth >= 0 &&
                previous.depth != incoming.depth))) {
      return;
    }
    final oldRawId = canonicalEewEventId(previous);
    final newRawId = canonicalEewEventId(incoming);
    if (oldRawId.isEmpty || newRawId.isEmpty) return;
    final oldRoot = resolve(previous);
    final newRoot = resolve(incoming);
    if (oldRoot == newRoot) return;
    final scope = _scope(previous);
    for (final key in _aliases.keys.toList()) {
      if (key.startsWith(scope) && _aliases[key] == newRoot) {
        _aliases[key] = oldRoot;
      }
    }
    _aliases['$scope$oldRawId'] = oldRoot;
    _aliases['$scope$newRawId'] = oldRoot;
    while (_aliases.length > maxAliases) {
      _aliases.remove(_aliases.keys.first);
    }
  }

  void clearReplay(String session) =>
      _aliases.removeWhere((key, _) => key.startsWith('$session|'));
}

/// Compare agency identity without rewriting an upstream ID or payload.
/// FAN's captured CWA namespace wraps the same seven-digit bulletin identity
/// supplied directly by Jian/Wolfx. Other ID formats retain their old rules.
String canonicalEewEventId(UnifiedQuakeData event) {
  final original = event.eventId.trim();
  if (!event.isEew || event.source != 'cwaEew') return original;
  final prefix = event.isReplay ? '${event.replaySessionId}:' : '';
  final id = prefix.isNotEmpty && original.startsWith(prefix)
      ? original.substring(prefix.length)
      : original;
  final match = RegExp(
    r'^(?:cwa\.gov\.tw_earthquakeEW_)?(\d{7})$',
  ).firstMatch(id);
  return match == null ? original : '$prefix${match.group(1)}';
}
