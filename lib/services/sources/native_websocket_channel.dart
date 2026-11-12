import 'source_socket_error.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'native_station_core_library_io.dart';

/// Push-based Windows transport. No polling timer, Dart socket, or isolate
/// message containing a reconstructed JSON object graph is involved.
final class NativeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel, Finalizable {
  NativeWebSocketChannel.connect(
    Uri uri, {
    Map<String, dynamic>? headers,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration? keepaliveInterval,
    bool allowBadCertificate = false,
    this.textAsBytes = false,
  }) {
    if ((uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw ArgumentError.value(uri, 'uri', 'Invalid WebSocket URI');
    }
    final lines = <String>[];
    for (final entry in (headers ?? <String, dynamic>{}).entries) {
      final value = entry.value is Iterable
          ? (entry.value as Iterable).join(', ')
          : entry.value.toString();
      if (entry.key.contains(RegExp(r'[\r\n:]')) ||
          value.contains(RegExp(r'[\r\n\x00]'))) {
        throw ArgumentError('Invalid WebSocket header');
      }
      lines.add('${entry.key}: $value\r\n');
    }
    final port = RawReceivePort();
    _port = port;
    // Capturing WeakReference avoids the native port rooting a forgotten
    // channel forever; its native finalizer cancels the worker on collection.
    final weak = WeakReference(this);
    port.handler = (_) {
      final channel = weak.target;
      if (channel == null) {
        port.close();
        return;
      }
      channel._drain();
    };
    final path = uri.hasQuery
        ? '${uri.path.isEmpty ? '/' : uri.path}?${uri.query}'
        : (uri.path.isEmpty ? '/' : uri.path);
    using((arena) {
      _id = _bindings.open(
        uri.host.toNativeUtf8(allocator: arena).cast(),
        path.toNativeUtf8(allocator: arena).cast(),
        lines.join().toNativeUtf8(allocator: arena).cast(),
        connectionPort(uri),
        (uri.scheme == 'wss' ? 1 : 0) | (allowBadCertificate ? 2 : 0),
        connectTimeout.inMilliseconds,
        keepaliveInterval?.inMilliseconds ?? 0,
        port.sendPort.nativePort,
        NativeApi.postCObject.cast(),
      );
    });
    if (_id == 0) {
      port.close();
      throw StateError('Native WebSocket allocation failed');
    }
    _finalizer.attach(this, Pointer<Void>.fromAddress(_id), detach: this);
    _portFinalizer.attach(this, port, detach: this);
    // Same connect-timeout contract as IOWebSocketChannel; cancellation reaches
    // the request even if it is still resolving DNS or awaiting HTTP headers.
    _connectTimer = Timer(connectTimeout, () {
      _drain();
      if (!_closed && !_ready.isCompleted)
        _fail(WebSocketChannelException('WebSocket handshake timed out'));
    });
    // Install a listener so callers that consume only stream errors do not
    // cause an uncaught ready error. The original future still rejects.
    unawaited(_ready.future.then<void>((_) {}, onError: (Object _) {}));
  }

  static final _bindings = _Bindings();

  /// JSON sources can pass the original UTF-8 directly to their Rust parser.
  final bool textAsBytes;
  static final _finalizer = NativeFinalizer(_bindings.releaseFinalizer);
  static final _portFinalizer = Finalizer<RawReceivePort>(
    (port) => port.close(),
  );
  static int get activeWorkers => _bindings.workers();
  static int connectionPort(Uri uri) =>
      uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 80);
  int _id = 0;
  late final RawReceivePort _port;
  final _ready = Completer<void>();
  final _done = Completer<void>();
  late final StreamController<dynamic> _incoming = StreamController<dynamic>(
    onCancel: () => _close(),
  );
  late final WebSocketSink _sink = _NativeSink(this);
  Timer? _connectTimer;
  static final Set<NativeWebSocketChannel> _closingChannels = {};
  bool _failed = false;
  bool _closed = false;
  bool _closing = false;
  @override
  int? closeCode;
  @override
  String? closeReason;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => _ready.future;
  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _sink;

