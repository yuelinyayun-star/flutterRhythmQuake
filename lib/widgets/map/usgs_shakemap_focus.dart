import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import '../../models/usgs_shakemap.dart';
import '../../providers/map_state_provider.dart';
import 'cenc_ir_focus.dart';

EdgeInsets usgsProductViewportPadding(BuildContext context) =>
    (cencIrViewportPadding(context) ?? const EdgeInsets.all(50)).copyWith(
      bottom: 155,
    );

void focusUsgsShakeMap({
  required BuildContext context,
  required MapStateProvider mapState,
  required UsgsShakeMapFrame frame,
}) {
  final epicenter = LatLng(frame.event.latitude, frame.event.longitude);
  // Fit the actual displayed lines; the product grid can include large empty
  // margins and its geographic midpoint need not coincide with the epicenter.
  final points = shakeMapFocusPoints(frame);
  mapState.smartMoveToPoints(
    points,
    minZoom: 2,
    maxZoom: 10,
    viewportPadding: usgsProductViewportPadding(context),
    focusAnchor: epicenter,
    sourceTag: 'policy-shakemap-${frame.product.identity}',
    minInterval: Duration.zero,
  );
}

List<LatLng> shakeMapFocusPoints(UsgsShakeMapFrame frame) => <LatLng>[
  LatLng(frame.event.latitude, frame.event.longitude),
  for (final contour in frame.contours)
    for (final line in contour.lines) ...line,
  if (frame.contours.isEmpty) ...[
    LatLng(frame.product.south, frame.product.west),
    LatLng(frame.product.north, frame.product.east),
  ],
];
