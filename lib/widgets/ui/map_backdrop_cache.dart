import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'ui_runtime_flags.dart';
import '../../services/debug/field_diagnostics.dart';

/// The map is the common background of the desktop glass panels. Cache its
/// filtered pixels when the map paints, rather than filtering it again when
/// only a panel's text or clock changes. Source observations are untouched.
class MapBackdropCacheHost extends StatefulWidget {
  const MapBackdropCacheHost({super.key, required this.child});
  final Widget child;
  static final nativeFiltersForDiagnostics = ValueNotifier(false);
  static _MapBackdropCache? _active;

  /// True while the map camera is moving. Combined with [UiRuntimeFlags]
  /// drag-glass mode: full glass keeps native baking, low-res glass bakes at
  /// half resolution, off degrades panels to plain translucency. Restored
  /// [mapMotionSettle] after the last camera event.
  static final ValueNotifier<bool> mapMotionActive = ValueNotifier(false);

  static Timer? _motionSettleTimer;
  static DateTime _motionDeadline = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration mapMotionSettle = Duration(milliseconds: 250);

  /// Call on every camera event (drag, fling, programmatic animation). The
  /// motion window is heart-beat based, so no explicit end event is needed.
  static void notifyMapMotion() {
    final now = DateTime.now();
    _motionDeadline = now.add(mapMotionSettle);
    if (!mapMotionActive.value) {
      mapMotionActive.value = true;
      _scheduleMotionSettle(now);
    }
  }

  static void _scheduleMotionSettle(DateTime now) {
    _motionSettleTimer?.cancel();
    final delay = _motionDeadline.difference(now);
    _motionSettleTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        final remaining = _motionDeadline.difference(DateTime.now());
        if (remaining > Duration.zero) {
          _scheduleMotionSettle(DateTime.now());
        } else if (mapMotionActive.value) {
          mapMotionActive.value = false;
        }
      },
    );
  }

  static void cameraMoved(BuildContext context) {
    context
        .getInheritedWidgetOfExactType<_MapBackdropScope>()
        ?.cache
        .mapPainted(urgent: true);
  }

  static Map<String, Object?> get diagnostics => {
    'nativeFilters': nativeFiltersForDiagnostics.value,
    'captures': _active?._captures ?? 0,
    'mapSceneChanges': _active?._mapSceneChanges ?? 0,
    'urgentInvalidations': _active?._urgentInvalidations ?? 0,
    'captureMicrosTotal': _active?._captureMicrosTotal ?? 0,
    'lastCaptureMicros': _active?._lastCaptureMicros ?? 0,
    'images': _active?._regions.length ?? 0,
    'regions':
        _active?._regions.values.fold<int>(0, (n, r) => n + r.length) ?? 0,
    'textures': _active?._atlas == null ? 0 : 1,
    'imageBytes':
        (_active?._atlas?.width ?? 0) * (_active?._atlas?.height ?? 0) * 4,
    'filtersRendered': _active?._filtersRendered ?? 0,
    'captureFailure': _active?._captureFailure,
    'backgroundRefreshMillis': 0,
    'captureMode': 'sameScene',
    'mapRevision': _active?._revision ?? 0,
    'imageRevision': _active?._imageRevision ?? 0,
    'staleSamples': _active?._staleSamples ?? 0,
  };

  @override
  State<MapBackdropCacheHost> createState() => _MapBackdropCacheHostState();
}

class _MapBackdropCacheHostState extends State<MapBackdropCacheHost> {
  final cache = _MapBackdropCache();
  @override
  void initState() {
    super.initState();
    MapBackdropCacheHost._active = cache;
  }

  @override
  Widget build(BuildContext context) =>
      _MapBackdropScope(cache: cache, child: widget.child);
  @override
  void dispose() {
    if (identical(MapBackdropCacheHost._active, cache)) {
      MapBackdropCacheHost._active = null;
    }
    cache.dispose();
    super.dispose();
  }
}

class _MapBackdropScope extends InheritedWidget {
  const _MapBackdropScope({required this.cache, required super.child});
  final _MapBackdropCache cache;
  static _MapBackdropCache? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MapBackdropScope>()?.cache;
  @override
  bool updateShouldNotify(_MapBackdropScope oldWidget) =>
      cache != oldWidget.cache;
}