  void _drain() {
    if (_closed) return;
    using((arena) {
      final size = arena<UintPtr>();
      final type = arena<Uint32>();
      final code = arena<Uint32>();
      // A bounded delivery batch lets rendering and other feeds run during a
      // burst. Native notifications are coalesced, so continue without a timer.
      for (var n = 0; n < 32 && !_closed; n++) {
        final data = _bindings.take(_id, size, type, code);
        if (data == nullptr) return;
        switch (type.value) {
          case 1:
            _connectTimer?.cancel();
            if (!_ready.isCompleted) _ready.complete();
          case 2:
            _incoming.add(
              textAsBytes
                  ? Uint8List.fromList(data.asTypedList(size.value))
                  : utf8.decode(data.asTypedList(size.value)),
            );
          case 3:
            _incoming.add(Uint8List.fromList(data.asTypedList(size.value)));
          case 4:
            _fail(
              SourceSocketException(
                'Native WebSocket transport error (${code.value}): ${utf8.decode(data.asTypedList(size.value), allowMalformed: true)}',
                statusCode: code.value & 0xffff0000 == 0x10000
                    ? code.value & 0xffff
                    : null,
              ),
            );
          case 5:
            closeCode = code.value;
            closeReason = utf8.decode(data.asTypedList(size.value));
          case 6:
            _finish();
        }
      }
      if (!_closed) Timer.run(_drain);
    });
  }

  void _send(dynamic message) {
    if (_closed || _closing) throw StateError('WebSocket is closed');
    final List<int> bytes;
    final bool text;
    if (message is String) {
      bytes = utf8.encode(message);
      text = true;
    } else if (message is List<int>) {
      bytes = message;
      text = false;
    } else {
      throw ArgumentError.value(message, 'message', 'Expected String or bytes');
    }
    using((arena) {
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      final result = _bindings.send(_id, data, bytes.length, text ? 1 : 0);
      if (result != 0) {
        _fail(
          WebSocketChannelException('Native WebSocket send failed ($result)'),
        );
      }
    });
  }

  Future<void> _close([int? code, String? reason]) {
    if (_closed || _closing) return _done.future;
    final bytes = utf8.encode(reason ?? '');
    if (bytes.length > 123 || code != null && (code < 1000 || code >= 5000)) {
      throw ArgumentError('Invalid WebSocket close status');
    }
    _closing = true;
    _closingChannels.add(this);
    using((arena) {
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      _bindings.close(_id, code ?? 1000, data, bytes.length);
    });
    return _done.future;
  }

  void _fail(Object error) {
    if (_closed || _failed) return;
    _failed = true;
    if (!_ready.isCompleted) _ready.completeError(error);
    _incoming.addError(error);
    // The native worker's final event confirms all WinHTTP handles closed.
    // An error notification itself is not that confirmation.
    unawaited(_close());
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    _closingChannels.remove(this);
    _connectTimer?.cancel();
    if (!_ready.isCompleted) {
      _ready.completeError(WebSocketChannelException('Closed before opening'));
    }
    _port.close();
    _finalizer.detach(this);
    _portFinalizer.detach(this);
    _bindings.release(_id);
    _id = 0;
    unawaited(_incoming.close());
    if (!_done.isCompleted) _done.complete();
  }
}

final class _NativeSink implements WebSocketSink {
  _NativeSink(this.channel);
  final NativeWebSocketChannel channel;
  @override
  void add(dynamic data) => channel._send(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => channel._fail(error);
  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final message in stream) {
      add(message);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      channel._close(closeCode, closeReason);
  @override
  Future<void> get done => channel._done.future;
}

final class _Bindings {
  _Bindings() {
    final lib = StationCoreLibrary.library;
    if (lib.lookupFunction<Uint32 Function(), int Function()>(
          'rq_ws_abi_version',
        )() !=
        1) {
      throw StateError('Unsupported native WebSocket ABI');
    }
    open = lib
        .lookupFunction<
          Uint64 Function(
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Uint32,
            Uint32,
            Uint32,
            Uint32,
            Int64,
            Pointer<Void>,
          ),
          int Function(
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            int,
            int,
            int,
            int,
            int,
            Pointer<Void>,
          )
        >('rq_ws_open');
    send = lib
        .lookupFunction<
          Uint32 Function(Uint64, Pointer<Uint8>, UintPtr, Uint32),
          int Function(int, Pointer<Uint8>, int, int)
        >('rq_ws_send');
    take = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Uint64,
            Pointer<UintPtr>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          ),
          Pointer<Uint8> Function(
            int,
            Pointer<UintPtr>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          )
        >('rq_ws_take');
    close = lib
        .lookupFunction<
          Void Function(Uint64, Uint32, Pointer<Uint8>, UintPtr),
          void Function(int, int, Pointer<Uint8>, int)
        >('rq_ws_close');
    release = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
      'rq_ws_release',
    );
    releaseFinalizer = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'rq_ws_release_finalizer',
    );
    workers = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_ws_workers',
    );
  }
  late final int Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
    int,
    int,
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
  )
  take;
  late final void Function(int, int, Pointer<Uint8>, int) close;
  late final void Function(int) release;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  releaseFinalizer;
  late final int Function() workers;
}
