import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import '../../models/source_payload.dart';
import 'native_station_core_library_io.dart';
import 'json_wire_envelope.dart';
import 'palert_wire_values.dart';

typedef _PAlertConfigureNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _SseFeedNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Uint32);
typedef _SseFeedDart = int Function(Pointer<Void>, Pointer<Uint8>, int, int);
typedef _SseNextNative =
    Int32 Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _SseNextDart =
    int Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _PAlertConfigureDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _PAlertExtractNative =
    Int32 Function(Pointer<Void>, Pointer<Pointer<Double>>, Pointer<Size>);
typedef _PAlertExtractDart =
    int Function(Pointer<Void>, Pointer<Pointer<Double>>, Pointer<Size>);

typedef _WrappedNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Void>,
      Size,
      Uint32,
      Pointer<Void>,
      Size,
      Pointer<Pointer<Uint8>>,
      Pointer<Size>,
    );
typedef _WrappedDart =
    int Function(
      Pointer<Void>,
      Pointer<Void>,
      int,
      int,
      Pointer<Void>,
      int,
      Pointer<Pointer<Uint8>>,
      Pointer<Size>,
    );

typedef _DecodeNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Void>,
      Size,
      Pointer<Pointer<Uint8>>,
      Pointer<Size>,
    );
typedef _DecodeDart =
    int Function(
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<Pointer<Uint8>>,
      Pointer<Size>,
    );

class StationJsonDecoder {
  StationJsonDecoder({
    this.preferNative = true,
    this.prepareStationNumbers = true,
  });
  final bool preferNative;
  final bool prepareStationNumbers;
  static bool get nativeSupported => StationCoreLibrary.supported;
  _NativeStationJson? _native;
  List<String> _palertIds = const [];

  void setPAlertStations(Iterable<String> ids) {
    final next = List<String>.unmodifiable(ids);
    if (next.toSet().length != next.length) {
      throw ArgumentError('Duplicate P-Alert station IDs');
    }
    _native?.configurePAlert(next);
    _palertIds = next;
  }

  PAlertWireResponse decodePAlertUtf8(
    List<int> input, {
    bool Function(dynamic)? shouldExtract,
  }) {
    if (!preferNative || !StationCoreLibrary.supported) {
      final raw = jsonDecode(utf8.decode(input));
      return PAlertWireResponse(
        raw,
        shouldExtract == null || shouldExtract(raw)
            ? PAlertWireValues.fromJson(raw, _palertIds)
            : null,
      );
    }
    try {
      final native = _native ??= _NativeStationJson();
      if (!native.palertConfigured) native.configurePAlert(_palertIds);
      final raw = native.decodeUtf8(input, false);
      return PAlertWireResponse(
        raw,
        shouldExtract == null || shouldExtract(raw)
            ? native.extractPAlert()
            : null,
      );
    } catch (_) {
      // A malformed frame must not retain parser scratch. Keep the directory
      // only, so the following valid frame can create an independent owner.
      _native?.dispose();
      _native = null;
      rethrow;
    }
  }

  dynamic decode(String input) => preferNative && StationCoreLibrary.supported
      ? (_native ??= _NativeStationJson()).decode(input, prepareStationNumbers)
      : jsonDecode(input);
  dynamic decodeUtf8(List<int> input) =>
      preferNative && StationCoreLibrary.supported
      ? (_native ??= _NativeStationJson()).decodeUtf8(
          input,
          prepareStationNumbers,
        )
      : jsonDecode(utf8.decode(input));
  dynamic decodeEnvelope(String input, JsonWireEnvelope kind, String name) =>
      preferNative && StationCoreLibrary.supported
      ? (_native ??= _NativeStationJson()).decodeEnvelope(
          input,
          null,
          kind,
          name,
        )
      : decodeJsonWireEnvelope(input, kind, name);
  dynamic decodeEnvelopeUtf8(
    List<int> input,
    JsonWireEnvelope kind,
    String name,
  ) => preferNative && StationCoreLibrary.supported
      ? (_native ??= _NativeStationJson()).decodeEnvelope(
          null,
          input,
          kind,
          name,
        )
      : decodeJsonWireEnvelope(utf8.decode(input), kind, name);
  void dispose() {
    _native?.dispose();
    _native = null;
    _palertIds = const [];
  }

