import 'package:flutter/material.dart';

import '../../services/sources/china_weather_hourly_service.dart';
import 'weather_temperature_path.dart';

// Official qxbm/fxbm/flbm tables in weather.com's indexTopNew.js.
const _weatherNames = {
  '00': '晴',
  '01': '多云',
  '02': '阴',
  '03': '阵雨',
  '04': '雷阵雨',
  '05': '雷阵雨伴有冰雹',
  '06': '雨夹雪',
  '07': '小雨',
  '08': '中雨',
  '09': '大雨',
  '10': '暴雨',
  '11': '大暴雨',
  '12': '特大暴雨',
  '13': '阵雪',
  '14': '小雪',
  '15': '中雪',
  '16': '大雪',
  '17': '暴雪',
  '18': '雾',
  '19': '冻雨',
  '20': '沙尘暴',
  '21': '小到中雨',
  '22': '中到大雨',
  '23': '大到暴雨',
  '24': '暴雨到大暴雨',
  '25': '大暴雨到特大暴雨',
  '26': '小到中雪',
  '27': '中到大雪',
  '28': '大到暴雪',
  '29': '浮尘',
  '30': '扬沙',
  '31': '强沙尘暴',
  '32': '浓雾',
  '49': '强浓雾',
  '53': '霾',
  '54': '中度霾',
  '55': '重度霾',
  '56': '严重霾',
  '57': '大雾',
  '58': '特强浓雾',
  '99': '无',
  '301': '雨',
  '302': '雪',
};

String chinaWeatherName(String code) =>
    _weatherNames[code] ?? (code.isEmpty ? '—' : '天气代码 $code');
const _windNames = [
  '微风',
  '东北风',
  '东风',
  '东南风',
  '南风',
  '西南风',
  '西风',
  '西北风',
  '北风',
  '旋转风',
];
const _windLevels = [
  '<3级',
  '3-4级',
  '4-5级',
  '5-6级',
  '6-7级',
  '7-8级',
  '8-9级',
  '9-10级',
  '10-11级',
  '11-12级',
];

class ChinaWeatherHourlyPanel extends StatefulWidget {
  const ChinaWeatherHourlyPanel({
    super.key,
    required this.state,
    this.scale = 1,
    this.now,
    this.showChart = false,
    this.showSource = true,
  });
  final ChinaWeatherHourlyState state;
  final double scale;
  final DateTime? now;
  final bool showChart;
  final bool showSource;

  @override
  State<ChinaWeatherHourlyPanel> createState() =>
      _ChinaWeatherHourlyPanelState();
}

