import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/http_response_bytes.dart';

void main() {
  test('discarding error bodies reuses the HTTP connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final remotePorts = <int>{};
    server.listen((request) async {
      remotePorts.add(request.connectionInfo!.remotePort);
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('not found');
      await request.response.close();
    });
    final client = HttpClient()..idleTimeout = const Duration(minutes: 1);
    try {
      final url = Uri.parse('http://127.0.0.1:${server.port}/missing');
      for (var i = 0; i < 12; i++) {
        final request = await client.getUrl(url);
        final response = await request.close();
        expect(response.statusCode, HttpStatus.notFound);
        await readHttpResponseBytes(
          response,
          timeout: const Duration(seconds: 1),
          discard: true,
        );
      }
      expect(remotePorts.length, lessThanOrEqualTo(2));
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });

  test('body timeout releases the connection slot', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    server.listen((request) async {
      requestCount++;
      if (requestCount == 1) {
        request.response.write('unfinished');
        await request.response.flush();
        return;
      }
      request.response.write('ok');
      await request.response.close();
    });
    final client = HttpClient()..maxConnectionsPerHost = 1;
    try {
      final url = Uri.parse('http://127.0.0.1:${server.port}/frame');
      final firstRequest = await client.getUrl(url);
      final firstResponse = await firstRequest.close();
      await expectLater(
        readHttpResponseBytes(
          firstResponse,
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );

      final nextRequest = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 2));
      final nextResponse = await nextRequest.close();
      final body = await readHttpResponseBytes(
        nextResponse,
        timeout: const Duration(seconds: 1),
      );
      expect(body, 'ok'.codeUnits);
      expect(requestCount, 2);
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
}
