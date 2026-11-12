import 'package:flutter/material.dart';

import '../../services/sources/china_weather_hourly_service.dart';
import 'china_weather_hourly_panel.dart';
import 'mobile_weather_home.dart';
import 'mobile_weather_home_details.dart';
import 'weather_marquee.dart';

/// Keeps the one map mounted while the desktop weather workspace is open.
class DesktopWeatherWorkspace extends StatelessWidget {
  const DesktopWeatherWorkspace({
    super.key,
    required this.active,
    required this.mapVisible,
    required this.map,
    this.weather,
  });
  final bool active, mapVisible;
  final Widget map;
  final Widget? weather;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: active && !mapVisible,
        child: TickerMode(enabled: !active || mapVisible, child: map),
      ),
      if (active && weather != null) Positioned.fill(child: weather!),
    ],
  );
}

/// Desktop layout for the existing weather home, without mobile navigation.
class DesktopWeatherHome extends StatelessWidget {
  const DesktopWeatherHome({
    super.key,
    required this.state,
    required this.station,
    required this.onBack,
    required this.onMap,
    required this.onLocate,
    required this.onLayers,
    this.stationTemperature,
    this.stationLabel = '',
    this.locationLabel = '',
    this.feelsLike,
    this.details = const SizedBox.shrink(),
    this.advice = const SizedBox.shrink(),
    this.forecastMessage,
    this.sourceText,
    this.now,
  });
  final ChinaWeatherHourlyState state;
  final Widget station, details, advice;
  final VoidCallback onBack, onMap, onLocate, onLayers;
  final double? stationTemperature, feelsLike;
  final String stationLabel, locationLabel;
  final String? forecastMessage, sourceText;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final current = state.current;
    final city = current?.cityName.isNotEmpty == true
        ? current!.cityName
        : state.areaName.isNotEmpty
        ? state.areaName
        : locationLabel;
    final cityTemperature = chinaWeatherTemperature(
      current?.raw['temp']?.toString() ?? '',
    );
    final temperature =
        cityTemperature ??
        chinaWeatherTemperature(stationTemperature?.toString() ?? '');
    final today = state.outlook?.today(now ?? DateTime.now());
    final high = chinaWeatherTemperature(today?.high ?? '');
    final low = chinaWeatherTemperature(today?.low ?? '');
    final background = mobileWeatherBackground(current?.weatherCode ?? '');
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          city.isEmpty ? '等待定位信息' : city,
          key: const ValueKey('weather-home-city'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
        ),
        Text(
          '${temperature?.toStringAsFixed(0) ?? '—'}°',
          key: const ValueKey('weather-home-temperature'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'MPLUSRounded1c',
            fontSize: 104,
            height: 1.25,
            letterSpacing: -5,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          current?.weather ??
              (state.loading || state.currentLoading
                  ? '正在获取天气状况…'
                  : '天气状况暂不可用'),
          key: const ValueKey('weather-home-condition'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22),
        ),
        const SizedBox(height: 12),
        Text(
          [
            if (high != null) '最高 ${high.toStringAsFixed(0)}°',
            if (low != null) '最低 ${low.toStringAsFixed(0)}°',
            if (feelsLike != null &&
                feelsLike!.isFinite &&
                feelsLike!.abs() < 100)
              '体感 ${feelsLike!.toStringAsFixed(0)}°',
          ].join('  '),
          textAlign: TextAlign.center,
        ),
        if (current != null && weatherAqiText(current) != '—') ...[
          const SizedBox(height: 14),
          Text(
            '空气质量 ${weatherAqiText(current)}',
            textAlign: TextAlign.center,
            style: TextStyle(color: weatherAqiColor(current)),
          ),
        ],
        const SizedBox(height: 14),
        if (current != null)
          Text(
            '${current.date} ${current.time} 更新 · UTC+8',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        if (cityTemperature == null &&
            temperature != null &&
            stationLabel.isNotEmpty)
          Text(
            '$stationLabel · 气象站实况',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
      ],
    );
    final stationCard = WeatherGlassCard(
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.sensors_rounded, size: 18, color: Colors.white70),
              SizedBox(width: 8),
              Text('附近气象站', style: TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 14),
          station,
        ],
      ),
    );
    final forecast = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WeatherMarquee(),
        advice,
        WeatherGlassCard(
          blur: false,
          child: forecastMessage != null
              ? Text(
                  forecastMessage!,
                  style: const TextStyle(color: Colors.white70),
                )
              : ChinaWeatherHourlyPanel(
                  state: state,
                  now: now,
                  showChart: true,
                  showSource: false,
                  showTopDivider: false,
                ),
        ),
        if (details is! SizedBox) ...[
          const SizedBox(height: 18),
          WeatherGlassCard(blur: false, child: details),
        ],
      ],
    );
    final safe = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: const Color(0xFF202D40),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (background != null)
            RepaintBoundary(
              child: Image.asset(
                'assets/images/weather/$background.png',
                key: ValueKey('weather-background-$background'),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                cacheWidth: 1600,
                gaplessPlayback: true,
              ),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x35101B2D), Color(0xA6142033)],
                ),
              ),
            ),
          ),
          // Pre-baked blur of the static weather backdrop: glass cards below
          // use plain translucent fills (blur: false) so scrolling costs zero
          // BackdropFilter passes while staying visually identical.
          if (background != null)
            Positioned.fill(
              child: WeatherFrozenBackdrop(
                asset: background,
                alignment: Alignment.center,
                decodeWidth: 1600,
              ),
            ),
          SafeArea(
            child: DefaultTextStyle(
              style:
                  (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        TextButton.icon(
                          key: const ValueKey('desktop-weather-back'),
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back_rounded, size: 21),
                          label: const Text('返回地震'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            '当地天气',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onLocate,
                          tooltip: '回到所在地',
                          icon: const Icon(
                            Icons.my_location_rounded,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: onLayers,
                          tooltip: '气象图层与预警设置',
                          icon: const Icon(
                            Icons.tune_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          key: const ValueKey('weather-home-open-map'),
                          onPressed: onMap,
                          icon: const Icon(Icons.map_outlined, size: 21),
                          label: const Text('气象地图'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: BackdropGroup(
                      child: SingleChildScrollView(
                        key: const PageStorageKey(
                          'desktop-weather-home-scroll',
                        ),
                        padding: EdgeInsets.fromLTRB(
                          28,
                          20,
                          28,
                          safe.bottom + 28,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1320),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final left = Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 24),
                                    summary,
                                    const SizedBox(height: 32),
                                    stationCard,
                                    if (sourceText != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 18),
                                        child: Text(
                                          sourceText!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                                return constraints.maxWidth >= 900
                                    ? Row(
                                        key: const ValueKey(
                                          'desktop-weather-columns',
                                        ),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(width: 340, child: left),
                                          const SizedBox(width: 28),
                                          Expanded(child: forecast),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          left,
                                          const SizedBox(height: 24),
                                          forecast,
                                        ],
                                      );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
