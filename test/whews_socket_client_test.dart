import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';

void main() {
  test('empty API token never opens a socket', () {
    final states = <WhewsSocketState>[];
    final client = WhewsSocketClient(
      url: 'not-a-socket-url',
      apiToken: ' ',
      onMessage: (_) => fail('Anonymous connection must not receive data'),
      onStateChanged: states.add,
    );
    addTearDown(client.dispose);
    client.start();
    expect(client.isRunning, isFalse);
    expect(states, [WhewsSocketState.unauthorized]);
  });

  test(
    'rejected token stops retries; replacement connects; clear disconnects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final queries = <String?>[];
      final rejected = Completer<void>();
      final connected = Completer<void>();
      final subscription = server.listen((request) async {
        queries.add(request.uri.queryParameters['token']);
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          final data = jsonDecode(frame as String) as Map;
          if (request.uri.queryParameters['token'] == 'replacement') {
            socket.add(jsonEncode({'type': 'pong'}));
          } else if (data.containsKey('token')) {
            expect(data['token'], 'rejected');
            socket.close(4401);
          }
        });
        if (request.uri.queryParameters['token'] == 'rejected') {
          await socket.close(4401);
        }
      });
      final client = WhewsSocketClient(
        url: 'ws://127.0.0.1:${server.port}/business',
        apiToken: 'rejected',
        onMessage: (_) {},
        onStateChanged: (state) {
          if (state == WhewsSocketState.unauthorized && !rejected.isCompleted) {
            rejected.complete();
          }
          if (state == WhewsSocketState.connected && !connected.isCompleted) {
            connected.complete();
          }
        },
      );
      addTearDown(() async {
        client.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await subscription.cancel();
        await server.close(force: true);
      });
      client.start();
      await rejected.future.timeout(const Duration(seconds: 5));
      expect(client.authorizationRejected, isTrue);
      client.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(queries, ['rejected', null]);
      client.setApiToken('replacement');
      await connected.future.timeout(const Duration(seconds: 5));
      expect(queries.last, 'replacement');
      client.setApiToken('');
      expect(client.isRunning, isFalse);
      expect(client.aliveConfirmed, isFalse);
      expect(queries, hasLength(3));
    },
  );

  test('buildConnectionUri appends the API token as a query parameter', () {
    final uri = WhewsSocketClient.buildConnectionUri(
      'wss://api.beecld.com/ws/all',
      'wat_test_token',
    );

    expect(uri.scheme, 'wss');
    expect(uri.host, 'api.beecld.com');
    expect(uri.path, '/ws/all');
    expect(uri.queryParameters['token'], 'wat_test_token');
  });

  test('buildConnectionUri preserves existing query parameters', () {
    final uri = WhewsSocketClient.buildConnectionUri(
      'wss://api.2v8.cn/ws/cea_all?lang=zh',
      'wat_domestic',
    );

    expect(uri.queryParameters['lang'], 'zh');
    expect(uri.queryParameters['token'], 'wat_domestic');
  });
}
