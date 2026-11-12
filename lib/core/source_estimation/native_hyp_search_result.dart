import 'dart:typed_data';
import 'native_hyp_score_result.dart';

/// Owned numeric output, independent of the native search/scoring session.
class NativeHypSearchResult {
  const NativeHypSearchResult(this.summary, this.score, this.log);
  final Float64List summary;
  final NativeHypScoreResult score;
  final Float64List log;
  static const rowWords = 32;

  List<Map<String, Object?>> get stages {
    const degrees = [3.0, 1.0, 0.3, 0.1];
    const depths = [100.0, 50.0, 20.0, 10.0];
    const reasons = [
      '',
      'non_finite_depth',
      'depth_below_0_km',
      'depth_above_700_km',
      'non_finite_coordinate',
      'latitude_outside_scratch_bounds',
    ];
    const jointOffsets = <(int, int, int)>[
      (-1, -1, -1),
      (-1, -1, 0),
      (-1, -1, 1),
      (-1, 0, -1),
      (-1, 0, 1),
      (-1, 1, -1),
      (-1, 1, 0),
      (-1, 1, 1),
      (0, -1, -1),
      (0, -1, 1),
      (0, 1, -1),
      (0, 1, 1),
      (1, -1, -1),
      (1, -1, 0),
      (1, -1, 1),
      (1, 0, -1),
      (1, 0, 1),
      (1, 1, -1),
      (1, 1, 0),
      (1, 1, 1),
    ];
    String signed(int value) =>
        value >= 0 ? '+' + value.toString() : value.toString();
    String direction(int step, int index) {
      if (index >= 6 && index < 26) {
        final (lat, lng, depth) = jointOffsets[index - 6];
        return 'joint_lat' +
            signed(lat) +
            '_lng' +
            signed(lng) +
            '_depth' +
            signed(depth);
      }
      return switch (index) {
        0 => 'lng+' + degrees[step].toString(),
        1 => 'lat-' + degrees[step].toString(),
        2 => 'lng-' + degrees[step].toString(),
        3 => 'lat+' + degrees[step].toString(),
        4 => 'depth-' + depths[step].toInt().toString(),
        _ => 'depth+' + depths[step].toInt().toString(),
      };
    }

    Map<String, Object?> point(int offset) => {
      'latitude': log[offset],
      'longitude': log[offset + 1],
      'depth_km': log[offset + 2],
      'score': log[offset + 3],
      'weighted_residual_squares': log[offset + 4],
      'weight_sum': log[offset + 5],
      'inactive_penalty': log[offset + 6],
      'inactive_p_radius_km': log[offset + 7],
      'station_scale': log[offset + 8],
      'wave_count_penalty_multiplier': log[offset + 9],
    };
    final result = <Map<String, Object?>>[];
    var moves = <Map<String, Object?>>[];
    for (var offset = 0; offset < log.length; offset += rowWords) {
      final type = log[offset].toInt(), step = log[offset + 1].toInt();
      if (type == 1) {
        moves.add({
          'stage_iteration': log[offset + 2].toInt(),
          'total_iteration': log[offset + 3].toInt(),
          'direction': direction(step, log[offset + 4].toInt()),
          'from': point(offset + 5),
          'to': point(offset + 15),
        });
      } else if (type == 0) {
        result.add({
          'step_index': step,
          'degree_step': degrees[step],
          'depth_step_km': depths[step],
          'move_limit': 1000,
          'termination_reason': log[offset + 11] == 0
              ? 'local_minimum'
              : 'move_limit',
          'iterations': log[offset + 2].toInt(),
          'total_iterations': log[offset + 3].toInt(),
          'evaluated_candidate_count': log[offset + 4].toInt(),
          'rejected_candidate_count': log[offset + 5].toInt(),
          'rejected_reason_counts': {
            for (var i = 1; i < reasons.length; i++)
              if (log[offset + 5 + i] != 0)
                reasons[i]: log[offset + 5 + i].toInt(),
          },
          'moves': moves,
          'best_score': log[offset + 15],
          'best_latitude': log[offset + 12],
          'best_longitude': log[offset + 13],
          'best_depth_km': log[offset + 14],
          'terminal_center': {
            'latitude': log[offset + 12],
            'longitude': log[offset + 13],
            'depth_km': log[offset + 14],
            'score': log[offset + 15],
            'error_level': log[offset + 15],
            'inactive_penalty': log[offset + 18],
          },
          'terminal_candidates': <Map<String, Object?>>[],
        });
        moves = <Map<String, Object?>>[];
      } else {
        (result.last['terminal_candidates'] as List<Map<String, Object?>>).add({
          'direction': direction(step, log[offset + 2].toInt()),
          'latitude': log[offset + 3],
          'longitude': log[offset + 4],
          'depth_km': log[offset + 5],
          if (log[offset + 6] != 0) ...{
            'score': log[offset + 8],
            'error_level': log[offset + 9],
            'inactive_penalty': log[offset + 10],
          },
          'evaluated': log[offset + 6] != 0,
          if (log[offset + 6] == 0)
            'reject_reason': reasons[log[offset + 7].toInt()],
        });
      }
    }
    return result;
  }
}
