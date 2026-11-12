import 'dart:typed_data';
import 'native_hyp_score_result.dart';
import 'native_hyp_search_result.dart';

class NativeHypScorer {
  NativeHypScorer({
    required List<double> coordinates,
    required Int64List stationInfo,
    required Float64List observedSeconds,
    required int inactiveCount,
  }) {
    throw UnsupportedError('Native HYP scorer requires Windows');
  }
  static bool get supported => false;
  static int get calls => 0;
  static int get sessions => 0;
  static int get searches => 0;
  static Map<String, int> get distanceReuse => const {'calls': 0, 'hits': 0};
  NativeHypSearchResult search(
    double latitude,
    double longitude,
    double depth, {
    bool finalJoint = false,
    int finalJointMinCount = 15,
    double finalJointMaxScore = 5.0,
  }) => throw UnsupportedError('Native HYP search unavailable');
  NativeHypScoreResult evaluate(
    double latitude,
    double longitude,
    double depth,
  ) => throw UnsupportedError('Native HYP scorer unavailable');
  void dispose() {}
}
