import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/event_animation_clock.dart';
import '../../models/sasmex_map_geometry.dart';
import '../../models/unified_quake_data.dart';
import '../../services/ntp_service.dart';

/// Website state highlight.
/// The existing QuakeWaveLayer draws our waves and epicenter above this layer.
class SasmexMapLayer extends StatefulWidget {
  final List<UnifiedQuakeData> events;

  /// Historical preview clock; does not modify any source event field.
  final DateTime Function()? displayClock;
  const SasmexMapLayer({super.key, required this.events, this.displayClock});

  @override
  State<SasmexMapLayer> createState() => _SasmexMapLayerState();
}

class _SasmexMapLayerState extends State<SasmexMapLayer> {
  SasmexMapCatalog? _catalog;
  EventAnimationLease? _lease;

  @override
  void initState() {
    super.initState();
    _syncClock();
    _load();
  }

  void _syncClock() {
    if (widget.events.isNotEmpty) {
      _lease ??= EventAnimationClock.instance.acquire();
    } else {
      _lease?.dispose();
      _lease = null;
    }
  }

  @override
  void didUpdateWidget(covariant SasmexMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  Future<void> _load() async {
    try {
      final catalog = await SasmexMapCatalog.load();
      if (mounted) setState(() => _catalog = catalog);
    } catch (error) {
      debugPrint('SASMEX map catalog load failed: $error');
    }
  }

  @override
  void dispose() {
    _lease?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ValueListenableBuilder<int>(
      valueListenable: EventAnimationClock.instance.second1Fps,
      builder: (context, tick, _) {
        final now = widget.displayClock?.call() ?? NtpService().now;
        final polygons = <Polygon>[];
        for (final event in widget.events) {
          final animation = SasmexMapAnimation.at(event, now);
          if (animation == null) continue;
          final color = animation.severe
              ? const Color(0xFFEF4444)
              : const Color(0xFFEAB308);
          final border = animation.severe
              ? const Color(0xFFB91C1C)
              : const Color(0xFFA16207);
          final state = _catalog?.stateFor(event);
          if (state != null) {
            for (final rings in state.polygons) {
              polygons.add(
                Polygon(
                  points: rings.first,
                  holePointsList: rings.length > 1 ? rings.sublist(1) : null,
                  color: color.withValues(alpha: .3),
                  borderColor: border.withValues(alpha: .8),
                  borderStrokeWidth: 2,
                ),
              );
            }
          }
        }
        if (polygons.isEmpty) return const SizedBox.shrink();
        return IgnorePointer(
          child: PolygonLayer(polygons: polygons, polygonLabels: false),
        );
      },
    ),
  );
}