  dynamic decodeIngressUtf8(
    List<int> input, {
    bool allowMalformed = false,
    JsonWireEnvelope? envelope,
    String name = '',
  }) {
    if (!preferNative || !StationCoreLibrary.supported) {
      final text = utf8.decode(input, allowMalformed: allowMalformed);
      return envelope == null
          ? jsonDecode(text)
          : decodeJsonWireEnvelope(text, envelope, name);
    }
    return (_native ??= _NativeStationJson()).decodeIngress(
      input,
      (envelope == null ? 0 : envelope.index + 1) |
          (allowMalformed ? 0x100 : 0),
      name,
    );
  }

  Iterable<dynamic> feedSseUtf8(List<int> input, {bool finish = false}) {
    if (!preferNative || !StationCoreLibrary.supported)
      throw StateError('Native SSE requires native station core');
    return (_native ??= _NativeStationJson()).feedSse(input, finish);
  }

  static Map<String, int> get diagnostics => {
    'sessions': _Bindings.instance.sessions(),
    'calls': _Bindings.instance.calls(),
  };
  static Map<String, int> get palertDiagnostics => {
    'calls': _PAlertBindings.instance.calls(),
  };
}

final class _NativeStationJson implements Finalizable {
  _NativeStationJson() {
    _owner = _Bindings.instance.create();
    if (_owner == nullptr) {
      throw StateError('Cannot create station JSON decoder');
    }
    _finalizer.attach(this, _owner, detach: this);
    try {
      _output = StationCoreBuffer(sizeOf<Pointer<Uint8>>());
      _length = StationCoreBuffer(sizeOf<Size>());
    } catch (_) {
      dispose();
      rethrow;
    }
  }
  static final _finalizer = NativeFinalizer(_Bindings.instance.destroyPointer);
  late final Pointer<Void> _owner;
  StationCoreBuffer? _input, _output, _length;
  Uint8List? _inputBytes;
  static final _surrogates = RegExp(r'[\uD800-\uDFFF]');
  bool _disposed = false;
  bool palertConfigured = false;
  int _palertCount = 0;

  void configurePAlert(List<String> ids) {
    if (_disposed) throw StateError('Disposed station JSON decoder');
    final bytes = ByteData(
      4 + ids.fold<int>(0, (size, id) => size + 4 + id.length * 2),
    );
    bytes.setUint32(0, ids.length, Endian.little);
    var offset = 4;
    for (final id in ids) {
      bytes.setUint32(offset, id.length, Endian.little);
      offset += 4;
      for (final unit in id.codeUnits) {
        bytes.setUint16(offset, unit, Endian.little);
        offset += 2;
      }
    }
    _reserveInput(bytes.lengthInBytes);
    _inputBytes!.setRange(0, bytes.lengthInBytes, bytes.buffer.asUint8List());
    final status = _PAlertBindings.instance.configure(
      _owner,
      _input!.pointer,
      bytes.lengthInBytes,
    );
    if (status != 0) throw StateError('P-Alert field layout failed ($status)');
    _palertCount = ids.length;
    palertConfigured = true;
  }

  PAlertWireValues extractPAlert() {
    final status = _PAlertBindings.instance.extract(
      _owner,
      _output!.pointer.cast(),
      _length!.pointer.cast(),
    );
    if (status != 0) {
      throw StateError('P-Alert field extraction failed ($status)');
    }
    final values = _output!.pointer.cast<Pointer<Double>>().value;
    final count = _length!.pointer.cast<Size>().value;
    return PAlertWireValues(
      Float64List.fromList(values.asTypedList(_palertCount * 4)),
      count,
    );
  }

  dynamic decode(String text, bool station) {
    if (_disposed) throw StateError('Disposed station JSON decoder');
    if (text.length > 32 * 1024 * 1024) {
      throw const FormatException('Station JSON size limit');
    }
    // Encoding surrogate units would replace unpaired values. Keep the exact
    // UTF-16 path for those strings (including paired literal surrogates).
    final encoded = text.length <= 64 * 1024 * 1024 ~/ 3
        ? utf8.encode(text)
        : null;
    final useUtf8 =
        encoded != null &&
        (encoded.length == text.length || !_surrogates.hasMatch(text));
    final needed = useUtf8 ? encoded.length : text.length * 2;
    _reserveInput(needed);
    if (useUtf8) {
      _inputBytes!.setRange(0, encoded.length, encoded);
    } else {
      _input!.pointer
          .cast<Uint16>()
          .asTypedList(text.length)
          .setRange(0, text.length, text.codeUnits);
    }
    return _readResult(
      (station
          ? (useUtf8
                ? _Bindings.instance.decodeUtf8
                : _Bindings.instance.decode)
          : (useUtf8
                ? _Bindings.instance.decodeApiUtf8
                : _Bindings.instance.decodeApi))(
        _owner,
        _input!.pointer.cast(),
        useUtf8 ? encoded.length : text.length,
        _output!.pointer.cast(),
        _length!.pointer.cast(),
      ),
    );
  }

