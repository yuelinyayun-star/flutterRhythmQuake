import 'dart:ffi';
import 'native_station_core_library_io.dart';
import 'dart:typed_data';

typedef _DecodeNative =
    Int32 Function(
      Pointer<Uint8>,
      Size,
      Pointer<Int64>,
      Size,
      Pointer<Uint64>,
      Pointer<Uint32>,
    );
typedef _Decode =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Int64>,
      int,
      Pointer<Uint64>,
      Pointer<Uint32>,
    );

class NativeStationImageFrame {
  const NativeStationImageFrame(this.width, this.height, this.pixels);
  final int width;
  final int height;
  // Owned Dart copy: no view survives reuse or disposal of native buffers.
  final Uint64List pixels;
}

class NativeNiedImageFrame {
  const NativeNiedImageFrame(this.width, this.height, this.values);
  final int width, height;
  // Independent rows [color position / NaN, shindo / NaN, quality 0..3].
  final Float64List values;
}

/// Called synchronously inside the existing persistent NIED worker isolate.
/// Windows packages the DLL through CMake; Android packages the same Rust
/// backend as an ABI-specific shared library in the APK.
class NativeStationImageDecoder {
  NativeStationImageDecoder(List<int> coordinates)
    : _count = coordinates.length ~/ 2 {
    if (!supported) {
      throw UnsupportedError(
        'Rust station decoder requires a supported native backend',
      );
    }
    if (coordinates.length.isOdd || _count > 1024 * 1024) {
      throw ArgumentError('Invalid station coordinate array');
    }
    _bindings; // Resolve and check ABI before allocating any buffers.
    _coordinates = StationCoreBuffer(coordinates.length * 8);
    _coordinates.pointer
        .cast<Int64>()
        .asTypedList(coordinates.length)
        .setAll(0, coordinates);
    _result = StationCoreBuffer(_count * 8);
    _dimensions = StationCoreBuffer(8);
  }

  // Flutter unit tests explicitly opt in with the verified library path.
  // A packaged Windows APP always requires the bundled DLL; load/ABI failures
  // are errors, never an availability probe that silently selects Dart.
  static bool get supported => StationCoreLibrary.supported;
  static final _Bindings _bindings = _Bindings();
  static Map<String, int> get memoryStats => {
    'rustCurrentBytes': _bindings.current(),
    'rustPeakBytes': _bindings.peak(),
    'decodeCalls': _bindings.calls(),
  };

  final int _count;
  late final StationCoreBuffer _coordinates;
  late final StationCoreBuffer _result;
  late final StationCoreBuffer _dimensions;
  StationCoreBuffer? _input;
  StationCoreBuffer? _niedOutput;
  bool _disposed = false;
  int get bufferCapacityBytes => _disposed
      ? 0
      : _coordinates.length +
            _result.length +
            _dimensions.length +
            (_input?.length ?? 0) +
            (_niedOutput?.length ?? 0);

  NativeNiedImageFrame sampleNied(Uint8List bytes, {bool physical = false}) {
    final frame = decode(bytes);
    _niedOutput ??= StationCoreBuffer(_count * 24);
    final status = _bindings.sampleNied(
      _result.pointer.cast(),
      _count,
      physical ? 1 : 0,
      _niedOutput!.pointer.cast(),
    );
    if (status != 0) {
      throw StateError('Rust NIED GIF sample failed (status $status)');
    }
    return NativeNiedImageFrame(
      frame.width,
      frame.height,
      Float64List.fromList(
        _niedOutput!.pointer.cast<Double>().asTypedList(_count * 3),
      ),
    );
  }

  NativeStationImageFrame decode(Uint8List bytes) {
    if (_disposed) throw StateError('Rust station decoder is disposed');
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('Station image is empty or exceeds 8 MiB');
    }
    if (_input == null || _input!.length < bytes.length) {
      _input?.dispose();
      _input = StationCoreBuffer(bytes.length);
    }
    _input!.pointer.asTypedList(bytes.length).setAll(0, bytes);
    final status = _bindings.decode(
      _input!.pointer,
      bytes.length,
      _coordinates.pointer.cast(),
      _count,
      _result.pointer.cast(),
      _dimensions.pointer.cast(),
    );
    if (status != 0) {
      throw FormatException(
        'Rust station image decode failed (status $status)',
      );
    }
    final dimensions = _dimensions.pointer.cast<Uint32>().asTypedList(2);
    return NativeStationImageFrame(
      dimensions[0],
      dimensions[1],
      Uint64List.fromList(_result.pointer.cast<Uint64>().asTypedList(_count)),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _input?.dispose();
    _niedOutput?.dispose();
    _input = null;
    _coordinates.dispose();
    _result.dispose();
    _dimensions.dispose();
  }
}

class _Bindings {
  late final sampleNied = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Uint64>, Size, Uint8, Pointer<Double>),
        int Function(Pointer<Uint64>, int, int, Pointer<Double>)
      >('rq_nied_gif_sample_rgba');
  _Bindings() {
    final library = StationCoreLibrary.library;
    decode = library.lookupFunction<_DecodeNative, _Decode>(
      'rq_station_decode_sample',
    );
    current = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_memory_current',
    );
    peak = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_memory_peak',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_decode_calls',
    );
  }
  late final _Decode decode;
  late final int Function() current, peak, calls;
}
