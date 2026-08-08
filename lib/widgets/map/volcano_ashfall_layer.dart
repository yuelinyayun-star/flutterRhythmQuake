import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/unified_quake_data.dart';
import '../../models/volcano_event_data.dart';

/// Displays the official JMA AshInfo geometry for the currently applicable
/// ashfall forecast window. It has no data fetching or camera behavior.
class VolcanoAshfallLayer extends StatefulWidget {
  final List<UnifiedQuakeData> events;

  const VolcanoAshfallLayer({super.key, required this.events});

  @override
  State<VolcanoAshfallLayer> createState() => _VolcanoAshfallLayerState();
}

class _VolcanoAshfallLayerState extends State<VolcanoAshfallLayer> {
  Timer? _windowTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant VolcanoAshfallLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    final hasWindows = widget.events.any(
      (event) => event.volcanoEvent?.hasAshfallForecast ?? false,
    );
    if (!hasWindows) {
      _windowTimer?.cancel();
      _windowTimer = null;
      return;
    }
    _windowTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final polygons = <Polygon>[];
    for (final event in widget.events) {
      final window = event.volcanoEvent?.mapAshfallWindow(now: _now);
      if (window == null) continue;
      for (final item in window.items) {
        final style = _styleFor(item);
        for (final coordinates in item.polygons) {
          if (coordinates.length < 3) continue;
          polygons.add(
            Polygon(
              points: coordinates
                  .map((point) => LatLng(point.latitude, point.longitude))
                  .toList(growable: false),
              color: style.fill,
              borderColor: style.border,
              borderStrokeWidth: style.borderWidth,
            ),
          );
        }
      }
    }
    if (polygons.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(child: PolygonLayer(polygons: polygons));
  }

  _AshfallStyle _styleFor(VolcanoAshfallItem item) {
    final isPyroclast =
        item.phenomenonCode == '75' || item.phenomenon.contains('噴石');
    if (isPyroclast) {
      return _AshfallStyle(
        fill: const Color(0xFFFF5B39).withValues(alpha: 0.18),
        border: const Color(0xFFFF6A45).withValues(alpha: 0.88),
        borderWidth: 1.35,
      );
    }
    return _AshfallStyle(
      fill: const Color(0xFFFFD34A).withValues(alpha: 0.16),
      border: const Color(0xFFFFD34A).withValues(alpha: 0.82),
      borderWidth: 1.15,
    );
  }
}

class _AshfallStyle {
  final Color fill;
  final Color border;
  final double borderWidth;

  const _AshfallStyle({
    required this.fill,
    required this.border,
    required this.borderWidth,
  });
}
