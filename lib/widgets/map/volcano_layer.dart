import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/jma_volcano_site.dart';

class VolcanoLayer extends StatelessWidget {
  final List<JmaVolcanoSite> sites;
  final bool showMarkers;
  final bool showHoverTargets;

  const VolcanoLayer({
    super.key,
    required this.sites,
    this.showMarkers = true,
    this.showHoverTargets = true,
  });

  @override
  Widget build(BuildContext context) {
    if (sites.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(markers: _buildMarkers());
  }

  List<Marker> _buildMarkers() {
    return sites.map((site) {
      final size = _markerSize(site);
      return Marker(
        point: LatLng(site.latitude, site.longitude),
        width: size,
        height: size,
        child: _VolcanoMarkerTile(
          site: site,
          showMarker: showMarkers,
          enableHover: showHoverTargets,
        ),
      );
    }).toList();
  }

  double _markerSize(JmaVolcanoSite site) {
    if (site.alertLevel >= 3 || site.hasRecentEruption) return 32;
    if (site.alertLevel >= 1 || site.hasFreshInfoOverlay) return 28;
    return 24;
  }
}

class _VolcanoMarkerTile extends StatefulWidget {
  final JmaVolcanoSite site;
  final bool showMarker;
  final bool enableHover;

  const _VolcanoMarkerTile({
    required this.site,
    required this.showMarker,
    required this.enableHover,
  });

  @override
  State<_VolcanoMarkerTile> createState() => _VolcanoMarkerTileState();
}

class _VolcanoMarkerTileState extends State<_VolcanoMarkerTile> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _showTimer;
  Timer? _hideTimer;

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _handleEnter(PointerEnterEvent event) {
    _hideTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = Timer(const Duration(milliseconds: 70), _showOverlay);
  }

  void _handleExit(PointerExitEvent event) {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 80), _removeOverlay);
  }

  void _showOverlay() {
    if (!mounted || _overlayEntry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return ExcludeSemantics(
          child: IgnorePointer(
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(6, 2),
              child: Align(
                alignment: Alignment.topLeft,
                widthFactor: 1,
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints.tightFor(width: 228),
                  child: _VolcanoHoverCard(site: widget.site),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final fillColor = _markerFillColorForSite(widget.site);
    final ringColor = _markerRingColorForSite(widget.site);
    final isEmphasized =
        widget.site.alertLevel >= 2 ||
        widget.site.hasFreshInfoOverlay ||
        widget.site.hasRecentEruption;

    final marker = ExcludeSemantics(
      child: CompositedTransformTarget(
        link: _link,
        child: Center(
          child: widget.showMarker
              ? CustomPaint(
                  size: Size.square(isEmphasized ? 24 : 18),
                  painter: _VolcanoTrianglePainter(
                    fillColor: fillColor,
                    borderColor: Colors.black.withValues(alpha: 0.72),
                    ringColor: ringColor,
                    drawRing: widget.site.hasFreshInfoOverlay,
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );

    if (!widget.enableHover) {
      return IgnorePointer(child: marker);
    }

    return MouseRegion(
      opaque: false,
      cursor: SystemMouseCursors.precise,
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _showOverlay,
        child: marker,
      ),
    );
  }
}

class _VolcanoTrianglePainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;
  final Color ringColor;
  final bool drawRing;

  _VolcanoTrianglePainter({
    required this.fillColor,
    required this.borderColor,
    required this.ringColor,
    required this.drawRing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outerPath = ui.Path()
      ..moveTo(size.width / 2, 1.2)
      ..lineTo(size.width - 1.2, size.height - 1.5)
      ..lineTo(1.2, size.height - 1.5)
      ..close();

    if (drawRing) {
      final ringPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      canvas.drawPath(outerPath, ringPaint);
    }

    final innerInset = drawRing ? 2.2 : 0.8;
    final innerPath = ui.Path()
      ..moveTo(size.width / 2, 1.2 + innerInset)
      ..lineTo(size.width - 1.2 - innerInset, size.height - 1.5 - innerInset)
      ..lineTo(1.2 + innerInset, size.height - 1.5 - innerInset)
      ..close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawPath(innerPath, fillPaint);
    canvas.drawPath(innerPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _VolcanoTrianglePainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.drawRing != drawRing;
  }
}

class _VolcanoHoverCard extends StatelessWidget {
  final JmaVolcanoSite site;

  const _VolcanoHoverCard({required this.site});

  @override
  Widget build(BuildContext context) {
    final color = _statusColorForSite(site);
    final tags = <String>[
      if (site.alertLevel > 0) 'Level ${site.alertLevel}',
      if (site.hasRecentEruption) 'Eruption',
      if (site.latestReportTime != null) _formatTime(site.latestReportTime!),
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121827).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.58),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomPaint(
                        size: const Size(14, 14),
                        painter: _VolcanoTrianglePainter(
                          fillColor: _markerFillColorForSite(site),
                          borderColor: Colors.black.withValues(alpha: 0.72),
                          ringColor: _markerRingColorForSite(site),
                          drawRing: site.hasFreshInfoOverlay,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          site.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.6,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    site.statusLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: tags
                        .where((item) => item.trim().isNotEmpty)
                        .map(
                          (item) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10.8,
                                height: 1.1,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if ((site.detailText ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      site.detailText!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.9,
                        height: 1.28,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

Color _statusColorForSite(JmaVolcanoSite site) {
  switch (site.alertLevel) {
    case 5:
      return const Color(0xFFC800FF);
    case 4:
      return const Color(0xFFFF2800);
    case 3:
      return const Color(0xFFFFAA00);
    case 2:
      return const Color(0xFFFAF500);
    case 1:
      return const Color(0xFFF2F2FF);
    default:
      return const Color(0xFFF2F2FF);
  }
}

Color _markerFillColorForSite(JmaVolcanoSite site) {
  final base = _statusColorForSite(site);
  final alpha = site.alertLevel >= 3 || site.hasRecentEruption ? 0.78 : 0.64;
  return base.withValues(alpha: alpha);
}

Color _markerRingColorForSite(JmaVolcanoSite site) {
  if (site.hasFreshInfoOverlay) {
    return const Color(0xFFD83A7C).withValues(alpha: 0.72);
  }
  return Colors.transparent;
}
