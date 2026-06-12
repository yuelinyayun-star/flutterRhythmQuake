import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/utils/topojson_loader.dart';
import '../../models/tsunami_message.dart';

class TsunamiLayer extends StatefulWidget {
  final TsunamiMessage? tsunami;
  final String source;

  const TsunamiLayer({super.key, this.tsunami, this.source = 'jp'});

  @override
  State<TsunamiLayer> createState() => _TsunamiLayerState();
}

class _TsunamiLayerState extends State<TsunamiLayer> {
  TopoJsonData? _topoData;
  bool _loading = false;
  String _lastSource = '';
  int _flickerCounter = 0;
  Timer? _flickerTimer;

  static const Map<String, int> _tsunamiColors = {
    'blue': 0xFF3399FF,
    'yellow': 0xFFEECC00,
    'red': 0xFFCC3333,
    'purple': 0xFF991199,
    'gray': 0xFF888888,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
    _flickerTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {
          _flickerCounter = (_flickerCounter + 1) % 6;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant TsunamiLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _flickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_loading) return;
    if (widget.source == _lastSource && _topoData != null) return;
    setState(() => _loading = true);

    TopoJsonData? data;
    switch (widget.source) {
      case 'jp':
        data = await TopoJsonLoader.loadJpTsunami();
        break;
    }

    if (mounted) {
      setState(() {
        _topoData = data;
        _loading = false;
        _lastSource = widget.source;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_topoData == null || _loading || widget.tsunami == null) {
      return const SizedBox.shrink();
    }

    if (!widget.tsunami!.isActive) {
      return const SizedBox.shrink();
    }

    // 6帧闪烁：5帧显示，1帧隐藏
    final showFlicker = _flickerCounter != 0;

    double zoom = 4.0;
    try {
      final camera = MapCamera.maybeOf(context);
      if (camera != null) zoom = camera.zoom;
    } catch (_) {}
    final strokeWidth = zoom.clamp(2.0, 10.0);

    final warnAreaMap = <String, TsunamiAreaInfo>{};
    for (final area in widget.tsunami!.areas) {
      warnAreaMap[area.name] = area;
    }

    final polylines = <Polyline>[];

    for (final region in _topoData!.regions) {
      final areaInfo = warnAreaMap[region.name];
      if (areaInfo == null) continue;
      final colorHex =
          _tsunamiColors[areaInfo.className] ?? _tsunamiColors['gray']!;
      final color = Color(colorHex);

      for (final polygonPoints in region.polygons) {
        if (polygonPoints.length < 2) continue;
        polylines.add(
          Polyline(
            points: polygonPoints,
            color: color,
            strokeWidth: strokeWidth,
          ),
        );
      }

      for (final linePoints in region.lines) {
        if (linePoints.length < 2) continue;
        polylines.add(
          Polyline(points: linePoints, color: color, strokeWidth: strokeWidth),
        );
      }
    }

    if (polylines.isEmpty) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: showFlicker ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: PolylineLayer(polylines: polylines),
    );
  }
}
