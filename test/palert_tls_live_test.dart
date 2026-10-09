import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutterrhythmquake/services/sources/palert_http_client.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';

class _LiveHttpOverrides extends HttpOverrides {}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.inner, this.directory);
  final http.Client inner;
  final Directory directory;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final index = ++requests;
    final response = await inner.send(request);
    final bytes = await response.stream.toBytes();
    // Preserve the original upstream bytes before the service parses them.
    await File(
      '${directory.path}/$index.response.raw',
    ).writeAsBytes(bytes, flush: true);
    await File('${directory.path}/$index.response.json').writeAsString(
      jsonEncode({'status': response.statusCode, 'headers': response.headers}),
      encoding: utf8,
    );
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      contentLength: bytes.length,
    );
  }

  @override
  void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('PALERT_TLS_LIVE');

  test(
    'Production service receives advancing frames through its TLS factory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'palert_tls_live_',
      );
      debugPrint('Original live responses: ${directory.path}');
      final service = PAlertService.forTesting(
        clientFactory: () async => _RecordingClient(
          await HttpOverrides.runWithHttpOverrides(
            createPAlertHttpClient,
            _LiveHttpOverrides(),
          ),
          directory,
        ),
      );
      addTearDown(service.stop);
      final frames = <DateTime>[];
      final ready = Completer<void>();
      void onFrame() {
        final time = service.dataTimeNotifier.value;
        if (time == null) return;
        frames.add(time);
        if (frames.length >= 3 && !ready.isCompleted) ready.complete();
      }

      service.dataTimeNotifier.addListener(onFrame);
      addTearDown(() => service.dataTimeNotifier.removeListener(onFrame));
      service.start();
      await ready.future.timeout(const Duration(seconds: 50));
      service.stop(clear: false);
      expect(service.stations, isNotEmpty);
      expect(service.stations.any((station) => station.hasRealtime), isTrue);
      for (var i = 1; i < frames.length; i++) {
        expect(frames[i].isAfter(frames[i - 1]), isTrue);
      }
      debugPrint('Stations=${service.stations.length}; accepted frames=$frames');
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'Supplemented TLS client still rejects an incorrect certificate hostname',
    () async {
      final client = await HttpOverrides.runWithHttpOverrides(
        createPAlertHttpClient,
        _LiveHttpOverrides(),
      );
      addTearDown(client.close);
      final addresses = await InternetAddress.lookup(
        'palert.earth.sinica.edu.tw',
      );
      final ipv4 = addresses.firstWhere(
        (address) => address.type == InternetAddressType.IPv4,
      );
      try {
        await client
            .get(Uri.https(ipv4.address, '/graphql/'))
            .timeout(const Duration(seconds: 12));
        fail(
          'TLS accepted an IP hostname absent from the official certificate',
        );
      } catch (error) {
        expect(
          error.toString(),
          anyOf(
            contains('CERTIFICATE_VERIFY_FAILED'),
            contains('HandshakeException'),
          ),
        );
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
