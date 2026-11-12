import 'dart:math' as math;
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/calculator.dart';
import '../../core/intensity_calculator.dart';
import '../../core/utils/topojson_loader.dart';
import '../../core/utils/world_wrap.dart';
import '../../models/cmt_catalog.dart';
import '../../models/jma_lpgm_bulletin.dart';
import '../../models/quake_message.dart';
import '../../models/unified_event_presentation.dart';
import '../../models/unified_quake_data.dart';
import '../../models/usgs_shakemap.dart';
import '../../services/quake_event_adapter.dart';
import '../../services/native_camera_focus.dart';
import '../../services/event_render_clipboard.dart';
import '../../services/render_information_loader.dart';
import '../../services/vector_basemap_service.dart';
import '../map/map_config.dart';
import '../map/cenc_ir_layer.dart';
import '../map/finite_camera_constraint.dart';
import '../map/history_marker_layer.dart';
import '../map/information_event_fill_layer.dart';
import '../map/information_fill_geometry.dart';
import '../map/intensity_fill_layer.dart';
import '../map/range_camera_geometry.dart';
import '../map/vector_basemap_layer.dart';
import '../map/usgs_shakemap_layer.dart';
import '../map/usgs_shakemap_focus.dart';
import 'app_page_background.dart';
import 'settings_controls.dart';
import 'event_render_export.dart';

enum EventRenderLayoutMode {
  /// 方案 A：分栏悬浮（左侧独立地图版块 + 右侧独立悬浮栏）。
  splitFloating,

  /// 方案 B：全幅悬浮（全幅地图铺底 + 右侧独立悬浮栏）。
  fullMapFloating,
}

enum EventRenderAspectRatio {
  /// 16:9 宽屏画布（1600×900）。
  ratio16x9(Size(1600, 900), '16:9'),

  /// 4:3 画布（1600×1200，保持宽度 1600 与右侧栏宽度 492 不变，纵向增高）。
  ratio4x3(Size(1600, 1200), '4:3');

  const EventRenderAspectRatio(this.canvasSize, this.label);

  final Size canvasSize;
  final String label;
}

/// In-app event rendering preview & poster workspace.
/// The captured event is independent of subsequent main-map selections.
class EventRenderPage extends StatefulWidget {
  const EventRenderPage({
    super.key,
    required this.event,
    this.initialLayoutMode = EventRenderLayoutMode.fullMapFloating,
    this.initialAspectRatio = EventRenderAspectRatio.ratio16x9,
    this.eventMatcher,
    this.cencIrMatcher,
    this.retainedCencIr,
    this.informationLoader,
    this.usgsEvent,
  });

  final UnifiedQuakeData event;
  final EventRenderLayoutMode initialLayoutMode;
  final EventRenderAspectRatio initialAspectRatio;
  final RenderEventMatcher? eventMatcher;
  final RenderIrMatcher? cencIrMatcher;
  final RenderCencIrProduct? retainedCencIr;
  final RenderInformationLoader? informationLoader;

  /// The clicked USGS row, including its upstream detail URL and identity.
  /// Independent of live-card enrichment which may omit rawEvent.
  final QuakeMessage? usgsEvent;

  static const Size canvasSize = Size(1600, 900);
  static const Size canvasSize4x3 = Size(1600, 1200);

  /// 按用户设计图比例精确测算：
  /// 画布 1600×900 下，右边栏宽 492 (30.78%)、高 834 (92.64%)，
  /// 上边距 32、下边距 34、右边距 36。
  static const double rightPanelWidth = 492;
  static const double panelTopMargin = 32;
  static const double panelBottomMargin = 34;
  static const double panelRightMargin = 36;
  static const double panelLeftMargin = 36;
  static const double splitPanelGap = 24;

  static const Size fullMapPanelSize = Size(
    1600 - panelLeftMargin - panelRightMargin,
    900 - panelTopMargin - panelBottomMargin,
  );
  static const double fullMapSidebarInset = 24;
  static const Size splitMapPanelSize = Size(
    1600 - panelLeftMargin - rightPanelWidth - splitPanelGap - panelRightMargin,
    900 - panelTopMargin - panelBottomMargin,
  );

  static Size fullMapPanelSizeFor(EventRenderAspectRatio ratio) => Size(
    ratio.canvasSize.width - panelLeftMargin - panelRightMargin,
    ratio.canvasSize.height - panelTopMargin - panelBottomMargin,
  );

  static Size splitMapPanelSizeFor(EventRenderAspectRatio ratio) => Size(
    ratio.canvasSize.width -
        panelLeftMargin -
        rightPanelWidth -
        splitPanelGap -
        panelRightMargin,
    ratio.canvasSize.height - panelTopMargin - panelBottomMargin,
  );
  static const EdgeInsets splitMapViewportPadding = EdgeInsets.all(36);
  static const EdgeInsets fullMapViewportPadding = EdgeInsets.fromLTRB(
    36,
    36,
    fullMapSidebarInset + rightPanelWidth + 36,
    36,
  );

  /// Rendering integration point: connects the event snapshot to the shared
  /// [InformationEventFillLayer] inside the renderer's own [FlutterMap].
  InformationEventFillLayer buildInformationFillLayer({
    ValueChanged<List<TopoJsonRegion>>? onInformationGeometry,
    ValueChanged<InformationFillSummary>? onInformationFillSummary,
  }) => InformationEventFillLayer(
    event: event,
    onInformationGeometry: onInformationGeometry,
    onInformationFillSummary: onInformationFillSummary,
  );

  @override
  State<EventRenderPage> createState() => _EventRenderPageState();
}

