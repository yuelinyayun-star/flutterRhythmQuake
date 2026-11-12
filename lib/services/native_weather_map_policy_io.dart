import 'dart:ffi';
import 'sources/native_station_core_library_io.dart';
import 'native_weather_map_policy_portable.dart' as portable;

abstract final class NativeWeatherMapPolicy {
  static bool get supported => StationCoreLibrary.supported;
  static final _required = StationCoreLibrary.library
      .lookupFunction<Uint32 Function(Uint32, Uint32), int Function(int, int)>(
        'rq_weather_map_required_sources',
      );
  static int requiredSources(int general, int mobile) => supported
      ? _required(general, mobile)
      : portable.NativeWeatherMapPolicy.requiredSources(general, mobile);
}
