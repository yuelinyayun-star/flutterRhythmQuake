import 'package:flutter/material.dart';

import '../../services/sources/china_weather_hourly_service.dart';
import 'china_weather_hourly_panel.dart';
import 'mobile_weather_home.dart';

/// A read-only view of the same observation used by the weather home.
class WeatherStatusEntry extends StatelessWidget {
  const WeatherStatusEntry({
    super.key,
    required this.state,
    required this.onPressed,
    this.stationTemperature,
    this.scale = 1,
  });
  final ChinaWeatherHourlyState state;
  final VoidCallback onPressed;
  final double? stationTemperature;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final current = state.current;
    final code = current?.weatherCode ?? '';
    final background = mobileWeatherBackground(code);
    final temperature =
        chinaWeatherTemperature(current?.raw['temp']?.toString() ?? '') ??
        chinaWeatherTemperature(stationTemperature?.toString() ?? '');
    final condition = current?.weather.trim();
    final label =
        '${condition == null || condition.isEmpty ? '天气' : condition} '
        '${temperature?.toStringAsFixed(0) ?? '—'}℃';
    final icon = switch (background) {
      'clear_night' => Icons.nightlight_round,
      'fog' => Icons.foggy,
      null => Icons.cloud_queue_rounded,
      _ => chinaWeatherIcon(code.replaceFirst(RegExp(r'^[dn]'), '')),
    };
    return Tooltip(
      message: '打开天气首页 · $label',
      child: TextButton.icon(
        key: const ValueKey('desktop-weather-entry'),
        onPressed: onPressed,
        icon: Icon(icon, size: 18 * scale, color: const Color(0xFFFFDF9B)),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: .85),
          textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 12 * scale,
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(0, 32 * scale),
          padding: EdgeInsets.symmetric(horizontal: 8 * scale),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
