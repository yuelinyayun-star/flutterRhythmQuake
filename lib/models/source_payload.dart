import 'dart:collection';

/// Copies a decoded JSON event without normalizing values or sharing mutable
/// nested containers with the source parser.
Map<String, dynamic> snapshotSourcePayload(Map<String, dynamic> payload) {
  if (payload is _SourcePayloadSnapshot) return payload;
  return _SourcePayloadSnapshot(
    payload.map((key, value) => MapEntry(key, _snapshotValue(value))),
  );
}

/// Only snapshots created here can be reused without copying mutable arrays.
List<dynamic> snapshotSourcePayloadList(List<dynamic> payload) {
  if (payload is _SourcePayloadListSnapshot) return payload;
  return _SourcePayloadListSnapshot(
    payload.map(_snapshotValue).toList(growable: false),
  );
}

class _SourcePayloadSnapshot extends UnmodifiableMapView<String, dynamic> {
  _SourcePayloadSnapshot(super.map);
}

class _SourcePayloadListSnapshot extends UnmodifiableListView<dynamic> {
  _SourcePayloadListSnapshot(super.list);
}

dynamic _snapshotValue(dynamic value) {
  if (value is Map) {
    if (value is _SourcePayloadSnapshot) return value;
    return snapshotSourcePayload(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return snapshotSourcePayloadList(value);
  }
  return value;
}
