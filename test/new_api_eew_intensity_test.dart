import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';

String badgeValue(UnifiedQuakeData event) {
  final estimate = estimatedNewApiEewBadgeIntensity(event);
  return estimate == null
      ? UnifiedEventPresentation.fromEvent(event).intensityValue
      : estimate == 0
      ? '0'
      : unifiedRomanIntensityLabel('$estimate');
}

// Synthetic protocol boundary cases, not observations or rewritten captures.
Map<String, dynamic> protocolCase({
  double magnitude = 4.7,
  double depth = 10,
  Object? intensity,
}) => {
  'id': 'protocol-boundary-case',
  'updates': 1,
  'shockTime': '2000-01-01 00:00:00',
  'magnitude': magnitude,
  'depth': depth,
  'latitude': 30.0,
  'longitude': 100.0,
  'placeName': 'Protocol boundary case',
  'epiIntensity': ?intensity,
};

Map<String, dynamic> jianProtocolCase({
  double magnitude = 4.7,
  double depth = 10,
  Object? intensity,
}) => {
  'id': 'protocol-boundary-case',
  'number': 1,
  'originTime': 946684800000,
  'magnitude': magnitude,
  'depth': depth,
  'latitude': 30.0,
  'longitude': 100.0,
  'placeName': 'Protocol boundary case',
  'intensity': ?intensity,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final jian =
      jsonDecode(
            File(
              'test/fixtures/jian/all.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map;
  final whews =
      jsonDecode(
            File(
              'test/fixtures/catalog_20260917/whews_all.json',
            ).readAsStringSync(encoding: utf8),
          )
          as List;

  test(
    'unchanged WHEWS captures retain reported values including KMA maxMMI',
    () {
      for (final frame in whews.whereType<Map>()) {
        final type = frame['source'] as String;
        if (!const {'sa_eew', 'kma_eew', 'jma_eew', 'cwa_eew'}.contains(type)) {
          continue;
        }
        final raw = Map<String, dynamic>.from(frame['Data'] as Map);
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertWhews(type, raw)!;
        final beforeEvent = jsonEncode(event.toMap());
        expect(estimatedNewApiEewBadgeIntensity(event), isNull, reason: type);
        if (type == 'kma_eew') {
          expect(
            QuakeEventAdapter.parseReportedIntensity(event.maxIntensity),
            6,
          );
          expect(badgeValue(event), 'VI');
        } else if (type == 'sa_eew') {
          expect(event.maxIntensity, '4.7');
          expect(badgeValue(event), 'V');
          final fan = FanService.decodeEventPayload(raw, sourceHint: 'sa')!;
          expect(
            badgeValue(event),
            UnifiedEventPresentation.fromEvent(fan).intensityValue,
          );
          expect(event.className, fan.className);
        } else {
          expect(event.useShindo, isTrue);
          expect(badgeValue(event), '3');
        }
        expect(event.sourcePayload, raw);
        expect(jsonEncode(raw), before);
        expect(jsonEncode(event.toMap()), beforeEvent);
      }
    },
  );

  test(
    'unchanged Jian EEW captures estimate only missing non-shindo badges',
    () {
      for (final type in [
        'cea',
        'cea-pr',
        'sa',
        'kma-eew',
        'jma-eew',
        'cwa-eew',
      ]) {
        final raw = Map<String, dynamic>.from(
          (jian['source：$type'] as Map)['Data'] as Map,
        );
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertJian(type, raw)!;
        final beforeEvent = jsonEncode(event.toMap());
        final estimate = estimatedNewApiEewBadgeIntensity(event);
        if (const {'cea', 'cea-pr', 'sa'}.contains(type)) {
          expect(
            estimate,
            IntensityCalculator.calcCsisLevel(event.magnitude, event.depth, 0),
          );
          expect(event.maxIntensity, '-');
        } else {
          expect(estimate, isNull);
        }
        expect(event.sourcePayload, raw);
        expect(jsonEncode(raw), before);
        expect(jsonEncode(event.toMap()), beforeEvent);
      }
    },
  );

  for (final intensity in [
    1.49,
    1.5,
    4.49,
    4.5,
    6.449,
    6.49,
    6.499999,
    6.5,
    9.49,
    9.5,
    11.49,
    11.5,
  ]) {
    test(
      'reported $intensity rounds once like FAN, not via one decimal place',
      () {
        for (final (jianType, whewsType, fanType) in const [
          ('cea', 'cea', 'cea'),
          ('cea-pr', 'cea_pr', 'cea_pr'),
          ('sa', 'sa_eew', 'sa'),
          ('kma-eew', 'kma_eew', 'kma_eew'),
        ]) {
          final fan = FanService.decodeEventPayload(
            protocolCase(intensity: intensity),
            sourceHint: fanType,
          )!;
          final expected = UnifiedEventPresentation.fromEvent(
            fan,
          ).intensityValue;
          for (final event in [
            QuakeEventAdapter.convertJian(
              jianType,
              jianProtocolCase(intensity: intensity),
            )!,
            QuakeEventAdapter.convertWhews(
              whewsType,
              protocolCase(intensity: intensity),
            )!,
          ]) {
            expect(
              QuakeEventAdapter.parseReportedIntensity(event.maxIntensity),
              intensity,
            );
            expect(estimatedNewApiEewBadgeIntensity(event), isNull);
            expect(badgeValue(event), expected, reason: '$jianType/$whewsType');
            expect(event.className, fan.className);
          }
        }
      },
    );
  }

  for (final (magnitude, depth) in [
    (3.1, 21.0),
    (4.7, 5.0),
    (5.3, 80.0),
    (6.4, 180.0),
    (8.0, 10.0),
  ]) {
    test(
      'missing intensity at M$magnitude depth $depth reuses the FAN estimate',
      () {
        for (final (jianType, whewsType, fanType) in const [
          ('cea', 'cea', 'cea'),
          ('cea-pr', 'cea_pr', 'cea_pr'),
          ('sa', 'sa_eew', 'sa'),
          ('kma-eew', 'kma_eew', 'kma_eew'),
        ]) {
          final fan = FanService.decodeEventPayload(
            protocolCase(magnitude: magnitude, depth: depth),
            sourceHint: fanType,
          )!;
          final expected = QuakeEventAdapter.parseReportedIntensity(
            fan.maxIntensity,
          )!.toInt();
          for (final event in [
            QuakeEventAdapter.convertJian(
              jianType,
              jianProtocolCase(magnitude: magnitude, depth: depth),
            )!,
            QuakeEventAdapter.convertWhews(
              whewsType,
              protocolCase(magnitude: magnitude, depth: depth),
            )!,
          ]) {
            final before = jsonEncode(event.toMap());
            final notification = UnifiedEventPresentation.fromEvent(
              event,
            ).notificationBody;
            expect(event.maxIntensity, '-');
            expect(estimatedNewApiEewBadgeIntensity(event), expected);
            expect(
              badgeValue(event),
              UnifiedEventPresentation.fromEvent(fan).intensityValue,
            );
            expect(jsonEncode(event.toMap()), before);
            expect(
              UnifiedEventPresentation.fromEvent(event).notificationBody,
              notification,
            );
          }
        }
      },
    );
  }

  for (final type in ['cea', 'cea_pr', 'sa_eew', 'kma_eew']) {
    test(
      'WHEWS $type tries valid aliases instead of trusting a placeholder',
      () {
        final raw = {
          ...protocolCase(),
          'maxIntensity': '-',
          'epiIntensity': 'NaN',
          'maxMMI': 6,
        };
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertWhews(type, raw)!;
        expect(QuakeEventAdapter.parseReportedIntensity(event.maxIntensity), 6);
        expect(badgeValue(event), 'VI');
        expect(estimatedNewApiEewBadgeIntensity(event), isNull);
        expect(jsonEncode(raw), before);
      },
    );

    test('WHEWS $type never estimates cancelled or invalid-parameter events', () {
      for (final extra in [
        {'cancel': true},
        {'isCancel': true},
        {'isTraining': true},
        {'magnitude': -1},
        {'magnitude': 'NaN'},
        {'depth': -1},
        {'depth': null},
      ]) {
        final event = QuakeEventAdapter.convertWhews(type, {
          ...protocolCase(),
          ...extra,
        })!;
        expect(
          estimatedNewApiEewBadgeIntensity(event),
          isNull,
          reason: '$extra',
        );
      }
      final valid = QuakeEventAdapter.convertWhews(type, protocolCase())!;
      // Test the badge guard directly; non-finite depth formatting is separate.
      for (final depth in [double.infinity, double.nan]) {
        expect(
          estimatedNewApiEewBadgeIntensity(valid.copyWith(depth: depth)),
          isNull,
        );
      }
    });
  }

  test(
    'KMA unknown labels cannot override a valid number; zero is not missing',
    () {
      for (final label in ['-', '不明', 'NaN', 'Ⅳ']) {
        final event = QuakeEventAdapter.convertWhews('kma_eew', {
          ...protocolCase(),
          'maxMmi': 6,
          'maxMmiLabel': label,
        })!;
        expect(QuakeEventAdapter.parseReportedIntensity(event.maxIntensity), 6);
        expect(badgeValue(event), 'VI');
      }
      for (final type in ['cea', 'cea_pr', 'sa_eew', 'kma_eew']) {
        final event = QuakeEventAdapter.convertWhews(
          type,
          protocolCase(intensity: 0),
        )!;
        expect(QuakeEventAdapter.parseReportedIntensity(event.maxIntensity), 0);
        expect(estimatedNewApiEewBadgeIntensity(event), isNull);
      }
    },
  );

  test(
    'Jian invalid intensity does not mask maxMMI and unknowns remain estimable',
    () {
      for (final type in ['cea', 'cea-pr', 'sa', 'kma-eew']) {
        final event = QuakeEventAdapter.convertJian(type, {
          ...jianProtocolCase(intensity: '-'),
          'maxMMI': 6,
        })!;
        expect(QuakeEventAdapter.parseReportedIntensity(event.maxIntensity), 6);
        expect(estimatedNewApiEewBadgeIntensity(event), isNull);
        final missing = QuakeEventAdapter.convertJian(
          type,
          jianProtocolCase(intensity: 'NaN'),
        )!;
        expect(missing.maxIntensity, '-');
        expect(estimatedNewApiEewBadgeIntensity(missing), isNotNull);
      }
    },
  );

  test('FAN, Wolfx, GQ and ICL retain their existing badge paths', () {
    final event = QuakeEventAdapter.convertJian('cea', jianProtocolCase())!;
    for (final label in [
      'FAN',
      'Wolfx',
      'GlobalQuake',
      'Jian_ICL',
      'China_EEW_ICL',
    ]) {
      expect(
        estimatedNewApiEewBadgeIntensity(event.copyWith(apiTypeLabel: label)),
        isNull,
      );
    }
  });
}
