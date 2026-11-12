import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_seedlink_signal_io.dart';
import 'package:flutterrhythmquake/services/sources/seedlink_signal_analysis.dart';

import 'support/seedlink_signal_analysis_before_20261015.dart' as frozen;

int bits(double value) => (ByteData(8)..setFloat64(0, value)).getInt64(0);

void main() {
  final enabled = NativeSeedLinkSignal.supported;
  final input = File(
    'tmp/fdsn_connection_review/costa_rica_QUEP_mmi_input.json',
  );
  test(
    'untouched connection records retain exact Dart signal results and release owners',
    () {
      final original = input.readAsBytesSync();
      final rows =
          (jsonDecode(utf8.decode(original)) as Map)['records'] as List;
      final old = <String, frozen.SeedLinkSignalAnalysis>{};
      final current = <String, SeedLinkSignalAnalysis>{};
      addTearDown(() {
        for (final signal in current.values) {
          signal.dispose();
        }
      });
      var compared = 0, ratios = 0, events = 0;
      for (final row in rows.cast<Map>()) {
        final id = row['id'] as String;
        final samples = (row['samples'] as List).cast<int>();
        final preserved = List<int>.of(samples);
        final rate = (row['sampleRate'] as num).toDouble();
        final time = DateTime.parse(row['start'] as String);
        final previous = old.putIfAbsent(id, frozen.SeedLinkSignalAnalysis.new);
        final next = current.putIfAbsent(id, SeedLinkSignalAnalysis.new);
        final expected = previous.accept(samples, rate, time);
        final result = next.accept(samples, rate, time);
        expect(result.event, expected.event, reason: 'record $compared $id');
        if (expected.ratio case final ratio?) {
          expect(result.ratio, isNotNull);
          expect(
            bits(result.ratio!),
            bits(ratio),
            reason: 'ratio bits $compared $id',
          );
          ratios++;
        } else {
          expect(result.ratio, isNull);
        }
        expect(identical(next.accept(samples, rate, time), result), isTrue);
        expect(samples, preserved);
        if (result.event) events++;
        compared++;
      }
      expect(compared, greaterThan(100));
      expect(ratios, greaterThan(100));
      for (final signal in current.values) {
        signal.dispose();
        signal.dispose();
      }
      expect(NativeSeedLinkSignal.diagnostics['sessions'], 0);
      expect(NativeSeedLinkSignal.diagnostics['scratchBytes'], 0);
      expect(input.readAsBytesSync(), original);
      stdout.writeln(
        jsonEncode({
          'sha256': sha256.convert(original).toString(),
          'records': compared,
          'ratios': ratios,
          'events': events,
          'native': NativeSeedLinkSignal.diagnostics,
        }),
      );
    },
    skip: !enabled || !input.existsSync(),
  );

  test(
    'raw-record gaps reset and late frames cannot roll back native state',
    () {
      final rows =
          ((jsonDecode(input.readAsStringSync()) as Map)['records'] as List)
              .where((row) => row['id'] == 'TC.QUEP..EHZ')
              .cast<Map>()
              .toList();
      final old = frozen.SeedLinkSignalAnalysis();
      final next = SeedLinkSignalAnalysis();
      addTearDown(next.dispose);
      for (final index in [...List.generate(30, (i) => i), 40, 10, 41, 42]) {
        final row = rows[index];
        final samples = (row['samples'] as List).cast<int>();
        final rate = (row['sampleRate'] as num).toDouble();
        final time = DateTime.parse(row['start'] as String);
        expect(
          next.accept(samples, rate, time),
          old.accept(samples, rate, time),
        );
      }
      next.dispose();
      expect(() => next.accept([1], 100, DateTime.utc(2026)), throwsStateError);
    },
    skip: !enabled || !input.existsSync(),
  );
}