  dynamic decodeUtf8(List<int> input, bool station) {
    if (_disposed) throw StateError('Disposed station JSON decoder');
    // Only unusually large byte payloads need materialization to enforce the
    // existing 32 Mi UTF-16-unit limit. Normal ingress never constructs text.
    if (input.length > 32 * 1024 * 1024) {
      return decode(utf8.decode(input), station);
    }
    if (input is! Uint8List) {
      for (final byte in input) {
        if (byte < 0 || byte > 255) {
          throw const FormatException('Invalid UTF-8 byte');
        }
      }
    }
    // Utf8Decoder consumes one leading BOM. Preserve every other byte,
    // including embedded BOMs and invalid sequences (validated by Rust).
    final start =
        input.length >= 3 &&
            input[0] == 0xef &&
            input[1] == 0xbb &&
            input[2] == 0xbf
        ? 3
        : 0;
    final length = input.length - start;
    _reserveInput(length);
    _inputBytes!.setRange(0, length, input, start);
    return _readResult(
      (station
          ? _Bindings.instance.decodeUtf8
          : _Bindings.instance.decodeApiUtf8)(
        _owner,
        _input!.pointer.cast(),
        length,
        _output!.pointer.cast(),
        _length!.pointer.cast(),
      ),
    );
  }

  void _reserveInput(int needed) {
    if (_input == null || _input!.length < needed) {
      _input?.dispose();
      _input = StationCoreBuffer(needed);
      _inputBytes = _input!.pointer.asTypedList(_input!.length);
    }
  }

  dynamic decodeEnvelope(
    String? text,
    List<int>? bytes,
    JsonWireEnvelope kind,
    String name,
  ) {
    if (_disposed) throw StateError('Disposed station JSON decoder');
    // Preserve the existing UTF-16-unit JSON size limit for unusually large
    // transports, including a large wrapper around a small JSON value.
    if (bytes != null &&
        (bytes.length > 32 * 1024 * 1024 || _surrogates.hasMatch(name))) {
      return decodeEnvelope(utf8.decode(bytes), null, kind, name);
    }
    final unitSize = bytes == null ? 2 : 1;
    final length = text?.length ?? bytes!.length;
    final selector = bytes == null ? name.codeUnits : utf8.encode(name);
    _reserveInput((length + selector.length) * unitSize);
    if (bytes != null) {
      if (bytes is! Uint8List && bytes.any((b) => b < 0 || b > 255)) {
        throw const FormatException('Invalid UTF-8 byte');
      }
      _inputBytes!.setRange(0, length, bytes);
      _inputBytes!.setRange(length, length + selector.length, selector);
    } else {
      final units = _input!.pointer.cast<Uint16>().asTypedList(
        length + selector.length,
      );
      units.setRange(0, length, text!.codeUnits);
      units.setRange(length, length + selector.length, selector);
    }
    return _readResult(
      (bytes == null
          ? _EnvelopeBindings.instance.utf16
          : _EnvelopeBindings.instance.utf8)(
        _owner,
        _input!.pointer.cast(),
        length,
        kind.index + 1,
        (_input!.pointer + length * unitSize).cast(),
        selector.length,
        _output!.pointer.cast(),
        _length!.pointer.cast(),
      ),
    );
  }

  dynamic _readResult(int status) {
    if (status != 0) {
      throw FormatException('Station JSON decode status $status');
    }
    final length = _length!.pointer.cast<Size>().value;
    final pointer = _output!.pointer.cast<Pointer<Uint8>>().value;
    final owned = Uint8List.fromList(pointer.asTypedList(length));
    return PackedSourceJson(owned).root;
  }

