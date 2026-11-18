import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/sources/jma_megaquake_advisory_service.dart';

void main() {
  test(
    'parses the current Wolfx JMA tsunami snapshot without rewriting it',
    () {
      final raw = <String, dynamic>{
        'status': 'active',
        'validUntil': '2026-11-17T04:31:20.706Z',
        'report': {
          'id': 'wolfx-tsunami-report',
          'product': 'VTSE41',
          'time': '2026-11-17T03:00:00.000Z',
          'title': '津波警報',
          'eventIds': ['20261117030000'],
        },
        'areas': [
          {
            'name': '北海道太平洋沿岸東部',
            'level': 'warning',
            'kind': '津波警報',
            'maxWave': {'height': 1.0, 'text': '１ｍ'},
          },
        ],
        'text': '公式本文',
        'md5': 'unchanged-md5',
      };

      final event = TsunamiMessage.parseWolfxJmaTsunami(raw);

      expect(event.source, TsunamiSource.jma);
      expect(event.id, 'wolfx-tsunami-report');
      expect(event.eventId, '20261117030000');
      expect(event.grade, TsunamiGrade.warning);
      expect(event.areas.single.name, '北海道太平洋沿岸東部');
      expect(event.areas.single.height, 1.0);
      expect(event.titleText, '公式本文');
      expect(event.sourcePayload, equals(raw));
    },
  );

  test(
    'maps the current Wolfx special earthquake snapshot to both families',
    () {
      final service = JmaMegaquakeAdvisoryService(
        now: () => DateTime.utc(2026, 11, 17),
      );
      service.ingestWolfxSnapshot({
        'reports': [
          {
            'id': 'nankai-report',
            'product': 'VYSE52',
            'time': '2026-11-17T03:00:00.000Z',
            'status': 'issued',
            'title': '南海トラフ地震関連解説情報',
            'kind': '南海トラフ地震関連解説情報',
            'code': '200',
            'label': '定例解説',
            'eventIds': ['nankai-event'],
            'text': '南海トラフ本文',
          },
          {
            'id': 'hokkaido-report',
            'product': 'VYSE60',
            'time': '2026-11-17T03:01:00.000Z',
            'status': 'issued',
            'title': '北海道・三陸沖後発地震注意情報',
            'label': '後発地震注意',
            'eventIds': ['hokkaido-event'],
          },
        ],
        'appendices': const [],
      });

      expect(service.active, hasLength(2));
      expect(
        service.active.map((item) => item.telegramCode),
        containsAll(<String>['VYSE52', 'VYSE60']),
      );
      expect(service.active.first.bodyText, anyOf('南海トラフ本文', ''));
      service.dispose();
    },
  );
}
