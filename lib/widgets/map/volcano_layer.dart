import 'dart:async';

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
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 4.0;
    return MarkerLayer(markers: _buildMarkers(_markerScaleForZoom(zoom)));
  }

  List<Marker> _buildMarkers(double markerScale) {
    final orderedSites = [...sites]
      ..sort((a, b) {
        final levelComparison = a.alertLevel.compareTo(b.alertLevel);
        if (levelComparison != 0) return levelComparison;
        return a.code.compareTo(b.code);
      });
    return orderedSites.map((site) {
      final size = _markerSize(site) * markerScale;
      return Marker(
        point: LatLng(site.latitude, site.longitude),
        width: size,
        height: size,
        child: _VolcanoMarkerTile(
          site: site,
          showMarker: showMarkers,
          enableHover: showHoverTargets,
          markerScale: markerScale,
        ),
      );
    }).toList();
  }

  double _markerScaleForZoom(double zoom) {
    return (1 + (zoom - 4) * 0.35).clamp(0.6, 1.25).toDouble();
  }

  double _markerSize(JmaVolcanoSite site) {
    if (site.alertLevel >= 3 || site.hasRecentEruption) return 26;
    if (site.alertLevel >= 1 || site.hasFreshInfoOverlay) return 22;
    return 18;
  }
}

class _VolcanoMarkerTile extends StatefulWidget {
  final JmaVolcanoSite site;
  final bool showMarker;
  final bool enableHover;
  final double markerScale;

  const _VolcanoMarkerTile({
    required this.site,
    required this.showMarker,
    required this.enableHover,
    required this.markerScale,
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
    final isEmphasized =
        widget.site.alertLevel >= 2 ||
        widget.site.hasFreshInfoOverlay ||
        widget.site.hasRecentEruption;

    final marker = ExcludeSemantics(
      child: CompositedTransformTarget(
        link: _link,
        child: Center(
          child: widget.showMarker
              ? _VolcanoIcon(
                  site: widget.site,
                  layoutSize: (isEmphasized ? 19 : 15) * widget.markerScale,
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

class _VolcanoIcon extends StatelessWidget {
  const _VolcanoIcon({required this.site, required this.layoutSize});

  // The supplied PNGs share a large transparent border. This keeps the visible
  // volcano outline at the same scale as the old 18/24 px marker artwork.
  static const double _assetScale = 3.0;

  final JmaVolcanoSite site;
  final double layoutSize;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: _assetScale,
      child: SizedBox.square(
        dimension: layoutSize,
        child: Image.asset(
          _assetForSite(site),
          filterQuality: FilterQuality.high,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  String _assetForSite(JmaVolcanoSite site) {
    final level = site.alertLevel;
    if (level < 1 || level > 5) {
      return 'assets/images/volcano/vol.png';
    }
    return 'assets/images/volcano/Lv$level.png';
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
          border: Border.all(color: color.withValues(alpha: 0.58), width: 1.2),
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
                      _VolcanoIcon(site: site, layoutSize: 14),
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
