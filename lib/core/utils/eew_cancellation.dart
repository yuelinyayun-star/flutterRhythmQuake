import '../../models/unified_quake_data.dart';
import '../../services/ntp_service.dart';
import 'quake_time.dart';

/// Call only after matching the agency/event identity. A cancellation closes
/// an event even when the agency assigns it a lower or unchanged serial number.
bool isEewCancellationTransition(
  UnifiedQuakeData previous,
  UnifiedQuakeData incoming,
) {
  if (!previous.isEew ||
      !incoming.isEew ||
      previous.isCanceled ||
      !incoming.isCanceled ||
      previous.source != incoming.source) {
    return false;
  }
  if (previous.reportTime == null || incoming.reportTime == null) return true;
  return !QuakeTime.unifiedInstantUtc(
    incoming,
    value: incoming.reportTime,
  ).isBefore(QuakeTime.unifiedInstantUtc(previous, value: previous.reportTime));
}

/// Separate source freshness at admission from the 20-second display window.
/// Some transports retain the last ordinary report's time on cancellation.
/// Such a delivery can close a recently observed event, but cannot revive an
/// unknown old snapshot. [previous] may be the latest saved lightweight report.
bool canAcceptEewCancellation(
  UnifiedQuakeData incoming, {
  UnifiedQuakeData? previous,
  DateTime? now,
  DateTime? localNow,
}) {
  if (!incoming.isEew || !incoming.isCanceled || incoming.isHistory) {
    return false;
  }
  if (previous != null && !isEewCancellationTransition(previous, incoming)) {
    return false;
  }
  final sourceNow = (now ?? NtpService().now).toUtc().subtract(
    incoming.replayClockOffset,
  );
  final reference = incoming.reportTime ?? incoming.originTime;
  if (reference != null) {
    final age = sourceNow.difference(
      QuakeTime.unifiedInstantUtc(incoming, value: reference),
    );
    if (age >= const Duration(seconds: -5) &&
        age < const Duration(seconds: 20)) {
      return true;
    }
  }
  final arrivedAt = previous?.arrivedAt;
  if (previous == null || arrivedAt == null) return false;
  final age = (localNow ?? DateTime.now()).difference(arrivedAt);
  return !age.isNegative &&
      age < Duration(seconds: QuakeTime.eewTimeoutSecondsUnified(previous));
}

int eewCancellationDisplayElapsed(UnifiedQuakeData event, {DateTime? now}) {
  final arrivedAt = event.arrivedAt;
  if (arrivedAt == null) return 0;
  return (now ?? DateTime.now())
      .difference(arrivedAt)
      .inSeconds
      .clamp(0, 999999);
}

Map<String, DateTime> decodeCanceledEewEvents(
  Iterable<String> rows, {
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).toUtc().subtract(
    const Duration(hours: 24),
  );
  final result = <String, DateTime>{};
  for (final row in rows) {
    final separator = row.lastIndexOf('|');
    if (separator < 1) continue;
    final milliseconds = int.tryParse(row.substring(separator + 1));
    if (milliseconds == null) continue;
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    if (time.isBefore(cutoff)) continue;
    final key = row.substring(0, separator);
    if (result[key] == null || time.isAfter(result[key]!)) result[key] = time;
  }
  final entries = result.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(entries.take(200));
}

List<String> encodeCanceledEewEvents(Map<String, DateTime> events) => [
  for (final entry in events.entries)
    '${entry.key}|${entry.value.millisecondsSinceEpoch}',
];
