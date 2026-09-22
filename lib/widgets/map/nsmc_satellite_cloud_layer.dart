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
    return OverlayImageLayer(
      overlayImages: [
        OverlayImage(
          key: ValueKey('nsmc-satellite-${data.time.toIso8601String()}'),
          bounds: LatLngBounds(
            const LatLng(-NsmcSatelliteCloudService.mercatorLatitude, -180),
            const LatLng(NsmcSatelliteCloudService.mercatorLatitude, 180),
          ),
          imageProvider: MemoryImage(data.imageBytes),
          opacity: 0.72,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }
}
