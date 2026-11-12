/// CWA's loc/placeName may contain a distance from a county office followed
/// by the actual epicentral area. Only shorten the display; retain the wire
/// location in sourcePayload for the full report.
String cwaDisplayLocation(String original) {
  final match = RegExp(r'[（(]\s*位[於于]\s*([^()（）]+)[)）]').firstMatch(original);
  final area = match?.group(1)?.trim();
  return area == null || area.isEmpty ? original : area;
}
