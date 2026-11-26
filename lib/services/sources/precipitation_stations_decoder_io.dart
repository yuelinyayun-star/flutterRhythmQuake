import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_station_core_library_io.dart';
import 'precipitation_stations_decoder_portable.dart' as portable;

final _parse = StationCoreLibrary.library
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Size, Uint64, Pointer<Double>, Size),
      int Function(Pointer<Uint8>, int, int, Pointer<Double>, int)
    >('rq_weather_precipitation_stations');

Float64List? decodePrecipitationStations(Uint8List bytes, int stamp) {
  if (!StationCoreLibrary.supported) {
    return portable.decodePrecipitationStations(bytes, stamp);
  }
  if (bytes.length > 512 * 1024) return null;
  return using((arena) {
    final input = arena<Uint8>(bytes.length)
      ..asTypedList(bytes.length).setAll(0, bytes);
    const capacity = 4096 * 3;
    final output = arena<Double>(capacity);
    final count = _parse(input, bytes.length, stamp, output, capacity);
    return count < 0
        ? null
        : Float64List.fromList(output.asTypedList(count * 3));
  });
}
