import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/cenc_ir_binding.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/nowquake_cenc_intensity_service.dart';

void main() {
  test(
    'renderer uses Rust binding with original reports and prior binding parity',
    () {
      dynamic read(String name) => jsonDecode(
        File(
          'test/fixtures/event_render_20261104/$name.original.json',
        ).readAsStringSync(encoding: utf8),
      );
      final original = Map<String, dynamic>.from(read('wolfx-cenc'));
      final messages = QuakeEventAdapter.convertWolfxCencEqlist(original);
      final rows = (read('cenc-ir') as List).cast<Map<String, dynamic>>();
      final summaries = rows
          .map(NowQuakeCencIntensityService.summaryFromJson)
          .toList();
      final before = jsonEncode([original, rows, summaries]);
      final owner = NativeUnifiedEventOwner(onBatch: (_, _) {});
      try {
        var matched = 0;
        var rejected = 0;
        for (final message in messages) {
          final source = original.values.whereType<Map>().firstWhere(
            (row) => row['EventID'] == message.eventId,
          );
          final event = QuakeEventAdapter.convert(
            'cencEqlist',
            Map<String, dynamic>.from(source),
            0,
          )!;
          final expected = CencIrBinding.find(message, summaries);
          final index = owner.query(
            'renderCencIrIndex',
            event: event,
            parameters: {'reports': summaries},
          );
          expect(index == null ? null : summaries[index as int], expected);
          if (expected == null) {
            rejected++;
          } else {
            matched++;
          }
          // Unified DTO timestamps carry wall-clock components regardless of
          // DateTime's UTC flag, matching the established QuakeTime contract.
          final time = event.originTime!;
          final utcFlag = event.copyWith(
            originTime: DateTime.utc(
              time.year,
              time.month,
              time.day,
              time.hour,
              time.minute,
              time.second,
            ),
          );
          expect(
            owner.query(
              'renderCencIrIndex',
              event: utcFlag,
              parameters: {'reports': summaries},
            ),
            index,
          );
        }
        expect(matched, greaterThan(0));
        expect(rejected, greaterThan(0));
        expect(jsonEncode([original, rows, summaries]), before);
        expect(owner.retainedViewCount, 0);
      } finally {
        owner.dispose();
      }
    },
  );
}
