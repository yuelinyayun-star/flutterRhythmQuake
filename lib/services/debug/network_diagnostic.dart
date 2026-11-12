import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../sources/native_station_core_library_io.dart';

/// Enabled only by main_network_diagnostic.dart, before any source starts.
/// The normal application entrypoint never installs this observer.
class NetworkDiagnostic {
  static bool active = false;
  static int _next = 0;
  static Directory? directory;
  static late final void Function(Pointer<Uint8>, Pointer<Uint8>, int) _record;
  static File? _keys;
  static bool get hasTransportOverrides {
    final current = HttpOverrides.current;
    return current is _DiagnosticOverrides
        ? current.previous != null
        : current != null;
  }

  static void start() {
    if (!kDebugMode || !Platform.isWindows || active) return;
    final root = Platform.environment['RHYTHMQUAKE_NETWORK_DIR'];
    final base = Platform.environment['LOCALAPPDATA'];
    if (root == null && base == null) {
      throw StateError('Diagnostic directory unavailable');
    }
    directory = Directory(
      root ??
          '$base/RhythmQuake/network_diagnostics/${DateTime.now().toUtc().microsecondsSinceEpoch}_$pid',
    )..createSync(recursive: true);
    final library = StationCoreLibrary.library;
    final start = library
        .lookupFunction<
          Uint32 Function(Pointer<Uint8>),
          int Function(Pointer<Uint8>)
        >('rq_network_diagnostic_start');
    final path = '${directory!.path}/network_raw.jsonl';
    final ok = using(
      (arena) => start(path.toNativeUtf8(allocator: arena).cast()),
    );
    if (ok != 1) throw StateError('Native diagnostic writer did not start');
    _record = library
        .lookupFunction<
          Void Function(Pointer<Uint8>, Pointer<Uint8>, UintPtr),
          void Function(Pointer<Uint8>, Pointer<Uint8>, int)
        >('rq_network_diagnostic_record');
    active = true;
    _keys = File('${directory!.path}/tls_keys.log');
    HttpOverrides.global = _DiagnosticOverrides(HttpOverrides.current);
    File('${directory!.path}/session.json').writeAsStringSync(
      jsonEncode({
        'schema': 'rhythmquake_network_debug_v1',
        'pid': pid,
        'startedUtc': DateTime.now().toUtc().toIso8601String(),
        'executable': Platform.resolvedExecutable,
        'directory': directory!.absolute.path,
        'rawCredentialsPresent': true,
        'nativeLibrary':
            Platform.environment['RQ_STATION_CORE_LIBRARY'] ??
            '${File(Platform.resolvedExecutable).parent.path}/rq_station_core.dll',
        'coverage': [
          'native_http',
          'native_ws',
          'native_tcp',
          'dart_http',
          'dart_http_tls_keys',
        ],
        'limitations': [
          'Raw UDP, native plugins and detached Dart sockets need the accompanying packet capture.',
          'send_queued is not proof of peer delivery.',
          'Check network_raw.jsonl.status.json for lost records and write errors.',
        ],
      }),
    );
    final registry = Directory('$base/RhythmQuake/network_diagnostics')
      ..createSync(recursive: true);
    File('${registry.path}/latest.json').writeAsStringSync(
      jsonEncode({'pid': pid, 'directory': directory!.absolute.path}),
    );
    event('dart', 0, 'capture_started', {'debugMode': kDebugMode});
    unawaited(_startControl());
  }

  static Future<void> _startControl() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final random = Random.secure();
      final token = base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      );
      File('${directory!.path}/control.json').writeAsStringSync(
        jsonEncode({'port': server.port, 'token': token, 'pid': pid}),
      );
      server.listen((request) async {
        if (request.method != 'POST' ||
            !const {'/flush', '/stop'}.contains(request.uri.path) ||
            request.headers.value('X-Diagnostic-Token') != token) {
          request.response.statusCode = HttpStatus.forbidden;
        } else {
          final flush = StationCoreLibrary.library
              .lookupFunction<Uint64 Function(), int Function()>(
                request.uri.path == '/stop' ? 'rq_network_diagnostic_stop' : 'rq_network_diagnostic_flush',
              );
          final bytes = flush();
          if (request.uri.path == '/stop') { active = false; }
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'ok': bytes > 0, 'fileBytes': bytes, 'pid': pid, 'recording': active}),
          );
        }
        await request.response.close();
      });
    } catch (error) {
      event('dart', 0, 'control_server_error', {
        'type': error.runtimeType.toString(),
      });
    }
  }

  static int nextId() => ++_next;
  static void event(
    String transport,
    int id,
    String event,
    Map<String, dynamic> details, [
    List<int> bytes = const [],
  ]) {
    if (!active) return;
    using((arena) {
      final metadata = jsonEncode({
        'transport': transport,
        'connectionId': id,
        'event': event,
        'details': details,
      }).toNativeUtf8(allocator: arena);
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      if (bytes.isNotEmpty) data.asTypedList(bytes.length).setAll(0, bytes);
      _record(metadata.cast(), data, bytes.length);
    });
  }

  static void keyLog(String line) {
    if (active) {
      // TLS can report several secrets synchronously. IOSink.flush followed
      // by another write before completion would throw and break the handshake.
      try {
        _keys?.writeAsStringSync(
          line.endsWith('\n') ? line : '$line\n',
          mode: FileMode.append,
        );
      } on FileSystemException {
        event('dart_tls', 0, 'key_file_write_error', {});
      }
      event('dart_tls', 0, 'key', {}, utf8.encode(line));
    }
  }

  static Map<String, List<String>> headers(HttpHeaders headers) {
    final value = <String, List<String>>{};
    headers.forEach((name, values) => value[name] = List.of(values));
    return value;
  }
}