class _EventRenderPageState extends State<EventRenderPage> {
  final MapController _mapController = MapController();
  late EventRenderLayoutMode _layoutMode = widget.initialLayoutMode;
  late EventRenderAspectRatio _aspectRatio = widget.initialAspectRatio;
  List<TopoJsonRegion> _paintedRegions = const [];
  InformationFillSummary _fillSummary = InformationFillSummary.empty;
  bool _showRegionDistribution = true;
  bool _mapReady = false;
  late UnifiedQuakeData _informationEvent = widget.event;
  late RenderCencIrProduct? _cencIr = widget.retainedCencIr;
  bool _showCencIr = false;
  UsgsShakeMapFrame? _shakeMap;
  bool _showShakeMap = false;
  bool _loadingSources = false;
  bool _saving = false;
  bool _copying = false;
  final _canvasKey = GlobalKey();
  final _tiles = <String, TileImage>{};
  int _tileGeneration = 0;
  String? _sourceError;
  RenderInformationLoader? _loader;
  String _tileKey = MapConfig.vectorBasemapKey;
  UnifiedQuakeData get _activeEvent => _showCencIr
      ? _cencIr!.event
      : _showShakeMap
      ? QuakeEventAdapter.shakeMapInfo(_shakeMap!)
      : _informationEvent;

