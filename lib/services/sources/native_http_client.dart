import '../debug/network_diagnostic.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'native_station_core_library_io.dart';

/// Ordinary buffered API requests use a shared async WinHTTP reactor. Custom
/// HttpOverrides, streaming/abortable uploads and non-gzip negotiation retain
/// their original IOClient contract. Never retry a native failure via Dart.
final class NativeHttpClient extends http.BaseClient implements Finalizable {
  NativeHttpClient({this.requestTimeout});
  final Duration? requestTimeout;
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.clientFinalizer);
  static int get activeClients => _bindings.clients();
  static int get activeRequests => _bindings.requests();

  /// Streaming receive queue only; complete-body GET owns up to 64 MiB until
  /// its external Uint8List is released, like an ordinary buffered Response.
  static int get queuePeakBytes => _bindings.queuePeak();
  int? _id;
  bool _closed = false;
  IOClient? _compatibility;
  final _active = <_Request>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _send(request);
  }

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final request = http.Request('GET', url);
    if (headers != null) request.headers.addAll(headers);
    final response = await _send(request, buffered: true);
    if (response is! _Response || response.directBody == null) {
      return http.Response.fromStream(response);
    }
    return http.Response.bytes(
      await response.directBody!,
      response.statusCode,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  Future<http.StreamedResponse> _send(
    http.BaseRequest request, {
    bool buffered = false,
  }) async {
    if (_closed) {
      throw http.ClientException('HTTP client is closed', request.url);
    }
    final uri = request.url;
    final encoding = request.headers.entries
        .where((e) => e.key.toLowerCase() == 'accept-encoding')
        .map((e) => e.value.trim().toLowerCase())
        .firstOrNull;
    if (NetworkDiagnostic.hasTransportOverrides ||
        request is! http.Request ||
        request is http.Abortable ||
        uri.userInfo.isNotEmpty ||
        (encoding != null && encoding != 'gzip')) {
      return (_compatibility ??= IOClient()).send(request);
    }
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw http.ClientException('Invalid HTTP URI', uri);
    }
    var headers = Map<String, String>.from(request.headers);
    if (encoding == null) headers['Accept-Encoding'] = 'gzip';
    for (final entry in headers.entries) {
      if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(entry.key) ||
          entry.value.contains(RegExp(r'[\r\n\x00]'))) {
        throw http.ClientException('Invalid HTTP header', uri);
      }
    }
    var body = await request.finalize().toBytes();
    if (_closed) throw http.ClientException('HTTP client is closed', uri);
    if (body.length > 64 * 1024 * 1024) {
      throw http.ClientException('HTTP upload exceeds 64 MiB', uri);
    }
    if ((request.method == 'GET' || request.method == 'HEAD') &&
        body.isNotEmpty) {
      throw http.ClientException(
        'HTTP ${request.method} request has a body',
        uri,
      );
    }
    _id ??= using((arena) {
      final version = Platform.version.split('.').take(2).join('.');
      return _bindings.clientOpen(
        'Dart/$version (dart:io)'.toNativeUtf8(allocator: arena).cast(),
      );
    });
    // Attach exactly once, after the first request that actually needs native IO.
    if (_active.isEmpty && !_attached) {
      _finalizer.attach(this, Pointer<Void>.fromAddress(_id!), detach: this);
      _attached = true;
    }
    var target = uri;
    var method = request.method;
    final visited = <Uri>{uri};
    for (var redirects = 0; ; redirects++) {
      if (_closed) throw http.ClientException('HTTP client is closed', target);
      final pending = _Request(
        _id!,
        target,
        method,
        headers,
        body,
        persistent: request.persistentConnection,
        buffered: buffered,
        timeout: requestTimeout,
        onFinish: (r) => _active.remove(r),
      );
      _active.add(pending);
      final response = await pending.response.future;
      final redirect = (method == 'GET' || method == 'HEAD')
          ? const {301, 302, 303, 307, 308}.contains(response.statusCode)
          : method == 'POST' && response.statusCode == 303;
      if (!request.followRedirects || !redirect) {
        return _Response(
          response.stream,
          response.statusCode,
          url: target,
          request: request,
          headers: response.headers,
          contentLength: response.contentLength,
          isRedirect: redirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
          directBody: buffered ? pending.bodyBytes.future : null,
        );
      }
      await response.stream.drain<void>();
      if (redirects >= request.maxRedirects) {
        throw http.ClientException('Redirect limit exceeded', target);
      }
      final location = response.headers['location'];
      if (location == null) {
        throw http.ClientException('Redirect is missing Location', target);
      }
      final next = target.resolve(location);
      if ((next.scheme != 'http' && next.scheme != 'https') ||
          next.userInfo.isNotEmpty ||
          !visited.add(next)) {
        throw http.ClientException('Invalid or looping HTTP redirect', next);
      }
      final sameOrigin =
          next.scheme == target.scheme &&
          next.port == target.port &&
          (next.host == target.host || next.host.endsWith('.${target.host}'));
      headers = Map.of(headers)
        ..removeWhere((key, _) {
          final name = key.toLowerCase();
          return name == 'host' ||
              name == 'content-length' ||
              !sameOrigin &&
                  const {
                    'authorization',
                    'www-authenticate',
                    'cookie',
                    'cookie2',
                  }.contains(name);
        });
      if (method == 'POST' && response.statusCode == 303) method = 'GET';
      body = Uint8List(
        0,
      ); // IOClient does not replay a body on automatic redirects.
      target = next;
    }
  }

  bool _attached = false;
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _active.toList()) {
      request.fail(http.ClientException('HTTP client is closed', request.uri));
    }
    _compatibility?.close();
    if (_id != null) {
      _finalizer.detach(this);
      _bindings.clientClose(_id!);
      _id = null;
    }
  }
}

