import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Copies a decoded JSON event without normalizing values or sharing mutable
/// nested containers with the source parser.
Map<String, dynamic> snapshotSourcePayload(Map<String, dynamic> payload) {
  if (payload is _SourcePayloadSnapshot ||
      payload is EncodedSourcePayload ||
      payload is SourcePayloadFields) {
    return payload;
  }
  return _SourcePayloadSnapshot(
    payload.map((key, value) => MapEntry(key, _snapshotValue(value))),
  );
}

/// One immutable schema shared by every station; original key order is kept.
final class SourcePayloadLayout {
  SourcePayloadLayout(List<String> keys)
    : keys = List.unmodifiable(keys),
      _indices = Map.unmodifiable({
        for (var i = 0; i < keys.length; i++) keys[i]: i,
      }) {
    if (_indices.length != keys.length)
      throw ArgumentError('Duplicate JSON keys');
  }
  final List<String> keys;
  final Map<String, int> _indices;
}

/// Frozen original values without allocating a hash-map node for every field.
/// JSON/FFI consumers still see the complete ordered Map. No station, timer,
/// native owner or mutable source container is retained in this object.
final class SourcePayloadFields extends MapBase<String, dynamic> {
  SourcePayloadFields(this.layout, List<dynamic> values)
    : _values = List.unmodifiable(values.map(_snapshotValue)) {
    if (values.length != layout.keys.length)
      throw ArgumentError('JSON field count');
  }
  final SourcePayloadLayout layout;
  final List<dynamic> _values;
  @override
  Iterable<String> get keys => layout.keys;
  @override
  int get length => _values.length;
  @override
  bool containsKey(Object? key) => layout._indices.containsKey(key);
  @override
  dynamic operator [](Object? key) {
    final i = layout._indices[key];
    return i == null ? null : _values[i];
  }

  @override
  Iterable<MapEntry<String, dynamic>> get entries sync* {
    for (var i = 0; i < _values.length; i++) {
      yield MapEntry(layout.keys[i], _values[i]);
    }
  }

  @override
  void forEach(void Function(String, dynamic) action) {
    for (var i = 0; i < _values.length; i++) {
      action(layout.keys[i], _values[i]);
    }
  }

  @override
  void operator []=(String key, dynamic value) =>
      throw UnsupportedError('Frozen source fields');
  @override
  dynamic remove(Object? key) => throw UnsupportedError('Frozen source fields');
  @override
  void clear() => throw UnsupportedError('Frozen source fields');
}

/// Complete historical JSON, held as UTF-8 instead of thousands of map nodes.
/// Reads materialize immutable values temporarily; exports keep the same JSON
/// values and key order. No decoded graph is retained after the read.
class EncodedSourcePayload extends MapBase<String, dynamic> {
  EncodedSourcePayload(Map<String, dynamic> payload)
    : _bytes = Uint8List.fromList(JsonUtf8Encoder().convert(payload)),
      _keys = List.unmodifiable(payload.keys);

  final Uint8List _bytes;
  final List<String> _keys;

  Map<String, dynamic> _decode() => snapshotSourcePayload(
    jsonDecode(utf8.decode(_bytes)) as Map<String, dynamic>,
  );

  @override
  Iterable<String> get keys => _keys;
  @override
  int get length => _keys.length;
  @override
  bool containsKey(Object? key) => _keys.contains(key);
  @override
  dynamic operator [](Object? key) => containsKey(key) ? _decode()[key] : null;
  @override
  void forEach(void Function(String, dynamic) action) =>
      _decode().forEach(action);
  @override
  Iterable<MapEntry<String, dynamic>> get entries => _decode().entries;
  @override
  Iterable<dynamic> get values => _decode().values;
  @override
  void operator []=(String key, dynamic value) =>
      throw UnsupportedError('Historical source payload is immutable');
  @override
  dynamic remove(Object? key) =>
      throw UnsupportedError('Historical source payload is immutable');
  @override
  void clear() =>
      throw UnsupportedError('Historical source payload is immutable');
}

Map<String, dynamic> compactSourcePayload(Map<String, dynamic> payload) =>
    payload is EncodedSourcePayload ? payload : EncodedSourcePayload(payload);

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
    if (value is Map<String, dynamic>) return snapshotSourcePayload(value);
    return snapshotSourcePayload(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return snapshotSourcePayloadList(value);
  }
  return value;
}
