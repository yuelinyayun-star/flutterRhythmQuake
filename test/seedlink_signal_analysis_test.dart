import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterrhythmquake/core/seedlink_activity.dart';
import 'package:flutterrhythmquake/core/seedlink_station_style.dart';
import 'package:flutterrhythmquake/services/sources/seedlink_signal_analysis.dart';

void main() {
  test('original GQ color lookup and thresholds', () {
    expect(SeedLinkStationStyle.colors.length, 80);
    for (final (ratio, color) in <(double, int)>[
      (1, 0xFF0008D2),
      (10, 0xFF008BB1),
      (100, 0xFF30DA59),
      (1000, 0xFF90FF00),
      (2000, 0xFFD1FF00),
      (5000, 0xFFFFCE00),
      (10000, 0xFFFF6500),
      (20000, 0xFFFB0000),
      (50000, 0xFF680000),
    ]) {
      expect(SeedLinkStationStyle.ratioColor(ratio), color);
    }
    expect(SeedLinkStationStyle.ratioColor(null), 0xFFC0C0C0);
    expect(SeedLinkStationStyle.eventColor(1999), 0xFF00FF00);
    expect(SeedLinkStationStyle.eventColor(2000), 0xFFFFFF00);
    expect(SeedLinkStationStyle.eventColor(20000), 0xFFFF0000);
    expect(SeedLinkActivity.fromJson({'ratio': double.nan})!.ratio, isNull);
  });

  final input = File(
    'tmp/fdsn_connection_review/costa_rica_QUEP_mmi_input.json',
  );
  final oracle = File('tmp/gq_reference/ratios.json');
  test(
    'untouched TC.QUEP records match upstream Java BetterAnalysis',
    () {
      final records =
          (jsonDecode(input.readAsStringSync()) as Map)['records'] as List;
      final expected = jsonDecode(oracle.readAsStringSync()) as List;
      final streams = <String, SeedLinkSignalAnalysis>{};
      var checked = 0, events = 0;
      var maximumError = 0.0;
      for (var i = 0; i < records.length; i++) {
        final row = records[i] as Map;
        final samples = (row['samples'] as List).cast<int>();
        final original = List<int>.of(samples);
        final detector = streams.putIfAbsent(
          row['id'] as String,
          SeedLinkSignalAnalysis.new,
        );
        final result = detector.accept(
          samples,
          (row['sampleRate'] as num).toDouble(),
          DateTime.parse(row['start'] as String),
        );
        expect(
          samples,
          orderedEquals(original),
          reason: 'raw samples must be unchanged',
        );
        expect(row['offset'], expected[i]['offset']);
        final value = expected[i]['ratio'] as num?;
        if (value == null) {
          expect(result.ratio, isNull, reason: 'initialization record $i');
        } else {
          expect(result.ratio, isNotNull, reason: 'record $i');
          final error = (result.ratio! - value).abs();
          if (error > maximumError) maximumError = error;
          expect(
            result.ratio,
            closeTo(value.toDouble(), value.abs() * 1e-9 + 1e-9),
            reason: 'record $i ${row['id']}',
          );
          checked++;
        }
        expect(
          result.event,
          expected[i]['event'],
          reason: 'event at record $i',
        );
        if (result.event) events++;
        expect(
          detector.accept(
            samples,
            (row['sampleRate'] as num).toDouble(),
            DateTime.parse(row['start'] as String),
          ),
          result,
          reason: 'duplicate record must not reset the baseline',
        );
      }
      debugPrint(
        'GQ oracle: $checked ready records, $events event records, max error $maximumError',
      );
      expect(checked, greaterThan(100));
    },
    skip: !input.existsSync() || !oracle.existsSync()
        ? 'Run tools/SeedLinkGqOracle.java against the original TC.QUEP audit input.'
        : false,
  );

  test('constant input and unsupported rate never invent a ratio', () {
    final detector = SeedLinkSignalAnalysis();
    final origin = DateTime.utc(2026);
    for (var i = 0; i < 30; i++) {
      final result = detector.accept(
        List.filled(100, 0),
        100,
        origin.add(Duration(seconds: i)),
      );
      expect(result.ratio, isNull);
      expect(result.event, isFalse);
    }
    expect(
      detector
          .accept([1, 2, 3], 10, origin.add(const Duration(minutes: 2)))
          .ratio,
      isNull,
    );
  });

  test(
    'original-record gap reinitializes, shared designs keep state isolated',
    () {
      final rows =
          ((jsonDecode(input.readAsStringSync()) as Map)['records'] as List)
              .where((r) => r['id'] == 'TC.QUEP..EHZ')
              .cast<Map>()
              .toList();
      SeedLinkActivity feed(SeedLinkSignalAnalysis detector, Map row) =>
          detector.accept(
            (row['samples'] as List).cast<int>(),
            (row['sampleRate'] as num).toDouble(),
            DateTime.parse(row['start'] as String),
          );
      final a = SeedLinkSignalAnalysis(), b = SeedLinkSignalAnalysis();
      final expected = [for (final row in rows) feed(a, row)];
      for (var i = 0; i < rows.length; i++) {
        expect(
          feed(b, rows[i]),
          expected[i],
          reason: 'state contamination at $i',
        );
      }
      final gapped = SeedLinkSignalAnalysis();
      for (final row in rows.take(30)) {
        feed(gapped, row);
      }
      expect(gapped.snapshot.ratio, isNotNull);
      final afterGap = feed(gapped, rows[40]);
      expect(afterGap.ratio, isNull);
      expect(afterGap.event, isFalse);
      expect(
        feed(gapped, rows[10]),
        afterGap,
        reason: 'old records cannot roll back time',
      );
    },
    skip: !input.existsSync()
        ? 'Original TC.QUEP audit input required.'
        : false,
  );
}