  QuakeMessage? get _usgsEvent {
    final event = widget.usgsEvent ?? widget.event.rawEvent;
    return event?.source == QuakeSourceType.usgs ? event : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadSources());
    });
  }

  Future<void> _loadSources() async {
    if (_loadingSources) return;
    if (widget.eventMatcher == null &&
        widget.cencIrMatcher == null &&
        _usgsEvent == null) {
      return;
    }
    _loader ??= widget.informationLoader ?? RenderInformationLoader();
    setState(() {
      _loadingSources = true;
      _sourceError = null;
    });
    try {
      if (_usgsEvent case final event?) {
        final frame = await _loader!.shakeMap(event);
        if (!mounted) return;
        setState(() {
          _shakeMap = frame;
          _showShakeMap = frame != null;
          _paintedRegions = const [];
          _fillSummary = InformationFillSummary.empty;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitMapCamera();
        });
      }
      if (widget.eventMatcher case final matcher?) {
        final observed = await _loader!.observed(widget.event, matcher);
        if (!mounted) return;
        if (observed != null)
          setState(() {
            _informationEvent = observed;
            _paintedRegions = const [];
            _fillSummary = InformationFillSummary.empty;
          });
      }
      final irMatcher = widget.cencIrMatcher;
      if (_cencIr == null && irMatcher != null) {
        final product = await _loader!.cencIr(widget.event, irMatcher);
        if (!mounted) return;
        setState(() => _cencIr = product);
      }
    } catch (error, stack) {
      debugPrint('Renderer upstream load failed: $error\n$stack');
      if (mounted) setState(() => _sourceError = '上游资料加载失败，可重试');
    } finally {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  void _selectProduct(bool useIr) {
    if (_saving || useIr && _cencIr == null || useIr == _showCencIr) return;
    setState(() {
      _showCencIr = useIr;
      _paintedRegions = const [];
      _fillSummary = InformationFillSummary.empty;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitMapCamera();
    });
  }

  void _selectShakeMap(bool show) {
    if (_saving || show && _shakeMap == null || show == _showShakeMap) return;
    setState(() {
      _showShakeMap = show;
      _paintedRegions = const [];
      _fillSummary = InformationFillSummary.empty;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitMapCamera();
    });
  }

  void _changeBasemap(String key) {
    if (_saving || key == _tileKey) return;
    setState(() {
      _tileKey = key;
      _tileGeneration++;
      _tiles.clear();
    });
  }

  Future<void> _saveImage() => _exportImage(copy: false);

  Future<void> _copyImage() => _exportImage(copy: true);

  Future<void> _exportImage({required bool copy}) async {
    if (_saving || _loadingSources || !_mapReady) return;
    setState(() {
      _saving = true;
      _copying = copy;
    });
    try {
      if (_tileKey == MapConfig.vectorBasemapKey) {
        await VectorBasemapService.instance.load().timeout(
          const Duration(seconds: 15),
        );
        if (!mounted) return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (_tileKey != MapConfig.vectorBasemapKey) {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (mounted &&
            (_tiles.isEmpty ||
                _tiles.values.any((t) => t.loadFinishedAt == null))) {
          _tiles.removeWhere((_, tile) => tile.cancelLoading.isCompleted);
          if (DateTime.now().isAfter(deadline))
            throw StateError('底图尚未加载完成，请稍后保存');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (_tiles.values.any((t) => t.loadError))
          throw StateError('底图加载失败，请更换底图后保存');
      }
      if (!mounted) return;
      final boundary = _canvasKey.currentContext!
          .findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
      final bool completed;
      if (copy) {
        await copyEventRenderPng(boundary);
        completed = true;
      } else {
        completed = await saveEventRenderPng(boundary, _activeEvent) != null;
      }
      if (completed && mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(copy ? '图片已复制' : '图片已保存')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${copy ? '复制' : '保存'}图片失败：$error')),
        );
    } finally {
      if (mounted)
        setState(() {
          _saving = false;
          _copying = false;
        });
    }
  }

  @override
  void dispose() {
    _loader?.close();
    _mapController.dispose();
    super.dispose();
  }

  bool get _hasUsableEpicenter =>
      _activeEvent.lat != null &&
      _activeEvent.lng != null &&
      QuakeCalculator.isUsableMapCoordinate(
        _activeEvent.lat!,
        _activeEvent.lng!,
      );

  LatLng get _initialMapCenter => _hasUsableEpicenter
      ? LatLng(_activeEvent.lat!, _activeEvent.lng!)
      : const LatLng(35.68, 139.76);

  Size get _activeCanvasSize => _aspectRatio.canvasSize;

  Size get _activeSplitMapPanelSize =>
      EventRenderPage.splitMapPanelSizeFor(_aspectRatio);

  EdgeInsets get _activeViewportPadding =>
      _layoutMode == EventRenderLayoutMode.splitFloating
      ? EventRenderPage.splitMapViewportPadding
      : EventRenderPage.fullMapViewportPadding;

  QuakeMessage get _markerMessage {
    if (_activeEvent.rawEvent case final raw?) {
      if (!_showCencIr &&
              QuakeCalculator.isUsableMapCoordinate(
                raw.latitude,
                raw.longitude,
              ) ||
          !_hasUsableEpicenter) {
        return raw;
      }
      return raw.copyWith(
        latitude: _activeEvent.lat,
        longitude: _activeEvent.lng,
      );
    }
    final source =
        cmtCatalogSources[_activeEvent.source] ??
        switch (_activeEvent.source) {
          'jmaEqlist' || 'p2pJmaEqlist' => QuakeSourceType.p2p,
          'cwaEqlist' => QuakeSourceType.cwa,
          'kmaEqlist' => QuakeSourceType.kma_eq,
          'usgsEqlist' => QuakeSourceType.usgs,
          _ => QuakeSourceType.cenc,
        };
    return QuakeMessage(
      source: source,
      eventId: _activeEvent.eventId,
      location: _activeEvent.hypocenter,
      magnitude: _activeEvent.magnitude,
      latitude: _activeEvent.lat ?? double.nan,
      longitude: _activeEvent.lng ?? double.nan,
      depth: _activeEvent.depth,
      originTime:
          _activeEvent.originTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      reportTime: _activeEvent.reportTime,
      timeZone: _activeEvent.timeZone,
      jmaShindo: _activeEvent.useShindo ? _activeEvent.maxIntensity : null,
      isHistory: true,
      isInfoEvent: !_activeEvent.isEew,
      infoTypeName: _activeEvent.titleText,
      reportNumText: _activeEvent.reportNumText,
      nodalPlane1: _activeEvent.nodalPlane1,
      nodalPlane2: _activeEvent.nodalPlane2,
      centroidDepth: _activeEvent.centroidDepth,
      momentTensor: _activeEvent.momentTensor,
      cmtMetadata: _activeEvent.cmtMetadata,
      apiTypeLabel: _activeEvent.apiTypeLabel,
    );
  }

  void _onInformationGeometry(List<TopoJsonRegion> regions) {
    if (!mounted) return;
    setState(() => _paintedRegions = regions);
    _fitMapCamera();
  }

  void _onInformationFillSummary(InformationFillSummary summary) {
    if (!mounted) return;
    setState(() => _fillSummary = summary);
  }

  void _switchLayoutMode(EventRenderLayoutMode mode) {
    if (_saving || _layoutMode == mode) return;
    setState(() {
      _layoutMode = mode;
      _tileGeneration++;
      _tiles.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitMapCamera();
    });
  }

  void _switchAspectRatio(EventRenderAspectRatio ratio) {
    if (_saving || _aspectRatio == ratio) return;
    setState(() {
      _aspectRatio = ratio;
      _tileGeneration++;
      _tiles.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitMapCamera();
    });
  }

  void _fitMapCamera() {
    if (!mounted || !_mapReady) return;
    final MapCamera camera;
    try {
      camera = _mapController.camera;
    } catch (_) {
      return;
    }
    final size = camera.nonRotatedSize;
    final padding = _activeViewportPadding;
    final width = size.width - padding.horizontal;
    final height = size.height - padding.vertical;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return;
    }

    final anchor = _hasUsableEpicenter
        ? LatLng(_activeEvent.lat!, _activeEvent.lng!)
        : null;
    final paddingX = (padding.right - padding.left) / 2;
    final paddingY = (padding.bottom - padding.top) / 2;

    final rawPoints = <LatLng>[];
    if (_showShakeMap) {
      rawPoints.addAll(shakeMapFocusPoints(_shakeMap!));
    } else if (_paintedRegions.isNotEmpty) {
      final isJma =
          !_activeEvent.isJmaLpgm &&
          (_activeEvent.source == 'jmaEqlist' ||
              _activeEvent.source == 'p2pJmaEqlist');
      rawPoints.addAll(
        InformationFillGeometry(_paintedRegions).forEvent(
          _activeEvent,
          namedRegions: isJma,
          representative: isJma && _activeEvent.warnArea.trim().isEmpty,
        ),
      );
      if (rawPoints.isEmpty) {
        for (final region in _paintedRegions) {
          for (final poly in region.polygons) {
            if (poly.length < 3) continue;
            rawPoints.addAll(poly);
          }
        }
      }
    }
    if (anchor != null) {
      rawPoints.insert(0, anchor);
    }

    if (rawPoints.length > 1) {
      final geometry = RangeCameraGeometry.prepare(rawPoints);
      if (anchor != null && geometry.points.isNotEmpty) {
        final anchorPixel = camera.projectAtZoom(anchor);
        final offsets = <List<double>>[];
        for (final point in geometry.points) {
          final wrapped = LatLng(
            point.latitude,
            WorldWrap.longitudeClosestTo(point.longitude, anchor.longitude),
          );
          final delta = camera.projectAtZoom(wrapped) - anchorPixel;
          offsets.add([delta.dx, delta.dy]);
        }
        final fit =
            NativeCameraFocus.prepare({
                  'op': 'fitAnchor',
                  'offsets': offsets,
                  'width': width,
                  'height': height,
                  'currentScale': camera.crs.scale(camera.zoom),
                  'rotation': camera.rotationRad,
                  'minZoom': 3.0,
                  'maxZoom': 8.0,
                  'paddingX': paddingX,
                  'paddingY': paddingY,
                })
                as Map?;
        if (fit != null) {
          final zoom = (fit['zoom'] as num).toDouble();
          final offset = Offset(
            (fit['offsetX'] as num).toDouble(),
            (fit['offsetY'] as num).toDouble(),
          );
          final targetCenter = WorldWrap.unprojectUnwrapped(
            camera,
            camera.projectAtZoom(anchor, zoom) + offset,
            zoom: zoom,
          );
          _mapController.move(targetCenter, zoom);
          return;
        }
      } else if (geometry.view case final rawView?) {
        final centerLat = (rawView['latitude'] as num).toDouble();
        final centerLng = WorldWrap.normalizeLongitude(
          (rawView['longitude'] as num).toDouble(),
        );
        final latDiff = (rawView['latDiff'] as num).toDouble();
        final lngDiff = (rawView['lngDiff'] as num).toDouble();
        final maxDiff = math.max(latDiff, lngDiff) + 0.8;
        final zoom =
            (maxDiff > 20
                    ? 3.8
                    : maxDiff > 10
                    ? 4.6
                    : maxDiff > 5
                    ? 5.5
                    : maxDiff > 2
                    ? 6.4
                    : 7.2)
                .clamp(3.5, 9.0);
        final viewAnchor = LatLng(centerLat, centerLng);
        final targetCenter = WorldWrap.unprojectUnwrapped(
          camera,
          camera.projectAtZoom(viewAnchor, zoom) + Offset(paddingX, paddingY),
          zoom: zoom,
        );
        _mapController.move(targetCenter, zoom);
        return;
      }
    }

    if (anchor != null) {
      const zoom = 6.0;
      final targetCenter = WorldWrap.unprojectUnwrapped(
        camera,
        camera.projectAtZoom(anchor, zoom) + Offset(paddingX, paddingY),
        zoom: zoom,
      );
      _mapController.move(targetCenter, zoom);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF020208),
    body: Stack(
      children: [
        const AppPageBackground(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: SettingsControlStyle.blurSigma,
                  sigmaY: SettingsControlStyle.blurSigma,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: SettingsControlStyle.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SettingsControlStyle.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                        child: _buildHeader(),
                      ),
                      const Divider(
                        height: 1,
                        color: SettingsControlStyle.divider,
                      ),
                      Expanded(
                        child: SizedBox.expand(
                          key: const ValueKey('event_render_content'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: RepaintBoundary(
                                  key: const ValueKey('render_canvas_repaint'),
                                  child: KeyedSubtree(
                                    key: _canvasKey,
                                    child: SizedBox(
                                      key: const ValueKey(
                                        'event_render_canvas',
                                      ),
                                      width: _activeCanvasSize.width,
                                      height: _activeCanvasSize.height,
                                      child: _buildRenderCanvas(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildHeader() => LayoutBuilder(
    builder: (context, constraints) {
      final title = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.of(context).pop(),
            color: SettingsControlStyle.accent,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          const SizedBox(width: 6),
          const Text(
            '渲染事件',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
      return constraints.maxWidth < 1000
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: title),
                _buildModeSwitcher(),
              ],
            )
          : Row(
              children: [
                title,
                const SizedBox(width: 16),
                Expanded(child: _buildModeSwitcher()),
              ],
            );
    },
  );

  Widget _buildModeSwitcher() {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        if (_usgsEvent != null)
          DropdownButton<bool>(
            key: const ValueKey('render_shakemap_selector'),
            value: _showShakeMap,
            dropdownColor: const Color(0xFF303034),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: [
              const DropdownMenuItem(value: false, child: Text('地震情报')),
              DropdownMenuItem(
                value: true,
                enabled: _shakeMap != null,
                child: Text(
                  _loadingSources ? 'MMI 加载中…' : 'ShakeMap · MMI',
                  style: TextStyle(
                    color: _shakeMap == null ? Colors.white24 : Colors.white,
                  ),
                ),
              ),
            ],
            onChanged: _saving || _loadingSources
                ? null
                : (value) {
                    if (value != null) _selectShakeMap(value);
                  },
          ),
        if (widget.event.source == 'cencEqlist') ...[
          DropdownButton<bool>(
            key: const ValueKey('render_product_selector'),
            value: _showCencIr,
            dropdownColor: const Color(0xFF303034),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: [
              const DropdownMenuItem(value: false, child: Text('地震情报')),
              DropdownMenuItem(
                value: true,
                enabled: _cencIr != null,
                child: Text(
                  _loadingSources ? '烈度速报加载中…' : '烈度速报',
                  style: TextStyle(
                    color: _cencIr == null ? Colors.white24 : Colors.white,
                  ),
                ),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) _selectProduct(value);
                  },
          ),
        ],
        DropdownButton<String>(
          key: const ValueKey('render_basemap_selector'),
          value: _tileKey,
          dropdownColor: const Color(0xFF303034),
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: MapConfig.baseTileOptions.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.value,
                  child: Text(entry.key),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) _changeBasemap(value);
                },
        ),
        if (_loadingSources)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_sourceError != null)
          IconButton(
            tooltip: _sourceError,
            onPressed: _loadSources,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        _modeTabButton(
          key: const ValueKey('render_toggle_region_distribution'),
          label: '区域分布',
          active: _showRegionDistribution,
          onTap:
              _saving || !_fillSummary.isObserved || _fillSummary.groups.isEmpty
              ? null
              : () {
                  setState(() {
                    _showRegionDistribution = !_showRegionDistribution;
                  });
                },
        ),
        _modeTabButton(
          key: const ValueKey('render_aspect_16_9'),
          label: EventRenderAspectRatio.ratio16x9.label,
          active: _aspectRatio == EventRenderAspectRatio.ratio16x9,
          onTap: _saving
              ? null
              : () => _switchAspectRatio(EventRenderAspectRatio.ratio16x9),
        ),
        _modeTabButton(
          key: const ValueKey('render_aspect_4_3'),
          label: EventRenderAspectRatio.ratio4x3.label,
          active: _aspectRatio == EventRenderAspectRatio.ratio4x3,
          onTap: _saving
              ? null
              : () => _switchAspectRatio(EventRenderAspectRatio.ratio4x3),
        ),
        _modeTabButton(
          key: const ValueKey('render_layout_split'),
          label: '分栏悬浮',
          active: _layoutMode == EventRenderLayoutMode.splitFloating,
          onTap: () => _switchLayoutMode(EventRenderLayoutMode.splitFloating),
        ),
        _modeTabButton(
          key: const ValueKey('render_layout_full_map'),
          label: '全幅悬浮',
          active: _layoutMode == EventRenderLayoutMode.fullMapFloating,
          onTap: () => _switchLayoutMode(EventRenderLayoutMode.fullMapFloating),
        ),
        TextButton.icon(
          key: const ValueKey('render_save_image'),
          onPressed: _saving || _loadingSources || !_mapReady
              ? null
              : _saveImage,
          icon: Icon(
            _saving && !_copying ? Icons.hourglass_top : Icons.save_alt,
            size: 16,
          ),
          label: Text(_saving && !_copying ? '保存中…' : '保存图片'),
          style: TextButton.styleFrom(
            foregroundColor: SettingsControlStyle.accent,
          ),
        ),
        TextButton.icon(
          key: const ValueKey('render_copy_image'),
          onPressed:
              _saving ||
                  _loadingSources ||
                  !_mapReady ||
                  !EventRenderClipboard.supported
              ? null
              : _copyImage,
          icon: Icon(
            _copying ? Icons.hourglass_top : Icons.copy_outlined,
            size: 16,
          ),
          label: Text(_copying ? '复制中…' : '复制图片'),
          style: TextButton.styleFrom(
            foregroundColor: SettingsControlStyle.accent,
          ),
        ),
      ],
    );
  }

  Widget _modeTabButton({
    required Key key,
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active && onTap != null
                  ? SettingsControlStyle.accent
                  : Colors.transparent,
              width: 2.0,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? Colors.white24
                  : active
                  ? Colors.white
                  : Colors.white54,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRenderCanvas() {
    final mapCore = _buildFlutterMap();
    final rightSidebarPanel = RenderRightSidebarPanel(
      key: const ValueKey('render_right_sidebar_panel'),
      event: _activeEvent,
      fillSummary: _fillSummary,
      shakeMap: _showShakeMap ? _shakeMap : null,
      showRegionDistribution: _showRegionDistribution,
    );

    final Widget body;
    if (_layoutMode == EventRenderLayoutMode.splitFloating) {
      final splitSize = _activeSplitMapPanelSize;
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: splitSize.width,
            height: splitSize.height,
            child: RepaintBoundary(
              key: const ValueKey('render_map_repaint'),
              child: RenderMapPanel(
                key: const ValueKey('render_map_panel'),
                map: mapCore,
              ),
            ),
          ),
          const SizedBox(width: EventRenderPage.splitPanelGap),
          SizedBox(
            width: EventRenderPage.rightPanelWidth,
            child: rightSidebarPanel,
          ),
        ],
      );
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: RepaintBoundary(
              key: const ValueKey('render_map_repaint'),
              child: RenderMapPanel(
                key: const ValueKey('render_map_panel'),
                map: mapCore,
              ),
            ),
          ),
          Positioned(
            top: EventRenderPage.fullMapSidebarInset,
            right: EventRenderPage.fullMapSidebarInset,
            bottom: EventRenderPage.fullMapSidebarInset,
            width: EventRenderPage.rightPanelWidth,
            child: rightSidebarPanel,
          ),
        ],
      );
    }

    return ColoredBox(
      color: const Color(0xFF070A12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EventRenderPage.panelLeftMargin,
              EventRenderPage.panelTopMargin,
              EventRenderPage.panelRightMargin,
              EventRenderPage.panelBottomMargin,
            ),
            child: body,
          ),
          const Positioned(
            right: EventRenderPage.panelRightMargin,
            bottom: 7,
            child: IgnorePointer(
              child: Text(
                'RhythmQuake绘制',
                key: ValueKey('render_canvas_watermark'),
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlutterMap() {
    final tileGeneration = _tileGeneration;
    Widget trackTile(BuildContext context, Widget child, TileImage tile) {
      if (tileGeneration == _tileGeneration) {
        _tiles.removeWhere((_, tile) => tile.cancelLoading.isCompleted);
        _tiles['${tile.coordinates}'] = tile;
      }
      return child;
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialMapCenter,
        initialZoom: 6.0,
        minZoom: 2.5,
        maxZoom: 12.0,
        cameraConstraint: const FiniteCameraConstraint(),
        backgroundColor: VectorBasemapLayer.oceanColor,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
        onMapReady: () {
          setState(() => _mapReady = true);
          _fitMapCamera();
        },
      ),
      children: [
        if (_tileKey == MapConfig.vectorBasemapKey)
          const VectorBasemapLayer()
        else
          TileLayer(
            key: ValueKey('$_tileKey-$_tileGeneration'),
            urlTemplate: MapConfig.urlByKey(_tileKey),
            subdomains: MapConfig.subdomainsByKey(_tileKey),
            userAgentPackageName: 'flutterrhythmquake/1.0',
            maxNativeZoom: MapConfig.maxNativeZoomByKey(_tileKey),
            tileDimension: _tileKey == MapConfig.mapboxEewceDarkKey ? 512 : 256,
            zoomOffset: _tileKey == MapConfig.mapboxEewceDarkKey ? -1 : 0,
            panBuffer: 0,
            keepBuffer: 0,
            tileDisplay: const TileDisplay.instantaneous(),
            tileBuilder: trackTile,
          ),
        if (_tileKey == MapConfig.jianSatelliteRoadsKey)
          TileLayer(
            key: ValueKey('render-roads-$_tileGeneration'),
            urlTemplate: MapConfig.jianTransportation,
            maxNativeZoom: MapConfig.jianTransportationMaxNativeZoom,
            panBuffer: 0,
            keepBuffer: 0,
            tileBuilder: (context, child, tile) {
              if (tileGeneration == _tileGeneration)
                _tiles['roads-${tile.coordinates}'] = tile;
              return child;
            },
          ),
        if (_showShakeMap)
          UsgsShakeMapLayer(
            key: const ValueKey('render_shakemap_mmi'),
            frame: _shakeMap,
            showLegend: false,
          )
        else if (_showCencIr)
          CencIrLayer(
            key: ValueKey('render_ir_${_cencIr!.data.reportId}'),
            data: _cencIr!.data,
            onInformationGeometry: _onInformationGeometry,
            onInformationFillSummary: _onInformationFillSummary,
          )
        else
          InformationEventFillLayer(
            key: const ValueKey('render_information_fill'),
            event: _activeEvent,
            onInformationGeometry: _onInformationGeometry,
            onInformationFillSummary: _onInformationFillSummary,
          ),
        if (_tileKey == MapConfig.vectorBasemapKey) const VectorBasemapLabels(),
        HistoryMarkerLayer(event: _markerMessage),
      ],
    );
  }
}

/// 独立悬浮地图版块
class RenderMapPanel extends StatelessWidget {
  const RenderMapPanel({super.key, required this.map});

  final Widget map;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF), width: 1.0),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: map),
    );
  }
}

