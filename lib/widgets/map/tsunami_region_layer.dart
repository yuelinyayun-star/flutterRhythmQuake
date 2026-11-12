import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/tsunami_message.dart';
import '../../services/tsunami_region_service.dart';
import 'tsunami_layer.dart';
import 'tsunami_gauge_layer.dart';

typedef _TsunamiRegionView = ({
  List<Map<String, dynamic>> regions,
  List<TsunamiOutline> outlines,
});

/// Presentation only; warning geometry and named coastal zones come from Rust.
class TsunamiRegionLayer extends StatefulWidget {
  const TsunamiRegionLayer({super.key, required this.tsunami, this.service});
  final TsunamiMessage tsunami;
  final TsunamiRegionService? service;
  @override
  State<TsunamiRegionLayer> createState() => _TsunamiRegionLayerState();
}

class _TsunamiRegionLayerState extends State<TsunamiRegionLayer> {
  late Future<_TsunamiRegionView> _future;
  Timer? _expiryTimer;
  void _load() {
    _expiryTimer?.cancel();
    final deadline = widget.tsunami.displayUntilUtc;
    if (deadline != null) {
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining > Duration.zero) {
        _expiryTimer = Timer(remaining, () {
          if (mounted) setState(() {});
        });
      }
    }
    _future = (widget.service ?? TsunamiRegionService())
        .load(widget.tsunami)
        .then(
          (regions) => (
            regions: regions,
            outlines: [
              for (final region in regions)
                for (final line in region['lines'] as List)
                  TsunamiOutline(
                    className: region['className'] as String,
                    strokeArgb: region['strokeArgb'] as int?,
                    points: [
                      for (final point in line as List)
                        LatLng(
                          (point[1] as num).toDouble(),
                          (point[0] as num).toDouble(),
                        ),
                    ],
                  ),
            ],
          ),
        );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TsunamiRegionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.tsunami, oldWidget.tsunami) ||
        widget.service != oldWidget.service) {
      _load();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TsunamiRegionView>(
    future: _future,
    builder: (context, snapshot) {
      if (!widget.tsunami.isDisplayableAt(DateTime.now()) ||
          snapshot.connectionState != ConnectionState.done ||
          !snapshot.hasData ||
          snapshot.data!.regions.isEmpty) {
        return const SizedBox.shrink();
      }
      final data = snapshot.data!;
      return Stack(
        children: [
          TsunamiLayer(tsunami: widget.tsunami, outlines: data.outlines),
          TsunamiGaugeLayer(tsunami: widget.tsunami, regions: data.regions),
        ],
      );
    },
  );
}
