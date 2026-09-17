import 'package:flutter/foundation.dart';

/// Only explicitly supported station settings can bypass a full source reload.
/// Unknown settings still take the existing full reload path.
class BackgroundSourceReloadPlan {
  BackgroundSourceReloadPlan(
    Map<String, Object> before,
    Map<String, Object> after,
  ) {
    for (final key in {...before.keys, ...after.keys}) {
      if (runtimeKeys.contains(key)) continue;
      final left = before[key];
      final right = after[key];
      final equal = left is List && right is List
          ? listEquals(left, right)
          : left == right;
      if (equal) continue;
      final station = stationKeys[key];
      if (station == null) {
        requiresFullReload = true;
      } else {
        stations.add(station);
      }
    }
  }

  bool requiresFullReload = false;
  final Set<String> stations = {};

  static const runtimeKeys = {
    // These are outputs/caches, not inputs to a connection. A fresh login
    // explicitly forces credential reload even if the profile is unchanged.
    'wauth_user_info',
    'unified_eew_history',
    'map_preferred_view_mode',
    'cma_weather_anchor_lat',
    'cma_weather_anchor_lng',
    'cma_weather_station_id',
    'cma_weather_station_name',
    'cma_weather_station_lat',
    'cma_weather_station_lng',
    'seen_usgs_info_body_keys',
    'seen_emsc_info_body_keys',
    'seen_cwa_info_body_keys',
    'seen_no_update_info_events',
    'background_seen_unified_info_events',
    'background_accepted_eew_report_nums',
    'jian_retry_after_ms',
  };

  static const stationKeys = {
    'nied_data_source': 'nied',
    'api_source_nied_monitor_enabled': 'nied',
    'kma_data_source': 'kma',
    'api_source_kma_pews_enabled': 'kma',
    'snet_data_source': 'snet',
    'api_source_snet_enabled': 'snet',
    'trem_station_enabled': 'trem',
    'api_source_wolfx_seisjs_enabled': 'seisjs',
    'api_source_palert_enabled': 'palert',
  };
}
