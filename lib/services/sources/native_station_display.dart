import '../obs_automation_input_service.dart';
import 'package:latlong2/latlong.dart';

class NativeStationGrid {
  const NativeStationGrid(this.center, this.level, this.points);
  final LatLng center;
  final int level;
  final List<LatLng> points;
  static List<NativeStationGrid> read(
    Map<String, dynamic> frame,
  ) => (frame['grids'] as List)
      .map(
        (dynamic row) => NativeStationGrid(
          LatLng(
            (row['center'][0] as num).toDouble(),
            (row['center'][1] as num).toDouble(),
          ),
          row['level'] as int,
          (row['points'] as List)
              .map(
                (dynamic p) =>
                    LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
              )
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}

/// Bind ready-to-display native automation rows; no threshold or source logic.
List<ObsStationInputSample> nativeStationAutomation(
  Map<String, dynamic> frame, {
  DateTime Function(String)? displayTime,
}) => (frame['automation'] as List)
    .map(
      (dynamic row) => ObsStationInputSample(
        stationId: row['id'] as String,
        stationName: row['name'] as String,
        active: true,
        intensityLevel: row['level'] as int,
        intensity: (row['intensity'] as num).toDouble(),
        latitude: (row['coordinate']['lat'] as num).toDouble(),
        longitude: (row['coordinate']['lng'] as num).toDouble(),
        observedAt: (displayTime ?? DateTime.parse)(row['time'] as String),
        strong: row['strong'] as bool,
      ),
    )
    .toList(growable: false);
