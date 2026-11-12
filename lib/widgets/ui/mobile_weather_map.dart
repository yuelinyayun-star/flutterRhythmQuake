import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/mobile_weather_layers.dart';
import '../../providers/map_state_provider.dart';
import '../../providers/quake_provider.dart';
import '../../services/background_service.dart';
import '../../services/sources/china_weather_alert_map_service.dart';
import '../../models/weather_alert_map_item.dart';
import 'mobile_weather_home.dart';
import '../../services/weather_playback_controller.dart';
import 'mobile_weather_playback_controls.dart';

typedef WeatherMapLayer = ({
  String key,
  String label,
  String source,
  IconData icon,
});
const weatherMapLayers = <WeatherMapLayer>[
  (
    key: 'radarChinaLayer',
    label: '全国雷达',
    source: '中国天气网 · 全国雷达拼图',
    icon: Icons.radar,
  ),
  (
    key: 'jmaRadarLayer',
    label: 'JMA 雷达',
    source: '日本气象厅 · 降水雷达',
    icon: Icons.radar,
  ),
  (
    key: 'precipitationChinaLayer',
    label: '全国小时降水',
    source: '中国天气网 · 1小时降水实况',
    icon: Icons.water_drop_outlined,
  ),
  (key: 'rainLayer', label: '实况降水瓦片', source: '现有地图降水产品', icon: Icons.grain),
  (
    key: 'cloudLayer',
    label: '实况云图瓦片',
    source: '现有地图云图产品',
    icon: Icons.cloud_outlined,
  ),
  (
    key: 'jmaSatelliteCloudLayer',
    label: '葵花卫星云图',
    source: '日本气象厅 · 葵花卫星',
    icon: Icons.satellite_alt,
  ),
  (
    key: 'nsmcSatelliteCloudLayer',
    label: '全球红外云图',
    source: '国家卫星气象中心 · NSMC',
    icon: Icons.public,
  ),
  (
    key: 'satelliteCloudLayer',
    label: '西太平洋卫星云图',
    source: '浙江省水利厅 · 30分钟云图',
    icon: Icons.satellite_alt,
  ),
  (
    key: 'windLayer',
    label: 'GFS 风场',
    source: 'NOAA GFS · 原有风场产品',
    icon: Icons.air,
  ),
  (
    key: 'weatherStationLayer',
    label: '气象站实况',
    source: '中国气象局 · 地面观测站',
    icon: Icons.sensors,
  ),
  (
    key: 'weatherAlertLayer',
    label: '气象灾害预警',
    source: '中国气象局 · 全国有效预警',
    icon: Icons.warning_amber_rounded,
  ),
  (
    key: 'typhoonLayer',
    label: '台风路径',
    source: '浙江省水利厅 · Jian备用',
    icon: Icons.storm_outlined,
  ),
];

class MobileWeatherMap extends StatefulWidget {
  const MobileWeatherMap({
    super.key,
    required this.onBack,
    required this.onLocate,
    required this.station,
    required this.frameTimes,
    this.playback,
    this.desktop = false,
    this.onClose,
  });
  final VoidCallback onBack, onLocate;
  final Widget station;
  final ValueListenable<Map<String, DateTime?>> frameTimes;
  final WeatherPlaybackController? playback;
  final bool desktop;
  final VoidCallback? onClose;
  @override
  State<MobileWeatherMap> createState() => _MobileWeatherMapState();
}

