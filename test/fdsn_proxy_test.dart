import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_network_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_proxy.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_windows_proxy.dart';

void main() {
  test(
    'Windows native PAC resolution returns proxy and direct per URL',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.set(
          'content-type',
          'application/x-ns-proxy-autoconfig',
        );
        request.response.write(
          'function FindProxyForURL(url, host) { return host == "direct.test" ? "DIRECT" : "PROXY 127.0.0.1:18080"; }',
        );
        await request.response.close();
      });
      final pac = 'http://127.0.0.1:${server.port}/proxy.pac';
      try {
        final proxied = await Isolate.run(
          () => resolveWindowsFdsnAutoProxy('https://proxy.test/', pac, false),
        );
        final direct = await Isolate.run(
          () => resolveWindowsFdsnAutoProxy('https://direct.test/', pac, false),
        );
        expect(
          windowsFdsnRoute(Uri.parse('https://proxy.test/'), proxied).port,
          18080,
        );
        expect(
          windowsFdsnRoute(Uri.parse('https://direct.test/'), direct).isDirect,
          isTrue,
        );
      } finally {
        await server.close(force: true);
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
  test(
    'running SeedLink follows direct/proxy/direct changes without reconnect churn',
    () async {
      final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      var upstreamConnections = 0;
      var proxyConnections = 0;
      var proxyEnabled = false;
      upstream.listen((socket) {
        peers.add(socket);
        upstreamConnections++;
        unawaited(socket.done.catchError((Object _) {}));
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line != 'END') socket.write('OK\r\n');
            }, onError: (_) {});
      });
      proxy.listen((socket) {
        peers.add(socket);
        proxyConnections++;
        unawaited(socket.done.catchError((Object _) {}));
        final header = <int>[];
        Socket? remote;
        socket.listen(
          (bytes) async {
            if (remote != null) {
              remote!.add(bytes);
              return;
            }
            header.addAll(bytes);
            if (!latin1.decode(header).endsWith('\r\n\r\n')) return;
            remote = await Socket.connect('127.0.0.1', upstream.port);
            peers.add(remote!);
            unawaited(remote!.done.catchError((Object _) {}));
            remote!.listen(socket.add, onError: (_) {}, onDone: socket.destroy);
            socket.write('HTTP/1.1 200 Connection established\r\n\r\n');
          },
          onError: (_) {},
          onDone: () => remote?.destroy(),
        );
      });
      final network = FdsnNetwork(
        resolve: (_) async => proxyEnabled
            ? FdsnProxyRoute.proxy('127.0.0.1', proxy.port)
            : const FdsnProxyRoute.direct(),
      );
      final service = FdsnMotionService.forTesting(
        streams: [
          FdsnSeedLinkStream(
            source: 'Test',
            host: '127.0.0.1',
            port: upstream.port,
            network: 'XX',
            station: 'TEST',
            selector: 'BHZ',
          ),
        ],
        network: network,
        watchdogInterval: const Duration(milliseconds: 30),
        reconnectDelay: const Duration(milliseconds: 10),
      );
      Future<void> waitFor(bool Function() check) async {
        await (() async {
          while (!check()) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        })().timeout(const Duration(seconds: 3));
      }

      try {
        service.connectProvidedStreamsForTesting();
        await waitFor(
          () =>
              service.connectionDiagnostics.single['networkRoute'] == 'DIRECT',
        );
        expect(upstreamConnections, 1);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(upstreamConnections, 1);
        proxyEnabled = true;
        await waitFor(
          () =>
              service.connectionDiagnostics.single['networkRoute'] ==
              'PROXY 127.0.0.1:${proxy.port}',
        );
        expect(upstreamConnections, 2);
        expect(proxyConnections, 1);
        proxyEnabled = false;
        await waitFor(
          () =>
              service.connectionDiagnostics.single['networkRoute'] ==
                  'DIRECT' &&
              upstreamConnections == 3,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(upstreamConnections, 3);
        expect(
          service.connectionDiagnostics.single['lastCloseReason'],
          'system proxy route changed',
        );
        service.disconnect();
        proxyEnabled = true;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(upstreamConnections, 3);
      } finally {
        service.disconnect();
        for (final peer in peers) {
          peer.destroy();
        }
        await upstream.close();
        await proxy.close();
      }
    },
  );
  test(
    'disabled Windows proxy is direct; enabled proxy is not hard-coded',
    () async {
      var reads = 0;
      var now = DateTime.utc(2026);
      var config = <String, Object>{};
      final resolver = FdsnProxyResolver(
        environment: {},
        windows: true,
        clock: () => now,
        readWindows: () async {
          reads++;
          return config;
        },
      );
      final uri = Uri.https('www.orfeus-eu.org', '/fdsnws/station/1/query');
      expect((await resolver.resolve(uri)).isDirect, isTrue);
      config = {'proxy': 'localhost:19001'};
      expect((await resolver.resolve(uri)).isDirect, isTrue);
      expect(reads, 1);
      now = now.add(const Duration(seconds: 16));
      expect((await resolver.resolve(uri)).directive, 'PROXY localhost:19001');
      config = {};
      now = now.add(const Duration(seconds: 16));
      expect((await resolver.resolve(uri)).directive, 'DIRECT');
      expect(reads, 3);
    },
  );

  test('scheme-specific Windows proxies, bypass, and IPv6 endpoints', () {
    final config = <String, Object>{
      'proxy': 'http=localhost:18080;https=[::1]:18081',
      'bypass': '*.example.org;<local>;exact.test:443',
    };
    expect(
      windowsFdsnRoute(Uri.parse('http://remote.test'), config).port,
      18080,
    );
    expect(
      windowsFdsnRoute(Uri.parse('https://remote.test'), config).directive,
      'PROXY [::1]:18081',
    );
    for (final url in [
      'https://a.example.org',
      'http://intranet',
      'https://exact.test',
      'http://127.0.0.1',
      'http://[::1]',
    ]) {
      expect(
        windowsFdsnRoute(Uri.parse(url), config).isDirect,
        isTrue,
        reason: url,
      );
    }
    expect(
      windowsFdsnRoute(Uri.parse('http://exact.test'), config).isDirect,
      isFalse,
    );
    expect(
      windowsFdsnRoute(Uri.parse('https://badexample.org'), config).isDirect,
      isFalse,
    );
  });

  test('unsupported proxies fail explicitly, never silently become direct', () {
    for (final value in [
      'socks5://localhost:1080',
      'http://user:secret@localhost:8080',
      'localhost:99999',
    ]) {
      expect(() => FdsnProxyRoute.parse(value), throwsFormatException);
    }
  });

  test('environment proxy and NO_PROXY work without Windows', () async {
    final resolver = FdsnProxyResolver(
      windows: false,
      environment: {
        'https_proxy': 'localhost:18001',
        'no_proxy': '.example.org',
      },
    );
    expect(
      (await resolver.resolve(Uri.parse('https://a.example.org'))).isDirect,
      isTrue,
    );
    expect(
      (await resolver.resolve(Uri.parse('https://remote.test'))).port,
      18001,
    );
    expect(
      (await resolver.resolve(Uri.parse('http://remote.test'))).isDirect,
      isTrue,
    );
    final withScheme = FdsnProxyResolver(
      windows: false,
      environment: {'HTTPS_PROXY': 'http://localhost:18002'},
    );
    expect(
      (await withScheme.resolve(Uri.parse('https://remote.test'))).port,
      18002,
    );
    final socks = FdsnProxyResolver(
      windows: false,
      environment: {'HTTPS_PROXY': 'socks5://localhost:1080'},
    );
    await expectLater(
      socks.resolve(Uri.parse('https://remote.test')),
      throwsFormatException,
    );
  });

  test('PAC is resolved per URL and respects explicit DIRECT', () async {
    final calls = <String>[];
    final resolver = FdsnProxyResolver(
      windows: true,
      environment: {},
      readWindows: () async => {'autoUrl': 'http://pac.test/proxy.pac'},
      resolveAuto: (url, pac, detect) async {
        calls.add(url);
        return {'proxy': url.endsWith('/direct') ? '' : 'localhost:18888'};
      },
    );
    expect(
      (await resolver.resolve(Uri.parse('https://remote.test/proxy'))).port,
      18888,
    );
    expect(
      (await resolver.resolve(
        Uri.parse('https://remote.test/direct'),
      )).isDirect,
      isTrue,
    );
    await resolver.resolve(Uri.parse('https://remote.test/proxy'));
    expect(calls, hasLength(2));
  });

  test(
    'concurrent lookups share configuration; read errors are not DIRECT',
    () async {
      var reads = 0;
      final pending = Completer<Map<String, Object>>();
      final resolver = FdsnProxyResolver(
        windows: true,
        environment: {},
        readWindows: () {
          reads++;
          return pending.future;
        },
      );
      final a = resolver.resolve(Uri.parse('https://a.test'));
      final b = resolver.resolve(Uri.parse('https://b.test'));
      final aCheck = expectLater(a, throwsStateError);
      final bCheck = expectLater(b, throwsStateError);
      pending.completeError(StateError('read failed'));
      await aCheck;
      await bCheck;
      expect(reads, 1);
    },
  );

  test(
    'HTTP follows proxy changes and resolves redirect target separately',
    () async {
      final direct = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final resolutions = <Uri>[];
      var enabled = false;
      var proxied = 0;
      direct.listen((req) async {
        req.response.write('direct');
        await req.response.close();
      });
      proxy.listen((req) async {
        proxied++;
        if (req.uri.path == '/redirect') {
          req.response.statusCode = 302;
          req.response.headers.set(
            'location',
            'http://127.0.0.1:${direct.port}/target',
          );
        } else {
          req.response.write('proxy');
        }
        await req.response.close();
      });
      final network = FdsnNetwork(
        resolve: (uri) async {
          resolutions.add(uri);
          return enabled && uri.host != '127.0.0.1'
              ? FdsnProxyRoute.proxy('127.0.0.1', proxy.port)
              : const FdsnProxyRoute.direct();
        },
      );
      final client = network.createHttpClient();
      try {
        expect(
          (await client.get(
            Uri.parse('http://localhost:${direct.port}/'),
          )).body,
          'direct',
        );
        enabled = true;
        expect(
          (await client.get(
            Uri.parse('http://localhost:${direct.port}/'),
          )).body,
          'proxy',
        );
        expect(
          (await client.get(Uri.parse('http://remote.invalid/redirect'))).body,
          'direct',
        );
        expect(resolutions.last.host, '127.0.0.1');
        enabled = false;
        expect(
          (await client.get(
            Uri.parse('http://localhost:${direct.port}/'),
          )).body,
          'direct',
        );
        expect(proxied, 2);
      } finally {
        client.close();
        await direct.close(force: true);
        await proxy.close(force: true);
      }
    },
  );

  test(
    'closed HTTP client cannot start a request after proxy resolution',
    () async {
      final ready = Completer<FdsnProxyRoute>();
      final client = FdsnNetwork(
        resolve: (_) => ready.future,
      ).createHttpClient();
      final request = client.get(Uri.parse('http://unused.invalid/'));
      final check = expectLater(request, throwsException);
      client.close();
      ready.complete(const FdsnProxyRoute.direct());
      await check;
    },
  );

  test('plain SeedLink CONNECT preserves coalesced original bytes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    final lines = <String>[];
    server.listen((socket) {
      peers.add(socket);
      unawaited(socket.done.catchError((Object _) {}));
      final header = <int>[];
      socket.listen((chunk) {
        header.addAll(chunk);
        if (latin1.decode(header).contains('\r\n\r\n')) {
          lines.add(latin1.decode(header).split('\r\n').first);
          socket.add([
            ...ascii.encode('HTTP/1.1 200 Connection established\r\n\r\n'),
            0,
            1,
            128,
            255,
          ]);
          header.clear();
        }
      }, onError: (_) {});
    });
    Socket? client;
    try {
      final network = FdsnNetwork(
        resolve: (_) async => FdsnProxyRoute.proxy('127.0.0.1', server.port),
      );
      final result = await network.connect('example.invalid', 18000);
      client = result.socket;
      final bytes = await client.first.timeout(const Duration(seconds: 2));
      expect(bytes, [0, 1, 128, 255]);
      expect(lines, ['CONNECT example.invalid:18000 HTTP/1.1']);
      expect(result.route.isDirect, isFalse);
    } finally {
      client?.destroy();
      for (final socket in peers) {
        socket.destroy();
      }
      await server.close();
    }
  });

  for (final secure in [false, true]) {
    test('CONNECT rejection never retries direct (TLS=$secure)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var attempts = 0;
      server.listen((req) async {
        attempts++;
        req.response.statusCode = 407;
        await req.response.close();
      });
      try {
        final network = FdsnNetwork(
          resolve: (_) async => FdsnProxyRoute.proxy('127.0.0.1', server.port),
        );
        await expectLater(
          network.connect('example.invalid', 18500, secure: secure),
          throwsA(isA<HttpException>()),
        );
        expect(attempts, 1);
      } finally {
        await server.close(force: true);
      }
    });

    test('CONNECT timeout closes pending socket (TLS=$secure)', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      final closed = Completer<void>();
      server.listen((socket) {
        peers.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        socket.listen(
          (_) {},
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
          onError: (_) {},
        );
      });
      try {
        final network = FdsnNetwork(
          resolve: (_) async => FdsnProxyRoute.proxy('127.0.0.1', server.port),
        );
        await expectLater(
          network.connect(
            'example.invalid',
            18500,
            secure: secure,
            timeout: const Duration(milliseconds: 150),
          ),
          throwsA(isA<TimeoutException>()),
        );
        await closed.future.timeout(const Duration(seconds: 2));
      } finally {
        for (final socket in peers) {
          socket.destroy();
        }
        await server.close();
      }
    });
  }
}