/// 右侧独立悬浮面板（参考设置毛玻璃效果 + 统一 UI 四排文字与比例 + 单行半高填充震度/烈度 + 下半部上游区域分布）
class RenderRightSidebarPanel extends StatelessWidget {
  const RenderRightSidebarPanel({
    super.key,
    required this.event,
    required this.fillSummary,
    this.showRegionDistribution = true,
    this.shakeMap,
  });

  final UnifiedQuakeData event;
  final InformationFillSummary fillSummary;
  final bool showRegionDistribution;
  final UsgsShakeMapFrame? shakeMap;

  static Color _mapFillColorForEvent(
    UnifiedQuakeData event,
    InformationFillSummary summary,
  ) {
    if (event.jmaLpgmBulletin case final bulletin? when bulletin.maxLgInt > 0) {
      final shindoVal = _lpgmShindoValue(event);
      if (shindoVal != null) {
        final info = IntensityCalculator.getJmaShindoInfoByLevel(shindoVal);
        if (info.level >= 0) {
          return Color(info.colorHex);
        }
      }
      return jmaLpgmClassColor(bulletin.maxLgInt);
    }
    if (summary.regions.isNotEmpty) {
      return summary.regions.first.color;
    }
    if (summary.groups.isNotEmpty) {
      return summary.groups.first.color;
    }
    final raw = event.maxIntensity.trim();
    if (event.useShindo) {
      final info = IntensityCalculator.getJmaShindoInfoByLevel(raw);
      if (info.level >= 0) {
        return Color(info.colorHex);
      }
    }
    final csis = double.tryParse(raw)?.round();
    if (csis != null && csis > 0) {
      return Color(IntensityCalculator.getCsisColor(csis));
    }
    if (event.magnitude.isFinite &&
        event.magnitude > 0 &&
        event.depth.isFinite &&
        event.depth >= 0) {
      final est = IntensityCalculator.calcCsisLevel(
        event.magnitude,
        event.depth,
        0,
      );
      if (est > 0) {
        return Color(IntensityCalculator.getCsisColor(est));
      }
    }
    return const Color(0xFF4499FF);
  }