class MapBackdropSource extends SingleChildRenderObjectWidget {
  const MapBackdropSource({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MapBackdropSourceRender(
        _MapBackdropScope.of(context),
        MediaQuery.devicePixelRatioOf(context),
      );
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _MapBackdropSourceRender).configure(
      _MapBackdropScope.of(context),
      MediaQuery.devicePixelRatioOf(context),
    );
  }
}

class _MapBackdropSourceRender extends RenderRepaintBoundary {
  _MapBackdropSourceRender(this.cache, this.pixelRatio);
  _MapBackdropCache? cache;
  double pixelRatio;
  bool get ready => attached && hasSize && layer != null && !size.isEmpty;
  void configure(_MapBackdropCache? value, double ratio) {
    if (cache == value && ratio == pixelRatio) return;
    if (cache?.source == this) cache?.source = null;
    cache = value;
    pixelRatio = ratio;
    if (attached) cache?.source = this;
    cache?.mapPainted(urgent: true);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    cache?.source = this;
  }

  @override
  void detach() {
    if (cache?.source == this) cache?.source = null;
    super.detach();
  }

  @override
  OffsetLayer updateCompositedLayer({required OffsetLayer? oldLayer}) =>
      oldLayer ??
      _MapBackdropOffsetLayer(
        () => cache?.mapSceneChanged(),
        () => cache?.mapContentChanged(),
      );
}

class _MapBackdropOffsetLayer extends OffsetLayer {
  _MapBackdropOffsetLayer(this.changed, this.invalidated);
  final VoidCallback changed;
  final VoidCallback invalidated;
  @override
  void markNeedsAddToScene() {
    invalidated();
    super.markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    super.addToScene(builder);
    changed();
  }
}

class _MapBackdropRegion {
  const _MapBackdropRegion(this.bounds, this.slot);
  final Rect bounds;
  final Rect slot;
}

class _MapBackdropCache extends ChangeNotifier {
  _MapBackdropCache() {
    MapBackdropCacheHost.nativeFiltersForDiagnostics.addListener(_modeChanged);
    MapBackdropCacheHost.mapMotionActive.addListener(_motionModeChanged);
    UiRuntimeFlags.mapDragGlassModeNotifier.addListener(_motionModeChanged);
  }

  /// Motion/quality switches change the bake scale or disable baking, so the
  /// next frame must re-bake the atlas at the new scale.
  void _motionModeChanged() {
    mapPainted();
  }

  bool get _glassOffDuringMotion =>
      MapBackdropCacheHost.mapMotionActive.value &&
      UiRuntimeFlags.mapDragGlassModeNotifier.value ==
          UiRuntimeFlags.mapDragGlassOff;

  double get _bakeScale =>
      MapBackdropCacheHost.mapMotionActive.value &&
          UiRuntimeFlags.mapDragGlassModeNotifier.value ==
              UiRuntimeFlags.mapDragGlassLowRes
      ? 0.5
      : 1.0;

  _MapBackdropSourceRender? source;
  final _users = <ui.ImageFilter, int>{};
  final _panels = <_CachedMapBackdropRender>{};
  ui.Image? _atlas;
  Map<ui.ImageFilter, List<_MapBackdropRegion>> _regions = {};
  Size? imageLogicalSize;
  double? imagePixelRatio;
  bool _dirty = true, _capturing = false, _disposed = false;
  bool _readingSnapshotScene = false;
  int _revision = 0;
  int _imageRevision = 0, _staleSamples = 0;
  int _captures = 0, _lastCaptureMicros = 0;
  int _mapSceneChanges = 0, _urgentInvalidations = 0;
  int _captureMicrosTotal = 0;
  int _filtersRendered = 0;
  String? _captureFailure;
  bool canUseMapPixels(_CachedMapBackdropRender panel) {
    final boundary = source;
    if (boundary == null || !boundary.ready) return false;
    final transform = panel.getTransformTo(boundary);
    // The image's blur is expressed in map pixels. Scaled/rotated panels keep
    // their native filter so its original local blur radius remains exact.
    if ((transform.entry(0, 0) - 1).abs() > 1e-9 ||
        (transform.entry(1, 1) - 1).abs() > 1e-9 ||
        transform.entry(0, 1).abs() > 1e-9 ||
        transform.entry(1, 0).abs() > 1e-9) {
      return false;
    }
    final inMap = MatrixUtils.transformRect(
      transform,
      Offset.zero & panel.size,
    );
    if (inMap.left < -1e-6 ||
        inMap.top < -1e-6 ||
        inMap.right > boundary.size.width + 1e-6 ||
        inMap.bottom > boundary.size.height + 1e-6) {
      return false;
    }
    return true;
  }

