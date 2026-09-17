import 'package:flutter/material.dart';
import '../../services/sources/china_weather_hourly_service.dart';
import '../../services/sources/cma_local_weather_service.dart';
import 'china_weather_hourly_panel.dart';
import 'weather_temperature_path.dart';

String weatherAqiText(ChinaWeatherCurrent? current) {
  final raw = current?.raw['aqi']?.toString() ?? '';
  final value = int.tryParse(raw);
  if (value == null || value < 0 || value > 500) return '—';
  final level = switch (value) {
    <= 50 => '优',
    <= 100 => '良',
    <= 150 => '轻度污染',
    <= 200 => '中度污染',
    <= 300 => '重度污染',
    _ => '严重污染',
  };
  return '$raw · $level';
}

Color weatherAqiColor(ChinaWeatherCurrent? current) {
  final value = int.tryParse(current?.raw['aqi']?.toString() ?? '');
  if (value == null || value < 0 || value > 500) return Colors.white60;
  return switch (value) {
    <= 50 => const Color(0xFF9BD69A),
    <= 100 => const Color(0xFFF9DA65),
    <= 150 => const Color(0xFFF2C339),
    <= 200 => const Color(0xFFDB555E),
    <= 300 => const Color(0xFFBA37D4),
    _ => const Color(0xFFED8EA8),
  };
}

ChinaWeatherIndex? weatherUv(ChinaWeatherHourlyState state, DateTime now) {
  for (final item
      in state.outlook?.todayIndices(now) ?? <ChinaWeatherIndex>[]) {
    if (item.code == 'uv') return item;
  }
  return null;
}

class MobileWeatherAdvice extends StatelessWidget {
  const MobileWeatherAdvice({super.key, required this.state, this.now});
  final ChinaWeatherHourlyState state;
  final DateTime? now;
  @override
  Widget build(BuildContext context) {
    final items =
        state.outlook?.todayIndices(now ?? DateTime.now()) ??
        <ChinaWeatherIndex>[];
    for (final item in items) {
      if (item.code != 'ct' || item.description.isEmpty) continue;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.checkroom, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${item.name} · ${item.description}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class MobileWeatherHomeDetails extends StatelessWidget {
  const MobileWeatherHomeDetails({
    super.key,
    required this.state,
    this.observation,
    this.now,
  });
  final ChinaWeatherHourlyState state;
  final CmaLocalWeatherObservation? observation;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final instant = now ?? DateTime.now();
    final today = state.outlook?.today(instant);
    final days = state.outlook?.upcoming(instant) ?? <ChinaWeatherDay>[];
    final indices =
        state.outlook?.todayIndices(instant) ?? <ChinaWeatherIndex>[];
    final uv = weatherUv(state, instant);
    String number(double? value, String unit, {int digits = 1}) =>
        value != null && value.isFinite && value.abs() < 9000
        ? '${value.toStringAsFixed(digits)}$unit'
        : '—';
    final metrics = <(IconData, String, String, String)>[
      (Icons.thermostat, '体感', number(observation?.feelsLike, '℃'), ''),
      (
        Icons.air,
        '风',
        [
          observation?.windDirection ?? '',
          observation?.windScale ?? '',
        ].where((s) => s.isNotEmpty).join(' · '),
        '',
      ),
      (
        Icons.water_drop_outlined,
        '湿度',
        number(observation?.humidity, '%', digits: 0),
        '',
      ),
      (Icons.wb_sunny_outlined, '紫外线', uv?.level ?? '—', '今日指数'),
      (
        Icons.visibility_outlined,
        '能见度',
        state.current?.raw['njd']?.toString() ?? '—',
        '',
      ),
      (Icons.speed, '气压', number(observation?.pressure, 'hPa', digits: 0), ''),
    ];
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('每日预报'),
          Text('${state.areaName} · 北京时间 UTC+8', style: _muted),
          if (state.failed) const Text('更新失败，显示上次有效预报', style: _muted),
          if (days.isEmpty)
            Text(state.loading ? '正在获取每日预报…' : '暂无有效每日预报', style: _muted)
          else
            _DailyForecast(days: days),
          const _Heading('气象实况'),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth < 230 ? 1 : 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: (box.maxWidth - (columns - 1) * 12) / columns,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  metric.$1,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: Text(metric.$2)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              metric.$3.isEmpty ? '—' : metric.$3,
                              style: const TextStyle(
                                fontSize: 20,
                                color: Color(0xFFB7E9F3),
                              ),
                            ),
                            if (metric.$4.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(metric.$4, style: _muted),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const _Heading('空气质量'),
          Text(
            'AQI ${weatherAqiText(state.current)}',
            key: const ValueKey('weather-home-aqi'),
            style: TextStyle(
              fontSize: 24,
              color: weatherAqiColor(state.current),
            ),
          ),
          const Text('当前实况', style: _muted),
          const _Heading('日出日落'),
          Wrap(
            spacing: 28,
            runSpacing: 10,
            children: [
              _SunTime(Icons.wb_twilight, '日出', today?.sunrise ?? ''),
              _SunTime(Icons.wb_twilight_outlined, '日落', today?.sunset ?? ''),
            ],
          ),
          const SizedBox(height: 6),
          const Text('当地时间 UTC+8', style: _muted),
          const _Heading('生活指数'),
          if (indices.isEmpty) const Text('暂无当日生活指数', style: _muted),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final code in const [
                  'ct',
                  'fs',
                  'tr',
                  'yd',
                  'dy',
                  'xc',
                  'ag',
                  'gm',
                  'ys',
                  'ls',
                ])
                  for (final item in indices.where((item) => item.code == code))
                    SizedBox(
                      width: box.maxWidth < 230
                          ? box.maxWidth
                          : (box.maxWidth - 16) / 2,
                      child: ExpansionTile(
                        key: PageStorageKey('weather-index-${item.code}'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 12),
                        iconColor: Colors.white70,
                        collapsedIconColor: Colors.white70,
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          item.level,
                          style: const TextStyle(color: Color(0xFFB7E9F3)),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(item.description, style: _muted),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _muted = TextStyle(color: Colors.white60, fontSize: 11, height: 1.4);

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(color: Colors.white24, height: 24),
      Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
    ],
  );
}

class _SunTime extends StatelessWidget {
  const _SunTime(this.icon, this.label, this.time);
  final IconData icon;
  final String label;
  final String time;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: const Color(0xFFFFCE82), size: 23),
      const SizedBox(width: 8),
      Text('$label ${time.isEmpty ? '—' : time}'),
    ],
  );
}

