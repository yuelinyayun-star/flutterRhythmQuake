import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import '../../models/source_payload.dart';
import 'package:ffi/ffi.dart';
import 'native_station_core_library_io.dart';

/// UI bridge only. Raw ingress never crosses the Dart port. The native source
/// actor prepares the station views, ordering, detection effects and signatures.
final class NativeStationRuntime implements Finalizable {
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static final _finalizer = NativeFinalizer(_api.finalizer);
  static int get workers => _api.workers();
  void Function(Map<String, dynamic>)? onFrame;
  void Function(List<dynamic>)? onPreparedPAlert;
  int _owner = 0;
  ReceivePort? _port;
  int _generation = 0;
  bool _preparedTree = false;
  Uint8List? _packedBytes;
  int _packedToken = 0;

  void start(Map<String, Object?> settings) {
    stop();
    final generation = _generation;
    _preparedTree = settings['kind'] != 'palert';
    final config = {...settings, 'preparedTree': _preparedTree};
    var catalogueRevision = -1;
    final port = _port = ReceivePort();
    final encoded = jsonEncode(config);
    final bytes = encoded.toNativeUtf8();
    try {
      _owner = _api.open(
        bytes.cast(),
        utf8.encode(encoded).length,
        port.sendPort.nativePort,
        NativeApi.postCObject.cast(),
      );
    } finally {
      malloc.free(bytes);
    }
    if (_owner == 0) {
      port.close();
      throw StateError('Native station runtime allocation failed');
    }
    _finalizer.attach(this, Pointer<Void>.fromAddress(_owner), detach: this);
    port.listen((dynamic message) {
      if (generation != _generation || _owner == 0) return;
      if (onPreparedPAlert != null) {
        if (message is List) {
          if (message[0] != 'palert_ui_v1' &&
              message[0] != 'palert_source_ui_v1')
            throw StateError('Unsupported P-Alert UI ABI');
          final delivery =
              message[message[0] == 'palert_ui_v1' ? 18 : 3] as int;
          if (_api.ackPAlert(_owner, delivery) != 0)
            throw StateError('Native P-Alert frame acknowledgement failed');
          if (message[0] == 'palert_ui_v1')
            catalogueRevision = message[15] as int;
          onPreparedPAlert!(message);
        } else {
          if (_api.postPAlert(_owner, catalogueRevision) != 0) {
            throw StateError('Native P-Alert UI delivery failed');
          }
        }
        return;
      }
      final frame = _take(0);
      if (frame != null) onFrame?.call(frame);
    });
  }

  Map<String, dynamic>? _take(int original) {
    if (_owner == 0) return null;
    final length = calloc<Size>();
    try {
      final p = _api.take(_owner, length, original + (_preparedTree ? 10 : 0));
      if (p == nullptr) return null;
      if (_preparedTree) {
        final frame =
            PackedSourceJson(
                  Uint8List.fromList(p.asTypedList(length.value)),
                ).root
                as Map<String, dynamic>;
        if (original != 0) return frame;
        final signals = _api.deliveredSignals(_owner, length);
        return {
          ...frame,
          'signals': List<int>.of(signals.asTypedList(length.value)),
        };
      }
      // Decode only a prepared UI projection, or an explicitly requested archive.
      return jsonDecode(utf8.decode(p.asTypedList(length.value)))
          as Map<String, dynamic>;
    } finally {
      calloc.free(length);
    }
  }

  Map<String, dynamic>? _palertTree(int part) {
    if (_owner == 0) return null;
    final size = calloc<Size>();
    try {
      final bytes = _api.palertTree(_owner, part, size);
      if (bytes == nullptr) return null;
      return PackedSourceJson(
            Uint8List.fromList(bytes.asTypedList(size.value)),
          ).root
          as Map<String, dynamic>;
    } finally {
      calloc.free(size);
    }
  }

  Map<String, dynamic>? get original => onPreparedPAlert == null
      ? _take(1)
      : {
          if (_palertTree(1) case final metadata?) 'metadata': metadata,
          if (_palertTree(2) case final data?) 'data': data,
        };
  Map<String, dynamic>? get archive =>
      onPreparedPAlert == null ? _take(2) : _palertTree(0);
  void settings(Map<String, Object?> settings) {
    if (_owner == 0) return;
    final data = utf8.encode(jsonEncode(settings));
    final b = malloc<Uint8>(data.length);
    try {
      b.asTypedList(data.length).setAll(0, data);
      _api.settings(_owner, b, data.length);
    } finally {
      malloc.free(b);
    }
  }

