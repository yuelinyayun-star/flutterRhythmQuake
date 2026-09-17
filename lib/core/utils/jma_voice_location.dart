import 'jma_voice_locations.g.dart';

/// Exact official names only: never infer a location or strip unknown kana.
String jmaVoiceLocation(String original) {
  final name = original.trim();
  final exact = jmaVoiceLocations[name];
  if (exact != null) return exact;
  return name.splitMapJoin(
    RegExp(r'[、,，／/\n]+'),
    onMatch: (match) => match.group(0)!,
    onNonMatch: (part) => jmaVoiceLocations[part.trim()] ?? part,
  );
}
