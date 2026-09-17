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
      expect(text, startsWith('地震信息，测试地点，震级3.0'));
      expect(text, endsWith('${entry.value}。'));
      expect(text, isNot(contains(entry.key)));
    }
  });

  test('CMT source labels remain unchanged for now', () {
    final text = AlertVoiceHelper.generateUnifiedEventText(
      eventFor('cencCmt'),
      phase: 'first',
    );
    expect(text, endsWith('cencCmt。'));
  });

  test('WHEWS generic sources use their Chinese institution names', () {
    const expected = {
      'whews_bmkg': '印度尼西亚气象气候与地球物理局',
      'whews_geonet': '新西兰地球科学局',
      'whews_tmd': '泰国气象局',
      'whews_ingv': '意大利国家地球物理与火山学研究所',
      'whews_nrcan': '加拿大自然资源部',
      'whews_mmd': '马来西亚气象局',
      'whews_phivolcs': '菲律宾火山与地震研究所',
      'whews_sgc': '哥伦比亚地质局',
      'whews_ga': '澳大利亚地质局',
      'whews_cenais': '古巴国家地震研究中心',
    };

    for (final entry in expected.entries) {
      final text = AlertVoiceHelper.generateUnifiedEventText(
        eventFor(entry.key),
        phase: 'first',
      );
      expect(text, startsWith('地震信息，测试地点，震级3.0'));
      expect(text, endsWith('${entry.value}。'));
      expect(text, isNot(contains(entry.key)));
    }
  });

  test(
    'non-P2P information voice reads review status without report serial',
    () {
      final jma = eventFor(
        'jmaEqlist',
      ).copyWith(origin: 3, reportNumText: '修正');
      final legacy = eventFor(
        'jmaEqlist',
      ).copyWith(origin: 3, reportNumText: '第2報（修正）');
      final cenc = eventFor('cencEqlist').copyWith(reportNumText: '正式测定');

      final jmaText = AlertVoiceHelper.generateUnifiedEventText(
        jma,
        phase: 'first',
      );
      final legacyText = AlertVoiceHelper.generateUnifiedEventText(
        legacy,
        phase: 'first',
      );
      final cencText = AlertVoiceHelper.generateUnifiedEventText(
        cenc,
        phase: 'first',
      );

      expect(jmaText, contains('修正'));
      expect(jmaText, isNot(contains('第2报')));
      expect(legacyText, contains('修正'));
      expect(legacyText, isNot(contains('第2报')));
      expect(cencText, contains('正式测定'));
    },
  );

  test('CENC voice reports the quake before naming its source only once', () {
    final event = eventFor('cencEqlist').copyWith(titleText: '中国地震台网地震信息');
    final text = AlertVoiceHelper.generateUnifiedEventText(
      event,
      phase: 'first',
    );
    expect(text, startsWith('地震信息，测试地点，震级3.0'));
    expect('中国地震台网'.allMatches(text), hasLength(1));
    expect(text, isNot(contains('发布地震信息')));
  });

  test('JMA information voice never reads report serial for any origin', () {
    final p2p = eventFor('jmaEqlist').copyWith(origin: 2, reportNumText: '第2報');
    final whews = eventFor(
      'jmaEqlist',
    ).copyWith(origin: 3, reportNumText: '第1報');
    final p2pText = AlertVoiceHelper.generateUnifiedEventText(
      p2p,
      phase: 'first',
    );
    final whewsText = AlertVoiceHelper.generateUnifiedEventText(
      whews,
      phase: 'first',
    );

    expect(p2pText, isNot(contains('第2报')));
    expect(p2pText, isNot(contains('第2報')));
    expect(whewsText, isNot(contains('第1报')));
    expect(whewsText, isNot(contains('第1報')));
  });

  test('KMA information title is localized for Chinese voice', () {
    final event = eventFor('kmaEqlist').copyWith(titleText: '기상청 지진정보正式测定');
    final text = AlertVoiceHelper.generateUnifiedEventText(
      event,
      phase: 'first',
    );

    expect(text, startsWith('地震信息，测试地点，震级3.0'));
    expect(text, contains('韩国气象厅'));
    expect(text, isNot(contains('기상청 지진정보')));
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
    expect(text, startsWith('地震速报，测试地点，震级4.0'));
    expect(text, endsWith('第2报。'));
    expect(text, isNot(contains('发布')));
    expect(text, isNot(contains('更新')));
  });

  test('EEW voice includes depth without rounding away reported decimals', () {
    final event = eventFor(
      'jmaEew',
    ).copyWith(isEew: true, depth: 14.9, depthText: '深度 14.9 km');
    final text = AlertVoiceHelper.generateUnifiedEventText(
      event,
      phase: 'first',
    );

    expect(text, contains('深度14.9公里'));
    expect(text, isNot(contains('14.9 km')));
    expect(text, isNot(contains('深度15公里')));
  });

  test('EEW voice localizes CWA name and Japanese UI depth text', () {
    final event = eventFor(
      'cwaEew',
    ).copyWith(isEew: true, reportNumText: '第2报', depthText: '深さ: 40km');

    final text = AlertVoiceHelper.generateUnifiedEventText(
      event,
      phase: 'first',
    );

    expect(text, startsWith('地震预警，测试地点，震级3.0'));
    expect(text, endsWith('中央气象署，第2报。'));
    expect(text, contains('深度10公里'));
    expect(text, isNot(contains('台湾中央气象署')));
    expect(text, isNot(contains('深さ')));
    expect(text, isNot(contains('40km')));
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
    expect(warnText, startsWith('紧急地震警报，测试地点'));
    expect(warnText, endsWith('第3报。'));
    expect(warnText, isNot(contains('发布')));
    expect(warnText, isNot(contains('更新')));
    expect(warnText, isNot(contains('警报警报')));

    final caution = warning.copyWith(isWarn: false);
    final cautionText = AlertVoiceHelper.generateUnifiedEventText(
      caution,
      phase: 'caution',
    );
    expect(cautionText, startsWith('紧急地震速报，测试地点'));
    expect(cautionText, endsWith('第3报。'));
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
    expect(jmaText, startsWith('紧急地震速报，测试地点'));
    expect(jmaText, endsWith('第1报。'));
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
      expect(text, startsWith('地震预警，测试地点'));
      expect(text, endsWith('第2报。'));
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

  test('unadapted sources speak the API name instead of CENC or FAN', () {
    final event = UnifiedQuakeData(
      source: 'unadapted_geonet',
      origin: 1,
      eventId: 'voice-unadapted',
      isEew: false,
      timeZone: 8,
      titleText: '新西兰地球科学局地震信息',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '35 km south-west of Tokoroa',
      magnitude: 1.5,
      depth: 192,
      apiTypeLabel: 'FAN',
    );
    final text = AlertVoiceHelper.generateUnifiedEventText(
      event,
      phase: 'first',
    );
    expect(text, startsWith('地震信息，35 km south-west of Tokoroa'));
    expect(text, endsWith('geonet。'));
    expect(text, isNot(contains('中国地震台网')));
    expect(text, isNot(contains('unadapted_geonet')));
  });
}
