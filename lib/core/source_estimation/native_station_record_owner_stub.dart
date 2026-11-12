import 'source_estimation_models.dart';
import 'station_observation_history.dart';

class NativeStationRecordOwner {
  NativeStationRecordOwner(DateTime startedAt) {
    throw UnsupportedError('Native records unavailable');
  }
  static bool get supported => false;
  static Map<String, int> get diagnostics => const {};
  void update({
    required SeismicActiveEvent event,
    required List<SeismicStationSample> samples,
    required DateTime observedAt,
    required Set<String> members,
    required StationObservationHistory Function()? historyFactory,
    required void Function(
      SeismicStationEventRecord,
      SeismicStationSample,
      bool,
    )
    append,
  }) => throw UnsupportedError('Native records unavailable');
  void dispose() {}
}
