import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/jian_icl_service.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'jian_integration_test.dart' show FakeChannel;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('ICL credential is isolated from preferences and Jian /all', () async {
    final store = JianIclTokenStore();
    await store.write('ja_test');
    expect(await store.hasToken(), isTrue);
    expect(await store.read(), 'ja_test');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    await expectLater(
      store.write('https://example.test/?token=ja_test'),
      throwsFormatException,
    );
    await store.clear();
    expect(await store.hasToken(), isFalse);
  });

  test('KA ICL fields enter the unified EEW model without mutating input', () {
    final raw = <String, dynamic>{
      'eventId': 42,
      'updates': 2,
      'latitude': 32.0,
      'longitude': 117.0,
      'magnitude': 5.1,
      'depth': 10,
      'epicenter': '测试地区',
      'startAt': 1780000000000,
      'updateAt': 1780000004000,
      'epiIntensity': 6,
    };
    final copy = Map<String, dynamic>.from(raw);
    final event = QuakeEventAdapter.convertJianIcl({
      'type': 'update',
      'Data': raw,
    });
    expect(raw, copy);
    expect(event, isNotNull);
    expect(event!.source, 'iclEew');
    expect(event.eventId, '42');
    expect(event.reportNumText, '第2报');
    expect(event.hypocenter, '测试地区');
    expect(event.maxIntensity, '6.0');
    expect(event.sourcePayload, raw);
    expect(
      QuakeTime.unifiedInstantUtc(event).millisecondsSinceEpoch,
      1780000000000,
    );
    final snapshot = QuakeEventAdapter.convertJianIcl({
      'type': 'all',
      'source：icl': {'Data': raw},
    });
    expect(snapshot?.isSnapshot, isTrue);
    final noReportedIntensity = Map<String, dynamic>.from(raw)
      ..remove('epiIntensity');
    final estimated = QuakeEventAdapter.convertJianIcl({
      'type': 'icl',
      'Data': noReportedIntensity,
    });
    expect(
      estimated?.maxIntensity,
      IntensityCalculator.calcCsisLevel(5.1, 10, 0)
          .toDouble()
          .toStringAsFixed(1),
    );
    expect(estimated?.reportNumText, contains('烈度估算'));
  });

  test('incomplete or unrelated ICL frames never become alerts', () {
    expect(QuakeEventAdapter.convertJianIcl({'type': 'pong'}), isNull);
    expect(
      QuakeEventAdapter.convertJianIcl({'type': 'update', 'Data': {}}),
      isNull,
    );
  });

  testWidgets('socket uses stored credential and never exposes server text', (
    tester,
  ) async {
    final store = JianIclTokenStore();
    await store.write('ja_test');
    final channel = FakeChannel();
    final service = JianIclService();
    service.disconnect();
    service.tokenStore = store;
    Uri? requested;
    service.socketFactory = (uri) {
      requested = uri;
      return channel;
    };
    service.connect();
    await tester.pump();
    expect(requested?.host, 'api.sismotide.top');
    expect(requested?.path, '/icl');
    expect(requested?.queryParameters['token'], 'ja_test');
    expect(service.status, SourceStatus.connected);
    channel.frames.add(
      jsonEncode({'type': 'error', 'message': 'ja_hidden_server_detail'}),
    );
    await tester.pump();
    expect(service.status, SourceStatus.error);
    expect(service.lastError, isNot(contains('ja_hidden_server_detail')));
    service.disconnect();
  });
}
