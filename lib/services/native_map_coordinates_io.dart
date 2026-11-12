import 'dart:ffi';
import 'dart:ui' show Offset;
import 'package:flutter_map/flutter_map.dart';
import 'sources/native_station_core_library_io.dart';

void configureNativeMapCoordinates() {
  if (StationCoreLibrary.supported) {
    ProjectedPointsTransform.batch = NativeMapCoordinates.transform;
  }
}

/// Geometry comes from flutter_map's immutable projected/simplified rings.
/// Weak keys tie native ownership to exactly those retained render geometries.
class NativeMapCoordinates {
  static final _cache = Expando<_Geometry>('map-projected-rings');
  static final _bindings = _Bindings();
  static int cacheMisses = 0;
  static int get calls => _bindings.calls();
  static int get sessions => _bindings.sessions();

  static List<Offset> transform(
    List<Offset> points,
    List<List<Offset>>? holes,
    double a,
    double b,
    double c,
    double d,
    double scale,
    double addedWidth,
    double originX,
    double originY,
    double shift,
  ) {
    var geometry = _cache[points];
    if (geometry == null || !identical(geometry.holes, holes)) {
      geometry?.dispose();
      geometry = _Geometry(points, holes);
      _cache[points] = geometry;
      cacheMisses++;
    }
    final p = _parameters.pointer.cast<Double>().asTypedList(9);
    p[0] = a;
    p[1] = b;
    p[2] = c;
    p[3] = d;
    p[4] = scale;
    p[5] = addedWidth;
    p[6] = originX;
    p[7] = originY;
    p[8] = shift;
    final output = _bindings.transform(
      geometry.pointer,
      _parameters.pointer.cast(),
    );
    if (output == nullptr) {
      throw StateError('Native map coordinate transform failed');
    }
    final xy = output.asTypedList(geometry.count * 2);
    // The native view is consumed synchronously; no reusable pointer escapes.
    return List<Offset>.generate(
      geometry.count,
      (i) => Offset(xy[i * 2], xy[i * 2 + 1]),
      growable: true,
    );
  }

  static final _parameters = StationCoreBuffer(9 * 8);
}

final class _Geometry implements Finalizable {
  _Geometry(List<Offset> points, this.holes) {
    count = points.length + (holes?.fold<int>(0, (n, r) => n + r.length) ?? 0);
    if (count > 2000000) throw ArgumentError('Map geometry too large');
    final input = StationCoreBuffer(count * 16);
    try {
      final xy = input.pointer.cast<Double>().asTypedList(count * 2);
      var i = 0;
      void append(List<Offset> ring) {
        for (final p in ring) {
          xy[i++] = p.dx;
          xy[i++] = p.dy;
        }
      }

      append(points);
      for (final ring in holes ?? const <List<Offset>>[]) {
        append(ring);
      }
      pointer = NativeMapCoordinates._bindings.create(
        input.pointer.cast(),
        count,
      );
      if (pointer == nullptr) {
        throw StateError('Cannot create native map geometry');
      }
      _finalizer.attach(this, pointer, detach: this, externalSize: count * 32);
    } finally {
      input.dispose();
    }
  }
  static final _finalizer = NativeFinalizer(
    NativeMapCoordinates._bindings.destroyPointer,
  );
  final List<List<Offset>>? holes;
  late final int count;
  late final Pointer<Void> pointer;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    NativeMapCoordinates._bindings.destroy(pointer);
  }
}

class _Bindings {
  _Bindings() {
    if (_library.lookupFunction<Uint32 Function(), int Function()>(
          'rq_map_coordinates_abi_version',
        )() !=
        1) {
      throw StateError('Unsupported map coordinates ABI');
    }
  }
  final _library = StationCoreLibrary.library;
  late final create = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Double>, Size),
        Pointer<Void> Function(Pointer<Double>, int)
      >('rq_map_coordinates_create');
  late final transform = _library
      .lookupFunction<
        Pointer<Double> Function(Pointer<Void>, Pointer<Double>),
        Pointer<Double> Function(Pointer<Void>, Pointer<Double>)
      >('rq_map_coordinates_transform');
  late final destroy = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('rq_map_coordinates_destroy');
  late final destroyPointer = _library
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_map_coordinates_destroy',
      );
  late final calls = _library.lookupFunction<Uint64 Function(), int Function()>(
    'rq_map_coordinates_calls',
  );
  late final sessions = _library
      .lookupFunction<Uint64 Function(), int Function()>(
        'rq_map_coordinates_sessions',
      );
}
