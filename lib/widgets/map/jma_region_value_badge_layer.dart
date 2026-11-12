import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// SREV's h-region stamp: 200-unit square at
/// 1.1 * screenScale * (4 + sqrt(mapScale)) percent. Its Mercator map has
/// 3600 units per world and the reference stage is 480 x 360. Only this badge
/// scale is adapted; no camera/fill/station rules are inherited from SREV.
double jmaRegionValueBadgeEdge(double worldWidth, Size viewport) {
  final screenScale = math.min(viewport.width / 480, viewport.height / 360);
  if (screenScale <= 0) return 0;
  final mapScale = worldWidth / (3600 * screenScale);
  return 2.2 * screenScale * (4 + math.sqrt(math.max(0, mapScale)));
}

Color jmaRegionValueBadgeForeground(Color regionColor) =>
    jmaRegionValueBadgeColor(regionColor).computeLuminance() > .45
    ? const Color(0xFF151B22)
    : const Color(0xFFF8FAFC);

/// A small same-hue lift keeps the badge clear on the subdued map fill.
/// Transparency is separate from lightness; no black/gray overlay is used.
Color jmaRegionValueBadgeColor(Color regionColor) {
  final hsl = HSLColor.fromColor(regionColor.withValues(alpha: 1));
  return hsl
      .withLightness((hsl.lightness + .035).clamp(0, 1))
      .toColor()
      .withValues(alpha: .86);
}

/// Normalized visible outlines from the bundled MPLUSRounded1c-Bold font
/// (1000 units/em). In particular, 1's ink center differs from its advance
/// center. Use the visible glyph, not its text line box, for optical alignment.
Rect jmaRegionValueInkBounds(TextPainter painter, String value) {
  const outlines = <String, Rect>{
    '0': Rect.fromLTRB(.040, -.740, .600, .010),
    '1': Rect.fromLTRB(.103, -.730, .443, .000),
    '2': Rect.fromLTRB(.082, -.740, .562, .000),
    '3': Rect.fromLTRB(.080, -.730, .558, .010),
    '4': Rect.fromLTRB(.013, -.730, .590, .000),
    '5': Rect.fromLTRB(.091, -.730, .569, .010),
    '6': Rect.fromLTRB(.050, -.740, .597, .010),
    '7': Rect.fromLTRB(.075, -.730, .572, .000),
    '+': Rect.fromLTRB(.074, -.580, .660, .000),
    '-': Rect.fromLTRB(.074, -.343, .408, -.237),
    '−': Rect.fromLTRB(.074, -.343, .660, -.237),
  };
  final outline = outlines[value.substring(0, 1)];
  if (outline == null) return Offset.zero & painter.size;
  final fontSize = painter.text!.style!.fontSize!;
  // Include line-height leading and Skia's snapped painted baseline; verified
  // against the bundled font's rendered alpha bounds, rather than a visual nudge.
  final baseline = painter.computeLineMetrics().first.baseline.ceilToDouble();
  var ink = Rect.fromLTRB(
    outline.left * fontSize,
    baseline + outline.top * fontSize,
    outline.right * fontSize,
    baseline + outline.bottom * fontSize,
  );
  if (value.length > 1) {
    for (final box in painter.getBoxesForSelection(
      TextSelection(baseOffset: 1, extentOffset: value.length),
    )) {
      ink = ink.expandToInclude(box.toRect());
    }
  }
  return ink;
}

Offset jmaRegionValueOpticalCenter(
  TextPainter painter,
  String value,
  Rect ink,
) {
  if (value == '1') {
    // The bundled glyph's main vertical stem spans x=300..443 / 1000 em.
    // Its top flag extends left to 103, so the full outline center is unsuitable.
    final fontSize = painter.text!.style!.fontSize!;
    final stemMidpoint = (.300 + .443) * fontSize / 2;
    // At the design size, font rasterization puts the straight stem slightly
    // left of its outline midpoint. Keep its two painted sides balanced rather
    // than including the flag in the centering calculation.
    return Offset(stemMidpoint - fontSize * .005, ink.center.dy);
  }
  return ink.center;
}