  bool get _enabled =>
      _captureFailure == null &&
      !MapBackdropCacheHost.nativeFiltersForDiagnostics.value;
  void _modeChanged() {
    _dirty = true;
    _captureFailure = null;
    final previous = _atlas;
    _atlas = null;
    _regions = {};
    if (previous != null) _retire([previous]);
    notifyListeners();
    if (_enabled) mapPainted();
  }

  void register(ui.ImageFilter filter) {
    _users.update(filter, (count) => count + 1, ifAbsent: () => 1);
    if (!_regions.containsKey(filter)) mapPainted();
  }

  void unregister(ui.ImageFilter filter) {
    final count = _users[filter];
    if (count == null) return;
    if (count > 1) {
      _users[filter] = count - 1;
    } else {
      _users.remove(filter);
      _regions.remove(filter);
      if (_users.isEmpty) {
        final image = _atlas;
        _atlas = null;
        if (image != null) _retire([image]);
      }
    }
  }

  void mapPainted({bool urgent = false}) {
    if (urgent) _urgentInvalidations++;
    _revision++;
    _dirty = true;
  }

  void mapContentChanged() {
    if (!_readingSnapshotScene) mapPainted();
  }

  void mapSceneChanged() {
    if (!_readingSnapshotScene) {
      // Exclude the offscreen copy of this same layer subtree.
      _mapSceneChanges++;
    }
  }

