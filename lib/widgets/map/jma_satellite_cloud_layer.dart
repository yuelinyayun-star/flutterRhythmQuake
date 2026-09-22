import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/sources/jma_satellite_cloud_service.dart';

class JmaSatelliteCloudLayer extends StatelessWidget {
  const JmaSatelliteCloudLayer({
    super.key,
    required this.frame,
    required this.tileProvider,
    required this.reset,
    required this.errorTileCallback,
  });

  final JmaSatelliteCloudFrame? frame;
  final TileProvider tileProvider;
  final Stream<void> reset;
  final ErrorTileCallBack errorTileCallback;

  @override
  Widget build(BuildContext context) {
    final data = frame;
    if (data == null) return const SizedBox.shrink();
    return Opacity(
      opacity: 0.6,
      child: TileLayer(
        key: ValueKey('jma-satellite-${data.basetime}-${data.validtime}'),
        urlTemplate: data.tileUrlTemplate,
        userAgentPackageName: 'flutterrhythmquake/1.0',
        tileProvider: tileProvider,
        // JMA's full-disk B13/TBB product supplies XYZ zooms 3 through 5.
        minNativeZoom: 3,
        maxNativeZoom: 5,
        panBuffer: 1,
        keepBuffer: 3,
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
        reset: reset,
        errorTileCallback: errorTileCallback,
        tileDisplay: const TileDisplay.instantaneous(),
      ),
    );
  }
}
