import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_scorer.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_geometry.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'native_hyp_scorer_test.dart' as score_check;
import 'support/dart_hyp_score_reference.dart';

void main() {
  test(
    'ordered native search matches frozen Dart moves, terminals and phase bits',
    () {
      // Controlled boundary inputs use original catalogue coordinates. These
      // fixtures do not represent raw event data or performance measurements.
      final baseline = NativeHypScorer.sessions;
      final searches = NativeHypScorer.searches;
      var compared = 0;
      for (final count in [5, 32, 120]) {
        for (var mode = 0; mode < 4; mode++) {
          final inactiveCount = mode == 3 ? count + 5 : 0;
          final coordinates = <double>[
            for (final station in NiedStationDb.stations.take(count)) ...[
              (station['lat'] as num).toDouble(),
              (station['lng'] as num).toDouble(),
            ],
            for (var i = 0; i < inactiveCount; i++) ...[35.2, 136.9],
          ];
          final geometry = NativeHypGeometry(
            coordinates.take(count * 2).toList(),
          );
          final arrivals = geometry.evaluate(35.2, 136.9, 10);
          geometry.dispose();
          final info = Int64List(count * 8), observed = Int64List(count);
          for (var i = 0; i < count; i++) {
            final useS = i % 3 == 0;
            observed[i] =
                (arrivals[i * 3 + (useS ? 2 : 1)] * 1000).round() + i % 5;
            info.setRange(i * 8, i * 8 + 8, [
              i % 9,
              mode == 2 ? 0 : 4,
              12,
              mode == 1 ? 1 : 0,
              [0, 6, 7, 8, 9, 20][i % 6],
              12,
              useS ? 1 : 0,
              i % 2 == 0 ? 1 : 0,
            ]);
          }
          final scorer = NativeHypScorer(
            coordinates: coordinates,
            stationInfo: info,
            observedSeconds: Float64List.fromList([
              for (final ms in observed) ms / 1000.0,
            ]),
            inactiveCount: inactiveCount,
          );
          try {
            NativeHypSearchResult? saved;
            Object? savedValue;
            for (final start in [(35.2, 136.9, 10.0), (89.9, 181.0, 700.0)]) {
              final expected = referenceHypSearch(
                coordinates,
                info,
                observed,
                inactiveCount,
                start.$1,
                start.$2,
                start.$3,
              );
              final actual = scorer.search(start.$1, start.$2, start.$3);
              final normalized = {
                'summary': actual.summary.toList(),
                'stages': actual.stages,
                'score': score_check.normalize(actual.score, count),
              };
              expect(
                score_check.exact(normalized),
                score_check.exact(expected),
                reason: 'count=$count mode=$mode start=$start',
              );
              compared++;
              saved ??= actual;
              savedValue ??= score_check.exact({
                'summary': actual.summary,
                'log': actual.log,
                'score': score_check.normalize(actual.score, count),
              });
            }
            expect(
              score_check.exact({
                'summary': saved!.summary,
                'log': saved.log,
                'score': score_check.normalize(saved.score, count),
              }),
              savedValue,
            );
          } finally {
            scorer.dispose();
            scorer.dispose();
          }
          expect(() => scorer.search(35.2, 136.9, 10), throwsStateError);
          expect(NativeHypScorer.sessions, baseline);
        }
      }
      expect(compared, 24);
      expect(NativeHypScorer.searches - searches, 24);
    },
    skip: !NativeHypScorer.supported,
  );
}
