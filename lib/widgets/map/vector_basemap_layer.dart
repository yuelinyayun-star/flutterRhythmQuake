import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/boundary_service.dart';
import '../../services/vector_basemap_service.dart';

class VectorBasemapLayer extends StatefulWidget {
  const VectorBasemapLayer({super.key, this.service});
  final VectorBasemapService? service;

  static const oceanColor = Color(0xFF202124);
  static const landColor = Color(0xFF393939);
  static const borderColor = Color(0xFFBBBBBB);

  @override
  State<VectorBasemapLayer> createState() => _VectorBasemapLayerState();
}

class _VectorBasemapLayerState extends State<VectorBasemapLayer> {
  Widget? _drawing;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await (widget.service ?? VectorBasemapService.instance)
          .load();
      if (!mounted) return;
      final layers = <Widget>[];
      for (final dataset in data) {
        layers.add(
          PolygonLayer<Object>(
            polygons: List.unmodifiable(
              dataset.polygons.map(
                (p) => Polygon<Object>(
                  points: p.rings.first,
                  holePointsList: p.rings.length > 1
                      ? p.rings.sublist(1)
                      : null,
                  color: VectorBasemapLayer.landColor,
                  borderStrokeWidth: 0,
                ),
              ),
            ),
            polygonCulling: true,
            drawInSingleWorld: true,
            polygonLabels: false,
            simplificationTolerance: 0.5,
          ),
        );
        layers.add(
          PolylineLayer<Object>(
            polylines: List.unmodifiable(
              dataset.borders.map(
                (points) => Polyline<Object>(
                  points: points,
                  color: VectorBasemapLayer.borderColor,
                  strokeWidth: 1,
                ),
              ),
            ),
            cullingMargin: 10,
            drawInSingleWorld: true,
            simplificationTolerance: 0.5,
          ),
        );
      }
      // Keep layer and geometry identities stable: native projection/zoom caches
      // must not be discarded by unrelated earthquake/station UI rebuilds.
      setState(
        () => _drawing = IgnorePointer(
          child: RepaintBoundary(
            child: Stack(fit: StackFit.expand, children: layers),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Vector basemap load failed: ${error.runtimeType}');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: VectorBasemapLayer.oceanColor,
    child:
        _drawing ??
        Center(
          child: _failed
              ? IconButton(
                  tooltip: '底图加载失败，重新加载',
                  onPressed: () {
                    setState(() => _failed = false);
                    _load();
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                )
              : const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        ),
  );
}

/// Reuse existing place labels without loading the legacy boundary geometry.
class VectorBasemapLabels extends StatelessWidget {
  const VectorBasemapLabels({super.key});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (camera.zoom < 5) return const SizedBox.shrink();
    final level = camera.zoom < 8 ? LabelLevel.province : LabelLevel.city;
    return IgnorePointer(
      child: MarkerLayer(
        markers: [
          for (final label in BoundaryService.overviewLabels)
            if (label.level == level &&
                camera.visibleBounds.contains(label.coord))
              Marker(
                point: label.coord,
                width: 90,
                height: 22,
                child: Text(
                  label.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xCCEEEEEE),
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                    shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
