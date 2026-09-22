import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/nsmc_satellite_cloud_service.dart';

class NsmcSatelliteCloudLayer extends StatelessWidget {
  const NsmcSatelliteCloudLayer({super.key, required this.frame});
  final NsmcSatelliteCloudFrame? frame;

  @override
  Widget build(BuildContext context) {
    final data = frame;
    if (data == null) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final image = MemoryImage(data.imageBytes);
    return MobileLayerTransformer(
      child: ClipRect(
        child: Stack(
          children: [
            for (final bounds in nsmcSatelliteWorldRects(camera))
              Positioned.fromRect(
                rect: bounds.shift(-camera.pixelOrigin),
                child: Image(
                  image: image,
                  fit: BoxFit.fill,
                  opacity: const AlwaysStoppedAnimation(0.72),
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Repeat the unchanged global image just as the basemap repeats across 180 degrees.
List<Rect> nsmcSatelliteWorldRects(MapCamera camera) {
  final world = Rect.fromPoints(
    camera.projectAtZoom(
      const LatLng(NsmcSatelliteCloudService.mercatorLatitude, -180),
    ),
    camera.projectAtZoom(
      const LatLng(-NsmcSatelliteCloudService.mercatorLatitude, 180),
    ),
  );
  final viewport = camera.pixelBounds;
  final width = camera.getWorldWidthAtZoom();
  if (width <= 0) return world.overlaps(viewport) ? [world] : [];
  final first = ((viewport.left - world.right) / width).floor() + 1;
  final last = ((viewport.right - world.left) / width).ceil() - 1;
  return [
    for (var copy = first; copy <= last; copy++)
      if (world.shift(Offset(copy * width, 0)).overlaps(viewport))
        world.shift(Offset(copy * width, 0)),
  ];
}
