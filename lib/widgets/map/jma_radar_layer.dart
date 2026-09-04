import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/sources/jma_radar_service.dart';

class JmaRadarLayer extends StatelessWidget {
  const JmaRadarLayer({
    super.key,
    required this.frame,
    required this.tileProvider,
    required this.reset,
    required this.errorTileCallback,
  });

  final JmaRadarFrame? frame;
  final TileProvider tileProvider;
  final Stream<void> reset;
  final ErrorTileCallBack errorTileCallback;

  @override
  Widget build(BuildContext context) {
    final data = frame;
    if (data == null) return const SizedBox.shrink();
    final nativeZoom = jmaRadarNativeZoom(MapCamera.of(context).zoom);
    return Opacity(
      opacity: 0.58,
      child: TileLayer(
        key: ValueKey(
          'jma-radar-${data.basetime}-${data.validtime}-$nativeZoom',
        ),
        urlTemplate: data.tileUrlTemplate,
        userAgentPackageName: 'flutterrhythmquake/1.0',
        tileProvider: tileProvider,
        minNativeZoom: nativeZoom,
        maxNativeZoom: nativeZoom,
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
