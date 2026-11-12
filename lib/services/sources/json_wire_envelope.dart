import 'dart:convert';

/// Exact existing source wrappers, not a JavaScript evaluator or full SSE codec.
enum JsonWireEnvelope {
  jsonp,
  assignment,
  sseDataLine,
  jsonpTight,
  firstObject,
  weatherAlarmAssignment,
}

/// Non-native platform implementation and original-algorithm comparison path.
dynamic decodeJsonWireEnvelope(
  String source,
  JsonWireEnvelope kind,
  String name, {
  dynamic Function(String) decoder = jsonDecode,
}) {
  switch (kind) {
    case JsonWireEnvelope.jsonp:
    case JsonWireEnvelope.jsonpTight:
      final gap = kind == JsonWireEnvelope.jsonp ? r'\s*' : '';
      final match = RegExp(
        '^\\s*${RegExp.escape(name)}$gap\\(([\\s\\S]*)\\)\\s*;?\\s*\$',
      ).firstMatch(source);
      if (match == null) throw const FormatException('Invalid JSONP');
      return decoder(match.group(1)!);
    case JsonWireEnvelope.assignment:
      final match = RegExp(
        '(?:^|[;\\s])var\\s+${RegExp.escape(name)}\\s*=\\s*',
      ).firstMatch(source);
      if (match == null ||
          match.end >= source.length ||
          !['{', '['].contains(source[match.end])) {
        throw FormatException('Missing JSON variable: $name');
      }
      var depth = 0, quoted = false, escaped = false;
      for (var i = match.end; i < source.length; i++) {
        final char = source[i];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            quoted = false;
          }
          continue;
        }
        if (char == '"') quoted = true;
        if (char == '{' || char == '[') depth++;
        if ((char == '}' || char == ']') && --depth == 0) {
          return decoder(source.substring(match.end, i + 1));
        }
      }
      throw const FormatException('Incomplete JSON assignment');
    case JsonWireEnvelope.sseDataLine:
      if (!source.startsWith('data:')) {
        throw const FormatException('Not an SSE data line');
      }
      return decoder(source.substring(5).trimLeft());
    case JsonWireEnvelope.firstObject:
      final start = source.indexOf('{'), end = source.lastIndexOf('}');
      if (start < 0 || end <= start)
        throw const FormatException('Missing JSON object');
      return decoder(source.substring(start, end + 1));
    case JsonWireEnvelope.weatherAlarmAssignment:
      final match = RegExp(
        r'var\s+alarminfo\s*=\s*(\{[\s\S]*?\})\s*;?',
      ).firstMatch(source);
      if (match == null)
        throw const FormatException('Missing weather alarm assignment');
      return decoder(match.group(1)!);
  }
}