  void ensureCurrentScene() {
    if (!_dirty) return;
    if (_glassOffDuringMotion) return;
    final boundary = source;
    if (_disposed ||
        !_enabled ||
        _capturing ||
        boundary == null ||
        !boundary.ready ||
        _users.isEmpty) {
      return;
    }
    _capturing = true;
    final watch = Stopwatch()..start();
    final revision = _revision;
    final baseRatio = boundary.pixelRatio;
    // Low-res glass: bake the moving map at half resolution. Displaying the
    // smaller atlas scaled back up keeps the visual blur radius identical
    // (sigma is applied in atlas pixels), while raster cost drops ~4x.
    final ratio = baseRatio * _bakeScale;
    final size = boundary.size;
    final targets = <({ui.ImageFilter filter, Rect bounds})>[];
    final slots = <({ui.ImageFilter filter, Rect bounds}), Rect>{};
    ui.Image? original, next;
    try {
      for (final filter in _users.keys.toList()) {
        final groups = <Rect>[];
        for (final panel in _panels) {
          if (!panel.attached ||
              !panel.hasSize ||
              panel._imageFilter != filter ||
              !canUseMapPixels(panel)) {
            continue;
          }
          var rect = MatrixUtils.transformRect(
            panel.getTransformTo(boundary),
            Offset.zero & panel.size,
          );
          // Share nearby samples but do not blur the unused middle of the
          // map merely because the same filter appears on both sidebars.
          var index = 0;
          while (index < groups.length) {
            if (rect.inflate(64).overlaps(groups[index])) {
              rect = rect.expandToInclude(groups.removeAt(index));
              index = 0;
            } else {
              index++;
            }
          }
          groups.add(rect);
        }
        for (var bounds in groups) {
          bounds = bounds.intersect(Offset.zero & size);
          if (bounds.isEmpty) continue;
          targets.add((
            filter: filter,
            bounds: Rect.fromLTRB(
              (bounds.left * ratio).floor() / ratio,
              (bounds.top * ratio).floor() / ratio,
              (bounds.right * ratio).ceil() / ratio,
              (bounds.bottom * ratio).ceil() / ratio,
            ),
          ));
        }
      }
      if (targets.isEmpty) return;
      int aligned(int value) => ((value + 15) ~/ 16) * 16;
      final atlasWidth = targets
          .map((r) => aligned((r.bounds.width * ratio).round()))
          .reduce((a, b) => a > b ? a : b);
      var x = 0, y = 0, rowHeight = 0;
      for (final entry in targets) {
        final width = (entry.bounds.width * ratio).round();
        final height = (entry.bounds.height * ratio).round();
        if (x + width > atlasWidth) {
          x = 0;
          y += rowHeight;
          rowHeight = 0;
        }
        slots[entry] = Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          width.toDouble(),
          height.toDouble(),
        );
        x += aligned(width);
        if (aligned(height) > rowHeight) rowHeight = aligned(height);
      }
      final atlasHeight = y + rowHeight;
      final bakeWatch = FieldDiagnostics.enabled ? (Stopwatch()..start()) : null;
      _readingSnapshotScene = true;
      try {
        // This returns a deferred engine texture synchronously. The same
        // scene references it directly; no UI-frame round trip or pixel
        // readback is involved, and an old camera image is never displayed.
        original = boundary.toImageSync(pixelRatio: ratio);
      } finally {
        _readingSnapshotScene = false;
      }
      if (_disposed || !_enabled) return;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (final entry in targets) {
        final bounds = entry.bounds, slot = slots[entry]!;
        final padded = bounds.inflate(64);
        final sourcePixels = Rect.fromLTRB(
          ((padded.left * ratio / 16).floor() * 16)
              .clamp(0, original.width)
              .toDouble(),
          ((padded.top * ratio / 16).floor() * 16)
              .clamp(0, original.height)
              .toDouble(),
          ((padded.right * ratio / 16).ceil() * 16)
              .clamp(0, original.width)
              .toDouble(),
          ((padded.bottom * ratio / 16).ceil() * 16)
              .clamp(0, original.height)
              .toDouble(),
        );
        final inputBounds = Rect.fromLTRB(
          sourcePixels.left / ratio,
          sourcePixels.top / ratio,
          sourcePixels.right / ratio,
          sourcePixels.bottom / ratio,
        );
        canvas.save();
        canvas.clipRect(slot, doAntiAlias: false);
        canvas.translate(slot.left, slot.top);
        canvas.scale(ratio);
        canvas.translate(-bounds.left, -bounds.top);
        canvas.drawImageRect(
          original,
          sourcePixels,
          inputBounds,
          Paint()..imageFilter = entry.filter,
        );
        canvas.restore();
      }
      final picture = recorder.endRecording();
      try {
        next = picture.toImageSync(atlasWidth, atlasHeight);
      } finally {
        picture.dispose();
      }
      if (bakeWatch != null) {
        _recordFieldBake(
          bakeWatch,
          ratio,
          original.width,
          original.height,
          atlasWidth,
          atlasHeight,
          targets.length,
        );
      }
      targets.removeWhere((r) => !_users.containsKey(r.filter));
      if (!_disposed &&
          _enabled &&
          identical(source, boundary) &&
          boundary.size == size &&
          boundary.pixelRatio == baseRatio &&
          targets.isNotEmpty) {
        final previous = _atlas;
        _atlas = next;
        next = null;
        _regions = {};
        for (final target in targets) {
          _regions
              .putIfAbsent(target.filter, () => [])
              .add(_MapBackdropRegion(target.bounds, slots[target]!));
        }
        imageLogicalSize = size;
        imagePixelRatio = ratio;
        _captures++;
        _filtersRendered += targets.length;
        _lastCaptureMicros = watch.elapsedMicroseconds;
        _captureMicrosTotal += _lastCaptureMicros;
        _dirty = revision != _revision;
        _imageRevision = revision;
        if (previous != null) _retire([previous]);
      }
    } catch (error) {
      // A failed capture must show live native glass, never an outdated image.
      if (!_disposed) {
        _captureFailure = error.runtimeType.toString();
        final previous = _atlas;
        _atlas = null;
        _regions = {};
        if (previous != null) _retire([previous]);
      }
      debugPrint('Map backdrop capture failed: ${error.runtimeType}');
    } finally {
      original?.dispose();
      next?.dispose();
      _capturing = false;
    }
  }

  static void _retire(Iterable<ui.Image> images) {
    final retired = images.toList();
    if (retired.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final image in retired) {
        image.dispose();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    MapBackdropCacheHost.nativeFiltersForDiagnostics.removeListener(
      _modeChanged,
    );
    MapBackdropCacheHost.mapMotionActive.removeListener(_motionModeChanged);
    UiRuntimeFlags.mapDragGlassModeNotifier.removeListener(
      _motionModeChanged,
    );
    source = null;
    _users.clear();
    _panels.clear();
    final image = _atlas;
    if (image != null) _retire([image]);
    _atlas = null;
    _regions = {};
    super.dispose();
  }
}

