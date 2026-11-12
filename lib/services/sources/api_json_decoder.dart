import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'station_json_decoder.dart';
import 'json_wire_envelope.dart';
export 'json_wire_envelope.dart' show JsonWireEnvelope;
import '../../models/source_payload.dart';

/// Decodes the original API text. Windows uses the native JSON kernel; all
/// native output is independently owned before returning. A single parser per
/// isolate reuses bounded scratch buffers through a weak reference. The cache
/// does not keep a decoder alive under GC and creates no application timers.
/// The returned graph has jsonDecode's mutable, growable container contract.
/// Only containers actually written to are copied into Dart collections.
dynamic decodeApiJson(String source) {
  if (!StationJsonDecoder.nativeSupported) return jsonDecode(source);
  return _decodeNative(source, null);
}

/// Original UTF-8 bytes pass directly to the native validator/parser. No
/// whole-payload Dart string or re-encoded UTF-8 buffer is allocated.
dynamic decodeApiJsonBytes(List<int> source) {
  if (!StationJsonDecoder.nativeSupported) {
    return jsonDecode(utf8.decode(source));
  }
  return _decodeNative(null, source);
}

/// Read-only consumers can use the owned native document directly, avoiding
/// mutable container wrappers for every coordinate pair. Callers never write
/// through this view; original Dart decoding is retained on non-native builds.
dynamic decodeApiJsonDocument(Object source) {
  if (!StationJsonDecoder.nativeSupported) {
    return jsonDecode(
      source is String ? source : utf8.decode(source as List<int>),
    );
  }
  return _decodeNative(
    source is String ? source : null,
    source is List<int> ? source : null,
    null,
    '',
    false,
  );
}

/// Use the source's existing UTF-8 error policy before JSON/wrapper parsing.
/// Raw input is never edited; malformed-byte replacement is opt-in only for
/// endpoints whose previous decoder already used allowMalformed: true.
dynamic decodeApiJsonIngressBytes(
  List<int> source, {
  bool allowMalformed = false,
  JsonWireEnvelope? envelope,
  String name = '',
}) {
  final cached = _decoder?.target;
  final decoder = cached ?? StationJsonDecoder(prepareStationNumbers: false);
  if (cached == null) _decoder = WeakReference(decoder);
  try {
    return _mutable(
      decoder.decodeIngressUtf8(
        source,
        allowMalformed: allowMalformed,
        envelope: envelope,
        name: name,
      ),
    );
  } catch (_) {
    disposeApiJsonResources();
    rethrow;
  }
}

/// Current TREM contract: each data: line is one independent JSON message.
/// Preserve CR/LF, split UTF-8, EOF, invalid-JSON skip and strict UTF-8 errors.
/// Each subscription owns its native framer and releases it on cancel/error/EOF.
Stream<Map<String, dynamic>> decodeApiSseStream(
  Stream<List<int>> source, {
  bool preferNative = true,
}) async* {
  if (!preferNative || !StationJsonDecoder.nativeSupported) {
    await for (final line
        in source.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      try {
        final value = decodeApiJsonEnvelope(line, JsonWireEnvelope.sseDataLine);
        if (value is Map<String, dynamic> && value.isNotEmpty) yield value;
      } on FormatException {
        /* Existing per-line malformed JSON skip. */
      }
    }
    return;
  }
  final decoder = StationJsonDecoder(prepareStationNumbers: false);
  try {
    await for (final chunk in source) {
      for (final value in decoder.feedSseUtf8(chunk)) {
        if (value is Map<String, dynamic> && value.isNotEmpty)
          yield _mutable(value);
      }
    }
    for (final value in decoder.feedSseUtf8(const [], finish: true)) {
      if (value is Map<String, dynamic> && value.isNotEmpty)
        yield _mutable(value);
    }
  } finally {
    decoder.dispose();
  }
}

dynamic decodeApiJsonEnvelope(
  String source,
  JsonWireEnvelope kind, [
  String name = '',
]) {
  if (!StationJsonDecoder.nativeSupported) {
    return decodeJsonWireEnvelope(source, kind, name);
  }
  return _decodeNative(source, null, kind, name);
}

dynamic decodeApiJsonEnvelopeBytes(
  List<int> source,
  JsonWireEnvelope kind, [
  String name = '',
]) {
  if (!StationJsonDecoder.nativeSupported) {
    return decodeJsonWireEnvelope(utf8.decode(source), kind, name);
  }
  return _decodeNative(null, source, kind, name);
}

/// Preserve package:http's response.body charset contract exactly. Only UTF-8
/// bodies use byte ingress; other encodings retain the declared interpretation.
dynamic decodeApiJsonResponse(http.Response response) {
  final header = response.headers['content-type'];
  final type = header == null
      ? MediaType('application', 'octet-stream')
      : MediaType.parse(header);
  final charset = type.parameters['charset'];
  final encoding = charset == null
      ? (type.type == 'application' && type.subtype == 'json' ? utf8 : latin1)
      : Encoding.getByName(charset) ?? latin1;
  return encoding == utf8
      ? decodeApiJsonBytes(response.bodyBytes)
      : decodeApiJson(response.body);
}

