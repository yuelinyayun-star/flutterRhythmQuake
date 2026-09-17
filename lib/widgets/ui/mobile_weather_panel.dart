import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/sources/cma_local_weather_service.dart';
import '../../services/sources/china_weather_hourly_service.dart';
import 'china_weather_hourly_panel.dart';
import 'weather_marquee.dart';
import 'mobile_weather_home_details.dart';

/// One clipped glass surface; the uncovered map keeps receiving gestures.
class MobileWeatherPanel extends StatefulWidget {
  const MobileWeatherPanel({
    super.key,
    required this.forecast,
    required this.station,
    required this.onLayers,
    required this.onLocate,
    this.current,
    this.conditions = const SizedBox.shrink(),
    this.details = const SizedBox.shrink(),
    this.advice = const SizedBox.shrink(),
    this.sourceText,
  });

  final Widget forecast;
  final Widget station;
  final VoidCallback onLayers;
  final VoidCallback onLocate;
  final CmaLocalWeatherObservation? current;
  final Widget conditions;
  final Widget details;
  final Widget advice;
  final String? sourceText;

  @override
  State<MobileWeatherPanel> createState() => _MobileWeatherPanelState();
}

class _MobileWeatherPanelState extends State<MobileWeatherPanel> {
  double _fraction = .53;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 74,
        12,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  key: const ValueKey('mobile-weather-panel'),
                  height: constraints.maxHeight * _fraction,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Material(
                        color: const Color(0xA61C2328),
                        child: Column(
                          children: [
                            GestureDetector(
                              key: const ValueKey('mobile-weather-grip'),
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragUpdate: (details) => setState(() {
                                _fraction =
                                    (_fraction -
                                            details.delta.dy /
                                                constraints.maxHeight)
                                        .clamp(.23, .92);
                              }),
                              child: SizedBox(
                                height: 24,
                                child: Center(
                                  child: Container(
                                    width: 42,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white38,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                key: const PageStorageKey(
                                  'mobile-weather-content',
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  0,
                                  14,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '当地天气',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '回到所在地',
                                          onPressed: widget.onLocate,
                                          icon: const Icon(
                                            Icons.my_location,
                                            color: Colors.lightBlueAccent,
                                          ),
                                        ),
                                        IconButton(
                                          key: const ValueKey(
                                            'mobile-weather-settings',
                                          ),
                                          tooltip: '气象图层与预警设置',
                                          onPressed: widget.onLayers,
                                          icon: const Icon(
                                            Icons.tune,
                                            color: Colors.lightBlueAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    widget.conditions,
                                    if (widget.current
                                        case final observation?) ...[
                                      Text(
                                        '${observation.station.name} · 气象站实况',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (observation.temperature
                                          case final temperature?
                                          when temperature.isFinite &&
                                              temperature.abs() < 100)
                                        Text(
                                          '${temperature.toStringAsFixed(1)}℃',
                                          style: const TextStyle(
                                            color: Color(0xFFB7E9F3),
                                            fontSize: 44,
                                            height: 1.2,
                                          ),
                                        ),
                                      if (observation.feelsLike
                                          case final feels?
                                          when feels.isFinite &&
                                              feels.abs() < 100)
                                        Text(
                                          '体感 ${feels.toStringAsFixed(1)}℃',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                    ],
                                    const WeatherMarquee(),
                                    widget.advice,
                                    widget.forecast,
                                    widget.details,
                                    const Divider(
                                      color: Colors.white24,
                                      height: 24,
                                    ),
                                    const Text(
                                      '气象站',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    widget.station,
                                    if (widget.sourceText case final source?)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 24),
                                        child: Text(
                                          source,
                                          key: const ValueKey(
                                            'mobile-weather-source',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MobileWeatherConditions extends StatelessWidget {
  const MobileWeatherConditions({super.key, required this.state, this.now});

  final ChinaWeatherHourlyState state;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final current = state.current;
    final instant = now ?? DateTime.now();
    final today = state.outlook?.today(instant);
    final uv = weatherUv(state, instant);
    if (current == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          state.loading || state.currentLoading ? '正在获取天气状况…' : '天气状况暂不可用',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }
    final code = current.weatherCode;
    final normalizedCode = code.startsWith('d') || code.startsWith('n')
        ? code.substring(1)
        : code;
    final icon = code == 'n00'
        ? Icons.nightlight_outlined
        : chinaWeatherIcon(normalizedCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              Text(
                'AQI ${weatherAqiText(current)}',
                style: TextStyle(color: weatherAqiColor(current), fontSize: 12),
              ),
              if (uv != null)
                Text(
                  '紫外线 ${uv.level} · 今日',
                  style: const TextStyle(
                    color: Color(0xFFFFCE82),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(icon, color: const Color(0xFFB7E9F3), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${current.weather}${today != null && chinaWeatherTemperature(today.low) != null && chinaWeatherTemperature(today.high) != null ? '  ${today.low}～${today.high}℃' : ''}',
                  key: const ValueKey('mobile-current-weather'),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${current.cityName} · ${current.date} ${current.time}（UTC+8）',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
