import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutterrhythmquake/services/sources/native_http_client.dart';
import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';
import 'package:flutterrhythmquake/services/sources/source_http_client.dart';

void main() {
  final native = StationCoreLibrary.supported;
  group('native HTTP', () {
    late HttpServer server;
    late NativeHttpClient client;
    late Uri base;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}');
      client = NativeHttpClient();
    });
    tearDown(() async {
      client.close();
      await server.close(force: true);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while ((NativeHttpClient.activeClients != 0 ||
              NativeHttpClient.activeRequests != 0) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(NativeHttpClient.activeClients, 0);
      expect(NativeHttpClient.activeRequests, 0);
    });
    test('factory selects native only without HttpOverrides', () {
      final ordinary = createSourceHttpClient();
      if (Platform.isAndroid || const bool.fromEnvironment('RQ_NATIVE_HTTP')) {
        expect(ordinary, isA<NativeHttpClient>());
      } else {
        expect(ordinary, isNot(isA<NativeHttpClient>()));
      }
      ordinary.close();
      final inner = HttpClient();
      HttpOverrides.runZoned(() {
        final override = createSourceHttpClient();
        expect(override, isNot(isA<NativeHttpClient>()));
        override.close();
      }, createHttpClient: (_) => inner);
    });
    test('original XML bytes, encoded URL and headers survive', () async {
      final bytes = await File(
        'test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml',
      ).readAsBytes();
      String? target, referer, agent;
      server.listen((request) async {
        target = request.uri.toString();
        referer = request.headers.value('referer');
        agent = request.headers.value('user-agent');
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
          charset: 'utf-8',
        );
        request.response.add(bytes);
        await request.response.close();
      });
      final response = await client.get(
        base.resolve('/a%2Fb?name=%E6%B5%8B%E8%AF%95&v=%25'),
        headers: {
          'Referer': 'https://www.data.jma.go.jp/',
          'User-Agent': 'RhythmQuake HTTP test',
        },
      );
      expect(response.bodyBytes, bytes);
      expect(target, '/a%2Fb?name=%E6%B5%8B%E8%AF%95&v=%25');
      expect(referer, 'https://www.data.jma.go.jp/');
      expect(agent, 'RhythmQuake HTTP test');
    });
    test('gzip bytes and response metadata match IOClient', () async {
      final bytes = await File(
        'test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml',
      ).readAsBytes();
      final compressed = gzip.encode(bytes);
      server.listen((request) async {
        request.response.headers.set('content-encoding', 'gzip');
        request.response.headers.set(
          'content-type',
          'application/xml; charset=utf-8',
        );
        request.response.contentLength = compressed.length;
        request.response.add(compressed);
        await request.response.close();
      });
      final dart = IOClient();
      try {
        final expected = await dart.get(base);
        final actual = await client.get(base);
        expect(actual.bodyBytes, expected.bodyBytes);
        expect(actual.bodyBytes, bytes);
        expect(
          actual.headers['content-encoding'],
          expected.headers['content-encoding'],
        );
        expect(
          actual.headers['content-length'],
          expected.headers['content-length'],
        );
        expect(
          actual.headers['content-type'],
          expected.headers['content-type'],
        );
      } finally {
        dart.close();
      }
    });
    test(
      'gzip expansion stays bounded and concatenated members survive',
      () async {
        final sample = await File(
          'test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml',
        ).readAsBytes();
        final bytes = BytesBuilder(copy: false);
        for (var i = 0; i < 64; i++) {
          bytes.add(sample);
        }
        final original = bytes.takeBytes();
        final wire = [...gzip.encode(original), ...gzip.encode(sample)];
        server.listen((request) async {
          request.response.headers.set('content-encoding', 'gzip');
          request.response.add(wire);
          await request.response.close();
        });
        final response = await http.Response.fromStream(
          await client.send(http.Request('GET', base)),
        );
        expect(response.bodyBytes, [...original, ...sample]);
        expect(NativeHttpClient.queuePeakBytes, lessThanOrEqualTo(65536));
      },
    );
    test('truncated and corrupt gzip reject without leaking requests', () async {
      final source = await File(
        'test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml',
      ).readAsBytes();
      final compressed = gzip.encode(source);
      // These are HTTP protocol error probes, never event fixtures or APP input.
      final truncated = compressed.sublist(0, compressed.length - 5);
      final corrupt = List<int>.of(compressed)..[compressed.length - 8] ^= 0xff;
      server.listen((request) async {
        request.response.headers.set('content-encoding', 'gzip');
        request.response.add(
          request.uri.path == '/truncated' ? truncated : corrupt,
        );
        await request.response.close();
      });
      await expectLater(
        client.get(base.resolve('/truncated')),
        throwsA(isA<http.ClientException>()),
      );
      await expectLater(
        client.get(base.resolve('/corrupt')),
        throwsA(isA<http.ClientException>()),
      );
    });
    test(
      'response status, duplicate headers and Latin1 charset survive',
      () async {
        server.listen((request) async {
          request.response.statusCode = 404;
          request.response.headers.set(
            'content-type',
            'text/plain; charset=iso-8859-1',
          );
          request.response.headers.add('x-values', 'first');
          request.response.headers.add('x-values', 'second');
          request.response.add(latin1.encode('caf\u00e9'));
          await request.response.close();
        });
        final response = await client.get(base);
        expect(response.statusCode, 404);
        expect(response.body, 'caf\u00e9');
        final dart = IOClient();
        try {
          expect(
            response.headers['x-values'],
            (await dart.get(base)).headers['x-values'],
          );
        } finally {
          dart.close();
        }
      },
    );
    test(
      'POST body bytes are unchanged; 303 follows as bodyless GET',
      () async {
        final original = Uint8List.fromList([0, 255, 13, 10, 128]);
        final methods = <String>[], bodies = <List<int>>[];
        server.listen((request) async {
          methods.add(request.method);
          bodies.add(await request.fold<List<int>>([], (a, b) => a..addAll(b)));
          if (request.uri.path == '/post') {
            request.response.statusCode = 303;
            request.response.headers.set('location', '/done');
          } else {
            request.response.write('done');
          }
          await request.response.close();
        });
        final response = await client.post(
          base.resolve('/post'),
          body: original,
        );
        expect(response.body, 'done');
        expect(methods, ['POST', 'GET']);
        expect(bodies, [original, <int>[]]);
      },
    );
    test('POST 302 is not automatically followed; no cookie jar', () async {
      final cookies = <String?>[];
      server.listen((request) async {
        cookies.add(request.headers.value('cookie'));
        request.response.statusCode = 302;
        request.response.headers.set('location', '/next');
        request.response.headers.add('set-cookie', 'sid=secret');
        await request.response.close();
      });
      final response = await client.post(base);
      expect(response.statusCode, 302);
      await client.post(base);
      expect(cookies, [null, null]);
    });
    test('HEAD completes without a response body', () async {
      server.listen((request) async {
        request.response.contentLength = 456;
        await request.response.close();
      });
      final response = await client.head(base);
      expect(response.bodyBytes, isEmpty);
      expect(response.headers['content-length'], '456');
    });
    test(
      'cross-origin redirect strips credentials and keeps ordinary headers',
      () async {
        final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        String? auth, cookie, referer;
        other.listen((request) async {
          auth = request.headers.value('authorization');
          cookie = request.headers.value('cookie');
          referer = request.headers.value('referer');
          request.response.write('target');
          await request.response.close();
        });
        server.listen((request) async {
          request.response.statusCode = 302;
          request.response.headers.set(
            'location',
            'http://127.0.0.1:${other.port}/target',
          );
          await request.response.close();
        });
        try {
          final response = await client.get(
            base,
            headers: {
              'Authorization': 'Bearer local-test-only',
              'Cookie': 'sid=local-test-only',
              'Referer': 'https://www.jma.go.jp/',
            },
          );
          expect(response.body, 'target');
          expect(auth, isNull);
          expect(cookie, isNull);
          expect(referer, 'https://www.jma.go.jp/');
        } finally {
          await other.close(force: true);
        }
      },
    );
    test('same-origin redirect and disabled redirects', () async {
      String? auth;
      server.listen((request) async {
        if (request.uri.path == '/target') {
          auth = request.headers.value('authorization');
          request.response.write('ok');
        } else {
          request.response.statusCode = 307;
          request.response.headers.set('location', '/target');
        }
        await request.response.close();
      });
      expect(
        (await client.get(
          base,
          headers: {'Authorization': 'Bearer local-test-only'},
        )).body,
        'ok',
      );
      expect(auth, 'Bearer local-test-only');
      final request = http.Request('GET', base)..followRedirects = false;
      final response = await client.send(request);
      expect(response.statusCode, 307);
      expect(response.isRedirect, isTrue);
      await response.stream.drain<void>();
    });
    test('redirect loop fails and releases requests', () async {
      server.listen((request) async {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/loop');
        await request.response.close();
      });
      await expectLater(client.get(base), throwsA(isA<http.ClientException>()));
    });
    test(
      'pause keeps receive queue bounded and frame valid after release',
      () async {
        final sample = await File(
          'test/fixtures/global_quake/stream_20260921.bin',
        ).readAsBytes();
        final payload = BytesBuilder(copy: false);
        for (var i = 0; i < 4096; i++) {
          payload.add(sample);
        }
        final bytes = payload.takeBytes();
        server.listen((request) async {
          request.response.add(bytes);
          await request.response.close();
        });
        final response = await client.send(http.Request('GET', base));
        final first = Completer<void>(), done = Completer<void>();
        final chunks = <List<int>>[];
        late StreamSubscription<List<int>> subscription;
        subscription = response.stream.listen(
          (chunk) {
            chunks.add(chunk);
            if (!first.isCompleted) {
              subscription.pause();
              first.complete();
            }
          },
          onError: done.completeError,
          onDone: done.complete,
        );
        await first.future;
        final retained = Uint8List.sublistView(chunks.first as Uint8List);
        final retainedCopy = Uint8List.fromList(retained);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(chunks.length, 1);
        expect(NativeHttpClient.queuePeakBytes, lessThanOrEqualTo(65536));
        subscription.resume();
        await done.future;
        final received = BytesBuilder(copy: false);
        for (final chunk in chunks) {
          received.add(chunk);
        }
        expect(received.takeBytes(), bytes);
        client.close();
        expect(retained, retainedCopy);
      },
    );
    test('cancel response stream aborts native read', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('start');
        await request.response.flush();
      });
      final dart = IOClient();
      try {
        final baseline = await dart
            .send(http.Request('GET', base))
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => throw StateError('Dart headers stalled'),
            );
        final received = Completer<void>();
        baseline.stream.listen((_) {
          if (!received.isCompleted) received.complete();
        }, onError: (_) {});
        await received.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError('Dart first chunk stalled'),
        );
      } finally {
        dart.close();
      }
      final response = await client
          .send(http.Request('GET', base))
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError('Native headers stalled'),
          );
      await response.stream
          .take(1)
          .drain<void>()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError('Native body stalled'),
          );
    });
    test(
      'close cancels pending headers; closed client cannot reopen',
      () async {
        final arrived = Completer<void>();
        server.listen((request) {
          arrived.complete();
        });
        final pending = client.get(base);
        final assertion = expectLater(
          pending,
          throwsA(isA<http.ClientException>()),
        );
        await arrived.future;
        client.close();
        await assertion;
        await expectLater(
          client.get(base),
          throwsA(isA<http.ClientException>()),
        );
      },
    );
    test('request deadline cancels before headers', () async {
      client.close();
      client = NativeHttpClient(
        requestTimeout: const Duration(milliseconds: 100),
      );
      server.listen((request) {});
      await expectLater(client.get(base), throwsA(isA<TimeoutException>()));
    });
    test('request deadline also cancels stalled body', () async {
      client.close();
      client = NativeHttpClient(
        requestTimeout: const Duration(milliseconds: 150),
      );
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('partial');
        await request.response.flush();
      });
      await expectLater(client.get(base), throwsA(isA<TimeoutException>()));
    });
    test('16 parallel requests retain independent payloads', () async {
      server.listen((request) async {
        request.response.write(request.uri.path);
        await request.response.close();
      });
      final results = await Future.wait(
        List.generate(16, (i) => client.get(base.resolve('/$i'))),
      );
      expect(results.map((r) => r.body), List.generate(16, (i) => '/$i'));
    });
    test('explicit non-gzip encoding retains IOClient route', () async {
      server.listen((request) async {
        request.response.write(request.headers.value('accept-encoding'));
        await request.response.close();
      });
      expect(
        (await client.get(base, headers: {'Accept-Encoding': 'identity'})).body,
        'identity',
      );
      expect(NativeHttpClient.activeClients, 0);
    });
  }, skip: !native);
}
