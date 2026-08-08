import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/sources/fan_satellite_cloud_service.dart';

class FanSatelliteCloudLayer extends StatelessWidget {
  const FanSatelliteCloudLayer({super.key, required this.frame});

  final FanSatelliteCloudFrame? frame;

  @override
  Widget build(BuildContext context) {
    final data = frame;
    if (data == null) return const SizedBox.shrink();
    final bounds = LatLngBounds.fromPoints([data.southWest, data.northEast]);
    return OverlayImageLayer(
      overlayImages: [
        OverlayImage(
          key: ValueKey('fan-satellite-cloud-${data.time.toIso8601String()}'),
          bounds: bounds,
          imageProvider: MemoryImage(data.imageBytes),
          opacity: 0.72,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }
}