class _MobileWeatherMapState extends State<MobileWeatherMap> {
  late final WeatherPlaybackController _playback =
      widget.playback ?? WeatherPlaybackController();
  MapStateProvider? _map;
  bool _loaded = false, _saving = false, _ready = false;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _map = context.read<MapStateProvider>()..addListener(_syncPlaybackSource);
      _load();
    }
  }

  void _syncPlaybackSource() {
    final enabled = weatherMapLayers.where(
      (e) => _map!.mobileWeatherLayerEnabled(e.key),
    );
    _playback.selectSource(enabled.isEmpty ? null : enabled.first.key);
  }

  @override
  void dispose() {
    _map?.removeListener(_syncPlaybackSource);
    if (widget.playback == null) {
      _playback.dispose();
    } else if (!_playback.isDisposed) {
      _playback.selectSource(null);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final map = context.read<MapStateProvider>();
      final saved = prefs.getString(mobileWeatherPreferenceKey);
      final values = saved == null
          ? {
              for (final key in mobileWeatherLayerKeys)
                key: map.overlayEnabledMap[key] ?? false,
            }
          : readMobileWeatherLayerValues(saved);
      // One complete profile write prevents later global changes leaking in.
      if (saved == null &&
          !await prefs.setString(
            mobileWeatherPreferenceKey,
            jsonEncode(values),
          )) {
        throw StateError('无法保存气象地图配置');
      }
      if (!mounted) return;
      map.restoreMobileWeatherLayers(
        values,
        stationMode: prefs.getString(mobileWeatherStationModeKey),
      );
      BackgroundService().syncWeatherMapLayers();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '气象图层设置读取失败：$error';
          _ready = true;
        });
    }
  }

  Future<void> _apply(Map<String, bool> changes, {String? mode}) async {
    if (_saving || !_ready) return;
    setState(() => _saving = true);
    final map = context.read<MapStateProvider>();
    final values = {
      for (final key in mobileWeatherLayerKeys)
        key: changes[key] ?? map.mobileWeatherLayerEnabled(key),
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        mobileWeatherPreferenceKey,
        jsonEncode(values),
      ))
        throw StateError('配置保存失败');
      if (mode != null &&
          !await prefs.setString(mobileWeatherStationModeKey, mode))
        throw StateError('要素保存失败');
      if (!mounted) return;
      map.restoreMobileWeatherLayers(
        values,
        stationMode: mode ?? map.mobileWeatherStationMode,
      );
      BackgroundService().syncWeatherMapLayers();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('图层设置失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _solo(String key, {String? mode}) => _apply({
    for (final candidate in mobileWeatherLayerKeys) candidate: candidate == key,
  }, mode: mode);

  void _showLayers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: widget.desktop ? const BoxConstraints(maxWidth: 680) : null,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .78,
        child: WeatherGlassCard(
          child: Selector<MapStateProvider, String>(
            selector: (_, map) =>
                '${[for (final layer in weatherMapLayers) map.mobileWeatherLayerEnabled(layer.key)].join()}|${map.mobileWeatherStationMode}',
            builder: (context, _, child) {
              final map = context.read<MapStateProvider>();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sheetHeading('气象图层', () => Navigator.pop(sheetContext)),
                  Text(
                    widget.desktop ? '气象地图独立保存，可单独显示或叠加' : '仅用于手机气象地图，可单独显示或叠加',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final layer in weatherMapLayers)
                          SwitchListTile.adaptive(
                            key: ValueKey('weather-layer-${layer.key}'),
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(
                              layer.icon,
                              color: const Color(0xFFB8DFFB),
                              size: 21,
                            ),
                            title: Text(
                              layer.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              layer.source,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                            value: map.mobileWeatherLayerEnabled(layer.key),
                            onChanged: (value) => _apply({layer.key: value}),
                          ),
                        const Divider(color: Colors.white24),
                        const Text(
                          '气象站展示要素',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final mode in const {
                              'auto': '综合',
                              'temperature': '气温',
                              'rain': '降水',
                              'wind': '风向风力',
                            }.entries)
                              ChoiceChip(
                                label: Text(mode.value),
                                selected:
                                    map.mobileWeatherStationMode == mode.key,
                                onSelected: (_) => _apply({
                                  'weatherStationLayer': true,
                                }, mode: mode.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _time(DateTime value) {
    final local = value.toUtc().add(const Duration(hours: 8));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}（UTC+8）';
  }

  Widget _sheetHeading(String label, VoidCallback close) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      IconButton(
        onPressed: close,
        tooltip: '关闭',
        icon: const Icon(Icons.close_rounded, color: Colors.white70),
      ),
    ],
  );

  void _showInformation() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: widget.desktop ? const BoxConstraints(maxWidth: 720) : null,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .78,
        child: WeatherGlassCard(
          child: ValueListenableBuilder<List<WeatherAlertMapItem>>(
            valueListenable: ChinaWeatherAlertMapService.alertItemsNotifier,
            builder: (context, alerts, _) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sheetHeading('气象信息', () => Navigator.pop(sheetContext)),
                      const Text(
                        '所在地气象站',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      widget.station,
                      const Divider(height: 28, color: Colors.white24),
                      const Text(
                        '活动台风',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Selector<QuakeProvider, int>(
                        selector: (_, p) => p.typhoonUpdateRevision,
                        builder: (context, _, child) {
                          final items = context
                              .read<QuakeProvider>()
                              .activeTyphoons;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (items.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    '暂未收到活动台风数据',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              for (final item in items)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.storm_outlined,
                                    color: Colors.amber,
                                  ),
                                  title: Text(
                                    item.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item.tfid,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 28, color: Colors.white24),
                      Text(
                        '全国气象预警 · ${alerts.length}条',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (alerts.isEmpty)
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              ChinaWeatherAlertMapService.isLoadingNotifier,
                          builder: (_, loading, child) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              loading ? '正在获取预警数据…' : '暂未收到有效预警数据，可在图层中开启预警显示',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SliverList.builder(
                  itemCount: alerts.length,
                  itemBuilder: (context, index) {
                    final item = alerts[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: item.levelColor,
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        item.areaName,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final playbackInset = widget.desktop
        ? math.max(14.0, (MediaQuery.sizeOf(context).width - 860) / 2)
        : 14.0;
    return Selector<MapStateProvider, String>(
      selector: (_, m) =>
          '${[for (final e in weatherMapLayers) m.mobileWeatherLayerEnabled(e.key)].join()}|${m.mobileWeatherStationMode}',
      builder: (context, _, child) {
        final map = context.read<MapStateProvider>();
        final enabled = weatherMapLayers
            .where((e) => map.mobileWeatherLayerEnabled(e.key))
            .toList();
        return Stack(
          children: [
            Positioned(
              top: safe.top + 12,
              left: 14,
              right: 14,
              child: WeatherGlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('weather-map-back'),
                      onPressed: widget.onBack,
                      tooltip: '天气首页',
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        '气象地图',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.onClose != null)
                      TextButton.icon(
                        key: const ValueKey('desktop-weather-map-close'),
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('返回地震'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                      ),
                    IconButton(
                      key: const ValueKey('weather-map-layers'),
                      onPressed: _ready ? _showLayers : null,
                      tooltip: '选择气象图层',
                      icon: const Icon(
                        Icons.layers_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: safe.top + 80,
              bottom: safe.bottom + 200,
              right: 14,
              width: 58,
              child: Align(
                alignment: Alignment.centerRight,
                child: WeatherGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 6,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in const [
                          ('radarChinaLayer', '雷达', Icons.radar),
                          (
                            'precipitationChinaLayer',
                            '降水',
                            Icons.water_drop_outlined,
                          ),
                          (
                            'nsmcSatelliteCloudLayer',
                            '云图',
                            Icons.cloud_outlined,
                          ),
                          ('weatherStationLayer', '气温', Icons.thermostat),
                          ('windLayer', '风场', Icons.air),
                          (
                            'weatherAlertLayer',
                            '预警',
                            Icons.warning_amber_rounded,
                          ),
                          ('typhoonLayer', '台风', Icons.storm_outlined),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: TextButton(
                              key: ValueKey('weather-map-quick-${item.$1}'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 7,
                                ),
                                minimumSize: const Size(50, 48),
                                foregroundColor: Colors.white,
                                backgroundColor:
                                    map.mobileWeatherLayerEnabled(item.$1)
                                    ? const Color(0x446CAFFF)
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saving || !_ready
                                  ? null
                                  : () => _solo(
                                      item.$1,
                                      mode: item.$1 == 'weatherStationLayer'
                                          ? 'temperature'
                                          : null,
                                    ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(item.$3, size: 21),
                                  const SizedBox(height: 3),
                                  Text(
                                    item.$2,
                                    style: const TextStyle(fontSize: 11),
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
            Positioned(
              left: 14,
              bottom: safe.bottom + 200,
              child: WeatherGlassCard(
                padding: const EdgeInsets.all(2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: widget.onLocate,
                      tooltip: '回到所在地',
                      icon: const Icon(
                        Icons.my_location_rounded,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('weather-map-information'),
                      onPressed: _showInformation,
                      tooltip: '气象信息',
                      icon: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: playbackInset,
              right: playbackInset,
              bottom: safe.bottom + 12,
              child: WeatherGlassCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11,
                        ),
                      ),
                    ListenableBuilder(
                      listenable: _playback,
                      builder: (context, _) =>
                          ValueListenableBuilder<Map<String, DateTime?>>(
                            valueListenable: widget.frameTimes,
                            builder: (context, times, _) {
                              final current = enabled.isEmpty
                                  ? null
                                  : enabled.first;
                              final selected = _playback.frame.value;
                              final time =
                                  selected?.time ??
                                  (current == null ? null : times[current.key]);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    enabled.isEmpty
                                        ? '选择要查看的气象图层'
                                        : enabled
                                              .map((e) => e.label)
                                              .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    current == null
                                        ? '图层单独保存，不影响地震地图'
                                        : time != null
                                        ? '${selected == null ? '数据时次' : '历史实况'} ${_time(time)}'
                                        : times.containsKey(current.key)
                                        ? '尚未收到当前图层数据'
                                        : '${current.source} · 按原信源更新',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                    ),
                    MobileWeatherPlaybackControls(controller: _playback),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
