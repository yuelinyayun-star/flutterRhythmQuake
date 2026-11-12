import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/unified_quake_data.dart';
import 'quake_time.dart';

/// A filename component only; the original event fields are never changed.
String replayNameComponent(
  String value, {
  int maxLength = 40,
  int maxBytes = 160,
}) {
  var result = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'[. ]+$'), '');
  final buffer = StringBuffer();
  var length = 0;
  var bytes = 0;
  for (final rune in result.runes) {
    final width = rune > 0xffff ? 2 : 1;
    final byteWidth = utf8.encode(String.fromCharCode(rune)).length;
    if (length + width > maxLength || bytes + byteWidth > maxBytes) {
      break;
    }
    buffer.writeCharCode(rune);
    length += width;
    bytes += byteWidth;
  }
  result = buffer.toString().replaceFirst(RegExp(r'[. ]+$'), '');
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(result)) {
    result = '_$result';
  }
  return result;
}

/// Readable event label using the supplied report's location and magnitude.
/// The short identity suffix distinguishes truncated/sanitized event IDs.
String replayEventName(UnifiedQuakeData event) {
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = event.originTime == null
      ? null
      : QuakeTime.unifiedInstantUtc(event).add(const Duration(hours: 8));
  final identity = sha256
      .convert(utf8.encode(jsonEncode([event.source, event.eventId])))
      .toString()
      .substring(0, 8);
  final parts = [
    if (clock != null)
      '${clock.year}-${two(clock.month)}-${two(clock.day)}_'
          '${two(clock.hour)}-${two(clock.minute)}-${two(clock.second)}_UTC+8',
    if (event.hypocenter.trim().isNotEmpty)
      replayNameComponent(event.hypocenter, maxLength: 32),
    if (event.magnitude.isFinite && event.magnitude >= 0) 'M${event.magnitude}',
    if (event.source.isNotEmpty)
      replayNameComponent(event.source, maxLength: 20),
    if (event.eventId.isNotEmpty)
      replayNameComponent(event.eventId, maxLength: 28),
  ].where((part) => part.isNotEmpty).join('_');
  // The collector appends a full SHA-256 and extension. Keep the complete
  // filename below Linux's 255-byte limit, including multibyte place names.
  return '${replayNameComponent(parts, maxLength: 150, maxBytes: 160)}_$identity';
}