  static String? _lpgmShindoValue(UnifiedQuakeData event) {
    final bulletin = event.jmaLpgmBulletin;
    if (bulletin == null) return null;
    final raw = event.isJmaLpgm || event.source == 'jmaLpgm'
        ? bulletin.maxInt.trim()
        : event.maxIntensity.trim();
    if (raw.isNotEmpty && !const {'-', '--', '不明', '未知', '长周期'}.contains(raw)) {
      return raw.replaceAll('弱', '-').replaceAll('強', '+').replaceAll('强', '+');
    }
    final fromBulletin = bulletin.maxInt.trim();
    if (fromBulletin.isNotEmpty &&
        !const {'-', '--', '不明', '未知', '长周期'}.contains(fromBulletin)) {
      return fromBulletin
          .replaceAll('弱', '-')
          .replaceAll('強', '+')
          .replaceAll('强', '+');
    }
    return null;
  }

  static String _intensitySingleLineText(
    UnifiedQuakeData event,
    UnifiedEventPresentation presentation,
    InformationFillSummary summary,
  ) {
    if (event.jmaLpgmBulletin case final bulletin? when bulletin.maxLgInt > 0) {
      final shindoVal = _lpgmShindoValue(event);
      if (shindoVal != null && shindoVal.isNotEmpty) {
        return '最大震度 $shindoVal';
      }
      return '长周期 ${bulletin.maxLgInt}';
    }

    final isCencIr =
        event.source == 'nowQuakeCencIr' ||
        summary.sourceModeLabel.contains('仪器烈度') ||
        event.titleText.contains('烈度速报');

    var val = presentation.intensityValue.trim();
    final isMissingVal =
        val.isEmpty || val == '-' || val == '--' || val == '不明' || val == '未知';

    if (isMissingVal) {
      if (summary.groups.isNotEmpty) {
        final groupLabel = summary.groups.first.badgeText.trim();
        val = groupLabel
            .replaceFirst(RegExp(r'^(最大震度|预估震度|震度|最大仪器烈度|最大烈度|预估烈度|烈度)\s*'), '')
            .trim();
      } else if (!event.useShindo &&
          event.magnitude.isFinite &&
          event.magnitude > 0 &&
          event.depth.isFinite &&
          event.depth >= 0) {
        final est = IntensityCalculator.calcCsisLevel(
          event.magnitude,
          event.depth,
          0,
        );
        if (est > 0) {
          val = unifiedRomanIntensityLabel('$est');
        }
      }
    }

    if (isCencIr) {
      return '最大仪器烈度 $val';
    }
    if (event.isJmaLpgm) {
      final lpgm = event.jmaLpgmBulletin?.maxLgInt ?? 0;
      return lpgm > 0 ? '长周期 $lpgm' : '长周期地震动';
    }
    if (event.useShindo) {
      final cwaBadge = cwaEewBadgeIntensity(event);
      if ((cwaBadge != null && cwaBadge.estimated) || isMissingVal) {
        return '预估震度 $val';
      }
      return '最大震度 $val';
    }
    return '预估烈度 $val';
  }

