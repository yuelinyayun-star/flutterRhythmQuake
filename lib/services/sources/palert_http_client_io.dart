import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'fdsn_proxy.dart';

const pAlertRootAsset = 'assets/certificates/TWCA_Global_Root_CA.der';
const pAlertRootSha256 =
    '59769007f7685d0fcd50872f9f95d5755a5b2b457d81f3692b610a98672f0e1b';

SecurityContext createPAlertSecurityContext(List<int> rootDer) {
  if (sha256.convert(rootDer).toString() != pAlertRootSha256) {
    throw StateError('P-Alert TWCA root certificate fingerprint mismatch');
  }
  final pem =
      '-----BEGIN CERTIFICATE-----\n'
      '${base64.encode(rootDer)}\n'
      '-----END CERTIFICATE-----\n';
  // Supplement only this client's roots, never SecurityContext.defaultContext.
  return SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(utf8.encode(pem));
}

Future<http.Client> createPAlertHttpClient() async {
  List<int>? root;
  try {
    final data = await rootBundle.load(pAlertRootAsset);
    root = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    // Keep context null if asset is not loaded in headless environments.
  }
  return createPAlertHttpClientWithRoot(root);
}

/// The UI loads this small asset once; the data isolate owns TLS and HTTP.
Future<http.Client> createPAlertHttpClientWithRoot(
  List<int>? root, {
  Future<String> Function(Uri)? resolveProxy,
}) async {
  final context = root == null ? null : createPAlertSecurityContext(root);
  final environment = Map<String, String>.of(Platform.environment);
  final allProxy = environment['all_proxy'] ?? environment['ALL_PROXY'];
  if (allProxy != null && allProxy.isNotEmpty) {
    for (final scheme in ['http', 'https']) {
      if (!environment.containsKey('${scheme}_proxy') &&
          !environment.containsKey('${scheme.toUpperCase()}_PROXY')) {
        environment['${scheme}_proxy'] = allProxy;
      }
    }
  }
  final resolver = FdsnProxyResolver(environment: environment);
  return _PAlertProxyClient(
    context,
    resolveProxy ?? (uri) async => (await resolver.resolve(uri)).directive,
  );
}

class _PAlertProxyRoute {
  _PAlertProxyRoute(this.client);
  final IOClient client;
  int users = 0;
}

/// Each request resolves the existing system/environment policy. Routes own
/// separate clients so concurrent requests cannot overwrite each other's proxy.
class _PAlertProxyClient extends http.BaseClient {
  _PAlertProxyClient(this.context, this.resolveProxy);
  final _creationZone = Zone.current;
  final SecurityContext? context;
  final Future<String> Function(Uri) resolveProxy;
  final _routes = <String, _PAlertProxyRoute>{};
  String? _current;
  bool _closed = false;

  _PAlertProxyRoute _open(String directive) {
    final client = _creationZone.run(() => HttpClient(context: context));
    client.findProxy = (_) => directive;
    client.badCertificateCallback = (cert, host, port) {
      // Keep the existing P-Alert-only TLS policy with its supplemental root.
      return host == 'palert.earth.sinica.edu.tw';
    };
    return _PAlertProxyRoute(IOClient(client));
  }

  void _release(String directive, _PAlertProxyRoute route) {
    route.users--;
    if (route.users == 0 &&
        directive != _current &&
        identical(_routes[directive], route)) {
      _routes.remove(directive);
      route.client.close();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('P-Alert client is closed', request.url);
    }
    final directive = FdsnProxyRoute.parse(
      await resolveProxy(request.url),
    ).directive;
    if (_closed) {
      throw http.ClientException('P-Alert client is closed', request.url);
    }
    _current = directive;
    // Retire idle connections after a proxy change without aborting responses
    // already in progress. The current route keeps its normal connection pool.
    for (final key in _routes.keys.toList()) {
      if (key != directive && _routes[key]!.users == 0) {
        _routes.remove(key)!.client.close();
      }
    }
    final route = _routes.putIfAbsent(directive, () => _open(directive));
    route.users++;
    late final http.StreamedResponse response;
    try {
      response = await route.client.send(request);
    } catch (_) {
      _release(directive, route);
      rethrow;
    }
    Stream<List<int>> body() async* {
      try {
        yield* response.stream;
      } finally {
        _release(directive, route);
      }
    }

    return http.StreamedResponse(
      body(),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final route in _routes.values) {
      route.client.close();
    }
    _routes.clear();
  }
}
