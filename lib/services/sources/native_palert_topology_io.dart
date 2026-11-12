import 'dart:ffi';
import 'native_station_core_library_io.dart';

class NativePAlertTopology {
  // An already running process may still have the previous DLL loaded.
  static bool get supported =>
      StationCoreLibrary.supported &&
      StationCoreLibrary.library.providesSymbol('rq_palert_topology');
  static final _build = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Double>, Size, Pointer<Uint32>),
        int Function(Pointer<Double>, int, Pointer<Uint32>)
      >('rq_palert_topology');

  static List<List<int>> build(List<double> coordinates) {
    if (coordinates.length.isOdd) {
      throw ArgumentError('Invalid P-Alert coordinates');
    }
    final count = coordinates.length ~/ 2;
    if (count == 0) return const [];
    final input = StationCoreBuffer(coordinates.length * 8);
    final output = StationCoreBuffer(count * 12 * 4);
    try {
      input.pointer
          .cast<Double>()
          .asTypedList(coordinates.length)
          .setAll(0, coordinates);
      final status = _build(input.pointer.cast(), count, output.pointer.cast());
      if (status != 0) {
        throw StateError('P-Alert topology failed (status $status)');
      }
      final indices = output.pointer.cast<Uint32>().asTypedList(count * 12);
      return [
        for (var i = 0; i < count; i++)
          [
            for (var j = i * 12; j < (i + 1) * 12; j++)
              if (indices[j] != 0xffffffff) indices[j],
          ],
      ];
    } finally {
      input.dispose();
      output.dispose();
    }
  }
}
