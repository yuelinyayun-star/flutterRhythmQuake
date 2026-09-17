import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../../core/calculator.dart';
import '../../models/cenc_ir_data.dart';
import '../ui/ui_scale.dart';

EdgeInsets? cencIrViewportPadding(BuildContext context) {
  if (UiScale.isPhone(context)) return null;
  // Match the desktop list (including its collapse tab), right dashboard and
  // top chrome. Pixel margins also keep station circles clear of the panels.
  return EdgeInsets.fromLTRB(
    UiScale.s(context, 20 + 420 + 26) + 24,
    UiScale.belowTopBar(context, 64),
    UiScale.sc(context, 20) + UiScale.sidePanelWidth(context, 234) + 24,
    32,
  );
}

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
