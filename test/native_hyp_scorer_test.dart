import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_scorer.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_geometry.dart';
import 'support/dart_hyp_score_reference.dart';

Object? exact(Object? v) {
  if (v is double) {
    return (ByteData(8)..setFloat64(0, v)).getUint64(0).toRadixString(16);
  }
  if (v is Map) return {for (final e in v.entries) e.key: exact(e.value)};
  if (v is Iterable) return v.map(exact).toList();
  return v;
}

Map<String, Object?>? normalize(NativeHypScoreResult raw, int count) {
  final selected = raw.values[0].toInt();
  if (selected < 0) return null;
  double at(int slot, int field) => raw.values[3 + slot * 16 + field];
  double value(int field) => at(selected, field);
  String first(int slot) => slot < 3 ? 'P' : 'S';
  String? last(int slot) => slot % 3 == 2
      ? null
      : slot % 3 == 0
      ? 'P'
      : 'S';
  String scenario(int slot) =>
      slot % 3 == 2 ? '${first(slot)}_PREV' : '${first(slot)}${last(slot)}';
  return {
    'fields': [
      for (var i = 1; i <= 12; i++) value(i),
      value(13).toInt().toString(),
      value(14).toInt().toString(),
    ],
    'diagnostics': {
      'reference_scenario': scenario(selected),
      'reference_first_wave': first(selected),
      'reference_last_wave': last(selected),
      'reference_filter_stage_level': value(15).toInt(),
      'reference_p_wave_count': value(11).toInt(),
      'reference_s_wave_count': value(12).toInt(),
      'reference_l_wave_count': value(13).toInt(),
      'reference_o_wave_count': value(14).toInt(),
      'reference_inactive_penalty': value(6),
      'reference_inactive_penalty_weight': value(7),
      'reference_wave_count_penalty_multiplier': value(8),
      'reference_scenario_candidates': [
        for (var slot = 0; slot < 6; slot++)
          if (at(slot, 0) != 0)
            <String, Object?>{
              'first_wave': first(slot),
              'scenario': scenario(slot),
              'score': at(slot, 2),
              'rmse': at(slot, 3),
              'p_wave_count': at(slot, 11).toInt(),
              's_wave_count': at(slot, 12).toInt(),
              'filter_stage_level': at(slot, 15).toInt(),
            },
      ],
    },
    'waves': {
      for (var side = 0; side < 2; side++)
        if (raw.values[1 + side] >= 0)
          side == 0 ? 'P' : 'S': {
            for (var i = 0; i < count; i++)
              if (raw.waves[side * count + i] >= 0)
                '$i': raw.waves[side * count + i] == 1,
          },
    },
  };
}

void main() {
  test(
    'reference P/S scenarios preserve every Float64 bit and insertion order',
    () {
      final baseline = NativeHypScorer.sessions, before = NativeHypScorer.calls;
      final filters = <int>{};
      for (final count in [5, 12, 32, 120, 201]) {
        for (final mode in [0, 1, 2, 3, 4]) {
          // Controlled ABI cases on original catalogue coordinates, not performance data.
          final inactiveCount = mode == 3 ? count + 1 : 0;
          final coordinates = <double>[
            for (final s in NiedStationDb.stations.take(count)) ...[
              (s['lat'] as num).toDouble(),
              (s['lng'] as num).toDouble(),
            ],
            for (var i = 0; i < inactiveCount; i++) ...[35.2, 136.9],
          ];
          final geometry = NativeHypGeometry(
            coordinates.take(count * 2).toList(),
          );
          final values = geometry.evaluate(35.2, 136.9, 10);
          geometry.dispose();
          final info = Int64List(count * 8), observedMs = Int64List(count);
          for (var i = 0; i < count; i++) {
            final s = i % 3 == 0;
            observedMs[i] =
                (values[i * 3 + (s ? 2 : 1)] * 1000).round() + i % 5;
            info.setRange(i * 8, (i + 1) * 8, [
              i % 9,
              mode == 2
                  ? 0
                  : i % 11 == 0
                  ? 1
                  : 4,
              12,
              mode == 1 ? 1 : 0,
              [0, 6, 7, 8, 9, 20][i % 6],
              12,
              mode != 4 && i % 7 == 0
                  ? -1
                  : s
                  ? 1
                  : 0,
              i % 2 == 0 ? 1 : 0,
            ]);
          }
          final scorer = NativeHypScorer(
            coordinates: coordinates,
            stationInfo: info,
            observedSeconds: Float64List.fromList([
              for (final ms in observedMs) ms / 1000.0,
            ]),
            inactiveCount: inactiveCount,
          );
          try {
            NativeHypScoreResult? saved;
            Object? savedValues;
            for (final candidate in [
              (35.2, 136.9, 10.0),
              (35.21, 136.91, 20.0),
              (35.21, 136.91, 60.0),
            ]) {
              final expected = referenceHypScore(
                coordinates,
                info,
                observedMs,
                inactiveCount,
                candidate.$1,
                candidate.$2,
                candidate.$3,
              );
              final actual = scorer.evaluate(
                candidate.$1,
                candidate.$2,
                candidate.$3,
              );
              final normalized = normalize(actual, count);
              expect(
                exact(normalized),
                exact(expected),
                reason: 'count=$count mode=$mode candidate=$candidate',
              );
              if (normalized != null) {
                for (final v
                    in (normalized['diagnostics']
                            as Map)['reference_scenario_candidates']
                        as List) {
                  filters.add((v as Map)['filter_stage_level'] as int);
                }
              }
              saved ??= actual;
              savedValues ??= exact(normalize(actual, count));
            }
            expect(exact(normalize(saved!, count)), savedValues);
          } finally {
            scorer.dispose();
            scorer.dispose();
          }
          expect(() => scorer.evaluate(35.2, 136.9, 10), throwsStateError);
          expect(NativeHypScorer.sessions, baseline);
        }
      }
      expect(filters, containsAll([0, 1, 2, 3]));
      expect(NativeHypScorer.calls - before, 75);
    },
    skip: !NativeHypScorer.supported,
  );
}