  /// 统一 UI (AlertModule) 四排基准字号：12.5 : 15.5 : 14.5 : 12.0
  /// 按侧栏宽度 (492px) 等比例放大系数
  static const double _textScale = 2.2;

  static String _groupShortLabel(
    UnifiedQuakeData event,
    PaintedRegionGroup group,
    InformationFillSummary summary,
  ) {
    final badge = group.badgeText.trim();
    if (event.isJmaLpgm ||
        group.levelLabel.contains('阶级') ||
        group.levelLabel.contains('长周期') ||
        summary.scaleTitle.contains('长周期')) {
      return '长周期 $badge';
    }
    if (event.useShindo) {
      return '震度 $badge';
    }
    return '烈度 $badge';
  }

  static String _distributionSectionTitle(
    UnifiedQuakeData event,
    InformationFillSummary summary,
  ) {
    if (event.isJmaLpgm || summary.scaleTitle.contains('长周期')) {
      return '长周期分布';
    }
    if (event.useShindo) {
      return '震度分布';
    }
    return '烈度分布';
  }

  static List<String> _uniqueRegionNames(PaintedRegionGroup group) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in group.regions) {
      final name = item.region.name.trim();
      if (name.isNotEmpty && seen.add(name)) {
        result.add(name);
      }
    }
    return result;
  }

  static Widget _buildHalfFillBadge({
    Key? boxKey,
    Key? textKey,
    required String text,
    required Color fillColor,
    required double fontSize,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 8),
  }) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    return DecoratedBox(
      key: boxKey,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.5, 0.5, 1.0],
          colors: [
            Colors.transparent,
            Colors.transparent,
            fillColor.withValues(alpha: 0.82),
            fillColor.withValues(alpha: 0.82),
          ],
        ),
      ),
      child: Padding(
        padding: padding,
        child: Builder(
          builder: (context) {
            final effectiveStyle = DefaultTextStyle.of(
              context,
            ).style.merge(textStyle);
            final stroke = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xCC000000);
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                ExcludeSemantics(
                  child: RichText(
                    key: ValueKey('render_stroke_$text'),
                    text: TextSpan(
                      text: text,
                      style: effectiveStyle.copyWith(foreground: stroke),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign:
                        DefaultTextStyle.of(context).textAlign ??
                        TextAlign.start,
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    textWidthBasis: DefaultTextStyle.of(context).textWidthBasis,
                    textHeightBehavior: DefaultTextHeightBehavior.maybeOf(
                      context,
                    ),
                    locale: Localizations.maybeLocaleOf(context),
                  ),
                ),
                Text(
                  text,
                  key: textKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: effectiveStyle,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRegionDistributionSection() {
    final sortedGroups = List<PaintedRegionGroup>.from(fillSummary.groups)
      ..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
    final totalRegions = fillSummary.regions.length;
    final compact = totalRegions > 20 || sortedGroups.length > 3;
    final ultraCompact = totalRegions > 38 || sortedGroups.length > 5;
    final titleFontSize =
        (ultraCompact
            ? 9.5
            : compact
            ? 10.5
            : 11.2) *
        _textScale;
    final regionFontSize =
        (ultraCompact
            ? 7.6
            : compact
            ? 8.3
            : 9.0) *
        _textScale;
    final groupGap = ultraCompact
        ? 12.0
        : compact
        ? 16.0
        : 20.0;
    final afterTitleGap = compact ? 7.0 : 9.0;
    final titleHeight = titleFontSize * 1.15 + afterTitleGap;
    final regionStyle = TextStyle(
      color: const Color(0xFFE2E8F0),
      fontSize: regionFontSize,
      fontWeight: FontWeight.w600,
      height: 1.32,
    );
    final lineHeight = regionFontSize * 1.32;

    return Expanded(
      key: const ValueKey('render_region_distribution_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _distributionSectionTitle(event, fillSummary),
            key: const ValueKey('render_distribution_title'),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.0 * _textScale,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final effectiveRegionStyle = DefaultTextStyle.of(
                  context,
                ).style.merge(regionStyle);
                final maxW = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 436.0;
                final maxH = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : 420.0;

                final visibleBlocks = <Widget>[];
                var usedHeight = 0.0;

                for (var i = 0; i < sortedGroups.length; i++) {
                  final group = sortedGroups[i];
                  final regionNames = _uniqueRegionNames(group);
                  if (regionNames.isEmpty) continue;

                  final gapBefore = visibleBlocks.isEmpty ? 0.0 : groupGap;
                  final remaining = maxH - usedHeight - gapBefore;
                  if (remaining < titleHeight + lineHeight) {
                    break;
                  }

                  final baseText = regionNames.join('  ');
                  final painter = TextPainter(
                    text: TextSpan(text: baseText, style: effectiveRegionStyle),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: maxW);
                  final totalLines = math.max(
                    1,
                    painter.computeLineMetrics().length,
                  );
                  painter.dispose();

                  final maxFitLines = ((remaining - titleHeight) / lineHeight)
                      .floor()
                      .clamp(1, totalLines);
                  final hasMoreGroups = i + 1 < sortedGroups.length;
                  final nextGroupFitsAtLeastOneLine =
                      hasMoreGroups &&
                      (remaining -
                              (titleHeight + maxFitLines * lineHeight) -
                              groupGap) >=
                          (titleHeight + lineHeight);

                  final isTruncatedHere =
                      maxFitLines < totalLines ||
                      (hasMoreGroups && !nextGroupFitsAtLeastOneLine);
                  final displayRegionsText =
                      (isTruncatedHere && maxFitLines == totalLines)
                      ? '$baseText ...'
                      : baseText;

                  if (gapBefore > 0) {
                    visibleBlocks.add(SizedBox(height: gapBefore));
                  }
                  visibleBlocks.add(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHalfFillBadge(
                          text: _groupShortLabel(event, group, fillSummary),
                          fillColor: group.color,
                          fontSize: titleFontSize,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        SizedBox(height: afterTitleGap),
                        Text(
                          displayRegionsText,
                          maxLines: maxFitLines,
                          overflow: isTruncatedHere
                              ? TextOverflow.ellipsis
                              : TextOverflow.clip,
                          style: effectiveRegionStyle,
                        ),
                      ],
                    ),
                  );

                  usedHeight +=
                      gapBefore + titleHeight + maxFitLines * lineHeight;
                  if (isTruncatedHere) {
                    break;
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: visibleBlocks,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentation = UnifiedEventPresentation.fromEvent(event);
    final mmi = shakeMap?.product.maxMmi;
    final contours = shakeMap?.contours;
    final intensityColor =
        contours != null && contours.isNotEmpty && mmi != null
        ? Color(
            contours
                .reduce(
                  (a, b) =>
                      (a.value - mmi).abs() <= (b.value - mmi).abs() ? a : b,
                )
                .colorArgb,
          )
        : shakeMap != null
        ? Colors.grey
        : _mapFillColorForEvent(event, fillSummary);
    final intensityLine = shakeMap != null
        ? '最大 MMI ${mmi?.toStringAsFixed(1) ?? '未知'}'
        : _intensitySingleLineText(event, presentation, fillSummary);
    final lpgmBulletin = event.jmaLpgmBulletin;
    final hasSeparateLpgmBadge =
        lpgmBulletin != null &&
        lpgmBulletin.maxLgInt > 0 &&
        _lpgmShindoValue(event) != null;
    final canShowDistribution =
        showRegionDistribution &&
        fillSummary.isObserved &&
        fillSummary.groups.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: SettingsControlStyle.blurSigma,
          sigmaY: SettingsControlStyle.blurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: SettingsControlStyle.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SettingsControlStyle.border),
          ),
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      presentation.title,
                      key: const ValueKey('render_header_title'),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5 * _textScale,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      presentation.primaryText,
                      key: const ValueKey('render_header_hypocenter'),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5 * _textScale,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      presentation.secondaryText,
                      key: const ValueKey('render_header_mag_depth'),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5 * _textScale,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      presentation.timeText,
                      key: const ValueKey('render_header_time'),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12.0 * _textScale,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHalfFillBadge(
                            boxKey: const ValueKey(
                              'render_header_intensity_box',
                            ),
                            textKey: const ValueKey(
                              'render_header_intensity_text',
                            ),
                            text: intensityLine,
                            fillColor: intensityColor,
                            fontSize: 16.5 * _textScale,
                          ),
                          if (hasSeparateLpgmBadge) ...[
                            const SizedBox(width: 16),
                            _buildHalfFillBadge(
                              boxKey: const ValueKey('render_header_lpgm_box'),
                              textKey: const ValueKey(
                                'render_header_lpgm_text',
                              ),
                              text: '长周期 ${lpgmBulletin.maxLgInt}',
                              fillColor: jmaLpgmClassColor(
                                lpgmBulletin.maxLgInt,
                              ),
                              fontSize: 16.5 * _textScale,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (canShowDistribution) ...[
                    const SizedBox(height: 30),
                    _buildRegionDistributionSection(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
