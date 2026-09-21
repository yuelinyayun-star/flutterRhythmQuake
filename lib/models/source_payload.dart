/// Copies a decoded JSON event without normalizing values or sharing mutable
/// nested containers with the source parser.
Map<String, dynamic> snapshotSourcePayload(Map<String, dynamic> payload) =>
    Map<String, dynamic>.unmodifiable(
      payload.map((key, value) => MapEntry(key, _snapshotValue(value))),
    );

dynamic _snapshotValue(dynamic value) {
  if (value is Map) {
    return snapshotSourcePayload(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_snapshotValue));
  }
  return value;
}