class _ChinaWeatherHourlyPanelState extends State<ChinaWeatherHourlyPanel> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ChinaWeatherHourlyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.areaId != widget.state.areaId && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _codeLabel(List<String> table, String value) {
    final index = int.tryParse(value);
    return index != null && index >= 0 && index < table.length
        ? table[index]
        : (value.isEmpty ? '—' : '代码 $value');
  }

  void _move(int direction) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      (_scroll.offset + direction * _scroll.position.viewportDimension).clamp(
        0,
        _scroll.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = widget.scale;
    final now = (widget.now ?? DateTime.now()).toUtc();
    final hours = state.hours
        .where((hour) => !hour.time.isBefore(now))
        .toList(growable: false);
    final style = TextStyle(
      fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
      fontSize: 11.5 * s,
      color: Colors.white.withValues(alpha: .9),
      height: 1.3,
    );
    final cellHeight = MediaQuery.textScalerOf(context).scale(11.5 * s) * 15;
    return DefaultTextStyle(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: Colors.white24, height: 16 * s),
          Row(
            children: [
              Expanded(
                child: Text(
                  '逐小时预报',
                  style: style.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (hours.isNotEmpty && !widget.showChart) ...[
                IconButton(
                  tooltip: '前一页预报',
                  onPressed: () => _move(-1),
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  color: Colors.white70,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: '后一页预报',
                  onPressed: () => _move(1),
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  color: Colors.white70,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ],
          ),
          if (widget.showSource)
            Text(
              '中国天气网${state.areaName.isEmpty ? '' : ' · ${state.areaName}'}',
              style: style.copyWith(color: Colors.white70),
            ),
          Text('北京时间 UTC+8', style: style.copyWith(color: Colors.white54)),
          if (state.failed)
            Text(
              hours.isEmpty ? '逐小时预报暂不可用' : '更新失败，显示上次预报',
              style: style.copyWith(color: Colors.white60),
            ),
          if (hours.isEmpty && !state.failed)
            Text(state.loading ? '正在获取逐小时预报...' : '暂无有效逐小时预报'),
          if (hours.isNotEmpty)
            if (widget.showChart)
              SizedBox(
                height:
                    166 +
                    MediaQuery.textScalerOf(context).scale(11.5 * s) * 1.3 * 9,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    key: const PageStorageKey('weather-hourly-chart-scroll'),
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: hours.length * 90,
                      child: Column(
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              key: const ValueKey('weather-temperature-curve'),
                              size: Size(hours.length * 90, 100),
                              painter: HourlyTemperaturePainter(hours),
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final hour in hours)
                                SizedBox(
                                  width: 90,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 6,
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          _temperatureText(hour),
                                          style: style.copyWith(
                                            color: const Color(0xFFFFCE82),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Icon(
                                          chinaWeatherIcon(hour.weatherCode),
                                          color: Colors.white70,
                                          size: 22,
                                        ),
                                        SizedBox(
                                          height:
                                              MediaQuery.textScalerOf(
                                                context,
                                              ).scale(11.5) *
                                              4,
                                          child: Text(
                                            _weatherNames[hour.weatherCode] ??
                                                '天气代码 ${hour.weatherCode}',
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        Text(
                                          _codeLabel(
                                            _windNames,
                                            hour.windDirectionCode,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        Text(
                                          _codeLabel(
                                            _windLevels,
                                            hour.windScaleCode,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${hour.time.add(chinaWeatherOffset).month}/${hour.time.add(chinaWeatherOffset).day}',
                                        ),
                                        Text(
                                          '${hour.time.add(chinaWeatherOffset).hour.toString().padLeft(2, '0')}:${hour.time.add(chinaWeatherOffset).minute.toString().padLeft(2, '0')}',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: cellHeight,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: ListView.builder(
                    key: const PageStorageKey('weather-hourly-list'),
                    controller: _scroll,
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    itemCount: hours.length,
                    itemExtent: 78 * s,
                    itemBuilder: (context, i) {
                      final hour = hours[i];
                      final time = hour.time.add(chinaWeatherOffset);
                      final temperature = double.tryParse(hour.temperature);
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          2 * s,
                          8 * s,
                          6 * s,
                          12 * s,
                        ),
                        child: Column(
                          children: [
                            Text('${time.month}/${time.day}'),
                            Text(
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                            ),
                            const Spacer(),
                            Text(
                              temperature == null ||
                                      !temperature.isFinite ||
                                      temperature.abs() >= 100
                                  ? '—'
                                  : '${hour.temperature}℃',
                              style: style.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.lightBlueAccent,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              height:
                                  MediaQuery.textScalerOf(
                                    context,
                                  ).scale(11.5 * s) *
                                  4,
                              child: Text(
                                _weatherNames[hour.weatherCode] ??
                                    '天气代码 ${hour.weatherCode}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Text(
                              _codeLabel(_windNames, hour.windDirectionCode),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              _codeLabel(_windLevels, hour.windScaleCode),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

double? _temperature(ChinaWeatherHour hour) {
  final value = double.tryParse(hour.temperature);
  return value != null && value.isFinite && value.abs() < 100 ? value : null;
}

String _temperatureText(ChinaWeatherHour hour) =>
    _temperature(hour) == null ? '—' : '${hour.temperature}℃';

IconData chinaWeatherIcon(String code) => switch (code) {
  '00' => Icons.wb_sunny_outlined,
  '01' || '02' => Icons.cloud_outlined,
  '04' || '05' => Icons.thunderstorm_outlined,
  '03' ||
  '07' ||
  '08' ||
  '09' ||
  '10' ||
  '11' ||
  '12' ||
  '19' ||
  '21' ||
  '22' ||
  '23' ||
  '24' ||
  '25' ||
  '301' => Icons.water_drop_outlined,
  '06' ||
  '13' ||
  '14' ||
  '15' ||
  '16' ||
  '17' ||
  '26' ||
  '27' ||
  '28' ||
  '302' => Icons.ac_unit,
  _ => Icons.horizontal_rule,
};

class HourlyTemperaturePainter extends CustomPainter {
  HourlyTemperaturePainter(this.hours);
  final List<ChinaWeatherHour> hours;

  @override
  void paint(Canvas canvas, Size size) {
    final values = hours.map(_temperature).toList();
    final valid = values.whereType<double>().toList();
    if (valid.isEmpty) return;
    final min = valid.reduce((a, b) => a < b ? a : b);
    final max = valid.reduce((a, b) => a > b ? a : b);
    final paint = Paint()
      ..color = const Color(0xFFFFCE82)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final points = <Offset?>[];
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        points.add(null);
        continue;
      }
      final x = (i + .5) * size.width / hours.length;
      final y = max == min
          ? size.height / 2
          : 20 + (max - value) / (max - min) * (size.height - 40);
      points.add(Offset(x, y));
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = paint.color);
    }
    canvas.drawPath(weatherTemperaturePath(points), paint);
  }

  @override
  bool shouldRepaint(HourlyTemperaturePainter oldDelegate) {
    if (hours.length != oldDelegate.hours.length) return true;
    for (var i = 0; i < hours.length; i++) {
      if (hours[i].time != oldDelegate.hours[i].time ||
          hours[i].temperature != oldDelegate.hours[i].temperature) {
        return true;
      }
    }
    return false;
  }
}
