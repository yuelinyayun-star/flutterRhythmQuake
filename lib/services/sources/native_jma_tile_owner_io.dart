import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_station_core_library_io.dart';

/// Commands and finite display snapshots only. No HTTP client, source parser,
/// retry timer or current-frame business policy lives in this bridge.
final class NativeJmaTileOwner implements Finalizable {
  NativeJmaTileOwner({required bool satellite, required this.onFrame}) {
    final weak = WeakReference(this);
    _port = RawReceivePort((_) => weak.target?._drain());
    _owner = _api.open(
      satellite ? 1 : 0,
      _port.sendPort.nativePort,
      NativeApi.postCObject.cast(),
    );
    if (_owner == nullptr) {
      _port.close();
      throw StateError('Native JMA tile owner allocation failed');
    }
    _finalizer.attach(this, _owner, detach: this);
    _portFinalizer.attach(this, _port, detach: this);
  }
  static bool get supported => StationCoreLibrary.supported;
  static int get workers => _api.workers();
  static final _api = _Bindings();
  static final _finalizer = NativeFinalizer(_api.closePointer);
  static final _portFinalizer = Finalizer<RawReceivePort>(
    (port) => port.close(),
  );
  final void Function(Map<String, dynamic>?) onFrame;
  late final RawReceivePort _port;
  Pointer<Void> _owner = nullptr;
  final _requests = <int, Completer<Map<String, dynamic>>>{};
  final _tiles = <int, Completer<Uint8List?>>{};
  int _serial = 0, _generation = 0;
  bool _disposed = false, _draining = false;

  void _send(Map<String, Object?> command) {
    if (_disposed) throw StateError('Native JMA tile owner disposed');
    final bytes = utf8.encode(jsonEncode(command));
    using((arena) {
      final data = arena<Uint8>(bytes.length)
        ..asTypedList(bytes.length).setAll(0, bytes);
      if (_api.send(_owner, data, bytes.length) != 1) {
        throw StateError('Native JMA tile command rejected');
      }
    });
  }

  Future<Map<String, dynamic>> _request(Map<String, Object?> command) {
    final id = ++_serial;
    final done = Completer<Map<String, dynamic>>();
    _requests[id] = done;
    try {
      _send({...command, 'request': id});
    } catch (error, stack) {
      _requests.remove(id);
      done.completeError(error, stack);
    }
    return done.future;
  }

  void start({
    required Duration interval,
    int attempts = 1,
    Uri? testEndpoint,
    Duration? testTimeout,
  }) {
    _send({
      'op': 'start',
      'generation': ++_generation,
      'intervalMs': interval.inMilliseconds,
      'attempts': attempts,
      if (testEndpoint != null)
        'testEndpoint': {
          'host': testEndpoint.host,
          'path': testEndpoint.path,
          'port': testEndpoint.port,
        },
      if (testTimeout != null) 'testTimeoutMs': testTimeout.inMilliseconds,
    });
  }

  void stop({bool clear = false}) =>
      _send({'op': 'stop', 'generation': ++_generation, 'clear': clear});
  Future<void> fetch({int attempts = 1}) async {
    await _request({'op': 'fetch', 'attempts': attempts});
  }

  Future<Map<String, dynamic>> diagnostics() => _request({'op': 'diagnostics'});
  Future<Uint8List?> tile(String path, Future<void> cancel) {
    if (_disposed) return Future.value(null);
    final id = ++_serial;
    final result = Completer<Uint8List?>();
    _tiles[id] = result;
    _send({'op': 'tile', 'request': id, 'path': path});
    unawaited(
      cancel.then((_) {
        if (!_disposed && _tiles.containsKey(id)) {
          _send({'op': 'cancelTile', 'request': id});
        }
      }),
    );
    return result.future;
  }

  void _drain() {
    if (_disposed || _draining) return;
    _draining = true;
    try {
      using((arena) {
        final length = arena<Size>();
        while (!_disposed) {
          final data = _api.take(_owner, length);
          if (data == nullptr) break;
          final bytes = data.asTypedList(length.value);
          if (bytes.first == 84) {
            final header = ByteData.sublistView(bytes, 1, 13);
            final id = header.getUint64(0, Endian.little),
                status = header.getUint32(8, Endian.little);
            final result = _tiles.remove(id);
            if (result == null) continue;
            if (status == 0) {
              result.complete(
                Uint8List.fromList(Uint8List.sublistView(bytes, 13)),
              );
            } else if (status == 1) {
              result.complete(null);
            } else {
              result.completeError(StateError(utf8.decode(bytes.sublist(13))));
            }
            continue;
          }
          final value =
              jsonDecode(utf8.decode(bytes.sublist(1))) as Map<String, dynamic>;
          if (value['type'] == 'frame' && value['generation'] == _generation) {
            onFrame(value['frame'] as Map<String, dynamic>?);
          } else if (value['request'] case final int id) {
            _requests.remove(id)?.complete(value);
          }
        }
      });
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _port.close();
    _finalizer.detach(this);
    _portFinalizer.detach(this);
    _api.close(_owner);
    _owner = nullptr;
    for (final request in _requests.values) {
      request.complete({});
    }
    _requests.clear();
    for (final tile in _tiles.values) {
      tile.complete(null);
    }
    _tiles.clear();
  }
}

class _Bindings {
  final lib = StationCoreLibrary.library;
  late final open = lib
      .lookupFunction<
        Pointer<Void> Function(Uint32, Int64, Pointer<Void>),
        Pointer<Void> Function(int, int, Pointer<Void>)
      >('rq_jma_tile_open');
  late final send = lib
      .lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Uint8>, Size),
        int Function(Pointer<Void>, Pointer<Uint8>, int)
      >('rq_jma_tile_send');
  late final take = lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>)
      >('rq_jma_tile_take');
  late final closePointer = lib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_jma_tile_close',
      );
  late final close = closePointer.asFunction<void Function(Pointer<Void>)>();
  late final workers = lib.lookupFunction<Size Function(), int Function()>(
    'rq_jma_tile_workers',
  );
}