class _DiagnosticOverrides extends HttpOverrides {
  _DiagnosticOverrides(this.previous);
  final HttpOverrides? previous;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        previous?.createHttpClient(context) ?? super.createHttpClient(context);
    client.keyLog = NetworkDiagnostic.keyLog;
    return _Client(client);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);
}

class _Client implements HttpClient {
  _Client(this.inner);
  final HttpClient inner;
  Future<HttpClientRequest> _observe(
    Future<HttpClientRequest> pending,
    String method,
    String target,
  ) async {
    final id = NetworkDiagnostic.nextId();
    NetworkDiagnostic.event('dart_http', id, 'open', {
      'method': method,
      'target': target,
    });
    try {
      return _Request(await pending, id);
    } catch (error) {
      NetworkDiagnostic.event('dart_http', id, 'open_error', {
        'error': error.toString(),
      });
      rethrow;
    }
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _observe(inner.openUrl(method, url), method, url.toString());
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _observe(
    inner.open(method, host, port, path),
    method,
    '$host:$port$path',
  );
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override
  Future<HttpClientRequest> get(String h, int p, String s) =>
      open('GET', h, p, s);
  @override
  Future<HttpClientRequest> post(String h, int p, String s) =>
      open('POST', h, p, s);
  @override
  Future<HttpClientRequest> put(String h, int p, String s) =>
      open('PUT', h, p, s);
  @override
  Future<HttpClientRequest> patch(String h, int p, String s) =>
      open('PATCH', h, p, s);
  @override
  Future<HttpClientRequest> delete(String h, int p, String s) =>
      open('DELETE', h, p, s);
  @override
  Future<HttpClientRequest> head(String h, int p, String s) =>
      open('HEAD', h, p, s);
  @override
  Duration get idleTimeout => inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => inner.idleTimeout = v;
  @override
  Duration? get connectionTimeout => inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => inner.connectionTimeout = v;
  @override
  int? get maxConnectionsPerHost => inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => inner.maxConnectionsPerHost = v;
  @override
  bool get autoUncompress => inner.autoUncompress;
  @override
  set autoUncompress(bool v) => inner.autoUncompress = v;
  @override
  String? get userAgent => inner.userAgent;
  @override
  set userAgent(String? v) => inner.userAgent = v;
  @override
  set authenticate(Future<bool> Function(Uri, String, String?)? f) =>
      inner.authenticate = f;
  @override
  void addCredentials(Uri u, String r, HttpClientCredentials c) =>
      inner.addCredentials(u, r, c);
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? f,
  ) => inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri)? f) => inner.findProxy = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String, int, String, String?)? f,
  ) => inner.authenticateProxy = f;
  @override
  void addProxyCredentials(
    String h,
    int p,
    String r,
    HttpClientCredentials c,
  ) => inner.addProxyCredentials(h, p, r, c);
  @override
  set badCertificateCallback(bool Function(X509Certificate, String, int)? f) =>
      inner.badCertificateCallback = f;
  @override
  set keyLog(Function(String)? f) {
    inner.keyLog = (line) {
      NetworkDiagnostic.keyLog(line);
      f?.call(line);
    };
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

class _Request implements HttpClientRequest {
  _Request(this.inner, this.id);
  final HttpClientRequest inner;
  final int id;
  bool sent = false;
  Future<HttpClientResponse>? response;
  void _head() {
    if (sent) return;
    sent = true;
    NetworkDiagnostic.event('dart_http', id, 'request_headers', {
      'method': method,
      'uri': uri.toString(),
      'headers': NetworkDiagnostic.headers(headers),
      'cookies': cookies.map((c) => c.toString()).toList(),
      'followRedirects': followRedirects,
    });
  }

  @override
  void add(List<int> data) {
    _head();
    NetworkDiagnostic.event('dart_http', id, 'request_body', {}, data);
    inner.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _head();
    return inner.addStream(
      stream.map((bytes) {
        NetworkDiagnostic.event('dart_http', id, 'request_body', {}, bytes);
        return bytes;
      }),
    );
  }

  @override
  void write(Object? object) => add(encoding.encode('$object'));
  @override
  void writeln([Object? object = '']) => write('$object\n');
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      write(objects.join(separator));
  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);
  Future<HttpClientResponse> _wrap(Future<HttpClientResponse> value) =>
      response ??= value.then(
        (r) {
          NetworkDiagnostic.event('dart_http', id, 'response_headers', {
            'status': r.statusCode,
            'headers': NetworkDiagnostic.headers(r.headers),
            'redirects': r.redirects
                .map(
                  (v) => {
                    'status': v.statusCode,
                    'method': v.method,
                    'location': v.location.toString(),
                  },
                )
                .toList(),
            'remoteAddress': r.connectionInfo?.remoteAddress.address,
            'remotePort': r.connectionInfo?.remotePort,
            'localPort': r.connectionInfo?.localPort,
          });
          return _Response(r, id);
        },
        onError: (Object e, StackTrace s) {
          NetworkDiagnostic.event('dart_http', id, 'error', {
            'error': e.toString(),
          });
          Error.throwWithStackTrace(e, s);
        },
      );
  @override
  Future<HttpClientResponse> close() {
    _head();
    return _wrap(inner.close());
  }

  @override
  Future<HttpClientResponse> get done => _wrap(inner.done);
  @override
  Future<void> flush() => inner.flush();
  @override
  void abort([Object? e, StackTrace? s]) {
    NetworkDiagnostic.event('dart_http', id, 'abort', {});
    inner.abort(e, s);
  }

  @override
  Encoding get encoding => inner.encoding;
  @override
  set encoding(Encoding v) => inner.encoding = v;
  @override
  bool get persistentConnection => inner.persistentConnection;
  @override
  set persistentConnection(bool v) => inner.persistentConnection = v;
  @override
  bool get followRedirects => inner.followRedirects;
  @override
  set followRedirects(bool v) => inner.followRedirects = v;
  @override
  int get maxRedirects => inner.maxRedirects;
  @override
  set maxRedirects(int v) => inner.maxRedirects = v;
  @override
  int get contentLength => inner.contentLength;
  @override
  set contentLength(int v) => inner.contentLength = v;
  @override
  bool get bufferOutput => inner.bufferOutput;
  @override
  set bufferOutput(bool v) => inner.bufferOutput = v;
  @override
  String get method => inner.method;
  @override
  Uri get uri => inner.uri;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  List<Cookie> get cookies => inner.cookies;
  @override
  HttpConnectionInfo? get connectionInfo => inner.connectionInfo;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.inner, this.id);
  final HttpClientResponse inner;
  final int id;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => inner
      .transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (bytes, sink) {
            NetworkDiagnostic.event(
              'dart_http',
              id,
              'response_body',
              {},
              bytes,
            );
            sink.add(bytes);
          },
          handleDone: (sink) {
            NetworkDiagnostic.event('dart_http', id, 'response_end', {});
            sink.close();
          },
          handleError: (Object error, StackTrace stack, sink) {
            NetworkDiagnostic.event('dart_http', id, 'response_error', {
              'error': error.toString(),
            });
            sink.addError(error, stack);
          },
        ),
      )
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  Future<Socket> detachSocket() {
    NetworkDiagnostic.event('dart_http', id, 'socket_detached', {
      'contentCoverage':
          'subsequent bytes require websocket observer or TLS packet capture',
    });
    return inner.detachSocket();
  }

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) async => _Response(await inner.redirect(method, url, followLoops), id);
  @override
  int get statusCode => inner.statusCode;
  @override
  String get reasonPhrase => inner.reasonPhrase;
  @override
  int get contentLength => inner.contentLength;
  @override
  HttpClientResponseCompressionState get compressionState =>
      inner.compressionState;
  @override
  bool get persistentConnection => inner.persistentConnection;
  @override
  bool get isRedirect => inner.isRedirect;
  @override
  List<RedirectInfo> get redirects => inner.redirects;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  List<Cookie> get cookies => inner.cookies;
  @override
  X509Certificate? get certificate => inner.certificate;
  @override
  HttpConnectionInfo? get connectionInfo => inner.connectionInfo;
}