/// The main digit stays centered; its top-right symbol never shifts that center.
class JmaRegionValueBadgeTextLayout {
  JmaRegionValueBadgeTextLayout(Polygon polygon) {
    final value = polygon.label!;
    _ownsMain = value.length > 1;
    main = _ownsMain
        ? (TextPainter(
            text: TextSpan(
              text: value.substring(0, 1),
              style: polygon.labelStyle,
            ),
            textDirection: TextDirection.ltr,
          )..layout())
        : polygon.textPainter!;
    final mainInk = jmaRegionValueInkBounds(main, value.substring(0, 1));
    var bounds = mainInk;
    final opticalCenter = jmaRegionValueOpticalCenter(main, value, mainInk);
    if (value.length > 1) {
      suffix = TextPainter(
        text: TextSpan(
          text: value.substring(1),
          style: polygon.labelStyle.copyWith(
            fontSize: polygon.labelStyle.fontSize! * .55,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final suffixInk = jmaRegionValueInkBounds(suffix!, value.substring(1));
      suffixOffset = Offset(
        mainInk.right + 1.0 - suffixInk.left,
        mainInk.top + mainInk.height * .28 - suffixInk.center.dy,
      );
      bounds = mainInk.expandToInclude(suffixInk.shift(suffixOffset));
    }
    ink = bounds;
    center = opticalCenter;
  }
  late final bool _ownsMain;
  late final TextPainter main;
  TextPainter? suffix;
  Offset suffixOffset = Offset.zero;
  late final Rect ink;
  late final Offset center;
  void paint(Canvas canvas) {
    main.paint(canvas, Offset.zero);
    suffix?.paint(canvas, suffixOffset);
  }

  void dispose() {
    if (_ownsMain) main.dispose();
    suffix?.dispose();
  }
}

/// Rounded squares for region values, separate from circular station symbols.
/// Consumes the fill's existing Polygon label/position/text caches; does not
/// calculate intensities, merge source data or change camera/marker policies.
class JmaRegionValueBadgeLayer extends StatefulWidget {
  const JmaRegionValueBadgeLayer({super.key, required this.polygons});
  final List<Polygon> polygons;

  @override
  State<JmaRegionValueBadgeLayer> createState() =>
      _JmaRegionValueBadgeLayerState();
}

class _JmaRegionValueBadgeLayerState extends State<JmaRegionValueBadgeLayer> {
  List<Polygon> _labels = const [];
  final _projected = HashMap<Polygon, _ProjectedRegionValue>.identity();
  final _styles = <int, _BadgePaints>{};
  final _layouts = HashMap<Polygon, JmaRegionValueBadgeTextLayout>.identity();
  double? _zoom;
  Crs? _crs;

  @override
  void initState() {
    super.initState();
    _readLabels();
  }

  @override
  void didUpdateWidget(covariant JmaRegionValueBadgeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.polygons, widget.polygons)) _readLabels();
  }

  void _readLabels() {
    for (final text in _layouts.values) {
      text.dispose();
    }
    _layouts.clear();
    _labels = widget.polygons
        .where((p) => p.label != null)
        .toList(growable: false);
    _projected.clear();
    _styles.clear();
  }

  @override
  void dispose() {
    for (final text in _layouts.values) {
      text.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_labels.isEmpty) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    if (camera.zoom != _zoom || camera.crs != _crs) {
      _projected.clear();
      _zoom = camera.zoom;
      _crs = camera.crs;
    }
    final edge = jmaRegionValueBadgeEdge(
      camera.getWorldWidthAtZoom(),
      camera.size,
    );
    final screen = Offset.zero & camera.size;
    final worldWidth = camera.getWorldWidthAtZoom();
    final origin = camera.pixelOrigin;
    final visible = <({Polygon polygon, Offset point})>[];
    // Bounded, per-frame spatial buckets avoid pairwise label comparisons.
    // Occupancy is not retained between frames or report changes.
    final occupied = <(int, int), List<Rect>>{};
    for (final polygon in _labels) {
      final placement = _projected.putIfAbsent(polygon, () {
        final bounds = polygon.boundingBox;
        final a = camera.projectAtZoom(bounds.northWest);
        final b = camera.projectAtZoom(bounds.southEast);
        return _ProjectedRegionValue(Rect.fromPoints(a, b));
      });
      final shift = worldWidth > 0
          ? ((camera.pixelBounds.center.dx - placement.bounds.center.dx) /
                        worldWidth)
                    .round() *
                worldWidth
          : 0.0;
      if (!placement.bounds
          .shift(Offset(shift, 0))
          .overlaps(camera.pixelBounds)) {
        continue;
      }
      // Expensive interior placement stays lazy for offscreen regions.
      final worldPoint = placement.point ??= camera.projectAtZoom(
        polygon.labelPosition,
      );
      final point = worldPoint.translate(shift, 0) - origin;
      final rectangle = Rect.fromCenter(
        center: point,
        width: edge,
        height: edge,
      );
      if (!rectangle.overlaps(screen)) continue;
      final padded = rectangle.inflate(3);
      final x0 = (padded.left / 40).floor(), x1 = (padded.right / 40).floor();
      final y0 = (padded.top / 40).floor(), y1 = (padded.bottom / 40).floor();
      var overlaps = false;
      for (var x = x0; x <= x1 && !overlaps; x++) {
        for (var y = y0; y <= y1 && !overlaps; y++) {
          overlaps = occupied[(x, y)]?.any((r) => r.overlaps(padded)) ?? false;
        }
      }
      if (overlaps) continue;
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          (occupied[(x, y)] ??= []).add(padded);
        }
      }
      visible.add((polygon: polygon, point: point));
      final color = (polygon.color ?? const Color(0xFF888888)).withValues(
        alpha: 1,
      );
      _styles.putIfAbsent(color.toARGB32(), () => _BadgePaints(color));
      _layouts.putIfAbsent(
        polygon,
        () => JmaRegionValueBadgeTextLayout(polygon),
      );
    }
    if (visible.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: MobileLayerTransformer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: camera.size,
            isComplex: true,
            painter: JmaRegionValueBadgePainter._(
              labels: visible,
              styles: _styles,
              layouts: _layouts,
              edge: edge,
            ),
          ),
        ),
      ),
    );
  }
}

