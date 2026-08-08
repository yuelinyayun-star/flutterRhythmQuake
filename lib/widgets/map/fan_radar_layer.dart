import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/sources/fan_radar_service.dart';

class FanRadarLayer extends StatelessWidget {
  const FanRadarLayer({super.key, required this.frame});

  final FanRadarFrame? frame;

  @override
  Widget build(BuildContext context) {
    final data = frame;
    if (data == null) return const SizedBox.shrink();
    final bounds = LatLngBounds.fromPoints([data.southWest, data.northEast]);
    return OverlayImageLayer(
      overlayImages: [
        OverlayImage(
          key: ValueKey('fan-radar-${data.time.toIso8601String()}'),
          bounds: bounds,
          imageProvider: MemoryImage(data.imageBytes),
          opacity: 0.78,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }
}
