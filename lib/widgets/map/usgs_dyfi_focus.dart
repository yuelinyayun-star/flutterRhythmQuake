import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/utils/world_wrap.dart';
import '../../models/usgs_dyfi.dart';
import '../../providers/map_state_provider.dart';
import '../../services/native_camera_focus.dart';
import 'range_camera_geometry.dart';
import 'usgs_shakemap_focus.dart';

// An automatic viewport limit, not a restriction on manual zoom or source data.
const dyfiMinimumCellPixels = 10.0;
const dyfiMaximumZoom = 12.0;

double dyfiMinimumZoom(MapCamera camera, UsgsDyfiFrame frame) {
  var smallestSide = double.infinity;
  for (final cell in frame.cells ?? <UsgsDyfiCell>[]) {
    final ring = cell.rings.first;
    if (ring.isEmpty) {
      continue;
    }
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final point in ring) {
      final pixel = camera.projectAtZoom(
        LatLng(
          point.latitude,
          WorldWrap.longitudeClosestTo(point.longitude, ring.first.longitude),
        ),
        0,
      );
      left = min(left, pixel.dx);
      right = max(right, pixel.dx);
      top = min(top, pixel.dy);
      bottom = max(bottom, pixel.dy);
    }
    final side = min(right - left, bottom - top);
    if (side.isFinite && side > 0) {
      smallestSide = min(smallestSide, side);
    }
  }
  if (!smallestSide.isFinite) {
    return 2;
  }
  return (log(dyfiMinimumCellPixels / smallestSide) / ln2)
      .clamp(2.0, dyfiMaximumZoom)
      .toDouble();
}

class DyfiCameraFit extends CameraFit {
  const DyfiCameraFit({
    required this.frame,
    this.padding = const EdgeInsets.all(10),
  });
  final UsgsDyfiFrame frame;
  final EdgeInsets padding;
  @override
  MapCamera fit(MapCamera camera) =>
      _fitDyfiAroundEpicenter(
        camera,
        frame.focusPoints,
        LatLng(frame.event.latitude, frame.event.longitude),
        padding: padding,
        minZoom: dyfiMinimumZoom(camera, frame),
        maxZoom: dyfiMaximumZoom,
      ) ??
      camera.withPosition(
        center: LatLng(frame.event.latitude, frame.event.longitude),
      );
}

void focusUsgsDyfi({
  required BuildContext context,
  required MapStateProvider mapState,
  required UsgsDyfiFrame frame,
}) {
  final camera = mapState.mapController?.camera;
  if (camera == null) {
    return;
  }
  mapState.smartMoveToPoints(
    frame.focusPoints,
    minZoom: dyfiMinimumZoom(camera, frame),
    maxZoom: dyfiMaximumZoom,
    viewportPadding: usgsProductViewportPadding(context),
    focusAnchor: LatLng(frame.event.latitude, frame.event.longitude),
    sourceTag: 'policy-dyfi-${frame.product.identity}',
    minInterval: Duration.zero,
  );
}

// DYFI only: fit original grid geometry around the epicenter.
MapCamera? _fitDyfiAroundEpicenter(
  MapCamera camera,
  List<LatLng> points,
  LatLng anchor, {
  required double minZoom,
  required double maxZoom,
  required EdgeInsets padding,
}) {
  final size = camera.nonRotatedSize;
  final width = size.width - padding.horizontal;
  final height = size.height - padding.vertical;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return null;
  }

  final anchorPixel = camera.projectAtZoom(anchor);
  final offsets = <List<double>>[];
  for (final point in RangeCameraGeometry.prepare(points).points) {
    final wrapped = LatLng(
      point.latitude,
      WorldWrap.longitudeClosestTo(point.longitude, anchor.longitude),
    );
    final delta = camera.projectAtZoom(wrapped) - anchorPixel;
    offsets.add([delta.dx, delta.dy]);
  }
  // Same fixed-anchor math as the main map; DYFI's 10px minimum-cell zoom,
  // padding and maximum zoom remain independent inputs to the native fit.
  final fit =
      NativeCameraFocus.prepare({
            'op': 'fitAnchor',
            'offsets': offsets,
            'width': width,
            'height': height,
            'currentScale': camera.crs.scale(camera.zoom),
            'rotation': camera.rotationRad,
            'minZoom': minZoom,
            'maxZoom': maxZoom,
            'paddingX': (padding.right - padding.left) / 2,
            'paddingY': (padding.bottom - padding.top) / 2,
          })
          as Map;
  final zoom = (fit['zoom'] as num).toDouble();
  final paddingOffset = Offset(
    (fit['offsetX'] as num).toDouble(),
    (fit['offsetY'] as num).toDouble(),
  );
  return camera.withPosition(
    center: WorldWrap.unprojectUnwrapped(
      camera,
      camera.projectAtZoom(anchor, zoom) + paddingOffset,
      zoom: zoom,
    ),
    zoom: zoom,
  );
}
