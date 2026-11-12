import 'dart:ffi';
import 'dart:collection';
import 'dart:typed_data';
import '../sources/native_station_core_library_io.dart';

/// Original JSON values cross FFI as typed binary words, not rounded JSON.
/// The Rust owner builds the existing station-json-table-v1 archive off UI.
class NativeStationArchive {
  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static int get sessions => _bindings.sessions();
  static int get calls => _bindings.calls();

  static Uint8List encode(List<Map<String, dynamic>> frames) =>
      _encode(frames, compressed: false);
  static Uint8List encodeCompressed(List<Map<String, dynamic>> frames) =>
      _encode(frames, compressed: true);

  static Uint8List _encode(
    List<Map<String, dynamic>> frames, {
    required bool compressed,
  }) {
    final writer = _Values()..u32(frames.length);
    for (final frame in frames) {
      writer.value(frame);
    }
    final bytes = writer.bytes;
    final input = StationCoreBuffer(bytes.length);
    final status = StationCoreBuffer(4);
    Pointer<Void> owner = nullptr;
    StationCoreBuffer? output;
    try {
      input.pointer.asTypedList(bytes.length).setAll(0, bytes);
      owner = (compressed ? _bindings.createGzip : _bindings.create)(
        input.pointer,
        bytes.length,
        status.pointer.cast(),
      );
      final code = status.pointer.cast<Int32>().value;
      if (owner == nullptr || code != 0) {
        throw StateError('Native station archive failed (status $code)');
      }
      final length = _bindings.length(owner);
      if (length == 0 || length > _Values.limit) {
        throw StateError('Invalid native station archive length $length');
      }
      output = StationCoreBuffer(length);
      final copied = _bindings.copy(owner, output.pointer, length);
      if (copied != 0) throw StateError('Native station archive copy: $copied');
      return Uint8List.fromList(output.pointer.asTypedList(length));
    } finally {
      if (owner != nullptr) _bindings.destroy(owner);
      input.dispose();
      status.dispose();
      output?.dispose();
    }
  }
}

class _Values {
  static const limit = 128 * 1024 * 1024;
  Uint8List _buffer = Uint8List(65536);
  late ByteData _data = ByteData.sublistView(_buffer);
  final _strings = <String, int>{};
  final _containers = HashMap<Object, int>.identity();
  int _length = 0;
  Uint8List get bytes => Uint8List.sublistView(_buffer, 0, _length);
  void reserve(int count) {
    final required = _length + count;
    if (required > limit) {
      throw const FormatException('Station archive too large');
    }
    if (required <= _buffer.length) return;
    final next = Uint8List(
      required > _buffer.length * 2 ? required : _buffer.length * 2,
    );
    next.setRange(0, _length, _buffer);
    _buffer = next;
    _data = ByteData.sublistView(next);
  }

  void tag(int tag) {
    reserve(1);
    _buffer[_length++] = tag;
  }

  void u32(int value) {
    reserve(4);
    _data.setUint32(_length, value, Endian.little);
    _length += 4;
  }

  void value(dynamic value, [int depth = 0]) {
    if (depth > 512) throw const FormatException('Station archive too deep');
    if (value is Map || value is List) {
      final existing = _containers[value];
      if (existing != null) {
        tag(9);
        u32(existing);
        return;
      }
    }
    if (value == null) {
      tag(0);
    } else if (value is bool) {
      tag(value ? 2 : 1);
    } else if (value is int) {
      tag(3);
      reserve(8);
      _data.setInt64(_length, value, Endian.little);
      _length += 8;
    } else if (value is double) {
      if (!value.isFinite) {
        throw const FormatException('Non-finite station value');
      }
      tag(4);
      reserve(8);
      _data.setFloat64(_length, value, Endian.little);
      _length += 8;
    } else if (value is String) {
      final existing = _strings[value];
      if (existing != null) {
        tag(8);
        u32(existing);
        return;
      }
      _strings[value] = _strings.length;
      tag(5);
      u32(value.length);
      reserve(value.length * 2);
      for (var i = 0; i < value.length; i++) {
        _data.setUint16(_length, value.codeUnitAt(i), Endian.little);
        _length += 2;
      }
    } else if (value is List) {
      tag(6);
      u32(value.length);
      for (final item in value) {
        this.value(item, depth + 1);
      }
    } else if (value is Map) {
      tag(7);
      u32(value.length);
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException('Invalid JSON map key');
        }
        this.value(entry.key, depth + 1);
        this.value(entry.value, depth + 1);
      }
    } else {
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported station JSON value',
      );
    }
    if (value is Map || value is List) {
      _containers[value] = _containers.length;
    }
  }
}

class _Bindings {
  _Bindings() {
    if (_library.lookupFunction<Uint32 Function(), int Function()>(
          'rq_station_archive_abi_version',
        )() !=
        1) {
      throw StateError('Unsupported station archive ABI');
    }
  }
  final _library = StationCoreLibrary.library;
  late final create = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, Size, Pointer<Int32>),
        Pointer<Void> Function(Pointer<Uint8>, int, Pointer<Int32>)
      >('rq_station_archive_create');
  late final createGzip = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, Size, Pointer<Int32>),
        Pointer<Void> Function(Pointer<Uint8>, int, Pointer<Int32>)
      >('rq_station_archive_create_gzip');
  late final length = _library
      .lookupFunction<
        Size Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('rq_station_archive_length');
  late final copy = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size),
        int Function(Pointer<Void>, Pointer<Uint8>, int)
      >('rq_station_archive_copy');
  late final destroy = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('rq_station_archive_destroy');
  late final sessions = _library
      .lookupFunction<Uint64 Function(), int Function()>(
        'rq_station_archive_sessions',
      );
  late final calls = _library.lookupFunction<Uint64 Function(), int Function()>(
    'rq_station_archive_calls',
  );
}
