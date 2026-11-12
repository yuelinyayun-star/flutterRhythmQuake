import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';
import 'native_nsmc_image_portable.dart' as portable;

abstract final class NativeNsmcImage {
  static bool get supported => StationCoreLibrary.supported;
  static final _bounds = StationCoreLibrary.library
      .lookupFunction<
        Uint32 Function(Int32, Int32, Int32, Pointer<Double>),
        int Function(int, int, int, Pointer<Double>)
      >('rq_nsmc_tile_bounds');
  static final _project = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(
          Pointer<Uint8>,
          Size,
          Int32,
          Int32,
          Pointer<Size>,
        ),
        Pointer<Uint8> Function(Pointer<Uint8>, int, int, int, Pointer<Size>)
      >('rq_nsmc_project');
  static final _free = StationCoreLibrary.library
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_nsmc_project_free');
  static List<double> bounds(int z, int x, int y) {
    if (!supported) return portable.NativeNsmcImage.bounds(z, x, y);
    return using((arena) {
      final out = arena<Double>(4);
      if (_bounds(z, x, y, out) != 0)
        throw const FormatException('Invalid cloud tile');
      return out.asTypedList(4).toList();
    });
  }

  static Uint8List project(Uint8List bytes, {int z = -1, int y = 0}) {
    if (!supported) return portable.NativeNsmcImage.project(bytes, z: z, y: y);
    return using((arena) {
      final input = arena<Uint8>(bytes.length)
        ..asTypedList(bytes.length).setAll(0, bytes);
      final size = arena<Size>();
      final out = _project(input, bytes.length, z, y, size);
      if (out == nullptr)
        throw const FormatException('Invalid NSMC cloud image');
      try {
        return Uint8List.fromList(out.asTypedList(size.value));
      } finally {
        _free(out, size.value);
      }
    });
  }
}
