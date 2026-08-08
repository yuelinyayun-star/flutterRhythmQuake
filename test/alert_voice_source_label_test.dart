import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';

void main() {
  UnifiedQuakeData eventFor(String source) => UnifiedQuakeData(
    source: source,
    origin: 0,
    eventId: 'voice-label-test',
    isEew: false,
    timeZone: 8,
    titleText: '地震信息',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '-',
    className: 'gray',
    hypocenter: '测试地点',
    magnitude: 3.0,
    depth: 10,
  );

  test('FAN source labels use the documented Chinese names', () {
    const expected = {
      'hko': '香港天文台',
      'bcsf': '法国中央地震研究所',
      'gfz': '德国地学研究中心',
      'usp': '巴西圣保罗大学',
      'ningxia': '宁夏自治区地震局',
      'guangxi': '广西壮族自治区地震局',
      'shanxi': '山西省地震局',
      'beijing': '北京市地震局',
      'yunnan': '云南省地震局',
      'usgsEqlist': '美国地质调查局',
      'sa': '美国ShakeAlert地震预警',
      'emscEqlist': '欧洲地中海地震中心',
      'emsc': '欧洲地中海地震中心',
    };

    for (final entry in expected.entries) {
      final text = AlertVoiceHelper.generateUnifiedEventText(
        eventFor(entry.key),
        phase: 'first',
      );
      expect(text, startsWith('${entry.value}，'));
      expect(text, isNot(contains(entry.key)));
    }
  });

  test('CMT source labels remain unchanged for now', () {
    final text = AlertVoiceHelper.generateUnifiedEventText(
      eventFor('cencCmt'),
      phase: 'first',
    );
    expect(text, startsWith('cencCmt，'));
  });

  test('legacy EEW voice uses the same report number shown by the UI', () {
    final event = QuakeMessage(
      source: QuakeSourceType.wolfx,
      eventId: 'legacy-voice-report-test',
      location: '测试地点',
      magnitude: 4.0,
      latitude: 35,
      longitude: 140,
      depth: 20,
      originTime: DateTime.utc(2026, 8, 5),
      reportNumber: 2,
    );

    final text = AlertVoiceHelper.generateLegacyAlertText(event, 12, 3.0);
    expect(text, contains('地震速报，第2报'));
    expect(text, isNot(contains('发布')));
    expect(text, isNot(contains('更新')));
  });

  test('EEW voice text reuses the UI depth text', () {
    final event = eventFor(
      'jmaEew',
    ).copyWith(isEew: true, depth: 14.9, depthText: '深度 14.9 km');
    final text = AlertVoiceHelper.generateUnifiedEventText(
      event,
      phase: 'first',
    );

    expect(text, contains('深度 14.9 km'));
    expect(text, isNot(contains('深度15公里')));
  });

  test('EEW warning phases use natural voice wording', () {
    final warning = eventFor('jmaEew').copyWith(
      isEew: true,
      isWarn: true,
      depthText: '深度 40 km',
      reportNumText: '第3报',
    );
    final warnText = AlertVoiceHelper.generateUnifiedEventText(
      warning,
      phase: 'warn',
    );
    expect(warnText, contains('紧急地震警报，第3报'));
    expect(warnText, isNot(contains('发布')));
    expect(warnText, isNot(contains('更新')));
    expect(warnText, isNot(contains('警报警报')));

    final caution = warning.copyWith(isWarn: false);
    final cautionText = AlertVoiceHelper.generateUnifiedEventText(
      caution,
      phase: 'caution',
    );
    expect(cautionText, contains('紧急地震速报，第3报'));
    expect(cautionText, isNot(contains('注意信息')));
    expect(cautionText, isNot(contains('发布')));
    expect(cautionText, isNot(contains('更新')));
  });

  test('EEW source families use the requested names', () {
    final jma = eventFor('jmaEew').copyWith(isEew: true, reportNumText: '第1报');
    final jmaText = AlertVoiceHelper.generateUnifiedEventText(
      jma,
      phase: 'first',
    );
    expect(jmaText, contains('紧急地震速报，第1报'));
    expect(jmaText, isNot(contains('发布')));
    expect(jmaText, isNot(contains('更新')));

    for (final source in [
      'cwaEew',
      'ceaEew',
      'scEew',
      'fjEew',
      'cqEew',
      'kmaEew',
    ]) {
      final event = eventFor(
        source,
      ).copyWith(isEew: true, reportNumText: '第2报');
      final text = AlertVoiceHelper.generateUnifiedEventText(
        event,
        phase: 'first',
      );
      expect(text, contains('地震预警，第2报'));
      expect(text, isNot(contains('紧急地震速报')));
      expect(text, isNot(contains('紧急地震警报')));
      expect(text, isNot(contains('发布')));
      expect(text, isNot(contains('更新')));
    }

    final shakeAlert = eventFor(
      'sa',
    ).copyWith(isEew: true, reportNumText: '第4报');
    final shakeAlertText = AlertVoiceHelper.generateUnifiedEventText(
      shakeAlert,
      phase: 'first',
    );
    expect(shakeAlertText, contains('美国ShakeAlert地震预警，第4报'));
    expect(shakeAlertText, isNot(contains('地震预警发布')));
    expect(shakeAlertText, isNot(contains('发布')));
    expect(shakeAlertText, isNot(contains('更新')));
  });
}
