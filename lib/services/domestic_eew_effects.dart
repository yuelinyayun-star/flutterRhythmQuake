import '../core/utils/quake_time.dart';
import '../models/unified_quake_data.dart';

typedef _ReportShape = (int, double, double, double, double);

/// Shares only fill ownership and threshold sounds after an identical domestic
/// report has actually been observed. Does not merge or rewrite UI events.
class DomesticEewEffects {
  final _members = <String, _Effects>{};
  int _sequence = 0;

  static String _key(UnifiedQuakeData e) => '${e.source}|${e.eventId}';

  static _ReportShape? _shape(UnifiedQuakeData e) {
    if (!e.isEew ||
        !const {'ceaEew', 'scEew', 'fjEew', 'cqEew'}.contains(e.source) ||
        e.eventId.trim().isEmpty ||
        e.originTime == null ||
        e.lat == null ||
        e.lng == null ||
        !e.lat!.isFinite ||
        !e.lng!.isFinite ||
        e.lat!.abs() > 90 ||
        e.lng!.abs() > 180 ||
        (e.lat == 0 && e.lng == 0) ||
        !e.magnitude.isFinite ||
        e.magnitude <= 0 ||
        !e.depth.isFinite ||
        e.depth < 0) {
      return null;
    }
    return (
      QuakeTime.unifiedInstantUtc(e).microsecondsSinceEpoch,
      e.lat!,
      e.lng!,
      e.magnitude,
      e.depth,
    );
  }

  void observe(UnifiedQuakeData event) {
    final shape = _shape(event);
    if (shape == null || event.isCanceled) return;
    final key = _key(event);
    var effects = _members[key];
    final matches = _members.values
        .toSet()
        .where(
          (candidate) =>
              candidate.shapes.containsKey(shape) &&
              candidate.members.entries.every(
                (member) => member.value != event.source || member.key == key,
              ),
        )
        .toList();
    effects ??= matches.firstOrNull ?? _Effects();
    for (final other in matches) {
      if (identical(other, effects)) continue;
      // Never join distinct event IDs belonging to the same agency.
      if (other.members.entries.any(
        (member) => effects!.members.entries.any(
          (own) => own.value == member.value && own.key != member.key,
        ),
      )) {
        continue;
      }
      effects.members.addAll(other.members);
      for (final entry in other.shapes.entries) {
        final existing = effects.shapes[entry.key];
        if (existing == null || entry.value < existing) {
          effects.shapes[entry.key] = entry.value;
        }
      }
      effects.caution |= other.caution;
      effects.warn |= other.warn;
      final preferOther = other.reportTime != null && effects.reportTime != null
          ? other.reportTime!.isAfter(effects.reportTime!)
          : other.revision > effects.revision;
      if (preferOther) {
        effects.owner = other.owner;
        effects.fillShape = other.fillShape;
        effects.revision = other.revision;
        effects.reportTime = other.reportTime;
      }
      for (final member in other.members.keys) {
        _members[member] = effects;
      }
    }
    effects.members[key] = event.source;
    _members[key] = effects;
    final revision = effects.shapes.putIfAbsent(shape, () => ++_sequence);
    final reportTime = event.reportTime == null
        ? null
        : QuakeTime.unifiedInstantUtc(event, value: event.reportTime);
    final isOlder =
        reportTime != null &&
        effects.reportTime != null &&
        reportTime.isBefore(effects.reportTime!);
    final isNewer =
        reportTime != null &&
        effects.reportTime != null &&
        reportTime.isAfter(effects.reportTime!);
    // A delayed copy of an observed old report must not restore its old fill.
    // Without publication time, order new content by acceptance, not agency
    // report numbers (which need not share a numbering scheme).
    if (!isOlder &&
        (isNewer || revision > effects.revision || effects.owner == key)) {
      effects.owner = key;
      effects.fillShape = shape;
      effects.revision = revision;
      effects.reportTime = reportTime;
    }
  }

  bool shouldDrawFill(UnifiedQuakeData event) {
    final effects = _members[_key(event)];
    return effects == null ||
        (effects.owner == _key(event) && effects.fillShape == _shape(event));
  }

  bool claimThresholdSound(UnifiedQuakeData event, {required bool warn}) {
    final effects = _members[_key(event)];
    if (effects == null) return true;
    if (warn) {
      if (effects.warn) return false;
      effects.warn = true;
      effects.caution = true;
    } else {
      if (effects.caution) return false;
      effects.caution = true;
    }
    return true;
  }

  void retainActive(Iterable<UnifiedQuakeData> events) {
    final keys = events.map(_key).toSet();
    final expired = _members.values
        .toSet()
        .where((effects) => !effects.members.keys.any(keys.contains))
        .toSet();
    _members.removeWhere((key, effects) => expired.contains(effects));
  }

  void clear() => _members.clear();
}

class _Effects {
  final members = <String, String>{};
  final shapes = <_ReportShape, int>{};
  String? owner;
  _ReportShape? fillShape;
  int revision = -1;
  DateTime? reportTime;
  bool caution = false;
  bool warn = false;
}