/// Same native filter and child when outside a desktop map cache. Rounded
/// clipping, panel alpha, text and borders stay in their original widgets.
class CachedMapBackdropFilter extends BackdropFilter {
  const CachedMapBackdropFilter({super.key, required super.filter, super.child})
    : _grouped = false;
  const CachedMapBackdropFilter.grouped({
    super.key,
    required super.filter,
    super.child,
  }) : _grouped = true,
       super.grouped();
  final bool _grouped;
  @override
  RenderBackdropFilter createRenderObject(BuildContext context) =>
      _CachedMapBackdropRender(
        cache: _MapBackdropScope.of(context),
        filter: filter!,
        backdropKey: _grouped
            ? BackdropGroup.of(context)?.backdropKey
            : backdropGroupKey,
      );
  @override
  void updateRenderObject(
    BuildContext context,
    RenderBackdropFilter renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _CachedMapBackdropRender).configure(
      _MapBackdropScope.of(context),
      filter!,
    );
  }
}

class _CachedMapBackdropRender extends RenderBackdropFilter {
  _CachedMapBackdropRender({
    required _MapBackdropCache? cache,
    required ui.ImageFilter filter,
    super.backdropKey,
  }) : _cache = cache,
       _imageFilter = filter,
       super(filter: filter);
  _MapBackdropCache? _cache;
  ui.ImageFilter _imageFilter;

  void configure(_MapBackdropCache? cache, ui.ImageFilter filter) {
    if (_cache == cache && _imageFilter == filter) return;
    if (attached) _unregister();
    _cache = cache;
    _imageFilter = filter;
    if (attached) _register();
    markNeedsPaint();
  }

  void _register() {
    _cache?._panels.add(this);
    _cache?.addListener(markNeedsPaint);
    MapBackdropCacheHost.mapMotionActive.addListener(markNeedsPaint);
    _cache?.register(_imageFilter);
  }

  void _unregister() {
    _cache?._panels.remove(this);
    _cache?.removeListener(markNeedsPaint);
    MapBackdropCacheHost.mapMotionActive.removeListener(markNeedsPaint);
    _cache?.unregister(_imageFilter);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _register();
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final cache = _cache;
    final source = cache?.source;
    if (!enabled ||
        cache?._enabled != true ||
        source == null ||
        !cache!.canUseMapPixels(this)) {
      if (layer is _SameSceneBackdropLayer) layer = null;
      // "Glass off" motion degradation: draw the panel as plain translucent
      // content; a full-price native blur here would defeat the atlas skip.
      if (MapBackdropCacheHost.mapMotionActive.value &&
          UiRuntimeFlags.mapDragGlassModeNotifier.value ==
              UiRuntimeFlags.mapDragGlassOff) {
        if (child != null) context.paintChild(child!, offset);
        return;
      }
      super.paint(context, offset);
      return;
    }
    final transform = getTransformTo(source);
    final sourceBounds = MatrixUtils.transformRect(
      transform,
      Offset.zero & size,
    );
    if (transform.invert() == 0) {
      if (layer is _SameSceneBackdropLayer) layer = null;
      super.paint(context, offset);
      return;
    }
    final sampled = layer is _SameSceneBackdropLayer
        ? layer! as _SameSceneBackdropLayer
        : _SameSceneBackdropLayer();
    sampled.configure(
      cache,
      _imageFilter,
      backdropKey,
      offset,
      size,
      transform,
      sourceBounds,
    );
    layer = sampled;
    context.pushLayer(sampled, (context, offset) {
      if (child != null) context.paintChild(child!, offset);
    }, offset);
  }
}

/// The map and its followers are submitted in the same scene. A follower must
/// observe nested map repaint boundaries even when its own foreground is
/// retained. It draws the current atlas, never a previous frame's camera.
class _SameSceneBackdropLayer extends BackdropFilterLayer {
  _SameSceneBackdropLayer() {
    _native = _NativeBackdropContents(this);
  }
  late final _NativeBackdropContents _native;
  _MapBackdropCache? _cache;
  ui.ImageFilter? _filter;
  Matrix4? _transform;
  Rect _sourceBounds = Rect.zero;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;
  ui.Picture? _picture;
  ui.Image? _pictureImage;
  ui.ClipRectEngineLayer? _clip;
  bool _geometryChanged = true;

  @override
  bool get alwaysNeedsAddToScene => true;

  bool get _degraded =>
      MapBackdropCacheHost.mapMotionActive.value &&
      UiRuntimeFlags.mapDragGlassModeNotifier.value ==
          UiRuntimeFlags.mapDragGlassOff;

