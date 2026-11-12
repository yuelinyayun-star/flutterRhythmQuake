import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../../widgets/ui/map_backdrop_cache.dart';

enum ProbePainting {
  all,
  withoutBasemap,
  withoutRadar,
  withoutStations,
  withoutNiedStations,
  withoutSnetStations,
  withoutKmaStations,
  withoutTyphoon,
  withoutInference,
  withoutBlur,
  separateBlur,
  nativeBlur,
  overlays,
  none,
}

typedef ProbeCamera = ({
  double latitude,
  double longitude,
  double zoom,
  bool autoFollow,
});

/// Explicit loopback diagnostics only. Painting can be omitted while the same
/// mounted widgets, original ingress and inference workers continue running.
class RuntimeRenderingProbe {
  static final painting = ValueNotifier(ProbePainting.all);
  static Object? _owner;
  static ProbeCamera Function()? _read;
  static void Function(ProbeCamera)? _move;
  static void Function(ProbeCamera)? _restore;
  static ProbeCamera? _saved;
  static Timer? _backdropScan;
  static final _backdrops =
      <RenderBackdropFilter, ({bool enabled, BackdropKey? key})>{};
  static bool _timingAttached = false;
  static int _frames = 0, _buildMicros = 0, _rasterMicros = 0;

  static void _recordTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frames++;
      _buildMicros += timing.buildDuration.inMicroseconds;
      _rasterMicros += timing.rasterDuration.inMicroseconds;
    }
  }

  static bool get cameraFrozen => _saved != null;

  static void bind(
    Object owner, {
    required ProbeCamera Function() read,
    required void Function(ProbeCamera) move,
    required void Function(ProbeCamera) restore,
  }) {
    _owner = owner;
    _read = read;
    _move = move;
    _restore = restore;
    _saved = null;
  }

  static void unbind(Object owner) {
    if (!identical(owner, _owner)) return;
    MapBackdropCacheHost.nativeFiltersForDiagnostics.value = false;
    _restoreBackdrops();
    _stopTimings();
    _owner = null;
    _read = null;
    _move = null;
    _restore = null;
    _saved = null;
    painting.value = ProbePainting.all;
  }

  static Map<String, Object?> get state {
    final camera = _read?.call();
    return {
      'painting': painting.value.name,
      'cameraFrozen': _saved != null,
      'isolatedBackdrops': _backdrops.length,
      'frames': _frames,
      'buildMicros': _buildMicros,
      'rasterMicros': _rasterMicros,
      'backdropCache': MapBackdropCacheHost.diagnostics,
      'backdrops': _describeBackdrops(),
      if (camera != null)
        'camera': {
          'latitude': camera.latitude,
          'longitude': camera.longitude,
          'zoom': camera.zoom,
          'autoFollow': camera.autoFollow,
        },
    };
  }

  static Map<String, Object?> configure(Map<String, dynamic> body) {
    if (body['reset'] == true) {
      reset();
      return state;
    }
    final mode = body['painting'];
    final selected = mode == null
        ? painting.value
        : ProbePainting.values.where((v) => v.name == mode).firstOrNull;
    if (selected == null) {
      throw FormatException(
        'painting: ${ProbePainting.values.map((v) => v.name).join('/')}',
      );
    }
    final freeze = body['freezeCamera'];
    ProbeCamera? target;
    if (freeze != null) {
      if (freeze is! Map) {
        throw const FormatException('freezeCamera must be an object');
      }
      double value(String key, double min, double max) {
        final v = freeze[key];
        if (v is! num || !v.toDouble().isFinite || v < min || v > max) {
          throw FormatException('Invalid camera $key');
        }
        return v.toDouble();
      }

      target = (
        latitude: value('latitude', -85, 85),
        longitude: value('longitude', -180, 180),
        zoom: value('zoom', 3, 18),
        autoFollow: false,
      );
      if (_read == null || _move == null) throw StateError('Map is not ready');
    }
    if (target != null) {
      _saved ??= _read!();
      _move!(target);
    }
    if (!_timingAttached) {
      _frames = _buildMicros = _rasterMicros = 0;
      SchedulerBinding.instance.addTimingsCallback(_recordTimings);
      _timingAttached = true;
    }
    painting.value = selected;
    MapBackdropCacheHost.nativeFiltersForDiagnostics.value =
        selected == ProbePainting.nativeBlur ||
        selected == ProbePainting.withoutBlur ||
        selected == ProbePainting.overlays ||
        selected == ProbePainting.none;
    _restoreBackdrops();
    if (selected == ProbePainting.withoutBlur ||
        selected == ProbePainting.separateBlur) {
      _isolateBackdrops();
      _backdropScan = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _isolateBackdrops(),
      );
    }
    return state;
  }

  static void _isolateBackdrops() {
    void visit(RenderObject node) {
      if (node is RenderBackdropFilter) {
        _backdrops.putIfAbsent(
          node,
          () => (enabled: node.enabled, key: node.backdropKey),
        );
        if (painting.value == ProbePainting.withoutBlur) node.enabled = false;
        if (painting.value == ProbePainting.separateBlur) {
          node.backdropKey = null;
        }
      }
      node.visitChildren(visit);
    }

    for (final view in RendererBinding.instance.renderViews) {
      visit(view);
    }
  }

  static void _restoreBackdrops() {
    _backdropScan?.cancel();
    _backdropScan = null;
    for (final entry in _backdrops.entries) {
      if (entry.key.attached) {
        entry.key.enabled = entry.value.enabled;
        entry.key.backdropKey = entry.value.key;
      }
    }
    _backdrops.clear();
  }

  static List<Map<String, Object?>> _describeBackdrops() {
    final result = <Map<String, Object?>>[];
    void visit(RenderObject node) {
      if (node is RenderBackdropFilter && node.hasSize) {
        final origin = node.localToGlobal(Offset.zero);
        result.add({
          'filter': node.filterConfig.toString(),
          'x': origin.dx,
          'y': origin.dy,
          'width': node.size.width,
          'height': node.size.height,
          'enabled': node.enabled,
          'group': node.backdropKey?.hashCode,
        });
      }
      node.visitChildren(visit);
    }

    for (final view in RendererBinding.instance.renderViews) {
      visit(view);
    }
    return result;
  }

  static void reset() {
    MapBackdropCacheHost.nativeFiltersForDiagnostics.value = false;
    _restoreBackdrops();
    _stopTimings();
    painting.value = ProbePainting.all;
    final saved = _saved;
    _saved = null;
    if (saved != null) _restore?.call(saved);
  }

  static void _stopTimings() {
    if (_timingAttached) {
      SchedulerBinding.instance.removeTimingsCallback(_recordTimings);
      _timingAttached = false;
    }
  }
}

class RuntimePaintGate extends StatelessWidget {
  const RuntimePaintGate({
    super.key,
    required this.mapOnly,
    this.basemapOnly = false,
    this.hideWhen,
    this.additionalHideWhen,
    required this.child,
  });
  final bool mapOnly;
  final bool basemapOnly;
  final ProbePainting? hideWhen;
  final ProbePainting? additionalHideWhen;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ProbePainting>(
    valueListenable: RuntimeRenderingProbe.painting,
    child: child,
    builder: (_, mode, child) => Offstage(
      offstage:
          mode == ProbePainting.none ||
          mode == hideWhen ||
          mode == additionalHideWhen ||
          (mapOnly && mode == ProbePainting.overlays) ||
          (basemapOnly && mode == ProbePainting.withoutBasemap),
      child: child,
    ),
  );
}