final class _Response extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _Response(
    super.stream,
    super.statusCode, {
    required this.url,
    super.request,
    super.headers,
    super.contentLength,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
    this.directBody,
  });
  @override
  final Uri url;
  final Future<Uint8List>? directBody;
}

final class _Request implements Finalizable {
  _Request(
    int client,
    this.uri,
    String method,
    Map<String, String> headers,
    Uint8List bytes, {
    required bool persistent,
    required this.buffered,
    Duration? timeout,
    required this.onFinish,
  }) {
    final weak = WeakReference(this);
    _port = RawReceivePort((_) => weak.target?._drain());
    _body = StreamController<List<int>>(
      onListen: _drain,
      onResume: () {
        _paused = false;
        _drain();
      },
      onPause: () => _paused = true,
      onCancel: _finish,
    );
    using((arena) {
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      final path =
          '${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      _id = NativeHttpClient._bindings.open(
        client,
        uri.host.toNativeUtf8(allocator: arena).cast(),
        path.toNativeUtf8(allocator: arena).cast(),
        method.toNativeUtf8(allocator: arena).cast(),
        headers.entries
            .map((e) => '${e.key}: ${e.value}\r\n')
            .join()
            .toNativeUtf8(allocator: arena)
            .cast(),
        data,
        bytes.length,
        uri.port,
        (uri.scheme == 'https' ? 1 : 0) |
            (persistent ? 0 : 2) |
            (buffered ? 4 : 0),
        _port.sendPort.nativePort,
        NativeApi.postCObject.cast(),
      );
    });
    if (_id == 0) {
      _port.close();
      throw StateError('Native HTTP allocation failed');
    }
    _finalizer.attach(this, Pointer<Void>.fromAddress(_id), detach: this);
    _portFinalizer.attach(this, _port, detach: this);
    if (buffered) {
      unawaited(bodyBytes.future.then<void>((_) {}, onError: (Object _) {}));
    }
    if (timeout != null) {
      _timer = Timer(
        timeout,
        () => fail(TimeoutException('HTTP request timed out', timeout)),
      );
    }
  }
  static final _finalizer = NativeFinalizer(
    NativeHttpClient._bindings.releaseFinalizer,
  );
  static final _portFinalizer = Finalizer<RawReceivePort>(
    (port) => port.close(),
  );
  final Uri uri;
  final bool buffered;
  final bodyBytes = Completer<Uint8List>();
  Uint8List? _receivedBody;
  final void Function(_Request) onFinish;
  final response = Completer<http.StreamedResponse>();
  late final RawReceivePort _port;
  late final StreamController<List<int>> _body;
  int _id = 0;
  bool _closed = false, _paused = false;
  Timer? _timer;
  void _drain() {
    if (_closed || _paused) return;
    using((arena) {
      final size = arena<UintPtr>(),
          kind = arena<Uint32>(),
          code = arena<Uint32>();
      final owner = arena<Pointer<Void>>();
      for (var i = 0; i < 8 && !_closed && !_paused; i++) {
        if (!buffered && response.isCompleted && !_body.hasListener) return;
        final data = NativeHttpClient._bindings.take(
          _id,
          size,
          kind,
          code,
          owner,
        );
        if (data == nullptr) return;
        if (kind.value == 2) {
          final bytes = data.asTypedList(
            size.value,
            finalizer: NativeHttpClient._bindings.chunkFinalizer,
            token: owner.value,
          );
          if (buffered) {
            _receivedBody = bytes;
          } else {
            _body.add(bytes);
          }
        } else {
          try {
            switch (kind.value) {
              case 1:
                final lines = utf8
                    .decode(data.asTypedList(size.value))
                    .split('\r\n');
                final status = RegExp(
                  r'^HTTP/\S+ (\d{3})(?: (.*))?$',
                ).firstMatch(lines.first);
                if (status == null) {
                  throw http.ClientException('Invalid HTTP status', uri);
                }
                final headers = <String, String>{};
                for (final line in lines.skip(1)) {
                  final split = line.indexOf(':');
                  if (split < 1) continue;
                  final name = line.substring(0, split).toLowerCase();
                  final value = line.substring(split + 1).trim();
                  headers.update(
                    name,
                    (old) => '$old,$value',
                    ifAbsent: () => value,
                  );
                }
                response.complete(
                  http.StreamedResponse(
                    _body.stream,
                    int.parse(status[1]!),
                    headers: headers,
                    contentLength: int.tryParse(
                      headers['content-length'] ?? '',
                    ),
                    reasonPhrase: status[2] ?? '',
                    persistentConnection:
                        headers['connection']?.toLowerCase() != 'close',
                  ),
                );
              case 3:
                if (buffered) bodyBytes.complete(_receivedBody ?? Uint8List(0));
                _finish();
              case 4:
                fail(
                  http.ClientException('Native HTTP error ${code.value}', uri),
                );
            }
          } catch (error, stack) {
            fail(error, stack);
          } finally {
            NativeHttpClient._bindings.freeChunk(owner.value);
          }
        }
      }
      if (!_closed && !_paused) Timer.run(_drain);
    });
  }

  void fail(Object error, [StackTrace? stack]) {
    if (_closed) return;
    if (buffered && !bodyBytes.isCompleted) {
      bodyBytes.completeError(error, stack);
    }
    if (!response.isCompleted) {
      response.completeError(error, stack);
    } else {
      _body.addError(error, stack);
    }
    _finish();
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _port.close();
    _finalizer.detach(this);
    _portFinalizer.detach(this);
    NativeHttpClient._bindings.release(_id);
    _id = 0;
    unawaited(_body.close());
    onFinish(this);
  }
}