  void configure(
    _MapBackdropCache cache,
    ui.ImageFilter filter,
    BackdropKey? key,
    Offset offset,
    Size size,
    Matrix4 transform,
    Rect sourceBounds,
  ) {
    var sameTransform = _transform != null;
    for (var i = 0; sameTransform && i < 16; i++) {
      sameTransform = _transform!.storage[i] == transform.storage[i];
    }
    final changed =
        _cache != cache ||
        _filter != filter ||
        _offset != offset ||
        _size != size ||
        !sameTransform;
    _cache = cache;
    _filter = filter;
    _offset = offset;
    _size = size;
    _sourceBounds = sourceBounds;
    if (changed) {
      _transform = transform;
      _geometryChanged = true;
      cache.mapPainted();
    }
    _native
      ..filter = _degraded ? null : filter
      ..backdropKey = key;
  }

  void _clearPicture() {
    _picture?.dispose();
    _picture = null;
    _pictureImage = null;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    // Motion degradation: skip the atlas re-bake (map toImageSync + per-panel
    // blur) entirely and draw the panel children directly. The blur returns
    // on the first frame after the motion window settles.
    if (_degraded) {
      _clip?.dispose();
      _clip = null;
      _clearPicture();
      addChildrenToScene(builder);
      return;
    }
    final cache = _cache!;
    cache.ensureCurrentScene();
    final image = cache._atlas;
    final region = cache._regions[_filter]
        ?.where(
          (r) =>
              r.bounds.inflate(.001).contains(_sourceBounds.topLeft) &&
              r.bounds.inflate(.001).contains(_sourceBounds.bottomRight),
        )
        .firstOrNull;
    final slot = region?.slot;
    final bounds = region?.bounds;
    if (image == null || slot == null || bounds == null || !cache._enabled) {
      _clip?.dispose();
      _clip = null;
      _clearPicture();
      _native.addToScene(builder);
      return;
    }
    if (cache._imageRevision != cache._revision) cache._staleSamples++;
    if (!identical(image, _pictureImage) || _geometryChanged) {
      _clearPicture();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(_offset.dx, _offset.dy);
      canvas.transform(_transform!.storage);
      canvas.drawImageRect(
        image,
        slot,
        bounds,
        Paint()..filterQuality = FilterQuality.none,
      );
      _picture = recorder.endRecording();
      _pictureImage = image;
      _geometryChanged = false;
    }
    final nextClip = builder.pushClipRect(
      (_offset & _size).inflate(1),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      oldLayer: _clip,
    );
    _clip?.dispose();
    _clip = nextClip;
    builder.addPicture(Offset.zero, _picture!);
    addChildrenToScene(builder);
    builder.pop();
  }

  @override
  void dispose() {
    _clearPicture();
    _clip?.dispose();
    _clip = null;
    _native.dispose();
    super.dispose();
  }
}

/// Keep the original grouped native filter when the engine cannot supply a
/// map texture. The children remain owned by the actual composition layer.
class _NativeBackdropContents extends BackdropFilterLayer {
  _NativeBackdropContents(this.contents);
  final _SameSceneBackdropLayer contents;
  @override
  void addChildrenToScene(ui.SceneBuilder builder) =>
      contents.addChildrenToScene(builder);
}

int _fieldBakeCount = 0;
int _fieldBakeMicros = 0;
int _fieldBakeMaxMicros = 0;
int _fieldBakeLastReport = 0;

/// Field-log only: aggregates backdrop bakes and reports them once a second.
/// `toImageSync` returns a deferred image, so the measured time is the UI
/// thread cost; the matching raster cost shows up in the heartbeat lines.
void _recordFieldBake(
  Stopwatch watch,
  double ratio,
  int sourceWidth,
  int sourceHeight,
  int atlasWidth,
  int atlasHeight,
  int targets,
) {
  final micros = watch.elapsedMicroseconds;
  _fieldBakeCount++;
  _fieldBakeMicros += micros;
  if (micros > _fieldBakeMaxMicros) _fieldBakeMaxMicros = micros;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - _fieldBakeLastReport < 1000) return;
  _fieldBakeLastReport = now;
  FieldDiagnostics.event('backdrop_bake', {
    'bakes': _fieldBakeCount,
    'avgMs': (_fieldBakeMicros / _fieldBakeCount / 100).round() / 10,
    'maxMs': (_fieldBakeMaxMicros / 100).round() / 10,
    'ratio': ratio,
    'source': '${sourceWidth}x$sourceHeight',
    'atlas': '${atlasWidth}x$atlasHeight',
    'targets': targets,
  });
  _fieldBakeCount = 0;
  _fieldBakeMicros = 0;
  _fieldBakeMaxMicros = 0;
}