class JmaRegionValueBadgePainter extends CustomPainter {
  JmaRegionValueBadgePainter._({
    required this.labels,
    required Map<int, _BadgePaints> styles,
    required Map<Polygon, JmaRegionValueBadgeTextLayout> layouts,
    required this.edge,
  }) : _styles = styles,
       _layouts = layouts;
  final double edge;
  static const _designEdge = 28.0;
  static final _square = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, _designEdge, _designEdge),
    const Radius.circular(4.2),
  );
  final List<({Polygon polygon, Offset point})> labels;
  final Map<int, _BadgePaints> _styles;
  final Map<Polygon, JmaRegionValueBadgeTextLayout> _layouts;

  @override
  void paint(Canvas canvas, Size size) {
    for (final label in labels) {
      final color = (label.polygon.color ?? const Color(0xFF888888)).withValues(
        alpha: 1,
      );
      final style = _styles[color.toARGB32()]!;
      final layout = _layouts[label.polygon]!;
      final ink = layout.ink;
      final center = layout.center;
      final scale = math.min(
        1.0,
        math.min((_designEdge - 4) / ink.width, (_designEdge - 6) / ink.height),
      );
      canvas.save();
      canvas.translate(label.point.dx - edge / 2, label.point.dy - edge / 2);
      canvas.scale(edge / _designEdge);
      canvas.drawRRect(_square, style.fill);
      canvas.drawRRect(_square, style.border);
      canvas.translate(
        _designEdge / 2 - center.dx * scale,
        _designEdge / 2 - center.dy * scale,
      );
      if (scale != 1) canvas.scale(scale);
      layout.paint(canvas);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant JmaRegionValueBadgePainter oldDelegate) =>
      !identical(oldDelegate.labels, labels);
}

class _BadgePaints {
  _BadgePaints(Color regionColor) {
    fill = Paint()..color = jmaRegionValueBadgeColor(regionColor);
    border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = HSLColor.fromColor(regionColor)
          .withLightness(HSLColor.fromColor(regionColor).lightness * .7)
          .toColor()
          .withValues(alpha: .78);
  }
  late final Paint fill;
  late final Paint border;
}

class _ProjectedRegionValue {
  _ProjectedRegionValue(this.bounds);
  final Rect bounds;
  Offset? point;
}
