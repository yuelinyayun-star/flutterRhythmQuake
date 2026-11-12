import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/boundary_service.dart';
import '../../services/vector_basemap_service.dart';
import '../../services/debug/runtime_rendering_probe.dart';

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
  List<Widget>? _layers;
  List<List<Polygon<Object>>>? _polygons;
  List<List<Polyline<Object>>>? _polylines;
  LatLngBounds? _projectionWindow;
  int? _windowZoom;
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
      final polygons = <List<Polygon<Object>>>[];
      final polylines = <List<Polyline<Object>>>[];
      for (final dataset in data) {
        polygons.add(
          List.unmodifiable(
            dataset.polygons.map(
              (p) => Polygon<Object>(
                points: p.rings.first,
                holePointsList: p.rings.length > 1 ? p.rings.sublist(1) : null,
                color: VectorBasemapLayer.landColor,
                borderStrokeWidth: 0,
              ),
            ),
          ),
        );
        polylines.add(
          List.unmodifiable(
            dataset.borders.map(
              (points) => Polyline<Object>(
                points: points,
                color: VectorBasemapLayer.borderColor,
                strokeWidth: 1,
              ),
            ),
          ),
        );
      }
      setState(() {
        _polygons = polygons;
        _polylines = polylines;
      });
    } catch (error) {
      debugPrint('Vector basemap load failed: ${error.runtimeType}');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _prepareWindow(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final zoom = camera.zoom.floor();
    if (_windowZoom == zoom &&
        _projectionWindow?.containsBounds(bounds) == true) {
      return;
    }
    // Buffer the viewport so ordinary small pans reuse projected geometry.
    // The margin also includes flutter_map's ten-pixel polyline culling area.
    final strokeMargin = 10 / math.pow(2, camera.zoom);
    final latMargin = math.max(
      (bounds.north - bounds.south) * .35,
      strokeMargin,
    );
    final lngMargin = math.max(bounds.longitudeWidth * .35, strokeMargin);
    final window = LatLngBounds.unsafe(
      north: math.min(90, bounds.north + latMargin),
      south: math.max(-90, bounds.south - latMargin),
      east: math.min(180, bounds.east + lngMargin),
      west: math.max(-180, bounds.west - lngMargin),
    );
    bool nearViewport(LatLngBounds geometry) {
      if (geometry.south > window.north || geometry.north < window.south) {
        return false;
      }
      // At a world edge, retain all longitudes: a path can wrap into view.
      // This conservative selection matches the renderer's world-edge culling.
      return window.east == 180 ||
          window.west == -180 ||
          geometry.isOverlapping(window);
    }

    _layers = [
      for (var i = 0; i < _polygons!.length; i++) ...[
        PolygonLayer<Object>(
          polygons: List.unmodifiable(
            _polygons![i].where((p) => nearViewport(p.boundingBox)),
          ),
          polygonCulling: true,
          drawInSingleWorld: true,
          polygonLabels: false,
          simplificationTolerance: 0.5,
        ),
        PolylineLayer<Object>(
          polylines: List.unmodifiable(
            _polylines![i].where((p) => nearViewport(p.boundingBox)),
          ),
          cullingMargin: 10,
          drawInSingleWorld: true,
          simplificationTolerance: 0.5,
        ),
      ],
    ];
    _projectionWindow = window;
    _windowZoom = zoom;
    _resetDrawing();
  }

  void _resetDrawing() {
    _drawing = IgnorePointer(
      child: RepaintBoundary(
        child: Stack(fit: StackFit.expand, children: _layers!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (_polygons != null) _prepareWindow(camera);
    return RuntimePaintGate(
      mapOnly: false,
      basemapOnly: true,
      child: ColoredBox(
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
      ),
    );
  }
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
