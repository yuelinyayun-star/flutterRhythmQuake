part of 'global_quake_service_io.dart';

typedef _GqAddNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Size,
      Pointer<Pointer<Uint8>>,
      Pointer<Size>,
    );
typedef _GqAddDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      Pointer<Pointer<Uint8>>,
      Pointer<Size>,
    );

final class _NativeJavaObjectStreamDecoder implements Finalizable {
  _NativeJavaObjectStreamDecoder() {
    _pointer = _bindings.create();
    if (_pointer == nullptr) throw StateError('Cannot create GQ stream');
    _finalizer.attach(this, _pointer, detach: this);
    try {
      _output = StationCoreBuffer(sizeOf<Pointer<Uint8>>());
      _outputLength = StationCoreBuffer(sizeOf<Size>());
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  static final _bindings = _GqBindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static Map<String, int> get diagnostics => {
    'sessions': _bindings.sessions(),
    'calls': _bindings.calls(),
  };
  late final Pointer<Void> _pointer;
  StationCoreBuffer? _input, _output, _outputLength;
  Uint8List? _inputBytes;
  bool _disposed = false;

  List<_JavaObject> add(Uint8List chunk) {
    if (_disposed) throw StateError('GQ decoder disposed');
    if ((_input?.length ?? 0) < chunk.length || _input == null) {
      _input?.dispose();
      _input = StationCoreBuffer(chunk.length);
      _inputBytes = _input!.pointer.asTypedList(chunk.length);
    }
    _inputBytes!.setRange(0, chunk.length, chunk);
    final status = _bindings.add(
      _pointer,
      _input!.pointer,
      chunk.length,
      _output!.pointer.cast(),
      _outputLength!.pointer.cast(),
    );
    if (status != 0) {
      throw FormatException('GlobalQuake native stream status $status');
    }
    final length = _outputLength!.pointer.cast<Size>().value;
    if (length == 0) return const [];
    final pointer = _output!.pointer.cast<Pointer<Uint8>>().value;
    final reader = _GqGraphReader(pointer.asTypedList(length));
    final result = <_JavaObject>[];
    while (!reader.done) {
      reader.references.clear();
      result.add(reader.value() as _JavaObject);
    }
    return result;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
    _input?.dispose();
    _input = null;
    _inputBytes = null;
    _output?.dispose();
    _outputLength?.dispose();
  }
}

class _GqGraphReader {
  _GqGraphReader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  final references = <int, dynamic>{};
  int offset = 0;
  bool get done => offset == bytes.length;
  int u8() => bytes[offset++];
  int u32() {
    final value = data.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  Uint8List block() {
    final length = u32();
    final value = Uint8List.fromList(
      Uint8List.sublistView(bytes, offset, offset + length),
    );
    offset += length;
    return value;
  }

  String text() {
    final length = u32();
    final value = utf8.decode(
      Uint8List.sublistView(bytes, offset, offset + length),
      allowMalformed: true,
    );
    offset += length;
    return value;
  }

  dynamic value() {
    switch (u8()) {
      case 0:
        return null;
      case 1:
        return false;
      case 2:
        return true;
      case 3:
        final result = data.getInt64(offset, Endian.little);
        offset += 8;
        return result;
      case 4:
        final result = data.getFloat64(offset, Endian.little);
        offset += 8;
        return result;
      case 5:
        return text();
      case 6:
        final id = u32();
        final result = _JavaObject(text());
        references[id] = result;
        final count = u32();
        for (var i = 0; i < count; i++) {
          final key = text();
          result.fields[key] = value();
        }
        final customCount = u32();
        for (var i = 0; i < customCount; i++) {
          final key = text();
          final length = u32();
          result.customData[key] = [for (var j = 0; j < length; j++) value()];
        }
        return result;
      case 7:
        final id = u32();
        final count = u32();
        final result = <dynamic>[];
        references[id] = result;
        for (var i = 0; i < count; i++) {
          result.add(value());
        }
        return result;
      case 8:
        final id = u32();
        final result = _JavaBlockData(block());
        references[id] = result;
        return result;
      case 9:
        final id = u32();
        final result = _JavaClassDesc(text());
        references[id] = result;
        result.flags = u8();
        final count = u32();
        for (var i = 0; i < count; i++) {
          final type = String.fromCharCode(u8());
          final name = text();
          final typeName = value() as String?;
          result.fields.add(_JavaField(type, name, typeName));
        }
        result.superDesc = value() as _JavaClassDesc?;
        return result;
      case 10:
        final id = u32();
        if (!references.containsKey(id)) {
          throw const FormatException('Invalid GQ graph reference');
        }
        return references[id];
      default:
        throw const FormatException('Invalid GQ graph tag');
    }
  }
}

class _GqBindings {
  _GqBindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_gq_stream_abi_version',
    )();
    if (version != 1) throw StateError('Unsupported GQ stream ABI $version');
    create = library
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'rq_gq_stream_create',
        );
    add = library.lookupFunction<_GqAddNative, _GqAddDart>('rq_gq_stream_add');
    destroyPointer = library
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'rq_gq_stream_destroy',
        );
    destroy = destroyPointer.asFunction<void Function(Pointer<Void>)>();
    sessions = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_gq_stream_sessions',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_gq_stream_calls',
    );
  }
  late final Pointer<Void> Function() create;
  late final _GqAddDart add;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final int Function() sessions, calls;
}
