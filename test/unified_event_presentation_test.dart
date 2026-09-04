import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';

void main() {
  test('P2P ScalePrompt notification uses unified UI investigation text', () {
    final event = UnifiedQuakeData(
      source: 'jmaEqlist',
      origin: 2,
      eventId: '2026-07-29 12:34:56',
      isEew: false,
      timeZone: 9,
      titleText: '震度速報',
      reportNumText: '',
      useShindo: true,
      maxIntensity: '3',
      className: 'green',
      hypocenter: '',
      originTime: DateTime(2026, 7, 29, 12, 34, 56),
      magnitude: -1,
      depth: -1,
      depthText: '',
    );

    final presentation = UnifiedEventPresentation.fromEvent(event);

    expect(presentation.title, '震度速報');
    expect(presentation.primaryText, '震源 調査中');
    expect(presentation.secondaryText, '規模 調査中');
    expect(presentation.intensityLabel, '震度');
    expect(presentation.intensityValue, '3');
    expect(presentation.notificationBody, contains('震源 調査中'));
    expect(presentation.notificationBody, contains('規模 調査中'));
    expect(presentation.notificationBody, contains('震度 3'));
    expect(presentation.notificationBody, isNot(contains('M-1.0')));
  });

  test('P2P and WHEWS JMA info titles never append report serial', () {
    final p2p = UnifiedQuakeData(
      source: 'jmaEqlist',
      origin: 2,
      eventId: '2026-08-15 20:30:00',
      isEew: false,
      timeZone: 9,
      titleText: '各地の震度に関する情報',
      reportNumText: '第1報',
      useShindo: true,
      maxIntensity: '1',
      className: 'gray',
      hypocenter: '台湾付近',
      originTime: DateTime(2026, 8, 15, 20, 30),
      magnitude: 4.6,
      depth: 70,
      depthText: '深さ: 70km',
      apiTypeLabel: 'P2PQ',
    );
    final whews = p2p.copyWith(
      origin: 3,
      reportNumText: '第2報（訂正）',
      apiTypeLabel: 'WHEWS',
    );
    final canceled = p2p.copyWith(
      origin: 3,
      reportNumText: '取消',
      apiTypeLabel: 'WHEWS',
    );

    expect(UnifiedEventPresentation.fromEvent(p2p).title, '各地の震度に関する情報');
    expect(UnifiedEventPresentation.fromEvent(whews).title, '各地の震度に関する情報 訂正');
    expect(
      UnifiedEventPresentation.fromEvent(canceled).title,
      '各地の震度に関する情報 取消',
    );
  });

  test('ordinary intensity report keeps the same UI title and fields', () {
    final event = UnifiedQuakeData(
      source: 'cencEqlist',
      origin: 1,
      eventId: 'test',
      isEew: false,
      timeZone: 8,
      titleText: '中国地震台网地震信息',
      reportNumText: '正式测定',
      useShindo: false,
      maxIntensity: '10.0',
      className: 'red',
      hypocenter: '测试地区',
      originTime: DateTime(2026, 7, 29, 12, 34, 56),
      magnitude: 6.1,
      depth: 10,
      depthText: '深度: 10km',
    );

    final presentation = UnifiedEventPresentation.fromEvent(event);

    expect(presentation.title, '中国地震台网地震信息 正式测定');
    expect(presentation.primaryText, '测试地区');
    expect(presentation.secondaryText, 'M6.1  ·  深度: 10km');
    expect(presentation.intensityLabel, '烈度');
    expect(presentation.intensityValue, 'X');
    expect(presentation.notificationBody, contains('烈度 X'));
  });

  test('compact volcano text omits the repeated ashfall time range', () {
    final startTime = DateTime.utc(2026, 8, 8, 15);
    final event = UnifiedQuakeData(
      source: 'whews_va',
      origin: 9,
      eventId: 'VFVO53_20260809000000_101',
      isEew: false,
      timeZone: 9,
      titleText: '日本气象厅火山情报',
      reportNumText: '降灰预报（定时）',
      useShindo: false,
      maxIntensity: '-',
      className: 'yellow',
      hypocenter: '雌阿寒岳',
      apiTypeLabel: 'WHEWS',
      volcanoEvent: VolcanoEventData(
        updates: 1,
        kindCode: 'VFVO53',
        kindName: '降灰预报（定时）',
        infoKind: '降灰予報（定時）',
        infoTypeName: '発表',
        title: '雌阿寒岳 降灰予報（定時）',
        volcanoName: '雌阿寒岳',
        volcanoCode: '101',
        craterName: '',
        headline: '',
        activity: '',
        prevention: '',
        nextAdvisory: '',
        plumeDirection: '',
        observation: '',
        winds: const [],
        publishingOffice: '札幌管区気象台',
        reportTime: startTime,
        targetTime: startTime.add(const Duration(hours: 3)),
        ashfallWindows: [
          VolcanoAshfallWindow(
            label: '予報  ３時間後',
            startTime: startTime,
            endTime: startTime.add(const Duration(hours: 3)),
            items: const [
              VolcanoAshfallItem(
                phenomenon: '降灰',
                phenomenonCode: '70',
                areaNames: ['北海道釧路市', '北海道足寄町'],
                areaCodes: ['01206', '01647'],
                plumeDirection: '',
                polygons: [],
              ),
            ],
          ),
        ],
      ),
    );

    final presentation = UnifiedEventPresentation.fromEvent(event);

    expect(presentation.secondaryText, contains('08/09 00:00-08/09 03:00'));
    expect(presentation.compactSecondaryText, isNot(contains('08/09')));
    expect(presentation.compactSecondaryText, '予報 ３時間後：降灰 北海道釧路市、北海道足寄町');
  });
}
