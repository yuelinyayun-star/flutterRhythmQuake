import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/utils/topojson_loader.dart';
import '../../core/event_animation_clock.dart';
import '../../models/tsunami_message.dart';
import 'package:latlong2/latlong.dart';

class TsunamiOutline {
  const TsunamiOutline({
    required this.points,
    required this.className,
    this.strokeArgb,
  });
  final List<LatLng> points;
  final String className;
  final int? strokeArgb;
}

class TsunamiLayer extends StatefulWidget {
  final TsunamiMessage? tsunami;
  final String source;
  final List<TsunamiOutline>? outlines;

  /// Presentation clock for replay; source bulletin timestamps stay unchanged.
  final DateTime Function()? now;

  const TsunamiLayer({
    super.key,
    this.tsunami,
    this.source = 'jp',
    this.now,
    this.outlines,
  });

  @override
  State<TsunamiLayer> createState() => _TsunamiLayerState();
}

class _TsunamiLayerState extends State<TsunamiLayer> {
  TopoJsonData? _topoData;
  bool _loading = false;
  String _lastSource = '';
  EventAnimationLease? _clockLease;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

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
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant TsunamiLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        (oldWidget.outlines != null && widget.outlines == null)) {
      _loadData();
    }
    _syncClock();
  }

  @override
  void dispose() {
    _clockLease?.dispose();
    super.dispose();
  }

  void _syncClock() {
    if (_displayable) {
      _clockLease ??= EventAnimationClock.instance.acquire();
    } else {
      _clockLease?.dispose();
      _clockLease = null;
    }
  }

  Future<void> _loadData() async {
    if (widget.outlines != null) return;
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
    if ((widget.outlines == null && (_topoData == null || _loading)) ||
        widget.tsunami == null) {
      return const SizedBox.shrink();
    }

    if (!_displayable) {
      return const SizedBox.shrink();
    }

    // 6帧闪烁：5帧显示，1帧隐藏
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

    for (final outline in widget.outlines ?? const <TsunamiOutline>[]) {
      polylines.add(
        Polyline(
          points: outline.points,
          color: Color(
            outline.strokeArgb ??
                _tsunamiColors[outline.className] ??
                _tsunamiColors['gray']!,
          ),
          strokeWidth: strokeWidth,
        ),
      );
    }
    for (final region
        in widget.outlines != null ? <TopoJsonRegion>[] : _topoData!.regions) {
      final areaInfo = warnAreaMap[region.name];
      if (areaInfo == null) continue;
      if (areaInfo.grade == TsunamiGrade.none) continue;
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

    return ValueListenableBuilder<int>(
      valueListenable: EventAnimationClock.instance.blink2Fps,
      child: PolylineLayer(polylines: polylines),
      builder: (context, tick, child) => Opacity(
        opacity: _displayable && tick % 6 != 0 ? 1.0 : 0.0,
        child: child,
      ),
    );
  }

  bool get _displayable => widget.outlines == null
      ? widget.tsunami?.hasCoastalDisplayAt(_now) == true
      : widget.outlines!.isNotEmpty &&
            widget.tsunami?.isDisplayableAt(_now) == true;
}