final class _Bindings {
  _Bindings() {
    final lib = StationCoreLibrary.library;
    clientOpen = lib
        .lookupFunction<
          Uint64 Function(Pointer<Uint8>),
          int Function(Pointer<Uint8>)
        >('rq_http_client_open');
    clientClose = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
      'rq_http_client_close',
    );
    clientFinalizer = lib.lookup('rq_http_client_finalizer');
    open = lib
        .lookupFunction<
          Uint64 Function(
            Uint64,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            UintPtr,
            Uint32,
            Uint32,
            Int64,
            Pointer<Void>,
          ),
          int Function(
            int,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            int,
            int,
            int,
            int,
            Pointer<Void>,
          )
        >('rq_http_open');
    take = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Uint64,
            Pointer<UintPtr>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Pointer<Void>>,
          ),
          Pointer<Uint8> Function(
            int,
            Pointer<UintPtr>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Pointer<Void>>,
          )
        >('rq_http_take');
    release = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
      'rq_http_release',
    );
    releaseFinalizer = lib.lookup('rq_http_release_finalizer');
    chunkFinalizer = lib.lookup('rq_http_chunk_release');
    freeChunk = chunkFinalizer.asFunction();
    clients = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_http_clients',
    );
    requests = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_http_requests',
    );
    queuePeak = lib.lookupFunction<UintPtr Function(), int Function()>(
      'rq_http_queue_peak',
    );
  }
  late final int Function() clients, requests, queuePeak;
  late final int Function(Pointer<Uint8>) clientOpen;
  late final void Function(int) clientClose, release;
  late final int Function(
    int,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
    int,
    int,
    int,
    Pointer<Void>,
  )
  open;
  late final Pointer<Uint8> Function(
    int,
    Pointer<UintPtr>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Pointer<Void>>,
  )
  take;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  clientFinalizer,
  releaseFinalizer,
  chunkFinalizer;
  late final void Function(Pointer<Void>) freeChunk;
}
