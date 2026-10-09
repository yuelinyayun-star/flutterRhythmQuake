import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/cenc_ir_binding.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/services/sources/nowquake_cenc_intensity_service.dart';

void main() {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/cenc_ir_mojiang_20260914170727.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final data = CencIrData.fromNowQuakeJson(raw);
  final summary = NowQuakeCencIntensityService.summaryFromJson(raw);
  final event = QuakeMessage(
    source: QuakeSourceType.cenc,
    eventId: raw['eq_id'],
    location: raw['hypocenter'],
    magnitude: (raw['magnitude'] as num).toDouble(),
    latitude: (raw['latitude'] as num).toDouble(),
    longitude: 101.61,
    depth: (raw['depth'] as num).toDouble(),
    originTime: DateTime.parse(raw['happen_time']),
    timeZone: 8,
  );

  test('captured CENC catalogue binds the corresponding NowQuake report', () {
    expect(CencIrBinding.find(event, [summary]), summary);
    expect(CencIrBinding.matchesData(event, data), isTrue);
  });
  test(
    'different API IDs still bind using original origin and coordinates',
    () {
      expect(
        CencIrBinding.find(event.copyWith(eventId: 'another-api-id'), [
          summary,
        ]),
        summary,
      );
    },
  );
  test('same name alone cannot bind a report from a different earthquake', () {
    expect(
      CencIrBinding.find(
        event.copyWith(
          originTime: event.originTime.add(const Duration(minutes: 1)),
        ),
        [summary],
      ),
      isNull,
    );
    expect(
      CencIrBinding.find(event.copyWith(latitude: event.latitude + 1), [
        summary,
      ]),
      isNull,
    );
  });
  test('the CENC report is never bound to a USGS list entry', () {
    final map = event.toMap()..['source'] = QuakeSourceType.usgs.toString();
    expect(CencIrBinding.find(QuakeMessage.fromMap(map), [summary]), isNull);
  });
  test('explicit timezone in report retains the same absolute origin', () {
    expect(
      CencIrBinding.matchesSummary(event, {
        ...summary,
        'oriTime': data.oriTime.toIso8601String(),
      }),
      isTrue,
    );
  });
}
