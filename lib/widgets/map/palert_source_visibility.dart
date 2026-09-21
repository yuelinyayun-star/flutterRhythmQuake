import '../../core/source_estimation/source_estimation_models.dart';
import '../../models/unified_quake_data.dart';
import '../../core/utils/quake_time.dart';

bool shouldShowPAlertSource(
  SourceEstimate estimate,
  Iterable<UnifiedQuakeData> events, {
  required bool hideOnMatchingEew,
}) {
  if (!hideOnMatchingEew) return true;
  final origin = estimate.originTime;
  final depth = estimate.depthKm;
  if (origin == null || depth == null) return true;
  return !events.any((event) {
    if (event.source != 'cwaEew' ||
        !event.isEew ||
        event.isCanceled ||
        event.isAssumption ||
        event.originTime == null ||
        event.lat == null ||
        event.lng == null ||
        event.depth < 0 ||
        !event.depth.isFinite ||
        !event.lat!.isFinite ||
        !event.lng!.isFinite) {
      return false;
    }
    final longitudeDelta = ((estimate.longitude - event.lng! + 180) % 360 - 180)
        .abs();
    return (estimate.latitude - event.lat!).abs() <= 1.0 &&
        longitudeDelta <= 1.0 &&
        (depth - event.depth).abs() <= 100 &&
        origin
                .difference(QuakeTime.unifiedInstantUtc(event))
                .inMilliseconds
                .abs() <=
            10000;
  });
}
