import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'cea_eew_event_id_portable.dart' as portable;
import 'sources/native_station_core_library_io.dart';

final _isCeaAgencyEventId = StationCoreLibrary.library
    .lookupFunction<
      Uint32 Function(Pointer<Utf8>, Size),
      int Function(Pointer<Utf8>, int)
    >('rq_cea_eew_is_agency_event_id');

bool isCeaAgencyEventId(String id) {
  if (id.length != 17) return false;
  if (!StationCoreLibrary.supported) return portable.isCeaAgencyEventId(id);
  return using((arena) {
    final value = id.toNativeUtf8(allocator: arena);
    return _isCeaAgencyEventId(value, value.length) != 0;
  });
}