class _DailyForecast extends StatelessWidget {
  const _DailyForecast({required this.days});
  final List<ChinaWeatherDay> days;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return SingleChildScrollView(
      key: const PageStorageKey('weather-home-daily-scroll'),
      scrollDirection: Axis.horizontal,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final day in days)
                SizedBox(
                  width: 94,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Column(
                      children: [
                        Text('${day.date.month}/${day.date.day}'),
                        Text(
                          '周${'一二三四五六日'[day.date.weekday - 1]}',
                          style: _muted,
                        ),
                        const SizedBox(height: 10),
                        Icon(
                          chinaWeatherIcon(day.dayCode),
                          color: const Color(0xFFFFCE82),
                          size: 25,
                        ),
                        SizedBox(
                          height: scale.scale(13) * 5,
                          child: Text(
                            '日 ${chinaWeatherName(day.dayCode)}\n夜 ${chinaWeatherName(day.nightCode)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          '${chinaWeatherTemperature(day.high) == null ? '—' : day.high}℃',
                          style: const TextStyle(color: Color(0xFFFFCE82)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          RepaintBoundary(
            child: CustomPaint(
              size: Size(days.length * 94, 100),
              painter: DailyTemperaturePainter(days),
            ),
          ),
          Row(
            children: [
              for (final day in days)
                SizedBox(
                  width: 94,
                  child: Text(
                    '${chinaWeatherTemperature(day.low) == null ? '—' : day.low}℃',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF80CFFF)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class DailyTemperaturePainter extends CustomPainter {
  DailyTemperaturePainter(this.days);
  final List<ChinaWeatherDay> days;
  @override
  void paint(Canvas canvas, Size size) {
    final highs = days.map((d) => chinaWeatherTemperature(d.high)).toList();
    final lows = days.map((d) => chinaWeatherTemperature(d.low)).toList();
    final valid = [...highs, ...lows].whereType<double>();
    if (valid.isEmpty) return;
    final min = valid.reduce((a, b) => a < b ? a : b);
    final max = valid.reduce((a, b) => a > b ? a : b);
    for (final (values, color) in [
      (highs, const Color(0xFFFFCE82)),
      (lows, const Color(0xFF80CFFF)),
    ]) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final points = <Offset?>[];
      for (var i = 0; i < values.length; i++) {
        final value = values[i];
        if (value == null) {
          points.add(null);
          continue;
        }
        final point = Offset(
          (i + .5) * size.width / days.length,
          max == min
              ? size.height / 2
              : 10 + (max - value) / (max - min) * (size.height - 20),
        );
        points.add(point);
        canvas.drawCircle(point, 3, Paint()..color = color);
      }
      canvas.drawPath(weatherTemperaturePath(points), paint);
    }
  }

  @override
  bool shouldRepaint(DailyTemperaturePainter oldDelegate) {
    if (days.length != oldDelegate.days.length) return true;
    for (var i = 0; i < days.length; i++) {
      if (days[i].date != oldDelegate.days[i].date ||
          days[i].high != oldDelegate.days[i].high ||
          days[i].low != oldDelegate.days[i].low) {
        return true;
      }
    }
    return false;
  }
}
