import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/network_diagnostic.dart';
import 'package:flutterrhythmquake/services/sources/native_http_client.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';
import 'package:flutterrhythmquake/services/sources/source_socket.dart';

void main() {
  test(
    'Debug observes both HTTP transports and native WS without rerouting',
    () async {
      HttpOverrides.global = null;
      NetworkDiagnostic.start();
      expect(NetworkDiagnostic.active, isTrue);
      expect(NetworkDiagnostic.hasTransportOverrides, isFalse);
      final received = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        if (request.uri.path == '/ws') {
          expect(
            request.headers.value('authorization'),
            'Bearer offline_contract',
          );
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen((data) {
            socket.add(data);
          });
        } else {
          final bytes = await request.fold<List<int>>(
            [],
            (a, b) => a..addAll(b),
          );
          received.add(utf8.decode(bytes));
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'received': utf8.decode(bytes)}));
          await request.response.close();
        }
      });
      final base = 'http://127.0.0.1:${server.port}';
      final dart = HttpClient();
      final request = await dart.postUrl(Uri.parse('$base/dart'));
      request.headers.set('Authorization', 'Bearer offline_contract');
      request.headers.contentType = ContentType.text;
      request.write('原始字节・日本語');
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(
        (jsonDecode(await utf8.decoder.bind(response).join())
            as Map)['received'],
        '原始字节・日本語',
      );
      dart.close(force: true);
      final context = SecurityContext()
        ..useCertificateChain(
          'test/fixtures/network_diagnostic/loopback_certificate.pem',
        )
        ..usePrivateKey(
          'test/fixtures/network_diagnostic/loopback_test_only_key.pem',
        );
      final tlsServer = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      final tlsSubscription = tlsServer.listen((r) async {
        r.response.write('TLS loopback bytes');
        await r.response.close();
      });
      final tlsClient = HttpClient()
        ..badCertificateCallback = (_, _, _) => true;
      final tlsRequest = await tlsClient.getUrl(
        Uri.parse('https://127.0.0.1:${tlsServer.port}/tls'),
      );
      final tlsResponse = await tlsRequest.close();
      expect(await utf8.decoder.bind(tlsResponse).join(), 'TLS loopback bytes');
      tlsClient.close(force: true);
      await tlsServer.close(force: true);
      await tlsSubscription.cancel();
      final native = NativeHttpClient();
      final result = await native.post(
        Uri.parse('$base/native'),
        body: 'native bytes',
      );
      expect(result.statusCode, 200);
      native.close();
      final ws = connectSourceSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
        headers: {'Authorization': 'Bearer offline_contract'},
      );
      expect(ws, isA<NativeWebSocketChannel>());
      await ws.ready;
      final echoed = ws.stream.first;
      ws.sink.add('完全な原文');
      final message = await echoed;
      expect(
        message is String ? message : utf8.decode(message as List<int>),
        '完全な原文',
      );
      await ws.sink.close();
      await server.close(force: true);
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final directory = NetworkDiagnostic.directory!;
      final keys = File('${directory.path}/tls_keys.log').readAsLinesSync();
      expect(keys.length, greaterThanOrEqualTo(1));
      expect(
        keys.every(
          (s) => RegExp(r'^[A-Z0-9_]+ [a-fA-F0-9]+ [a-fA-F0-9]+$').hasMatch(s),
        ),
        isTrue,
      );
      final rows = File('${directory.path}/network_raw.jsonl')
          .readAsLinesSync()
          .where((s) => s.isNotEmpty)
          .map((s) => jsonDecode(s) as Map)
          .toList();
      for (final transport in [
        'native',
        'dart_http',
        'native_http',
        'native_ws',
      ]) {
        expect(
          rows.any((r) => r['transport'] == transport),
          isTrue,
          reason: transport,
        );
      }
      expect(received, ['原始字节・日本語', 'native bytes']);
      expect(
        rows.any(
          (r) =>
              r['event'] == 'request_headers' &&
              (r['details'] as Map)['headers']['authorization'][0] ==
                  'Bearer offline_contract',
        ),
        isTrue,
      );
      expect(
        rows.any(
          (r) =>
              r['transport'] == 'native_ws' &&
              r['base64'] == base64Encode(utf8.encode('完全な原文')),
        ),
        isTrue,
      );
      final status =
          jsonDecode(
                File(
                  '${directory.path}/network_raw.jsonl.status.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(status['lost'], 0);
      expect(status['writeErrors'], 0);
      HttpOverrides.global = null;
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
