import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/palert_http_client_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_proxy.dart';

// Actual saved P-Alert archive bytes are transported unchanged. The local
// servers/proxy errors below are transport controls, not earthquake events.
final original = File(
  'test/fixtures/palert_cwa_1150077_20261017/060367f0ba216c84b9a644f1b3a4271b4549a546f8210301b008b7038996e6ef.json',
).readAsBytesSync();

void main() {
  test(
    'both P-Alert query requests use resolved Windows proxy and retain bytes',
    () async {
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <(String, Uri, List<int>)>[];
      final sub = proxy.listen((request) async {
        requests.add((
          request.method,
          request.uri,
          await request.fold<List<int>>([], (a, b) => a..addAll(b)),
        ));
        request.response.add(original);
        await request.response.close();
      });
      final resolver = FdsnProxyResolver(
        environment: {},
        windows: true,
        readWindows: () async => {'proxy': '127.0.0.1:${proxy.port}'},
      );
      final client = await createPAlertHttpClientWithRoot(
        null,
        resolveProxy: (uri) async => (await resolver.resolve(uri)).directive,
      );
      try {
        for (final part in ['metadata', 'realtime']) {
          final uri = Uri.parse('http://palert-source.invalid/$part');
          final response = await client.post(uri, body: original);
          expect(response.bodyBytes, original);
          expect(requests.last.$1, 'POST');
          expect(requests.last.$2, uri);
          expect(requests.last.$3, original);
        }
        expect(requests, hasLength(2));
      } finally {
        client.close();
        await sub.cancel();
        await proxy.close(force: true);
      }
    },
  );

  test(
    'proxy changes and concurrent direct response keep independent routes',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>(), release = Completer<void>();
      var directRequests = 0, proxyRequests = 0;
      final directSub = upstream.listen((request) async {
        directRequests++;
        if (request.uri.path == '/slow') {
          request.response.add(original.sublist(0, 16));
          await request.response.flush();
          started.complete();
          await release.future;
          request.response.add(original.sublist(16));
        } else {
          request.response.add(original);
        }
        await request.response.close();
      });
      final proxySub = proxy.listen((request) async {
        proxyRequests++;
        request.response.add(original);
        await request.response.close();
      });
      var enabled = false;
      final client = await createPAlertHttpClientWithRoot(
        null,
        resolveProxy: (uri) async =>
            enabled ? 'PROXY 127.0.0.1:${proxy.port}' : 'DIRECT',
      );
      final target = Uri.parse('http://127.0.0.1:${upstream.port}');
      try {
        final pending = client.get(target.replace(path: '/slow'));
        await started.future;
        enabled = true;
        expect(
          (await client.get(target.replace(path: '/proxied'))).bodyBytes,
          original,
        );
        release.complete();
        expect((await pending).bodyBytes, original);
        enabled = false;
        expect(
          (await client.get(target.replace(path: '/direct'))).bodyBytes,
          original,
        );
        expect([directRequests, proxyRequests], [2, 1]);
      } finally {
        if (!release.isCompleted) release.complete();
        client.close();
        await directSub.cancel();
        await proxySub.cancel();
        await upstream.close(force: true);
        await proxy.close(force: true);
      }
    },
  );

  test('HTTPS uses CONNECT for the official host', () async {
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    final header = Completer<String>();
    final sub = proxy.listen((socket) {
      peers.add(socket);
      var received = '';
      socket.listen((bytes) {
        received += latin1.decode(bytes);
        if (!header.isCompleted && received.contains('\r\n\r\n')) {
          header.complete(received);
          socket.write(
            'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
          );
          unawaited(socket.flush().then((_) => socket.close()));
        }
      }, onError: (_) {});
    });
    final client = await createPAlertHttpClientWithRoot(
      null,
      resolveProxy: (_) async => 'PROXY 127.0.0.1:${proxy.port}',
    );
    try {
      await expectLater(
        client.get(Uri.https('palert.earth.sinica.edu.tw', '/graphql/')),
        throwsException,
      );
      expect(
        await header.future,
        startsWith('CONNECT palert.earth.sinica.edu.tw:443 HTTP/1.1\r\n'),
      );
    } finally {
      client.close();
      for (final peer in peers) {
        peer.destroy();
      }
      await sub.cancel();
      await proxy.close();
    }
  });

  test('failed proxy never silently bypasses to the direct upstream', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = reserved.port;
    await reserved.close();
    var directRequests = 0;
    final sub = origin.listen((r) async {
      directRequests++;
      await r.response.close();
    });
    final client = await createPAlertHttpClientWithRoot(
      null,
      resolveProxy: (_) async => 'PROXY 127.0.0.1:$port',
    );
    try {
      await expectLater(
        client.get(Uri.parse('http://127.0.0.1:${origin.port}/graphql/')),
        throwsException,
      );
      expect(directRequests, 0);
    } finally {
      client.close();
      await sub.cancel();
      await origin.close(force: true);
    }
  });

  test(
    'close during pending proxy resolution cannot create a late connection',
    () async {
      final route = Completer<String>();
      final client = await createPAlertHttpClientWithRoot(
        null,
        resolveProxy: (_) => route.future,
      );
      final request = client.get(
        Uri.https('palert.earth.sinica.edu.tw', '/graphql/'),
      );
      client.close();
      route.complete('DIRECT');
      await expectLater(request, throwsException);
    },
  );
}