  dynamic decodeIngress(List<int> input, int mode, String name) {
    if (_disposed) throw StateError('Disposed station JSON decoder');
    final selector = utf8.encode(name);
    _reserveInput(input.length + selector.length);
    _inputBytes!.setRange(0, input.length, input);
    _inputBytes!.setRange(
      input.length,
      input.length + selector.length,
      selector,
    );
    return _readResult(
      _IngressBindings.instance.decode(
        _owner,
        _input!.pointer.cast(),
        input.length,
        mode,
        (_input!.pointer + input.length).cast(),
        selector.length,
        _output!.pointer.cast(),
        _length!.pointer.cast(),
      ),
    );
  }

  Iterable<dynamic> feedSse(List<int> input, bool finish) sync* {
    if (_disposed) throw StateError('Disposed station JSON decoder');
    _reserveInput(input.length);
    _inputBytes!.setRange(0, input.length, input);
    final bindings = _IngressBindings.instance;
    final status = bindings.feed(
      _owner,
      _input!.pointer.cast(),
      input.length,
      finish ? 1 : 0,
    );
    if (status != 0) throw FormatException('SSE input status $status');
    while (true) {
      final next = bindings.next(
        _owner,
        _output!.pointer.cast(),
        _length!.pointer.cast(),
      );
      if (next == 100) return;
      yield _readResult(next);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _Bindings.instance.destroy(_owner);
    _input?.dispose();
    _input = null;
    _inputBytes = null;
    _output?.dispose();
    _length?.dispose();
  }
}

class _PAlertBindings {
  _PAlertBindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_palert_values_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported P-Alert values ABI $version');
    }
    configure = library
        .lookupFunction<_PAlertConfigureNative, _PAlertConfigureDart>(
          'rq_palert_values_configure',
        );
    extract = library.lookupFunction<_PAlertExtractNative, _PAlertExtractDart>(
      'rq_palert_values_extract',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_palert_values_calls',
    );
  }
  static final instance = _PAlertBindings();
  late final _PAlertConfigureDart configure;
  late final _PAlertExtractDart extract;
  late final int Function() calls;
}

class _EnvelopeBindings {
  _EnvelopeBindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_json_envelope_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported JSON envelope ABI $version');
    }
    utf8 = library.lookupFunction<_WrappedNative, _WrappedDart>(
      'rq_api_json_wrapped_utf8',
    );
    utf16 = library.lookupFunction<_WrappedNative, _WrappedDart>(
      'rq_api_json_wrapped_utf16',
    );
  }
  static final instance = _EnvelopeBindings();
  late final _WrappedDart utf8, utf16;
}

class _IngressBindings {
  _IngressBindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_api_ingress_abi_version',
    )();
    if (version != 1) throw StateError('Unsupported API ingress ABI $version');
    decode = library.lookupFunction<_WrappedNative, _WrappedDart>(
      'rq_api_ingress_utf8',
    );
    feed = library.lookupFunction<_SseFeedNative, _SseFeedDart>(
      'rq_api_sse_feed',
    );
    next = library.lookupFunction<_SseNextNative, _SseNextDart>(
      'rq_api_sse_next',
    );
  }
  static final instance = _IngressBindings();
  late final _WrappedDart decode;
  late final _SseFeedDart feed;
  late final _SseNextDart next;
}

class _Bindings {
  _Bindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_station_json_abi_version',
    )();
    if (version != 2) throw StateError('Unsupported station JSON ABI $version');
    create = library
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'rq_station_json_create',
        );
    destroyPointer = library
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'rq_station_json_destroy',
        );
    destroy = destroyPointer.asFunction<void Function(Pointer<Void>)>();
    decode = library.lookupFunction<_DecodeNative, _DecodeDart>(
      'rq_station_json_decode',
    );
    decodeUtf8 = library.lookupFunction<_DecodeNative, _DecodeDart>(
      'rq_station_json_decode_utf8',
    );
    decodeApi = library.lookupFunction<_DecodeNative, _DecodeDart>(
      'rq_api_json_decode',
    );
    decodeApiUtf8 = library.lookupFunction<_DecodeNative, _DecodeDart>(
      'rq_api_json_decode_utf8',
    );
    sessions = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_json_sessions',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_json_calls',
    );
  }
  static final instance = _Bindings();
  late final Pointer<Void> Function() create;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final _DecodeDart decode, decodeUtf8, decodeApi, decodeApiUtf8;
  late final int Function() sessions, calls;
}