/// Collects original HTTP chunks without building or joining decoded strings.
/// Callers keep their existing timeout and connection/close ordering.
Future<Uint8List> readApiJsonBytes(
  Stream<List<int>> source, {
  Duration? timeout,
}) async {
  final collecting = source.fold<BytesBuilder>(
    BytesBuilder(copy: false),
    (buffer, chunk) => buffer..add(chunk),
  );
  final buffer = timeout == null
      ? await collecting
      : await collecting.timeout(timeout);
  return buffer.takeBytes();
}

dynamic _decodeNative(
  String? text,
  List<int>? bytes, [
  JsonWireEnvelope? kind,
  String name = '',
  bool mutable = true,
]) {
  final cached = _decoder?.target;
  final decoder = cached ?? StationJsonDecoder(prepareStationNumbers: false);
  if (cached == null) _decoder = WeakReference(decoder);
  try {
    final value = kind == null
        ? (text != null ? decoder.decode(text) : decoder.decodeUtf8(bytes!))
        : (text != null
              ? decoder.decodeEnvelope(text, kind, name)
              : decoder.decodeEnvelopeUtf8(bytes!, kind, name));
    return mutable ? _mutable(value) : value;
  } catch (_) {
    disposeApiJsonResources();
    rethrow;
  }
}

WeakReference<StationJsonDecoder>? _decoder;

/// Frees parser scratch only. Published graphs stay valid; the next API call
/// recreates its parser. Used at application shutdown and diagnostic teardown.
void disposeApiJsonResources() {
  _decoder?.target?.dispose();
  _decoder = null;
}

dynamic _mutable(dynamic value, [void Function()? onChange]) {
  if (value is Map<String, dynamic>) return _ApiMap(value, onChange);
  if (value is List) return _ApiList(value, onChange);
  return value;
}

final class _ApiMap extends MapBase<String, dynamic>
    implements SourceJsonSnapshot {
  _ApiMap(this._original, this._onChange);
  final void Function()? _onChange;
  bool _changed = false;
  void _change() {
    if (_changed) return;
    _changed = true;
    _onChange?.call();
  }

  @override
  dynamic freezeSourceJson() => !_changed && _original != null
      ? _original!
      : snapshotSourcePayload(_write());
  Map<String, dynamic>? _original;
  Map<String, dynamic>? _written;
  Map<String, dynamic>? _children;
  int _version = 0;

  @override
  int get length => (_written ?? _original!).length;
  @override
  bool containsKey(Object? key) => (_written ?? _original!).containsKey(key);
  @override
  Iterable<String> get keys => _ApiKeys(this);
  @override
  dynamic operator [](Object? key) {
    if (_written != null) return _written![key];
    final value = _original![key];
    if (value is! Map && value is! List) return value;
    return (_children ??= {}).putIfAbsent(
      key as String,
      () => _mutable(value, _change),
    );
  }

  Map<String, dynamic> _write() {
    if (_written != null) return _written!;
    final result = <String, dynamic>{};
    for (final key in _original!.keys) {
      result[key] = this[key];
    }
    _written = result;
    _original = null;
    _children = null;
    return result;
  }

  @override
  void operator []=(String key, dynamic value) {
    _change();
    if (!containsKey(key)) _version++;
    _write()[key] = value;
  }

  @override
  dynamic remove(Object? key) {
    if (!containsKey(key)) return null;
    _change();
    _version++;
    return _write().remove(key);
  }

  @override
  void clear() {
    if (isEmpty) return;
    _change();
    _version++;
    _written = <String, dynamic>{};
    _original = null;
    _children = null;
  }
}

final class _ApiKeys extends IterableBase<String> {
  _ApiKeys(this._map);
  final _ApiMap _map;
  @override
  int get length => _map.length;
  @override
  Iterator<String> get iterator => _ApiKeyIterator(_map);
}

final class _ApiKeyIterator implements Iterator<String> {
  _ApiKeyIterator(this._map)
    : _version = _map._version,
      _iterator = (_map._written ?? _map._original!).keys.iterator;
  final _ApiMap _map;
  final int _version;
  final Iterator<String> _iterator;
  @override
  String get current => _iterator.current;
  @override
  bool moveNext() {
    if (_version != _map._version) throw ConcurrentModificationError(_map);
    return _iterator.moveNext();
  }
}

final class _ApiList extends ListBase<dynamic> implements SourceJsonSnapshot {
  _ApiList(this._original, this._onChange);
  final void Function()? _onChange;
  bool _changed = false;
  void _change() {
    if (_changed) return;
    _changed = true;
    _onChange?.call();
  }

  @override
  dynamic freezeSourceJson() => !_changed && _original != null
      ? _original!
      : snapshotSourcePayloadList(_write());
  List<dynamic>? _original;
  List<dynamic>? _written;
  Map<int, dynamic>? _children;
  @override
  int get length => (_written ?? _original!).length;
  @override
  set length(int value) {
    _change();
    _write().length = value;
  }

  @override
  dynamic operator [](int index) {
    if (_written != null) return _written![index];
    final value = _original![index];
    if (value is! Map && value is! List) return value;
    return (_children ??= {}).putIfAbsent(
      index,
      () => _mutable(value, _change),
    );
  }

  List<dynamic> _write() {
    if (_written != null) return _written!;
    final result = List<dynamic>.generate(length, (i) => this[i]);
    _written = result;
    _original = null;
    _children = null;
    return result;
  }

  @override
  void operator []=(int index, dynamic value) {
    _change();
    _write()[index] = value;
  }
}
