import 'dart:ffi';

import 'sources/native_station_core_library_io.dart';

final _select = StationCoreLibrary.library
    .lookupFunction<
      Uint32 Function(Pointer<Uint32>, Size),
      int Function(Pointer<Uint32>, int)
    >('rq_background_api_select');

int selectNativeBackgroundApis(List<int> rows) {
  final buffer = StationCoreBuffer(rows.length * sizeOf<Uint32>());
  try {
    final input = buffer.pointer.cast<Uint32>();
    input.asTypedList(rows.length).setAll(0, rows);
    return _select(input, rows.length ~/ 3);
  } finally {
    buffer.dispose();
  }
}
