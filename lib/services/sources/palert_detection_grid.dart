import 'package:latlong2/latlong.dart';

import 'shake_detection_service.dart';

/// Fixed Taiwan display grid. The same geometry is used for both sources,
/// including old recorded/hosted frames and native prepared frames.
LatLng taiwanDetectionGridCenter(LatLng point) => LatLng(
  point.latitude.floorToDouble() + 0.5,
  point.longitude.floorToDouble() + 0.5,
);

List<LatLng> taiwanDetectionGridVertices(LatLng point) {
  final center = taiwanDetectionGridCenter(point);
  const half = 0.495;
  return [
    LatLng(center.latitude - half, center.longitude - half),
    LatLng(center.latitude + half, center.longitude - half),
    LatLng(center.latitude + half, center.longitude + half),
    LatLng(center.latitude - half, center.longitude + half),
  ];
}

List<PAlertDetectionGridCell> alignTaiwanDetectionCells(
  Iterable<PAlertDetectionGridCell> cells,
) {
  final unique = <String, PAlertDetectionGridCell>{};
  for (final cell in cells) {
    if (!cell.center.latitude.isFinite || !cell.center.longitude.isFinite)
      continue;
    final center = taiwanDetectionGridCenter(cell.center);
    final key = '${center.latitude},${center.longitude}';
    if ((unique[key]?.level ?? -1) < cell.level) {
      unique[key] = PAlertDetectionGridCell(center: center, level: cell.level);
    }
  }
  return unique.values.toList()..sort((a, b) {
    final lat = a.center.latitude.compareTo(b.center.latitude);
    return lat != 0 ? lat : a.center.longitude.compareTo(b.center.longitude);
  });
}

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
    _cells = List.unmodifiable(alignTaiwanDetectionCells(cells));
  }

  void clear() => _cells = const [];
}
