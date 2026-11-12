import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'native_station_core_library_io.dart';
import 'source_tcp_socket.dart';

final class NativeTcpSocket extends SourceTcpSocket implements Finalizable {
  NativeTcpSocket.open(
    InternetAddress address,
    int port, {
    Duration timeout = const Duration(seconds: 12),
    String authority = '',
  }) {
    if (port < 1 || port > 65535 || authority.contains(RegExp(r'[\r\n\x00]'))) {
      throw ArgumentError('Invalid TCP endpoint');
    }
    final incomingPort = RawReceivePort();
    _port = incomingPort;
    final weak = WeakReference(this);
    incomingPort.handler = (_) {
      final socket = weak.target;
      if (socket == null) {
        incomingPort.close();
      } else {
        socket._drain();
      }
    };
    using((arena) {
      _id = _bindings.open(
        address.address.toNativeUtf8(allocator: arena).cast(),
        port,
        authority.toNativeUtf8(allocator: arena).cast(),
        timeout.inMilliseconds.clamp(1, 120000),
        incomingPort.sendPort.nativePort,
        NativeApi.postCObject.cast(),
      );
    });
    if (_id == 0) {
      incomingPort.close();
      throw StateError('Native TCP allocation failed');
    }
    _finalizer.attach(this, Pointer<Void>.fromAddress(_id), detach: this);
    _portFinalizer.attach(this, incomingPort, detach: this);
    unawaited(_ready.future.then<void>((_) {}, onError: (Object _) {}));
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.releaseFinalizer);
  static final _portFinalizer = Finalizer<RawReceivePort>(
    (port) => port.close(),
  );
  static int get activeSessions => _bindings.sessions();
  static int get activeSockets => _bindings.sockets();
  static int get reactorThreads => _bindings.threads();
  static int get peakQueuedBytesPerSocket => _bindings.queuePeak();
  late final RawReceivePort _port;
  int _id = 0, _serial = 0;
  bool _closed = false;
  bool _connected = false;
  final _ready = Completer<void>();
  final _done = Completer<void>();
  final _flushes = <int, Completer<void>>{};
  late final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>(
        onCancel: destroy,
        onPause: () {
          if (!_closed) _bindings.pause(_id, 1);
        },
        onResume: () {
          if (!_closed) _bindings.pause(_id, 0);
        },
      );
  Future<void> get ready => _ready.future;
  @override
  Future<void> get done => _done.future;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void _drain() {
    if (_closed) return;
    using((arena) {
      final size = arena<UintPtr>(),
          kind = arena<Uint32>(),
          error = arena<Uint32>(),
          serial = arena<Uint64>(),
          owner = arena<Pointer<Void>>();
      var delivered = 0;
      for (var i = 0; i < 256 && !_closed && delivered < 1024 * 1024; i++) {
        final bytes = _bindings.take(_id, size, kind, error, serial, owner);
        if (bytes == nullptr) return;
        switch (kind.value) {
          case 1:
            _connected = true;
            if (!_ready.isCompleted) _ready.complete();
          case 2:
            delivered += size.value;
            late final Uint8List chunk;
            try {
              chunk = bytes.asTypedList(
                size.value,
                finalizer: _bindings.chunkFinalizer,
                token: owner.value,
              );
            } catch (error) {
              _bindings.freeChunk(owner.value);
              _fail(error);
              return;
            }
            _incoming.add(chunk);
          case 3:
            _flushes.remove(serial.value)?.complete();
          case 4:
            final value = error.value;
            _fail(
              value >= 0x10000 && value < 0x10400
                  ? HttpException(
                      value == 0x10000
                          ? 'Invalid proxy CONNECT header'
                          : 'Proxy CONNECT HTTP ${value - 0x10000}',
                    )
                  : value == 10060
                  ? TimeoutException('TCP connect timed out')
                  : SocketException(
                      'Native TCP error $value',
                      osError: OSError('TCP', value),
                    ),
            );
          case 5:
            destroy();
        }
      }
      if (!_closed) Timer.run(_drain);
    });
  }

  int _send(List<int> bytes) {
    if (_closed) throw StateError('TCP socket is closed');
    final serial = ++_serial;
    final result = using((arena) {
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      return _bindings.send(_id, data, bytes.length, serial);
    });
    if (result != 0) {
      final error = SocketException('Native TCP send failed ($result)');
      _fail(error);
      throw error;
    }
    return serial;
  }

  @override
  void add(List<int> bytes) {
    _send(bytes);
  }

  @override
  Future<void> flush() {
    try {
      final serial = _send(const []);
      final completer = Completer<void>();
      _flushes[serial] = completer;
      return completer.future;
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    if (!_ready.isCompleted) _ready.completeError(error);
    // A failed attempt has no consumer yet. Its ready future reports the error;
    // do not buffer an unobserved stream error for an abandoned DNS candidate.
    if (_connected || _incoming.hasListener) _incoming.addError(error);
    _finish(error);
  }

  @override
  void destroy() => _finish(const SocketException('TCP connection closed'));
  void _finish(Object pendingError) {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) _ready.completeError(pendingError);
    for (final completer in _flushes.values) {
      completer.completeError(pendingError);
    }
    _flushes.clear();
    _port.close();
    _finalizer.detach(this);
    _portFinalizer.detach(this);
    _bindings.release(_id);
    _id = 0;
    unawaited(_incoming.close());
    _done.complete();
  }
}

final class _Bindings {
  _Bindings() {
    final lib = StationCoreLibrary.library;
    if (lib.lookupFunction<Uint32 Function(), int Function()>(
          'rq_tcp_abi_version',
        )() !=
        1) {
      throw StateError('Unsupported native TCP ABI');
    }
    open = lib
        .lookupFunction<
          Uint64 Function(
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint8>,
            Uint32,
            Int64,
            Pointer<Void>,
          ),
          int Function(
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            int,
            Pointer<Void>,
          )
        >('rq_tcp_open');
    send = lib
        .lookupFunction<
          Uint32 Function(Uint64, Pointer<Uint8>, UintPtr, Uint64),
          int Function(int, Pointer<Uint8>, int, int)
        >('rq_tcp_send');
    take = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Uint64,
            Pointer<UintPtr>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint64>,
            Pointer<Pointer<Void>>,
          ),
          Pointer<Uint8> Function(
            int,
            Pointer<UintPtr>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint64>,
            Pointer<Pointer<Void>>,
          )
        >('rq_tcp_take_owned');
    chunkFinalizer = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'rq_tcp_chunk_release',
    );
    freeChunk = chunkFinalizer.asFunction<void Function(Pointer<Void>)>();
    pause = lib
        .lookupFunction<Void Function(Uint64, Uint32), void Function(int, int)>(
          'rq_tcp_pause',
        );
    release = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
      'rq_tcp_release',
    );
    releaseFinalizer = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'rq_tcp_release_finalizer',
    );
    sessions = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_tcp_sessions',
    );
    sockets = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_tcp_sockets',
    );
    threads = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_tcp_threads',
    );
    queuePeak = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_tcp_queue_peak',
    );
  }
  late final int Function(
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Void>,
  )
  open;
  late final int Function(int, Pointer<Uint8>, int, int) send;
  late final Pointer<Uint8> Function(
    int,
    Pointer<UintPtr>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint64>,
    Pointer<Pointer<Void>>,
  )
  take;
  late final void Function(int, int) pause;
  late final void Function(int) release;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  chunkFinalizer;
  late final void Function(Pointer<Void>) freeChunk;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  releaseFinalizer;
  late final int Function() sessions, sockets, threads, queuePeak;
}
