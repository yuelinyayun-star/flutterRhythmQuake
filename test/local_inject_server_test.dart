import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_server.dart';
import 'package:flutterrhythmquake/services/sources/mock_input_service.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = MockInputService();
  setUpAll(() => SourceManager().registerSource(source));
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await LocalInjectServer.stop();
    debugDefaultTargetPlatformOverride = null;
  });

  test('disabled by default; port and opt-in survive restart', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(LocalInjectServer.shouldStart(prefs), isFalse);
    final port = await freePort();
    await LocalInjectServer.setEnabled(true, port: port);
    expect(LocalInjectServer.boundPort, port);
    expect(prefs.getInt(LocalInjectServer.portPreferenceKey), port);
    expect(prefs.getBool(LocalInjectServer.enabledPreferenceKey), isTrue);
    await LocalInjectServer.stop();
    await LocalInjectServer.startIfEnabled(prefs: prefs);
    expect(LocalInjectServer.boundPort, port);
    await LocalInjectServer.setEnabled(false);
    expect(LocalInjectServer.isRunning, isFalse);
    expect(prefs.getBool(LocalInjectServer.enabledPreferenceKey), isFalse);
  });

  test(
    'failed bind cannot claim enabled or overwrite a working port',
    () async {
      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(occupied.close);
      await expectLater(
        LocalInjectServer.setEnabled(true, port: occupied.port),
        throwsA(isA<SocketException>()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(LocalInjectServer.isUserEnabled(prefs), isFalse);
      final port = await freePort();
      await LocalInjectServer.setEnabled(true, port: port);
      await expectLater(
        LocalInjectServer.setPort(occupied.port),
        throwsA(isA<SocketException>()),
      );
      expect(LocalInjectServer.boundPort, port);
      expect(LocalInjectServer.configuredPort(prefs), port);
      expect(LocalInjectServer.lastError, isNotNull);
      final next = await freePort();
      await LocalInjectServer.setPort(next);
      expect(LocalInjectServer.boundPort, next);
      expect(LocalInjectServer.lastError, isNull);
    },
  );

  test(
    'HTTP identity, unchanged real report and cross-site protection',
    () async {
      await LocalInjectServer.start(port: await freePort());
      final client = _LoopbackHttpOverrides().createHttpClient(null);
      addTearDown(() => client.close(force: true));
      final base = 'http://127.0.0.1:${LocalInjectServer.boundPort}';
      final health = await (await client.getUrl(
        Uri.parse('$base/health'),
      )).close();
      final identity = jsonDecode(await utf8.decoder.bind(health).join());
      expect(identity['service'], 'RhythmQuake.LocalInject');
      final raw =
          (jsonDecode(
                    File(
                      'test/fixtures/jma_voice/p2p_history_20260921.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .first;
      final event = source.onUnifiedEvent.first;
      final request = await client.postUrl(
        Uri.parse('$base/inject?format=p2p'),
      );
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(raw)));
      final response = await request.close();
      expect(response.statusCode, 200);
      final result = jsonDecode(await utf8.decoder.bind(response).join());
      expect(result['injected'], 1);
      expect((await event).sourcePayload, raw);
      final crossSite = await client.postUrl(Uri.parse('$base/inject'));
      crossSite.headers.set('Origin', 'https://example.com');
      crossSite.add(utf8.encode(jsonEncode(raw)));
      final rejected = await crossSite.close();
      expect(rejected.statusCode, 403);
      await rejected.drain<void>();
    },
  );

  test('invalid ports are rejected without changing saved settings', () async {
    for (final port in [0, -1, 65536]) {
      await expectLater(LocalInjectServer.setPort(port), throwsFormatException);
    }
    expect(LocalInjectServer.isRunning, isFalse);
  });
}
