import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'fdsn_proxy.dart';

http.Client createFdsnHttpClient() => FdsnNetwork.instance.createHttpClient();

class FdsnSocket {
  const FdsnSocket(this.socket, this.route);
  final Socket socket;
  final FdsnProxyRoute route;
}

class FdsnNetwork {
  FdsnNetwork({Future<FdsnProxyRoute> Function(Uri)? resolve})
    : resolve = resolve ?? FdsnProxyResolver().resolve;
  static final instance = FdsnNetwork();
  final Future<FdsnProxyRoute> Function(Uri) resolve;

  http.Client createHttpClient() => _FdsnHttpClient(resolve);
  Uri socketUri(String host, int port) =>
      Uri(scheme: 'https', host: host, port: port, path: '/');

  Future<FdsnSocket> connect(
    String host,
    int port, {
    bool secure = false,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final route = await resolve(socketUri(host, port));
    if (route.isDirect) {
      final socket = await (secure ? SecureSocket.connect : Socket.connect)(
        host,
        port,
        timeout: timeout,
      );
      unawaited(socket.done.catchError((Object _) {}));
      return FdsnSocket(socket, route);
    }
    // Dart's CONNECT parser preserves bytes coalesced after the response header.
    // For plaintext SeedLink we can use its detached socket directly.
    if (!secure) {
      final client = HttpClient()
        ..connectionTimeout = timeout
        ..findProxy = (_) => route.directive;
      Socket? detached;
      var expired = false;
      try {
        final operation = () async {
          final request = await client.openUrl(
            'CONNECT',
            Uri(host: host, port: port),
          );
          request.followRedirects = false;
          final response = await request.close();
          if (response.statusCode != 200) {
            throw HttpException(
              'SeedLink proxy CONNECT HTTP ${response.statusCode}',
            );
          }
          final socket = await response.detachSocket();
          unawaited(socket.done.catchError((Object _) {}));
          if (expired) {
            socket.destroy();
            throw TimeoutException('SeedLink proxy CONNECT');
          }
          detached = socket;
          return FdsnSocket(socket, route);
        }();
        return await operation.timeout(timeout);
      } catch (_) {
        expired = true;
        detached?.destroy();
        rethrow;
      } finally {
        client.close(force: true);
      }
    }
    // SecureSocket.secure requires an actual Dart socket, not HttpClient's
    // detached wrapper. Pause after CONNECT and hand that socket to TLS.
    final socket = await Socket.connect(
      route.host,
      route.port,
      timeout: timeout,
    );
    unawaited(socket.done.catchError((Object _) {}));
    final ready = Completer<void>();
    final header = <int>[];
    late StreamSubscription<Uint8List> subscription;
    subscription = socket.listen(
      (chunk) {
        if (ready.isCompleted) return;
        header.addAll(chunk);
        if (header.length > 16384) {
          ready.completeError(
            const HttpException('Oversized proxy CONNECT header'),
          );
          return;
        }
        final text = latin1.decode(header);
        if (!text.contains('\r\n\r\n')) return;
        subscription.pause();
        final status = RegExp(
          r'^HTTP/1\.[01] (\d{3})(?: |\r)',
        ).firstMatch(text)?.group(1);
        if (status != '200') {
          ready.completeError(
            HttpException('SeedLink proxy CONNECT HTTP ${status ?? 'invalid'}'),
          );
        } else if (!text.endsWith('\r\n\r\n')) {
          ready.completeError(
            const HttpException('Unexpected data before TLS handshake'),
          );
        } else {
          ready.complete();
        }
      },
      onError: (Object e) {
        if (!ready.isCompleted) ready.completeError(e);
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            const SocketException('Proxy closed during CONNECT'),
          );
        }
      },
    );
    final authority = host.contains(':') ? '[$host]:$port' : '$host:$port';
    socket.write('CONNECT $authority HTTP/1.1\r\nHost: $authority\r\n\r\n');
    try {
      await ready.future.timeout(timeout);
      final pending = SecureSocket.secure(socket, host: host);
      var expired = false;
      final secured = await pending
          .then((value) {
            if (expired) value.destroy();
            return value;
          })
          .timeout(
            timeout,
            onTimeout: () {
              expired = true;
              socket.destroy();
              throw TimeoutException('SeedLink proxy TLS handshake');
            },
          );
      unawaited(secured.done.catchError((Object _) {}));
      return FdsnSocket(secured, route);
    } catch (_) {
      socket.destroy();
      await subscription.cancel();
      rethrow;
    }
  }
}

class _FdsnHttpClient extends http.BaseClient {
  _FdsnHttpClient(this.resolve);
  final Future<FdsnProxyRoute> Function(Uri) resolve;
  final _clients = <String, http.Client>{};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!['GET', 'HEAD'].contains(request.method)) {
      throw UnsupportedError('FDSN metadata client only accepts GET/HEAD');
    }
    var uri = request.url;
    final headers = Map<String, String>.of(request.headers);
    for (var redirects = 0; ; redirects++) {
      if (_closed) throw http.ClientException('FDSN client closed', uri);
      final route = await resolve(uri);
      if (_closed) throw http.ClientException('FDSN client closed', uri);
      final client = _clients.putIfAbsent(
        route.directive,
        () => IOClient(HttpClient()..findProxy = (_) => route.directive),
      );
      final next = http.Request(request.method, uri)
        ..headers.addAll(headers)
        ..followRedirects = false
        ..persistentConnection = request.persistentConnection;
      final response = await client.send(next);
      final location = response.headers['location'];
      if (!request.followRedirects ||
          location == null ||
          ![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      await response.stream.drain<void>();
      if (redirects >= request.maxRedirects) {
        throw http.ClientException('Too many FDSN redirects', uri);
      }
      final target = uri.resolve(location);
      if (!['http', 'https'].contains(target.scheme)) {
        throw http.ClientException('Invalid FDSN redirect scheme', target);
      }
      if (target.origin != uri.origin) {
        headers.removeWhere(
          (key, _) =>
              ['authorization', 'cookie', 'host'].contains(key.toLowerCase()),
        );
      }
      uri = target;
    }
  }

  @override
  void close() {
    _closed = true;
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}
