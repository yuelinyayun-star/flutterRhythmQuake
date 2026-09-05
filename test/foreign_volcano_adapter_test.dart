import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

void main() {
  group('Foreign Volcano Eruption Title Adaptation', () {
    test('P2PQuake foreign volcano eruption translates title and intensity badge', () {
      final p2pPayload = {
        "code": 551,
        "issue": {
          "source": "気象庁",
          "time": "2026/09/05 03:00:00",
          "type": "Foreign"
        },
        "earthquake": {
          "time": "2026/09/05 02:50:00",
          "hypocenter": {
            "name": "スンダ海峡",
            "latitude": -6.1,
            "longitude": 105.4,
            "depth": -1,
            "magnitude": -1
          },
          "maxScale": -1
        },
        "comments": {
          "freeFormComment":
              "令和８年９月５日０２時５０分頃（日本時間）にクラカタウ火山で大規模な噴火が発生しました（ダーウィン航空路火山灰情報センター（ＶＡＡＣ）による）。\n日本への津波の影響はありません。"
        }
      };

      final unified = QuakeEventAdapter.convert(
        'jmaEqlist',
        p2pPayload,
        2,
      );

      expect(unified, isNotNull);
      expect(unified!.titleText, equals('遠地噴火に関する情報'));
      expect(unified.hypocenter, equals('スンダ海峡'));

      final presentation = UnifiedEventPresentation.fromEvent(unified);
      expect(presentation.title, equals('遠地噴火に関する情報'));
      expect(presentation.intensityLabel, equals('噴火'));
      expect(presentation.intensityValue, equals('噴火'));
    });

    test('P2PQuake normal foreign earthquake remains 遠地地震に関する情報', () {
      final p2pPayload = {
        "code": 551,
        "issue": {
          "source": "気象庁",
          "time": "2026/09/05 03:00:00",
          "type": "Foreign"
        },
        "earthquake": {
          "time": "2026/09/05 02:50:00",
          "hypocenter": {
            "name": "南太平洋",
            "latitude": -18.2,
            "longitude": -175.1,
            "depth": 30,
            "magnitude": 6.5
          },
          "maxScale": -1
        },
        "comments": {
          "freeFormComment": "太平洋で地震が発生しました。"
        }
      };

      final unified = QuakeEventAdapter.convert(
        'jmaEqlist',
        p2pPayload,
        2,
      );

      expect(unified, isNotNull);
      expect(unified!.titleText, equals('遠地地震に関する情報'));
    });

    test('Wolfx JMA volcano eruption translates title', () {
      final wolfxPayload = {
        "Title": "遠地地震情報",
        "shindo": "不明",
        "location": "クラカタウ火山",
        "Comments": "大規模な噴火が発生しました",
        "time": "2026/09/05 02:50:00",
        "latitude": "-6.1",
        "longitude": "105.4",
        "depth": "-1",
        "magnitude": "-1"
      };

      final unified = QuakeEventAdapter.convert(
        'jmaEqlist',
        wolfxPayload,
        0,
      );

      expect(unified, isNotNull);
      expect(unified!.titleText, equals('遠地噴火に関する情報'));
    });
  });
}
