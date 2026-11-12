import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/nsmc_satellite_cloud_service.dart';
import 'nsmc_cloud_tile_provider.dart';

class NsmcSatelliteCloudLayer extends StatefulWidget {
  const NsmcSatelliteCloudLayer({
    super.key,
    required this.frame,
    this.tileProvider,
  });
  final NsmcSatelliteCloudFrame? frame;
  final NsmcCloudTileProvider? tileProvider;

  @override
  State<NsmcSatelliteCloudLayer> createState() => _NsmcLayerState();
}

class _NsmcLayerState extends State<NsmcSatelliteCloudLayer> {
  NsmcCloudTileProvider? _provider;
  NsmcTileProviderLease? _lease;
  int? _committed;
  bool _commitScheduled = false;
  void _tryCommit() {
    final data = widget.frame;
    if (!mounted ||
        data == null ||
        !data.isTiled ||
        _provider?.visibleReady(data.time) != true ||
        _commitScheduled)
      return;
    if (_committed == data.time.millisecondsSinceEpoch) {
      data.onVisibleReady?.call();
      return;
    }
    _commitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commitScheduled = false;
      if (!mounted ||
          widget.frame?.time != data.time ||
          _provider?.visibleReady(data.time) != true)
        return;
      setState(() => _committed = data.time.millisecondsSinceEpoch);
      data.onVisibleReady?.call();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.frame;
    if (data == null) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    if (data.isTiled) {
      if (!TickerMode.valuesOf(context).enabled) {
        _provider?.dispose();
        _provider = null;
        _lease = null;
        _committed = null;
        return const SizedBox.shrink();
      }
      if (_provider == null || _provider!.isDisposed) {
        _provider = widget.tileProvider ?? NsmcCloudTileProvider();
        _lease = NsmcTileProviderLease(_provider!);
        _committed = null;
      }
      _provider!.targetTime = '${data.time.toUtc().millisecondsSinceEpoch}';
      _provider!.onVisibleReady = _tryCommit;
      _provider!.setView(camera);
      _tryCommit();
      Widget layer(int stamp) => TileLayer(
        key: ValueKey('nsmc-tiles-$stamp'),
        urlTemplate: 'nsmc://$stamp/{z}/{x}/{y}',
        tileProvider: _lease!,
        minNativeZoom: 0,
        maxNativeZoom: 3,
        panBuffer: 1,
        keepBuffer: 1,
        tileDisplay: const TileDisplay.instantaneous(),
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
      );
      final next = data.time.toUtc().millisecondsSinceEpoch;
      return Opacity(
        opacity: 0.72,
        child: Stack(
          children: [
            if (_committed != null) layer(_committed!),
            if (_committed != next) Opacity(opacity: 0, child: layer(next)),
          ],
        ),
      );
    }

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
