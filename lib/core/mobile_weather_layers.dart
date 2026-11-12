import 'dart:convert';

// Display-profile keys only. Original source data and global switches stay intact.
const mobileWeatherPreferenceKey = 'mobile_weather_map_layers_v1';
const mobileWeatherStationModeKey = 'mobile_weather_map_station_mode';
const mobileWeatherLayerKeys = <String>{
  'cloudLayer',
  'rainLayer',
  'windLayer',
  'radarChinaLayer',
  'precipitationChinaLayer',
  'jmaRadarLayer',
  'jmaSatelliteCloudLayer',
  'nsmcSatelliteCloudLayer',
  'satelliteCloudLayer',
  'typhoonLayer',
  'weatherStationLayer',
  'weatherAlertLayer',
};
// Stable order for the source-request bitmask ABI.
const hostedWeatherLayerKeys = <String>[
  'radarChinaLayer',
  'precipitationChinaLayer',
  'jmaRadarLayer',
  'jmaSatelliteCloudLayer',
  'nsmcSatelliteCloudLayer',
  'satelliteCloudLayer',
  'typhoonLayer',
];

Map<String, bool> readMobileWeatherLayerValues(String? value) {
  if (value == null) return const {};
  final decoded = jsonDecode(value);
  if (decoded is! Map)
    throw const FormatException('Invalid mobile weather layer settings');
  return {
    for (final key in mobileWeatherLayerKeys)
      if (decoded[key] is bool) key: decoded[key] as bool,
  };
}
