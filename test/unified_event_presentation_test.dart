import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';

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
}
