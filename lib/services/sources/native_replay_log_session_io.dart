import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_station_core_library_io.dart';

/// Thin archive command bridge. The native owner retains all records/GIFs,
/// schedules automatic saves and performs file IO. Record views are requested
/// explicitly for diagnostics, never materialized for automatic saving.
final class NativeReplayLogSession implements Finalizable {
  NativeReplayLogSession({this.onStatus}) {
    final weak = WeakReference(this);
    _port = RawReceivePort((_) => weak.target?._drain());
    _id = _bindings.open(
      _port.sendPort.nativePort,
      NativeApi.postCObject.cast(),
    );
    if (_id == 0) {
      _port.close();
      throw StateError('Native archive allocation failed');
    }
    _finalizer.attach(this, Pointer<Void>.fromAddress(_id), detach: this);
    _portFinalizer.attach(this, _port, detach: this);
  }
  // A hot restart cannot replace the already loaded DLL. Keep the old running
  // checkout usable until a full restart loads the newly built archive ABI.
  static bool get supported =>
      StationCoreLibrary.supported && _archiveAvailable;
  static final _archiveAvailable = StationCoreLibrary.library.providesSymbol(
    'rq_replay_open',
  );
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.finalizer);
  static final _portFinalizer = Finalizer<RawReceivePort>(
    (port) => port.close(),
  );
  static int get activeWorkers => _bindings.workers();
  final void Function(Map<String, dynamic>)? onStatus;
  late final RawReceivePort _port;
  int _id = 0, _nextSerial = 1;
  bool _disposed = false;
  final _pending = <int, Completer<void>>{};
  Map<String, dynamic> _status = const {};
  Map<String, dynamic> get lastStatus => _status;

  void start({
    required String sessionStart,
    required String stamp,
    required String outputDirectory,
    required bool writeToDisk,
  }) {
    command(1, {
      'session_start': sessionStart,
      'stamp': stamp,
      'out_dir': outputDirectory,
      'write_to_disk': writeToDisk,
    });
  }

  void append(int type, Map<String, dynamic> record) => command(type, record);
  void appendRaw(int type, Uint8List originalJson) => _send(type, originalJson);
  void capture(Map<String, dynamic> metadata, Uint8List originalGif) =>
      command(6, metadata, blob: originalGif);
  void command(int op, Map<String, dynamic> value, {Uint8List? blob}) =>
      _send(op, utf8.encode(jsonEncode(value)), blob: blob);
  void _send(int op, Uint8List json, {Uint8List? blob, int serial = 0}) {
    if (_disposed) throw StateError('Archive session is disposed');
    using((arena) {
      final bytes = arena<Uint8>(json.isEmpty ? 1 : json.length);
      bytes.asTypedList(json.length).setAll(0, json);
      final payload = arena<Uint8>(
        blob == null || blob.isEmpty ? 1 : blob.length,
      );
      if (blob != null) payload.asTypedList(blob.length).setAll(0, blob);
      final error = _bindings.send(
        _id,
        op,
        bytes,
        json.length,
        payload,
        blob?.length ?? 0,
        serial,
      );
      if (error != 0) throw StateError('Archive command rejected ($error)');
    });
  }

  Future<void> save() async {
    final serial = _nextSerial++, ready = Completer<void>();
    _pending[serial] = ready;
    try {
      _send(8, Uint8List(0), serial: serial);
    } catch (_) {
      _pending.remove(serial);
      rethrow;
    }
    return ready.future;
  }

  void saveSync() {
    _send(8, Uint8List(0));
    barrier();
    refreshStatus();
  }

  void stopSync() {
    _send(7, Uint8List(0));
    barrier();
    refreshStatus();
  }

  void barrier() {
    if (!_disposed) _bindings.barrier(_id);
  }

  Map<String, dynamic> refreshStatus() {
    final status = _query(false);
    _acceptStatus(Map<String, dynamic>.from(status as Map));
    return _status;
  }

  List<Map<String, dynamic>> readRecords() {
    final result = _query(true);
    if (result is! List) {
      throw StateError('Archive records unavailable: $result');
    }
    return result
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Object? _query(bool records) {
    if (_disposed) throw StateError('Archive session is disposed');
    return using((arena) {
      final length = arena<UintPtr>(), owner = arena<Pointer<Void>>();
      final pointer = _bindings.query(_id, records ? 1 : 0, length, owner);
      if (pointer == nullptr) throw StateError('Archive query failed');
      try {
        return jsonDecode(utf8.decode(pointer.asTypedList(length.value)));
      } finally {
        _bindings.free(owner.value);
      }
    });
  }

  void _acceptStatus(Map<String, dynamic> status) {
    _status = Map.unmodifiable(status);
    onStatus?.call(_status);
  }

  void _drain() {
    if (_disposed) return;
    using((arena) {
      final length = arena<UintPtr>(), serial = arena<Uint64>();
      final owner = arena<Pointer<Void>>();
      for (var i = 0; i < 16 && !_disposed; i++) {
        final pointer = _bindings.take(_id, length, serial, owner);
        if (pointer == nullptr) return;
        try {
          _acceptStatus(
            Map<String, dynamic>.from(
              jsonDecode(utf8.decode(pointer.asTypedList(length.value))) as Map,
            ),
          );
          final ready = _pending.remove(serial.value);
          if (_status['error'] != null) {
            ready?.completeError(StateError(_status['error'] as String));
          } else {
            ready?.complete();
          }
        } finally {
          _bindings.free(owner.value);
        }
      }
      if (!_disposed) Timer.run(_drain);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _port.close();
    _finalizer.detach(this);
    _portFinalizer.detach(this);
    _bindings.release(_id);
    _id = 0;
    for (final ready in _pending.values) {
      ready.completeError(StateError('Archive disposed before save completed'));
    }
    _pending.clear();
  }
}

final class _Bindings {
  _Bindings() {
    final lib = StationCoreLibrary.library;
    open = lib
        .lookupFunction<
          Uint64 Function(Int64, Pointer<Void>),
          int Function(int, Pointer<Void>)
        >('rq_replay_open');
    send = lib
        .lookupFunction<
          Uint32 Function(
            Uint64,
            Uint32,
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Uint64,
          ),
          int Function(int, int, Pointer<Uint8>, int, Pointer<Uint8>, int, int)
        >('rq_replay_send');
    query = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Uint64,
            Uint32,
            Pointer<UintPtr>,
            Pointer<Pointer<Void>>,
          ),
          Pointer<Uint8> Function(
            int,
            int,
            Pointer<UintPtr>,
            Pointer<Pointer<Void>>,
          )
        >('rq_replay_query');
    take = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Uint64,
            Pointer<UintPtr>,
            Pointer<Uint64>,
            Pointer<Pointer<Void>>,
          ),
          Pointer<Uint8> Function(
            int,
            Pointer<UintPtr>,
            Pointer<Uint64>,
            Pointer<Pointer<Void>>,
          )
        >('rq_replay_take');
    free = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('rq_replay_free');
    release = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
      'rq_replay_release',
    );
    barrier = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
      'rq_replay_barrier',
    );
    workers = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_replay_workers',
    );
    finalizer = lib.lookup('rq_replay_finalizer');
  }
  late final int Function(int, Pointer<Void>) open;
  late final int Function(
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    int,
  )
  send;
  late final Pointer<Uint8> Function(
    int,
    int,
    Pointer<UintPtr>,
    Pointer<Pointer<Void>>,
  )
  query;
  late final Pointer<Uint8> Function(
    int,
    Pointer<UintPtr>,
    Pointer<Uint64>,
    Pointer<Pointer<Void>>,
  )
  take;
  late final void Function(Pointer<Void>) free;
  late final void Function(int) release, barrier;
  late final int Function() workers;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>> finalizer;
}
