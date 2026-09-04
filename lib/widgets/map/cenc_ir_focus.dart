import 'package:latlong2/latlong.dart';

import '../../core/calculator.dart';
import '../../models/cenc_ir_data.dart';

List<LatLng> cencIrFocusPoints({
  required CencIrData data,
  required String eventId,
  required double epicenterLatitude,
  required double epicenterLongitude,
}) {
  final normalizedEventId = eventId.trim();
  if (normalizedEventId.isEmpty ||
      (normalizedEventId != data.reportId.trim() &&
          normalizedEventId != data.uniEventId.trim())) {
    return const [];
  }

  final points = <LatLng>[];
  if (QuakeCalculator.isUsableMapCoordinate(
    epicenterLatitude,
    epicenterLongitude,
  )) {
    points.add(LatLng(epicenterLatitude, epicenterLongitude));
  }
  for (final station in data.instrumentIntensities) {
    if (!station.hasUsableCoordinate) continue;
    points.add(LatLng(station.latitude, station.longitude));
  }
  return points;
}
