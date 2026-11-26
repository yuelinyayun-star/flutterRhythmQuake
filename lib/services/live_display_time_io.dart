import 'dart:ffi';

import 'live_display_time_portable.dart' as portable;
import 'sources/native_station_core_library_io.dart';

final _elapsed = StationCoreLibrary.library
    .lookupFunction<Int64 Function(), int Function()>(
      'rq_live_display_elapsed_us',
      isLeaf: true,
    );

final _lifetime = StationCoreLibrary.library
    .lookupFunction<Int64 Function(Uint8), int Function(int)>(
      'rq_live_display_lifetime_us',
      isLeaf: true,
    );

int liveDisplayElapsedUs() =>
    StationCoreLibrary.supported ? _elapsed() : portable.liveDisplayElapsedUs();

int liveDisplayLifetimeUs(int kind) => StationCoreLibrary.supported
    ? _lifetime(kind)
    : portable.liveDisplayLifetimeUs(kind);
