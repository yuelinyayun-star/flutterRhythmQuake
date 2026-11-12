import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/sources/china_weather_hourly_service.dart';
import 'china_weather_hourly_panel.dart';
import 'mobile_weather_home_details.dart';
import 'weather_marquee.dart';

/// Visual selection only. Source observations and forecast values are untouched.
String? mobileWeatherBackground(String code) {
  final value = code.trim().toLowerCase();
  if (!RegExp(r'^[dn]?\d{2,3}$').hasMatch(value)) return null;
  final night = value.startsWith('n');
  final number = int.tryParse(value.replaceFirst(RegExp(r'^[dn]'), ''));
  return switch (number) {
    0 => night ? 'clear_night' : 'clear_day',
    1 || 2 => night ? 'cloudy_night' : 'cloudy_day',
    4 || 5 => 'storm',
    6 || 13 || 14 || 15 || 16 || 17 || 26 || 27 || 28 || 302 => 'snow',
    3 ||
    7 ||
    8 ||
    9 ||
    10 ||
    11 ||
    12 ||
    19 ||
    21 ||
    22 ||
    23 ||
    24 ||
    25 ||
    301 => 'rain',
    18 || 20 || 29 || 30 || 31 || 53 || 54 || 55 || 56 || 57 || 58 => 'fog',
    _ => null,
  };
}

class MobileWeatherHome extends StatelessWidget {
  const MobileWeatherHome({
    super.key,
    required this.state,
    required this.station,
    required this.onMap,
    required this.onLayers,
    required this.onLocate,
    this.mapVisible = false,
    this.locationLabel = '',
    this.stationTemperature,
    this.stationTemperatureLabel = '',
    this.feelsLike,
    this.advice = const SizedBox.shrink(),
    this.details = const SizedBox.shrink(),
    this.forecastMessage,
    this.sourceText,
    this.now,
    this.mapOverlay,
  });

