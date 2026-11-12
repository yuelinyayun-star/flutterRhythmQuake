import '../debug/network_diagnostic.dart';
import 'dart:async';
import 'dart:convert';
import 'source_socket_error.dart';
import 'source_connection_lifecycle.dart';
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'native_station_core_library_io.dart';
import 'native_websocket_channel.dart';

WebSocketChannel connectSourceSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration? pingInterval,
  bool allowBadCertificate = false,
  bool textAsBytes = true,
}) {
  // WinHTTP keepalive emits unsolicited pong, NOT ping with a pong deadline.
  // EMSC requires IOWebSocket's pingInterval semantics; never substitute these.
  if (StationCoreLibrary.supported &&
      !NetworkDiagnostic.hasTransportOverrides &&
      pingInterval == null) {
    return NativeWebSocketChannel.connect(
      uri,
      headers: headers,
      connectTimeout: connectTimeout,
      allowBadCertificate: allowBadCertificate,
      textAsBytes: textAsBytes,
    );
  }
  return _OwnedIoSocket(
    uri,
    headers: headers,
    connectTimeout: connectTimeout,
    pingInterval: pingInterval,
    allowBadCertificate: allowBadCertificate,
  );
}

/// Own the HTTP handshake so cancellation aborts it, rather than timing out
/// only its Future and permitting a late, unauthenticated upgrade.
class _OwnedIoSocket extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _OwnedIoSocket(
    Uri uri, {
    Map<String, dynamic>? headers,
    required Duration connectTimeout,
    Duration? pingInterval,
    required bool allowBadCertificate,
  }) {
    NetworkDiagnostic.event('dart_ws', _diagnosticId, 'connect', {
      'uri': uri.toString(),
      'headersSupplied': headers,
    });
    _client = HttpClient()..connectionTimeout = connectTimeout;
    if (allowBadCertificate) _client.badCertificateCallback = (_, _, _) => true;
    final connecting =
        WebSocket.connect(
          uri.toString(),
          headers: headers,
          customClient: _client,
        ).then(
          (socket) {
            NetworkDiagnostic.event('dart_ws', _diagnosticId, 'connected', {});
            _socket = socket;
            if (_cancelled) {
              unawaited(socket.close());
              throw SourceSocketException('WebSocket connection cancelled');
            }
            socket.pingInterval = pingInterval;
            return socket;
          },
          onError: (Object error, StackTrace stack) {
            NetworkDiagnostic.event('dart_ws', _diagnosticId, 'error', {
              'error': error.toString(),
            });
            _client.close(force: true);
            if (error is WebSocketException) {
              Error.throwWithStackTrace(
                SourceSocketException(
                  'WebSocket handshake rejected',
                  statusCode: error.httpStatusCode,
                ),
                stack,
              );
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
    _inner = IOWebSocketChannel(
      sourceReady(connecting, connectTimeout).catchError((
        Object error,
        StackTrace stack,
      ) {
        _cancelled = true;
        _client.close(force: true);
        Error.throwWithStackTrace(error, stack);
      }),
    );
    _inner.stream.listen(
      (data) {
        recordFrame('receive', data);
        if (!_cancelled) _incoming.add(data);
      },
      onError: (Object error, StackTrace stack) {
        if (!_closeRequested) _incoming.addError(error, stack);
      },
      onDone: () {
        NetworkDiagnostic.event('dart_ws', _diagnosticId, 'peer_closed', {
          'code': _inner.closeCode,
          'reason': _inner.closeReason,
        });
        if (!_networkDone.isCompleted) _networkDone.complete();
        unawaited(_incoming.close());
      },
    );
    _handshakeDone = _inner.ready.then<void>(
      (_) => _client.close(),
      onError: (Object _, StackTrace _) {
        _client.close(force: true);
      },
    );
  }
  late final HttpClient _client;
  final int _diagnosticId = NetworkDiagnostic.active
      ? NetworkDiagnostic.nextId()
      : 0;
  void recordFrame(String event, dynamic data) {
    if (!NetworkDiagnostic.active) return;
    NetworkDiagnostic.event(
      'dart_ws',
      _diagnosticId,
      event,
      {'text': data is String},
      data is String ? utf8.encode(data) : (data as List<int>),
    );
  }

  late final IOWebSocketChannel _inner;
  late final Future<void> _handshakeDone;
  final _networkDone = Completer<void>();
  late final StreamController<dynamic> _incoming = StreamController<dynamic>(
    onCancel: _close,
  );
  WebSocket? _socket;
  bool _cancelled = false;
  bool _closeRequested = false;
  Future<void>? _closing;
  @override
  Future<void> get ready => _inner.ready;
  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  int? get closeCode => _inner.closeCode;
  @override
  String? get closeReason => _inner.closeReason;
  @override
  String? get protocol => _inner.protocol;
  @override
  late final WebSocketSink sink = _OwnedIoSink(this);

  Future<void> _close([int? code, String? reason]) => _closing ??= () async {
    NetworkDiagnostic.event('dart_ws', _diagnosticId, 'close_requested', {
      'code': code,
      'reason': reason,
    });
    _closeRequested = true;
    _cancelled = true;
    if (_socket == null) {
      _client.close(force: true);
      await _handshakeDone;
    }
    try {
      if (_socket != null) {
        unawaited(
          _inner.sink
              .close(code, reason)
              .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }
      // Keep the adapter subscription alive until peer close or Dart's actual
      // socket cancellation; readyState alone stays open after stream.cancel.
      await _networkDone.future.timeout(const Duration(seconds: 6));
    } finally {
      _client.close(force: true);
    }
  }();
}

class _OwnedIoSink implements WebSocketSink {
  _OwnedIoSink(this.owner);
  final _OwnedIoSocket owner;
  @override
  void add(dynamic data) {
    if (owner._cancelled) throw StateError('WebSocket closed');
    owner.recordFrame('send_queued', data);
    owner._inner.sink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      owner._inner.sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<dynamic> stream) => owner._inner.sink.addStream(
    stream.map((data) {
      owner.recordFrame('send_queued', data);
      return data;
    }),
  );
  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      owner._close(closeCode, closeReason);
  @override
  Future<void> get done => owner._closing ?? owner._networkDone.future;
}
