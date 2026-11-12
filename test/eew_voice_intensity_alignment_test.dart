import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/cwa_intensity_prediction.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/core/utils/jian_cea_eew.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final jianFile = File('test/fixtures/jian/all.json');
  final whewsFile = File('test/fixtures/catalog_20260917/whews_all.json');
  final jianText = jianFile.readAsStringSync(encoding: utf8);
  final whewsText = whewsFile.readAsStringSync(encoding: utf8);
  final jian = jsonDecode(jianText) as Map;
  final whews = jsonDecode(whewsText) as List;
  tearDownAll(() {
    expect(jianFile.readAsStringSync(encoding: utf8), jianText);
    expect(whewsFile.readAsStringSync(encoding: utf8), whewsText);
  });

  for (final (type, value, shindo) in [
    ('cea', '6', false),
    ('cea-pr', '4', false),
    ('sa', '5', false),
    ('cwa-eew', '3', true),
    ('jma-eew', '4', true),
    ('kma-eew', '6.0', false),
  ]) {
    test('original Jian $type shares the EEW wording and badge value', () {
      final raw = Map<String, dynamic>.from(
        (jian['source：$type'] as Map)['Data'] as Map,
      );
      final before = jsonEncode(raw);
      final event = QuakeEventAdapter.convertJian(type, raw)!;
      final saved = jsonEncode(event.toMap());
      expect(event.useShindo, shindo);
      expect(unifiedEewIntensityValue(event), value);
      expect(effectiveEewIntensityText(event), value);
      final text = voice(event);
      expect(text, contains('预计最大${shindo ? '震度' : '烈度'}$value'));
      expect(text, isNot(contains('预估最大')));
      expect(text, isNot(contains(shindo ? '最大烈度' : '最大震度')));
      expect(jsonEncode(raw), before);
      expect(jsonEncode(event.toMap()), saved);
    });
  }

  test('original WHEWS EEW and FAN SA keep their reported values', () {
    var count = 0;
    for (final frame in whews.whereType<Map>()) {
      final type = frame['source'];
      if (!const {'sa_eew', 'kma_eew', 'jma_eew', 'cwa_eew'}.contains(type)) {
        continue;
      }
      final raw = Map<String, dynamic>.from(frame['Data'] as Map);
      final before = jsonEncode(raw);
      final event = QuakeEventAdapter.convertWhews(type as String, raw)!;
      final saved = jsonEncode(event.toMap());
      final value = unifiedEewIntensityValue(event);
      expect(
        voice(event),
        contains('预计最大${event.useShindo ? '震度' : '烈度'}$value'),
      );
      if (type == 'sa_eew') {
        final fan = FanService.decodeEventPayload(raw, sourceHint: 'sa')!;
        final savedFan = jsonEncode(fan.toMap());
        expect(voice(fan), contains('预计最大烈度${fan.maxIntensity}'));
        expect(voice(fan), isNot(contains('预估最大')));
        expect(jsonEncode(fan.toMap()), savedFan);
      }
      expect(jsonEncode(raw), before);
      expect(jsonEncode(event.toMap()), saved);
      count++;
    }
    expect(count, 4);
  });

  test(
    'missing CWA intensity uses the existing forecast label, never its rank',
    () {
      for (final api in ['FAN', 'Jian Project', 'WHEWS']) {
        final event = model('cwaEew', api, shindo: true);
        final saved = jsonEncode(event.toMap());
        final badge = cwaEewBadgeIntensity(event)!;
        expect(badge.estimated, isTrue);
        expect(badge.rank, greaterThanOrEqualTo(5));
        final label = CwaIntensityPrediction.labels[badge.rank];
        expect(unifiedEewIntensityValue(event), label);
        expect(unifiedEewIntensityValue(event), isNot('${badge.rank}'));
        final spokenLabel = label.replaceAll('-', '弱').replaceAll('+', '强');
        expect(voice(event), contains('预计最大震度$spokenLabel'));
        expect(voice(event), isNot(contains('最大烈度')));
        expect(jsonEncode(event.toMap()), saved);
      }
    },
  );

  test('all API labels retain reported zero and weak or strong shindo', () {
    for (final api in ['Wolfx', 'FAN', 'Jian Project', 'WHEWS']) {
      for (final (value, reading) in [('0', '0'), ('5-', '5弱'), ('6+', '6强')]) {
        for (final source in ['jmaEew', 'cwaEew']) {
          final event = model(
            source,
            api,
            shindo: true,
          ).copyWith(maxIntensity: value);
          expect(voice(event), contains('预计最大震度$reading'));
        }
      }
      for (final source in [
        'ceaEew',
        'scEew',
        'fjEew',
        'cqEew',
        'kmaEew',
        'sa',
        'iclEew',
      ]) {
        final event = model(source, api).copyWith(maxIntensity: '0');
        expect(voice(event), contains('预计最大烈度0'));
        expect(voice(event), isNot(contains('最大震度')));
      }
    }
  });

  test(
    'unknown, canceled and historical events gain no fabricated intensity',
    () {
      final event = model('ceaEew', 'Jian Project');
      for (final unknown in [
        event.copyWith(magnitude: -1),
        event.copyWith(depth: -1),
        event.copyWith(isHistory: true),
        event.copyWith(source: 'sasmex', apiTypeLabel: 'Rhythm'),
      ]) {
        expect(unifiedEewIntensityValue(unknown), '-');
        expect(voice(unknown), isNot(contains('最大烈度')));
      }
      final canceled = voice(event.copyWith(isCanceled: true));
      expect(canceled, contains('已取消'));
      expect(canceled, isNot(contains('最大烈度')));
      final info = event.copyWith(isEew: false, maxIntensity: '6');
      expect(voice(info), contains('最大烈度6'));
      expect(voice(info), isNot(contains('预计最大')));
    },
  );
}

String voice(UnifiedQuakeData event) =>
    AlertVoiceHelper.generateUnifiedEventText(event, phase: 'first');

// Explicit model-level boundaries, separate from unchanged source captures.
UnifiedQuakeData model(String source, String api, {bool shindo = false}) =>
    UnifiedQuakeData(
      source: source,
      origin: 4,
      eventId: 'voice-contract-boundary',
      isEew: true,
      timeZone: 8,
      titleText: '',
      reportNumText: '第1报',
      useShindo: shindo,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: 'model boundary',
      magnitude: 6.8,
      depth: 10,
      lat: 23.8,
      lng: 121.5,
      apiTypeLabel: api,
      sourcePayload: const {},
    );
