import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';

// Synthetic unit-test input, not a real earthquake bulletin.
const event = UnifiedQuakeData(
  source: 'jmaEew',
  origin: 0,
  eventId: 'voice-unit-test',
  isEew: true,
  timeZone: 9,
  titleText: '緊急地震速報',
  reportNumText: '第3報',
  useShindo: true,
  maxIntensity: '5+',
  className: 'orange',
  hypocenter: 'カムチャツカ半島付近',
  magnitude: 6.2,
  depth: 30,
  depthText: '深さ: 30km',
  isWarn: true,
  warnArea: '北海道、青森県、岩手県、宮城県、秋田県、山形県、福島県',
);

String speak(UnifiedQuakeData data, {String phase = 'first'}) =>
    AlertVoiceHelper.generateUnifiedEventText(data, phase: phase);

void main() {
  test('EEW puts critical information first and omits long detail reading', () {
    final text = speak(event);
    expect(text, '紧急地震警报，堪察加半岛附近，震级6.2，预计最大震度5强，深度30公里。日本气象厅，第3报。');
    expect(text, isNot(contains(event.warnArea)));
    expect(text, isNot(contains('。，')));
  });

  test('every unified transport uses the same Japanese voice mapping', () {
    for (final origin in [0, 1, 2, 3, 4]) {
      expect(speak(event.copyWith(origin: origin)), speak(event));
    }
  });

  test('speech leaves original fields and source payload untouched', () {
    final data = event.copyWith(
      sourcePayload: {
        'hypocenter': event.hypocenter,
        'warnArea': event.warnArea,
      },
    );
    final before = data.toMap();
    speak(data);
    expect(data.toMap(), before);
    expect(data.hypocenter, 'カムチャツカ半島付近');
    expect(data.maxIntensity, '5+');
  });

  test('JMA information also maps names and retains review status', () {
    final text = speak(
      event.copyWith(
        source: 'jmaEqlist',
        isEew: false,
        reportNumText: '第2報（修正）',
        titleText: '震度速報',
      ),
    );
    expect(text, startsWith('震度速报，堪察加半岛附近，震级6.2，最大震度5强'));
    expect(text, endsWith('日本气象厅，修正。'));
    expect(text, isNot(contains('第2报')));
  });

  test('non-JMA locations are not translated using Japanese names', () {
    expect(speak(event.copyWith(source: 'cwaEew')), contains(event.hypocenter));
  });

  test('all legacy JMA alert transports use the same dictionary', () {
    for (final source in [
      QuakeSourceType.wolfx,
      QuakeSourceType.p2p,
      QuakeSourceType.jma_fan,
    ]) {
      final data = QuakeMessage(
        source: source,
        eventId: 'voice-unit-test',
        location: event.hypocenter,
        magnitude: 6.2,
        latitude: 50,
        longitude: 160,
        depth: 30,
        originTime: DateTime.utc(2026, 1, 1),
        reportNumber: 3,
        jmaShindo: '5+',
      );
      final text = AlertVoiceHelper.generateLegacyAlertText(data, 12, 3);
      expect(text, contains('堪察加半岛附近，震级6.2，最大震度5强'));
      expect(text, endsWith('预计12秒后到达，第3报。'));
      expect(data.location, event.hypocenter);
    }
  });

  test('JMA intensity symbols are spoken as weak and strong', () {
    for (final entry in {
      '5-': '5弱',
      '5+': '5强',
      '6-': '6弱',
      '6+': '6强',
      '6強': '6强',
      '0': '0',
    }.entries) {
      expect(
        speak(event.copyWith(maxIntensity: entry.key)),
        contains('预计最大震度${entry.value}'),
      );
    }
  });

  test('Roman intensity labels are spoken as numbers', () {
    for (final entry in {'Ⅳ': '4', 'VII': '7', 'Ⅻ': '12'}.entries) {
      expect(
        speak(
          event.copyWith(
            source: 'ceaEew',
            useShindo: false,
            maxIntensity: entry.key,
          ),
        ),
        contains('预计最大烈度${entry.value}'),
      );
    }
  });

  test('cancellation takes precedence over earthquake parameters', () {
    expect(speak(event.copyWith(isCanceled: true)), '日本气象厅，紧急地震速报已取消。');
    expect(
      speak(
        event.copyWith(source: 'jmaEqlist', isEew: false, isCanceled: true),
      ),
      '日本气象厅，地震信息已取消。',
    );
  });

  test('final announcement occurs once, retaining the report number', () {
    expect(speak(event.copyWith(isFinal: true)), endsWith('第3报，最终报。'));
    final text = speak(event.copyWith(isFinal: true, reportNumText: '最终报'));
    expect('最终报'.allMatches(text), hasLength(1));
  });

  test('title-only review status survives compact information wording', () {
    for (final status in ['正式测定', '自动测定', '已核实', '待核实']) {
      final text = speak(
        event.copyWith(
          source: 'kmaEqlist',
          isEew: false,
          reportNumText: '',
          titleText: '기상청 지진정보$status',
        ),
      );
      expect(text, endsWith('韩国气象厅，$status。'));
      expect(text, isNot(contains('기상청')));
    }
  });

  test('updates and special information keep their semantic type', () {
    expect(
      speak(
        event.copyWith(source: 'nowQuakeCencIr', isEew: false),
        phase: 'update',
      ),
      startsWith('烈度速报更新，'),
    );
    expect(
      speak(event.copyWith(isEew: false, isJmaLpgm: true)),
      startsWith('长周期地震动情报，'),
    );
    expect(
      speak(event.copyWith(isEew: false, titleText: 'CENC 地震矩心矩张量解')),
      startsWith('震源机制解，'),
    );
  });

  test('missing parameters do not become fabricated numbers', () {
    final text = speak(
      event.copyWith(
        hypocenter: '',
        magnitude: -1,
        depth: -1,
        maxIntensity: '--',
      ),
    );
    expect(text, '紧急地震警报，震源待定。日本气象厅，第3报。');
  });
}
