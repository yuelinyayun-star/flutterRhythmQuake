import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/services/sources/wolfx_jma_detail_decoder.dart';
import 'package:flutterrhythmquake/services/sources/wolfx_jma_detail_decoder_portable.dart'
    as portable;
import 'package:flutterrhythmquake/services/sources/wolfx_jma_detail_feed.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _fixture = 'test/fixtures/wolfx_jma_detail_20261119';
const _eventId = '20261119022225';
const _detailUrl =
    'https://www.data.jma.go.jp/developer/xml/data/20261118173154_0_VXSE62_010000.xml';
final _publication = DateTime.utc(2026, 11, 18, 17, 31, 54);
final _receipt = _publication.add(const Duration(seconds: 10));

final _wolfxBytes = File(
  '$_fixture/jma_earthquake_detail.original.json',
).readAsBytesSync();
final _xmlBytes = File(
  '$_fixture/jma-vxse62-20261119022225.original.xml',
).readAsBytesSync();

List<Map<String, dynamic>> _rows() =>
    (decodeWolfxJmaDetail(_wolfxBytes)['reports'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the original snapshot keeps supported JMA products in their slots', () {
    final decoded = decodeWolfxJmaDetail(_wolfxBytes);
    expect(decoded, portable.decodeWolfxJmaDetail(_wolfxBytes));
    final rows = decoded['reports'] as List;
    expect(
      rows.map((row) => row['report']['product']),
      isNot(contains('VXSE61')),
    );
    expect(
      rows
          .where((row) => row['eventId'] == _eventId)
          .map((row) => row['report']['product']),
      ['VXSE53', 'VXSE62'],
    );
    // The original snapshot contains a VXSE51 filed after the combined report.
    final combined = rows.singleWhere(
      (row) => row['eventId'] == '20261119023642',
    );
    expect(combined['report']['product'], 'VXSE53');
  });

  test('a product withdrawal does not cancel a different active product', () {
    final bytes = utf8.encode('''
{"events":[{"eventId":"jma-product-test","reports":[
  {"id":"ordinary", "product":"VXSE53","status":"issued","time":"2026-11-18T17:26:00Z"},
  {"id":"preliminary", "product":"VXSE51","status":"cancelled","time":"2026-11-18T17:31:00Z"},
  {"id":"observation", "product":"VXSE62","status":"issued","time":"2026-11-18T17:31:00Z"},
  {"id":"withdrawal", "product":"VXSE62","status":"cancelled","time":"2026-11-18T17:31:00Z","issuedAt":"2026-11-18T17:31:54Z"}
]}]}
''');
    final decoded = decodeWolfxJmaDetail(bytes);
    expect(decoded, portable.decodeWolfxJmaDetail(bytes));
    final rows = (decoded['reports'] as List).cast<Map<String, dynamic>>();
    final ordinary = QuakeEventAdapter.convertWolfxJmaDetail(
      rows.first,
      isSnapshot: false,
    )!;
    final withdrawal = QuakeEventAdapter.convertWolfxJmaDetail(
      rows.last,
      isSnapshot: false,
    )!;
    expect(ordinary.source, 'jmaEqlist');
    expect(ordinary.isCanceled, isFalse);
    expect(withdrawal.source, 'jmaLpgm');
    expect(withdrawal.jmaLpgmBulletin?.isCanceled, isTrue);
  });

  test(
    'Wolfx receives one parsed observation from the original HTTP snapshot',
    () async {
      final events = <UnifiedQuakeData>[];
      var requests = 0;
      final client = MockClient((request) async {
        expect(request.url.host, 'api.wolfx.jp');
        expect(request.url.path, '/jma_earthquake_detail.json');
        if (++requests > 1) {
          expect(request.headers['If-None-Match'], '"original"');
          return http.Response('', 304);
        }
        return http.Response.bytes(
          _wolfxBytes,
          200,
          headers: {'etag': '"original"', 'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final feed = WolfxJmaDetailFeed(
        client: client,
        now: () => _receipt,
        onReport: events.add,
      );
      addTearDown(feed.dispose);
      await feed.fetchNow();
      await feed.fetchNow();

      final observation = events.singleWhere((event) => event.isJmaLpgm);
      expect(observation.eventId, _eventId);
      expect(observation.source, 'jmaLpgm');
      expect(observation.isSnapshot, isTrue);
      final bulletin = observation.jmaLpgmBulletin!;
      expect(bulletin.reportTime, DateTime.utc(2026, 11, 18, 17, 31));
      expect(bulletin.publishedAt, _publication);
      expect(bulletin.maxLgInt, 2);
      expect(bulletin.regions, hasLength(4));
      expect(bulletin.stations, hasLength(5));
      expect(bulletin.stations.first.prefecture, '熊本県');
      expect(bulletin.stations.last.prefecture, '宮崎県');
      expect(bulletin.stations.first.svaPerPeriod, hasLength(7));
      expect(bulletin.stations.first.svaPerPeriod.first.value, 17.6);

      final ordinary = events.singleWhere(
        (event) => event.source == 'jmaEqlist' && event.eventId == _eventId,
      );
      expect(ordinary.useShindo, isTrue);
      expect(ordinary.jmaLpgmBulletin, isNull);
      final payload = observation.sourcePayload!;
      expect(
        payload['report'],
        _rows().singleWhere(
          (row) => row['report']['product'] == 'VXSE62',
        )['report'],
      );

      final background = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
        eewClock: () => _receipt,
      );
      final handoff = background.process(observation).event;
      expect(handoff, isNotNull);
      final restored = UnifiedQuakeData.fromMap(handoff!.toMap());
      expect(restored.jmaLpgmBulletin!.publishedAt, _publication);
      expect(restored.jmaLpgmBulletin!.isActive(now: _receipt), isTrue);
      final lateBackground = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
        eewClock: () => _publication.add(const Duration(seconds: 61)),
      );
      expect(lateBackground.process(observation).event, isNull);
    },
  );

  test(
    'JMAXML serves the original bulletin after its body minute elapsed',
    () async {
      var now = _receipt;
      final client = MockClient((request) async {
        if (request.url.toString() == JmaLpgmService.feedUrl) {
          // Mock the feed transport, using the original detail XML unmodified.
          return http.Response.bytes(
            utf8.encode('''
<feed><entry>
  <id>$_detailUrl</id>
  <title>長周期地震動に関する観測情報</title>
  <updated>2026-11-18T17:31:54Z</updated>
  <link href="$_detailUrl"/>
</entry></feed>
'''),
            200,
          );
        }
        expect(request.url.toString(), _detailUrl);
        return http.Response.bytes(_xmlBytes, 200);
      });
      addTearDown(client.close);
      final service = JmaLpgmService(client: client, now: () => now);
      addTearDown(service.dispose);
      await service.fetchNow();

      final bulletin = service.latest!;
      expect(bulletin.eventId, _eventId);
      expect(bulletin.reportTime, DateTime.utc(2026, 11, 18, 17, 31));
      expect(bulletin.publishedAt, _publication);
      expect(bulletin.maxLgInt, 2);
      expect(bulletin.stations, hasLength(5));
      final transported = JmaLpgmBulletin.fromMap(bulletin.toMap());
      expect(transported.signature, bulletin.signature);
      now = _publication.add(const Duration(seconds: 61));
      await service.fetchNow();
      expect(service.latest, isNull);
    },
  );

  test(
    'native owner associates the two reports and expires only VXSE62',
    () {
      final rows = _rows().where((row) => row['eventId'] == _eventId);
      final reports = rows.map(
        (row) =>
            QuakeEventAdapter.convertWolfxJmaDetail(row, isSnapshot: true)!,
      );
      var now = _receipt;
      withClock(Clock(() => now), () {
        late Map<String, dynamic> batch;
        final owner = NativeUnifiedEventOwner(
          manualClock: true,
          onBatch: (value, _) => batch = value,
        );
        try {
          for (final event in reports) {
            owner.admit(event, {
              'nowUs': now.microsecondsSinceEpoch,
              'nowIso': now.toIso8601String(),
              'sourceNowUs': now.microsecondsSinceEpoch,
              'eewNowUs': now.microsecondsSinceEpoch,
              'localOffsetMinutes': 0,
              'showStale': false,
              'historyLoaded': true,
              'historyKeepForever': true,
            });
          }
          expect(batch['active'], hasLength(2));
          expect(batch['jmaLpgmDisplay']['active'], hasLength(1));
          expect(batch['jmaLpgmDisplay']['links'], hasLength(1));
          now = _publication.add(const Duration(seconds: 61));
          owner.send({'op': 'tick'});
          expect(batch['active'], hasLength(1));
          expect(batch['jmaLpgmDisplay']['links'], isEmpty);
        } finally {
          owner.dispose();
        }
      });
    },
    skip: !NativeUnifiedEventOwner.supported,
  );
}
