import 'package:latlong2/latlong.dart';

import 'shake_detection_service.dart';

class PAlertDetectionGridCell {
  final LatLng center;
  final int level;

  const PAlertDetectionGridCell({required this.center, required this.level});

  factory PAlertDetectionGridCell.fromDetection(NiedDetectionGridCell cell) =>
      PAlertDetectionGridCell(center: cell.center, level: cell.level);
}

/// A display snapshot only. Detection and grid alignment belong to the engine.
class PAlertDetectionGrid {
  List<PAlertDetectionGridCell> _cells = const [];

  List<PAlertDetectionGridCell> get cells => _cells;
  List<LatLng> get centers => _cells.map((cell) => cell.center).toList();
  String get signature => _cells
      .map(
        (cell) =>
            '${cell.center.latitude},${cell.center.longitude}:${cell.level}',
      )
      .join('|');

  void update(Iterable<PAlertDetectionGridCell> cells) {
    final ordered = cells.toList()
      ..sort((a, b) {
        final lat = a.center.latitude.compareTo(b.center.latitude);
        return lat != 0
            ? lat
            : a.center.longitude.compareTo(b.center.longitude);
      });
    _cells = List.unmodifiable(ordered);
  }

  void clear() => _cells = const [];
}
