import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/sources/noaa_tsunami_area_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('NMEFC parser prefers alarmDate code and handles dismissal level', () {
    final message = TsunamiMessage.parseNmefcTsunami({
      'id': 'frame-id',
      'code': '202512272305',
      'warningInfo': {'title': '海啸信息', 'level': '解除', 'subtitle': '中国台湾省周边海域'},
      'timeInfo': {
        'alarmDate': '2025-12-28 02:25:45',
        'updateDate': '2025-12-28 01:53:10',
      },
      'shockInfo': {
        'shockTime': '2025-12-27 23:05',
        'latitude': 24.67,
        'longitude': 122.06,
        'depth': 60,
        'magnitude': 6.6,
        'placeName': '中国台湾省周边海域',
      },
      'details': {'batch': '3'},
      'forecasts': [],
      'waterLevelMonitoring': [],
    });

    expect(message.source, TsunamiSource.nmefc);
    expect(message.id, '202512272305');
    expect(message.reportTime, '2025-12-28 02:25:45');
    expect(message.titleText, '中国台湾省周边海域');
    expect(message.isActive, isFalse);
    expect(message.title, '海啸信息');
  });

  test('PTWC NTWC and INCOIS international frames map warning levels', () {
    final ptwc = TsunamiMessage.parseInternationalTsunami(TsunamiSource.ptwc, {
      'id': 'PHEB-1-26224050',
      'eventId': '26224050',
      'updates': 1,
      'agency': 'PTWC',
      'level': 'Warning',
      'headline': 'Tsunami Warning',
      'description': 'A tsunami may have been generated.',
      'shockTime': '2026-08-10 20:34:28',
      'issueTime': '2026-08-10 20:58:30',
      'magnitude': 7.1,
      'depth': 120,
      'latitude': 5.0,
      'longitude': -76.3,
      'placeName': 'in Colombia',
      'bulletinUrl': 'https://www.tsunami.gov/example',
      'maps': {
        'energyMapUrl': 'https://example/energy.jpg',
        'travelTimeMapUrl': 'https://example/travel.jpg',
      },
    });
    expect(ptwc.source, TsunamiSource.ptwc);
    expect(ptwc.grade, TsunamiGrade.warning);
    expect(ptwc.isActive, isTrue);
    expect(ptwc.reportTime, '2026-08-10 20:58:30');
    expect(ptwc.epicenterLat, 5.0);
    expect(ptwc.earthquakeMapUrl, 'https://example/energy.jpg');

    final ntwc = TsunamiMessage.parseInternationalTsunami(TsunamiSource.ntwc, {
      'id': 'PAAQ-1-tjk09g',
      'level': 'Advisory',
      'headline': 'Tsunami Advisory',
      'issueTime': '2026-08-10 20:58:30',
      'latitude': 5.0,
      'longitude': -76.3,
    });
    expect(ntwc.source, TsunamiSource.ntwc);
    expect(ntwc.grade, TsunamiGrade.watch);

    final incois =
        TsunamiMessage.parseInternationalTsunami(TsunamiSource.incois, {
          'id': 'incois2026ptdz_B1',
          'eventId': 'incois2026ptdz',
          'level': 'Information',
          'headline': 'EARTHQUAKE BULLETIN',
          'issueTime': '2026-08-10 20:46:00',
          'detailUrl': 'https://tsunami.incois.gov.in/example',
        });
    expect(incois.source, TsunamiSource.incois);
    expect(incois.grade, TsunamiGrade.none);
    expect(incois.isActive, isFalse);
    expect(incois.htmlUrl, 'https://tsunami.incois.gov.in/example');
  });

  test('saved WHEWS information frames stay non-warning and expire', () {
    final raw =
        jsonDecode(
              File(
                'test/fixtures/catalog_20260917/whews_all.json',
              ).readAsStringSync(),
            )
            as List<dynamic>;
    for (final frame in raw.whereType<Map<String, dynamic>>()) {
      final source = switch (frame['source']) {
        'ptwc' => TsunamiSource.ptwc,
        'ntwc' => TsunamiSource.ntwc,
        'incois' => TsunamiSource.incois,
        _ => null,
      };
      if (source == null) continue;
      final data = Map<String, dynamic>.from(frame['Data'] as Map);
      final message = TsunamiMessage.parseInternationalTsunami(source, data);
      expect(message.isInformation, isTrue);
      expect(message.isActive, isFalse);
      expect(message.areas, isEmpty);
      final issued = message.reportInstantUtc!;
      expect(message.isDisplayableAt(issued), isTrue);
      expect(
        message.isDisplayableAt(message.informationDisplayUntilUtc!),
        isFalse,
      );
      expect(TsunamiMessage.fromMap(message.toMap()).expires, message.expires);
      expect(
        AlertVoiceHelper.generateTsunamiText(message, isUpdate: false),
        contains('发布海啸信息'),
      );
      expect(
        AlertVoiceHelper.generateTsunamiText(message, isUpdate: false),
        isNot(contains('解除')),
      );
    }
  });

  test('NOAA detail uses actual advisory coastline labels only', () async {
    final bytes = File(
      'test/fixtures/noaa_ntwc_advisory_20250918.json',
    ).readAsBytesSync();
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response.bytes(bytes, 200);
    });
    final service = NoaaTsunamiAreaService(client: client);
    final areas = await service.fetch(
      'http://www.tsunami.gov/events/PAAQ/2025/09/18/t2ssp5/1/WEAK51/PAAQ.json',
    );
    expect(requested?.scheme, 'https');
    expect(areas, hasLength(1));
    expect(areas.single.grade, TsunamiGrade.watch);
    expect(areas.single.name, contains('Amchitka Pass'));
    expect(areas.single.name, contains('Attu'));
    expect(await service.fetch('https://example.com/other.json'), isEmpty);
    client.close();
  });
}
