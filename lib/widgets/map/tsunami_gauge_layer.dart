import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/tsunami_gauge_plan.dart';
import '../../models/tsunami_message.dart';
import '../../services/tsunami_gauge_service.dart';
import 'tsunami_gauge_marker.dart';

class TsunamiGaugeLayer extends StatefulWidget {
  const TsunamiGaugeLayer({
    super.key,
    required this.tsunami,
    this.regions = const [],
    this.service,
    this.now,
  });
  final TsunamiMessage tsunami;
  final List<Map<String, dynamic>> regions;
  final TsunamiGaugeService? service;
  final DateTime Function()? now;
  @override
  State<TsunamiGaugeLayer> createState() => _TsunamiGaugeLayerState();
}

class _TsunamiGaugeLayerState extends State<TsunamiGaugeLayer> {
  late Future<TsunamiGaugePlan> _future;
  Timer? _expiry;
  DateTime? _deadline;
  int _generation = 0;
  TsunamiGaugePlan? _displayPlan;
  double? _displayZoom;
  Widget? _displayLayer;
  final _gaugeChildren = <TsunamiGaugeData, Widget>{};
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  void _scheduleExpiry(DateTime? deadline) {
    _expiry?.cancel();
    _deadline = deadline;
    if (deadline != null) {
      final remaining = deadline.difference(_now.toUtc());
      if (remaining > Duration.zero) {
        _expiry = Timer(remaining, () {
          if (mounted) setState(() {});
        });
      }
    }
  }

  void _load() {
    final generation = ++_generation;
    _displayPlan = null;
    _displayLayer = null;
    _displayZoom = null;
    _gaugeChildren.clear();
    _scheduleExpiry(widget.tsunami.displayUntilUtc);
    _future = (widget.service ?? TsunamiGaugeService())
        .prepare(widget.tsunami, regions: widget.regions, now: _now)
        .then((plan) {
          if (mounted &&
              generation == _generation &&
              plan.expiresUtcMs != null) {
            _scheduleExpiry(
              DateTime.fromMillisecondsSinceEpoch(
                plan.expiresUtcMs!,
                isUtc: true,
              ),
            );
          }
          return plan;
        });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TsunamiGaugeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.tsunami, oldWidget.tsunami) ||
        !identical(widget.regions, oldWidget.regions) ||
        widget.service != oldWidget.service ||
        widget.now != oldWidget.now) {
      _load();
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TsunamiGaugePlan>(
    future: _future,
    builder: (context, snapshot) {
      if (!widget.tsunami.isActive ||
          !widget.tsunami.isDisplayableAt(_now) ||
          (_deadline != null && !_deadline!.isAfter(_now.toUtc())) ||
          snapshot.connectionState != ConnectionState.done ||
          !snapshot.hasData) {
        return const SizedBox.shrink();
      }
      final plan = snapshot.data!;
      final zoom = MapCamera.maybeOf(context)?.zoom ?? 5;
      // Pans still let MarkerLayer project/cull, but keep its marker list and
      // label children. Fractional zooms change only bounds and paint transforms.
      if (identical(_displayPlan, plan) && _displayZoom == zoom) {
        return _displayLayer!;
      }
      if (!identical(_displayPlan, plan)) _gaugeChildren.clear();
      final scale = TsunamiGaugeMarker.scaleAtZoom(zoom);
      final markers = [
        for (final gauge in plan.atZoom(zoom))
          Marker(
            point: LatLng(gauge.latitude, gauge.longitude),
            // Keep the foot of the water column on the station, as SREV does.
            alignment: const Alignment(0, -0.3714285714),
            width: TsunamiGaugeMarker.markerWidth * scale,
            height: TsunamiGaugeMarker.markerHeight * scale,
            child: FittedBox(
              child: _gaugeChildren.putIfAbsent(
                gauge,
                () => RepaintBoundary(
                  child: TsunamiGaugeMarker(
                    key: ValueKey(
                      'tsunami_gauge_${widget.tsunami.source.name}_${gauge.id}',
                    ),
                    data: gauge,
                    onTap: () => _showDetails(context, plan, gauge),
                  ),
                ),
              ),
            ),
          ),
      ];
      _displayPlan = plan;
      _displayZoom = zoom;
      return _displayLayer = markers.isEmpty
          ? const SizedBox.shrink()
          : MarkerLayer(markers: markers);
    },
  );

  Future<void> _showDetails(
    BuildContext context,
    TsunamiGaugePlan plan,
    TsunamiGaugeData gauge,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${widget.tsunami.source.displayLabel} 海啸观测'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final member in gauge.members)
                for (final row in plan.entries[member]['details'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${row['label']}：${row['value']}'),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
