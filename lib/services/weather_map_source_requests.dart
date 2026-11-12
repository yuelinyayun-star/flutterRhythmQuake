import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../core/mobile_weather_layers.dart';
import 'native_weather_map_policy.dart';

Set<String> requiredWeatherMapSources(SharedPreferences prefs) {
  var general = 0, mobile = 0;
  Map<String, bool> mobileLayers;
  try {
    mobileLayers = readMobileWeatherLayerValues(
      prefs.getString(mobileWeatherPreferenceKey),
    );
  } on FormatException {
    debugPrint(
      'Invalid mobile weather layer settings; global source requests are preserved.',
    );
    mobileLayers = const {};
  }
  for (var index = 0; index < hostedWeatherLayerKeys.length; index++) {
    final key = hostedWeatherLayerKeys[index];
    if (prefs.getBool('map_overlay_$key') ?? false) general |= 1 << index;
    if (mobileLayers[key] ?? false) mobile |= 1 << index;
  }
  final requested = NativeWeatherMapPolicy.requiredSources(general, mobile);
  return {
    for (var index = 0; index < hostedWeatherLayerKeys.length; index++)
      if (requested & (1 << index) != 0) hostedWeatherLayerKeys[index],
  };
}