  /// Untouched original archive input. This cannot change a source's clock/ID.
  void injectOriginal(List<int> bytes, DateTime clock) {
    if (_owner == 0) throw StateError('Station runtime is stopped');
    final b = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      b.asTypedList(bytes.length).setAll(0, bytes);
      if (_api.input(_owner, b, bytes.length, clock.millisecondsSinceEpoch) !=
          0) {
        throw StateError('Native station input rejected');
      }
    } finally {
      malloc.free(b);
    }
  }

  void injectPacked(Uint8List bytes, int root, DateTime clock) {
    if (_owner == 0) throw StateError('Station runtime is stopped');
    final fresh = !identical(bytes, _packedBytes);
    final pointer = fresh ? malloc<Uint8>(bytes.length) : nullptr;
    try {
      if (fresh) {
        pointer.asTypedList(bytes.length).setAll(0, bytes);
        _packedToken++;
      }
      if (_api.inputPacked(
            _owner,
            pointer,
            fresh ? bytes.length : 0,
            root,
            clock.millisecondsSinceEpoch,
            _packedToken,
          ) !=
          0) {
        throw StateError('Native replay input rejected');
      }
      _packedBytes = bytes;
    } finally {
      if (fresh) malloc.free(pointer);
    }
  }

  void stop() {
    _generation++;
    _packedBytes = null;
    _port?.close();
    _port = null;
    if (_owner != 0) {
      _finalizer.detach(this);
      _api.release(_owner);
      _owner = 0;
    }
  }
}

class _Bindings {
  final lib = StationCoreLibrary.library;
  late final deliveredSignals = lib
      .lookupFunction<
        Pointer<Int32> Function(Uint64, Pointer<Size>),
        Pointer<Int32> Function(int, Pointer<Size>)
      >('rq_station_runtime_delivered_signals');
  late final ackPAlert = lib
      .lookupFunction<Uint32 Function(Uint64, Uint64), int Function(int, int)>(
        'rq_station_runtime_ack_palert',
      );
  late final inputPacked = lib
      .lookupFunction<
        Uint32 Function(Uint64, Pointer<Uint8>, Size, Uint32, Int64, Uint64),
        int Function(int, Pointer<Uint8>, int, int, int, int)
      >('rq_station_runtime_input_packed');
  late final palertTree = lib
      .lookupFunction<
        Pointer<Uint8> Function(Uint64, Uint32, Pointer<Size>),
        Pointer<Uint8> Function(int, int, Pointer<Size>)
      >('rq_station_runtime_take_palert_tree');
  late final postPAlert = lib
      .lookupFunction<Uint32 Function(Uint64, Int64), int Function(int, int)>(
        'rq_station_runtime_post_palert',
      );
  late final open = lib
      .lookupFunction<
        Uint64 Function(Pointer<Uint8>, Size, Int64, Pointer<Void>),
        int Function(Pointer<Uint8>, int, int, Pointer<Void>)
      >('rq_station_runtime_open');
  late final take = lib
      .lookupFunction<
        Pointer<Uint8> Function(Uint64, Pointer<Size>, Uint32),
        Pointer<Uint8> Function(int, Pointer<Size>, int)
      >('rq_station_runtime_take');
  late final input = lib
      .lookupFunction<
        Uint32 Function(Uint64, Pointer<Uint8>, Size, Int64),
        int Function(int, Pointer<Uint8>, int, int)
      >('rq_station_runtime_input');
  late final settings = lib
      .lookupFunction<
        Uint32 Function(Uint64, Pointer<Uint8>, Size),
        int Function(int, Pointer<Uint8>, int)
      >('rq_station_runtime_settings');
  late final release = lib
      .lookupFunction<Void Function(Uint64), void Function(int)>(
        'rq_station_runtime_release',
      );
  late final workers = lib.lookupFunction<Size Function(), int Function()>(
    'rq_station_runtime_workers',
  );
  late final finalizer = lib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_station_runtime_finalizer',
      );
}