  final ChinaWeatherHourlyState state;
  final Widget station, advice, details;
  final VoidCallback onMap, onLayers, onLocate;
  final bool mapVisible;
  final String locationLabel, stationTemperatureLabel;
  final double? stationTemperature, feelsLike;
  final String? forecastMessage, sourceText;
  final DateTime? now;
  final Widget? mapOverlay;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    if (mapVisible) {
      if (mapOverlay != null) return mapOverlay!;
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, padding.top + 76, 16, 0),
          child: WeatherGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('weather-map-back'),
                  onPressed: onMap,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  label: const Text('天气首页'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
                const Spacer(),
                _WeatherAction(
                  icon: Icons.my_location_rounded,
                  tooltip: '回到所在地',
                  onPressed: onLocate,
                ),
                _WeatherAction(
                  icon: Icons.tune_rounded,
                  tooltip: '气象图层与预警设置',
                  onPressed: onLayers,
                ),
              ],
            ),
          ),
        ),
      );
    }
    final current = state.current;
    final city = current?.cityName.isNotEmpty == true
        ? current!.cityName
        : state.areaName.isNotEmpty
        ? state.areaName
        : locationLabel;
    final cityTemperature = chinaWeatherTemperature(
      current?.raw['temp']?.toString() ?? '',
    );
    final fallback = stationTemperature;
    final temperature =
        cityTemperature ??
        (fallback != null && fallback.isFinite && fallback.abs() < 100
            ? fallback
            : null);
    final day = state.outlook?.today(now ?? DateTime.now());
    final high = day == null ? null : chinaWeatherTemperature(day.high);
    final low = day == null ? null : chinaWeatherTemperature(day.low);
    final background = mobileWeatherBackground(current?.weatherCode ?? '');
    final heroStyle =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          color: Colors.white,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 16,
              offset: const Offset(0, 2),
            ),
          ],
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: ColoredBox(
            key: const ValueKey('mobile-weather-home-background'),
            color: const Color(0xFF202D40),
            child: background == null
                ? null
                : Image.asset(
                    'assets/images/weather/$background.png',
                    key: ValueKey('weather-background-$background'),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    cacheWidth:
                        (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context))
                            .round()
                            .clamp(320, 900),
                    gaplessPlayback: true,
                  ),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x26101B2D),
                  Color(0x38101B2D),
                  Color(0xA6142033),
                ],
                stops: [0, .45, 1],
              ),
            ),
          ),
        ),
        // Pre-baked blur of the static backdrop (color + art + gradient). The
        // glass cards below read it through plain translucent fills instead of
        // running a live BackdropFilter each frame while scrolling.
        if (background != null)
          Positioned.fill(child: WeatherFrozenBackdrop(asset: background)),
        Positioned.fill(
          top: padding.top + 126,
          child: BackdropGroup(
            child: SingleChildScrollView(
              key: const PageStorageKey('mobile-weather-home-scroll'),
              padding: EdgeInsets.fromLTRB(20, 8, 20, padding.bottom + 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DefaultTextStyle(
                    style: heroStyle.copyWith(fontSize: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          city.isEmpty ? '等待定位信息' : city,
                          key: const ValueKey('weather-home-city'),
                          textAlign: TextAlign.center,
                          style: heroStyle.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          temperature == null
                              ? '—°'
                              : '${temperature.toStringAsFixed(0)}°',
                          key: const ValueKey('weather-home-temperature'),
                          textAlign: TextAlign.center,
                          style: heroStyle.copyWith(
                            fontFamily: 'MPLUSRounded1c',
                            fontSize: 94,
                            height: 1.22,
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
                          style: heroStyle.copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 8),
                        if (high != null || low != null || feelsLike != null)
                          Text(
                            [
                              if (high != null)
                                '最高 ${high.toStringAsFixed(0)}°',
                              if (low != null) '最低 ${low.toStringAsFixed(0)}°',
                              if (feelsLike case final feels?
                                  when feels.isFinite && feels.abs() < 100)
                                '体感 ${feels.toStringAsFixed(0)}°',
                            ].join('  '),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (current != null && weatherAqiText(current) != '—')
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0x30202C40),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    '空气质量 ${weatherAqiText(current)}',
                                    style: TextStyle(
                                      color: weatherAqiColor(current),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (current != null)
                          Text(
                            '${current.date} ${current.time} 更新 · UTC+8',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        if (cityTemperature == null &&
                            temperature != null &&
                            stationTemperatureLabel.isNotEmpty)
                          Text(
                            '$stationTemperatureLabel · 气象站实况',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(height: 24),
                        const WeatherMarquee(),
                        advice,
                        if (forecastMessage != null)
                          WeatherGlassCard(
                            blur: false,
                            child: Text(
                              forecastMessage!,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          )
                        else
                          WeatherGlassCard(
                            blur: false,
                            child: _HomeHourly(state: state, now: now),
                          ),
                        const SizedBox(height: 14),
                        if (details is! SizedBox)
                          WeatherGlassCard(blur: false, child: details),
                        const SizedBox(height: 14),
                        WeatherGlassCard(
                          blur: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.sensors_rounded,
                                    color: Colors.white70,
                                    size: 17,
                                  ),
                                  SizedBox(width: 7),
                                  Text(
                                    '附近气象站',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              station,
                            ],
                          ),
                        ),
                        if (sourceText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: Text(
                              sourceText!,
                              key: const ValueKey('mobile-weather-source'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                                height: 1.5,
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
        ),
        Positioned(
          top: padding.top + 76,
          left: 20,
          right: 20,
          child: DefaultTextStyle(
            style: heroStyle.copyWith(fontSize: 13),
            child: Row(
              children: [
                const Icon(
                  Icons.near_me_rounded,
                  color: Colors.white70,
                  size: 14,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('当地天气', style: TextStyle(color: Colors.white70)),
                ),
                _WeatherAction(
                  icon: Icons.my_location_rounded,
                  tooltip: '回到所在地',
                  onPressed: onLocate,
                ),
                _WeatherAction(
                  icon: Icons.tune_rounded,
                  tooltip: '气象图层与预警设置',
                  onPressed: onLayers,
                ),
                _WeatherAction(
                  key: const ValueKey('mobile-weather-map-entry'),
                  icon: Icons.map_outlined,
                  tooltip: '气象地图',
                  onPressed: onMap,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class WeatherGlassCard extends StatelessWidget {
  const WeatherGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.blur = true,
  });
  final Widget child;
  final EdgeInsets padding;

  /// True: live BackdropFilter glass (over moving content, e.g. the map).
  /// False: plain translucent fill — use only over the static pre-blurred
  /// weather backdrop, where live glass would be visually identical.
  final bool blur;

  Widget _card() => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x44202C40),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0x22FFFFFF), width: .7),
    ),
    child: Padding(padding: padding, child: child),
  );
  @override
  Widget build(BuildContext context) => blur
      ? ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter.grouped(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: _card(),
          ),
        )
      : _card();
}

/// Bakes blur(sigma 8) of the weather art once per (asset, width bucket) and
/// paints it cover with the given alignment, mirroring the visible background
/// image. The weather backdrop is static, so glass cards read this pre-baked
/// layer through plain translucent fills instead of live BackdropFilters.
/// Edges fading into the solid base color match what a live backdrop blur
/// would sample underneath.
class WeatherFrozenBackdrop extends StatefulWidget {
  const WeatherFrozenBackdrop({
    super.key,
    required this.asset,
    this.alignment = Alignment.topCenter,
    this.decodeWidth,
  });
  final String asset;
  final Alignment alignment;

  /// Fixed decode width. Null: responsive clamp(320, 900) like the visible
  /// background image.
  final int? decodeWidth;
  @override
  State<WeatherFrozenBackdrop> createState() => _WeatherGlassBackdropState();
}

class _WeatherGlassBackdropState extends State<WeatherFrozenBackdrop> {
  static const _blurSigma = 8.0;
  static final Map<String, ui.Image> _cache = {};
  static const _cacheLimit = 12;

  ui.Image? _image;
  String? _key;
  int _generation = 0;
  bool _baking = false;
  String? _pendingKey;

  @override
  void didUpdateWidget(covariant WeatherFrozenBackdrop old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _scheduleBake();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleBake();
  }

  String get _targetKey {
    final width =
        widget.decodeWidth ??
        (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(
          context,
        ))
            .round()
            .clamp(320, 900);
    return '${widget.asset}@$width';
  }

  void _scheduleBake() {
    final key = _targetKey;
    if (key == _key) return;
    final cached = _cache[key];
    if (cached != null) {
      _generation++;
      setState(() {
        _image = cached;
        _key = key;
      });
      return;
    }
    _pendingKey = key;
    if (_baking) return;
    _baking = true;
    _runBake();
  }

  Future<void> _runBake() async {
    while (mounted && _pendingKey != null) {
      final key = _pendingKey!;
      _pendingKey = null;
      final split = key.lastIndexOf('@');
      final asset = key.substring(0, split);
      final width = int.parse(key.substring(split + 1));
      final generation = ++_generation;
      try {
        final image = await _bake(asset, width);
        if (!mounted || generation != _generation) continue;
        if (_cache.length >= _cacheLimit) {
          for (final stale in _cache.keys.take(_cache.length - _cacheLimit + 1)
              .toList()) {
            _cache.remove(stale);
          }
        }
        _cache[key] = image;
        setState(() {
          _image = image;
          _key = key;
        });
      } catch (_) {
        // Keep the previous image; glass falls back to tint-only cards.
      }
    }
    _baking = false;
  }

  static Future<ui.Image> _bake(String asset, int width) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    final src = frame.image;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(
        src,
        ui.Offset.zero,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: _blurSigma,
            sigmaY: _blurSigma,
          ),
      );
      return recorder.endRecording().toImageSync(src.width, src.height);
    } finally {
      src.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BackdropPainter(image, widget.alignment),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.image, this.alignment);
  final ui.Image image;
  final Alignment alignment;
  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: ui.Offset.zero & size,
      image: image,
      alignment: alignment,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.image != image || old.alignment != alignment;
}

class _WeatherAction extends StatelessWidget {
  const _WeatherAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    constraints: const BoxConstraints.tightFor(width: 42, height: 44),
    padding: const EdgeInsets.all(9),
    iconSize: 21,
    tooltip: tooltip,
    onPressed: onPressed,
    color: Colors.white,
    icon: Icon(icon),
  );
}

class _HomeHourly extends StatelessWidget {
  const _HomeHourly({required this.state, this.now});
  final ChinaWeatherHourlyState state;
  final DateTime? now;
  @override
  Widget build(BuildContext context) {
    final instant = (now ?? DateTime.now()).toUtc();
    final hours = state.hours
        .where((hour) => !hour.time.isBefore(instant))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '逐小时预报',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: Colors.white24),
        ),
        if (state.failed)
          const Text(
            '更新失败，显示上次有效预报',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        if (hours.isEmpty)
          Text(
            state.loading ? '正在获取逐小时预报…' : '暂无有效逐小时预报',
            style: const TextStyle(color: Colors.white70),
          )
        else
          SingleChildScrollView(
            key: const PageStorageKey('weather-home-hourly-scroll'),
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final hour in hours)
                      SizedBox(
                        width: 70,
                        child: Column(
                          children: [
                            Text(
                              '${hour.time.add(chinaWeatherOffset).hour.toString().padLeft(2, '0')}:00',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Icon(
                              chinaWeatherIcon(hour.weatherCode),
                              color: const Color(0xFFFFDF9B),
                              size: 25,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${chinaWeatherTemperature(hour.temperature)?.toStringAsFixed(0) ?? '—'}°',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size(hours.length * 70, 48),
                    painter: HourlyTemperaturePainter(hours),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '北京时间 UTC+8${state.areaName.isEmpty ? '' : ' · ${state.areaName}'}',
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}
