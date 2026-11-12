import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';
import '../../services/sources/native_station_core_library_io.dart';

typedef _GeometryNative =
    Int32 Function(Pointer<Double>, Size, Double, Pointer<Double>);
typedef _Geometry = int Function(Pointer<Double>, int, double, Pointer<Double>);

/// Reused for one ordered candidate search; disposed before the search returns.
/// The numerical kernel keeps no pointers or station state after each call.
class NativeHypGeometry {
  NativeHypGeometry(List<double> coordinates)
    : _count = coordinates.length ~/ 2,
      _coordinates = Float64List.fromList(coordinates) {
    if (!supported) {
      throw UnsupportedError('Native HYP geometry requires Windows');
    }
    if (coordinates.length.isOdd || _count > 1024 * 1024) {
      throw ArgumentError('Invalid original HYP coordinate array');
    }
    _bindings;
    final input = StationCoreBuffer(_count * 8);
    try {
      _output = StationCoreBuffer(_count * 3 * 8);
      _input = input;
    } catch (_) {
      input.dispose();
      rethrow;
    }
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _Bindings _bindings = _Bindings();
  static int get calls => _bindings.calls();
  final int _count;
  final Float64List _coordinates;
  late final StationCoreBuffer _input, _output;
  bool _disposed = false;

  Float64List evaluate(double latitude, double longitude, double depthKm) {
    if (_disposed) throw StateError('HYP geometry buffers are disposed');
    // Keep Dart's original trigonometry: Windows Rust/libm differed by one
    // ULP on the original catalogue. Only the exact interpolation moves here.
    final distances = _input.pointer.cast<Double>().asTypedList(_count);
    writeHypDistances(latitude, longitude, _coordinates, distances);
    final status = _bindings.evaluate(
      _input.pointer.cast(),
      _count,
      depthKm,
      _output.pointer.cast(),
    );
    if (status != 0) throw StateError('HYP geometry failed (status $status)');
    // An owned copy cannot change when the next candidate reuses FFI buffers.
    return Float64List.fromList(
      _output.pointer.cast<Double>().asTypedList(_count * 3),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _input.dispose();
    _output.dispose();
  }
}

class _Bindings {
  _Bindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_hyp_geometry_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported HYP geometry ABI: $version');
    }
    evaluate = library.lookupFunction<_GeometryNative, _Geometry>(
      'rq_hyp_geometry',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_hyp_geometry_calls',
    );
  }
  late final _Geometry evaluate;
  late final int Function() calls;
}

/// Keep original Dart trigonometry and operation order for both native kernels.
void writeHypDistances(
  double latitude,
  double longitude,
  Float64List coordinates,
  Float64List output,
) {
  double radians(double value) => value * math.pi / 180.0;
  for (var i = 0; i < coordinates.length ~/ 2; i++) {
    final lat = coordinates[i * 2], lng = coordinates[i * 2 + 1];
    final a =
        math.pow(math.sin(radians(lat - latitude) / 2), 2) +
        math.cos(radians(latitude)) *
            math.cos(radians(lat)) *
            math.pow(math.sin(radians(lng - longitude) / 2), 2);
    output[i] = 6371.0088 * (2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)));
  }
}
