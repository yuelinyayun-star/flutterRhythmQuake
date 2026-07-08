import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../services/location_service.dart';
import '../../services/tts_service.dart';
import '../../services/sources/fan_service.dart';
import '../../services/sources/fdsn_motion_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/source_manager.dart';
import '../map/map_config.dart';
import '../map/quake_map_view.dart';
import '../../models/quake_message.dart';
import 'app_page_background.dart';
import 'debug_page.dart';
import 'ui_runtime_flags.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsCategory _selectedCategory = _SettingsCategory.data;
  String _settingsQuery = '';
  int _fanServerIndex = 0;
  String _tileKey = 'petalLight';
  bool _overlayCloud = false;
  bool _overlayWind = false;
  bool _overlayRain = false;
  bool _overlayCnContour = false;
  bool _overlayJmaVolcano = false;
  bool _overlayTyphoon = false;
  bool _overlayFdsnEarthScope = false;
  bool _overlayFdsnGeofon = false;
  int _fdsnStationLimit = FdsnMotionService.defaultStationLimit;
  final Map<String, double> _sourceMagFilters = {};
  String _niedDataSource = 'lmoni';
  bool _niedReplayEnabled = false;
  String _niedReplayStart = '2026-05-30 23:34:00';
  int _niedReplayStepSeconds = 1;
  int _shakeSensitivity = 2;
  bool _tremStationEnabled = true;
  bool _hideGridOnEew = false;
  bool _sideInfoAutoShowBeta = true;
  bool _showEpicenter = false;
  static const String _showEpicenterKey = 'show_estimated_epicenter';
  bool _weatherMarqueeEnabled = false;
  bool _weatherLocalOnly = false;
  String _weatherLocalLevel = 'county';
  bool _ttsEnabled = true;
  bool _ttsEventEnabled = true;
  bool _ttsCountdownEnabled = true;
  bool _ttsUpdateEnabled = false;
  String _ttsVoiceId = '';
  double _ttsSpeechRate = 0.58;
  double _ttsPitch = 1.0;
  List<TtsVoiceOption> _ttsVoices = const [TtsVoiceOption.systemDefault];
  bool _gptSovitsEnabled = false;
  int _gptSovitsStatus = 0; // 0=未检测, 1=检查中, 2=已连接, -1=不可达
  bool _initialized = false;
  final TextEditingController _niedReplayStartController =
      TextEditingController();
  final TextEditingController _settingsSearchController =
      TextEditingController();
  final TextEditingController _gptSovitsUrlController = TextEditingController();
  final TextEditingController _gptSovitsRefAudioController =
      TextEditingController();
  final TextEditingController _gptSovitsPromptTextController =
      TextEditingController();

  static const String _fanServerKey = 'fan_default_server_index';
  static const String _tileKeyKey = 'tile_key';
  static const String _overlayCloudKey = 'map_overlay_cloudLayer';
  static const String _overlayWindKey = 'map_overlay_windLayer';
  static const String _overlayRainKey = 'map_overlay_rainLayer';
  static const String _overlayCnContourKey = 'map_overlay_cnContour';
  static const String _overlayJmaVolcanoKey = 'map_overlay_volcanoLayer';
  static const String _overlayTyphoonKey = 'map_overlay_typhoonLayer';
  static const String _overlayFdsnEarthScopeKey = 'map_overlay_fdsnEarthScope';
  static const String _overlayFdsnGeofonKey = 'map_overlay_fdsnGeofon';
  static const String _fdsnStationLimitKey =
      FdsnMotionService.stationLimitPreferenceKey;
  static const String _magFilterPrefix = 'source_mag_filter_';
  static const String _niedDataSourceKey = 'nied_data_source';
  static const String _niedReplayEnabledKey = 'nied_replay_enabled';
  static const String _niedReplayStartKey = 'nied_replay_start_jst';
  static const String _niedReplayStepKey = 'nied_replay_step_seconds';
  static const String _shakeSensitivityKey = 'shake_sensitivity';
  static const String _hideGridOnEewKey = 'hide_grid_on_eew';
  static const String _sideInfoAutoShowBetaKey = 'side_info_auto_show_beta';
  static const String _weatherMarqueeEnabledKey = 'weather_marquee_enabled';
  static const String _weatherLocalOnlyKey = 'weather_alarm_local_only';
  static const String _weatherLocalLevelKey = 'weather_alarm_local_level';
  static const String _mapViewLatKey = 'map_view_lat';
  static const String _mapViewLngKey = 'map_view_lng';

  double? _mapViewLat;
  double? _mapViewLng;

  static const List<double> magOptions = [
    -1,
    0,
    1.0,
    1.5,
    2.0,
    2.5,
    3.0,
    3.5,
    4.0,
    4.5,
    5.0,
  ];

  static const Color _accentColor = Color(0xFF82B1FF);
  static const Color _appBarColor = Color.fromRGBO(8, 8, 24, 0.8);
  static const Color _panelColor = Color.fromRGBO(8, 10, 24, 0.66);
  static const Color _fieldColor = Color.fromRGBO(255, 255, 255, 0.07);
  static const Color _borderColor = Color.fromRGBO(130, 177, 255, 0.32);
  static const Color _dividerColor = Color.fromRGBO(255, 255, 255, 0.08);
  static const Color _mutedTextColor = Color.fromRGBO(255, 255, 255, 0.58);
  static const List<_SettingsCategoryInfo> _categories = [
    _SettingsCategoryInfo(
      category: _SettingsCategory.data,
      title: '数据源',
      subtitle: '连接与实时监测',
      icon: Icons.hub_outlined,
      accent: Color(0xFF62C6FF),
      keywords: ['fan', '服务器', 'nied', 'lmoni', 'kmoni', 'yahoo', '摇晃', '灵敏度'],
    ),
    _SettingsCategoryInfo(
      category: _SettingsCategory.map,
      title: '地图与测站',
      subtitle: '底图、图层和定位',
      icon: Icons.map_outlined,
      accent: Color(0xFF72D6B1),
      keywords: [
        '地图',
        '底图',
        '图层',
        '云图',
        '风场',
        '降水',
        '等高线',
        '火山',
        '定位',
        '经纬度',
        'fdsn',
        'earthscope',
        'geofon',
        'seedlink',
        '测站',
        '连接上限',
      ],
    ),
    _SettingsCategoryInfo(
      category: _SettingsCategory.alert,
      title: '预警显示',
      subtitle: '预警范围与界面行为',
      icon: Icons.crisis_alert_outlined,
      accent: Color(0xFFFFC66D),
      keywords: [
        '预警',
        '气象',
        '当地',
        '省级',
        '市级',
        '县级',
        '网格',
        '侧边',
        '震中',
        '旧事件',
        '更新报',
      ],
    ),
    _SettingsCategoryInfo(
      category: _SettingsCategory.voice,
      title: '语音播报',
      subtitle: '音色、内容与语速',
      icon: Icons.record_voice_over_outlined,
      accent: Color(0xFFD6A5FF),
      keywords: [
        '语音',
        'tts',
        'gpt-sovits',
        '播报',
        '事件',
        '倒计时',
        '更新报',
        '音色',
        '语速',
        '音调',
        '试听',
      ],
    ),
    _SettingsCategoryInfo(
      category: _SettingsCategory.filter,
      title: '信息过滤',
      subtitle: '按来源过滤事件',
      icon: Icons.filter_alt_outlined,
      accent: Color(0xFFFF8F8F),
      keywords: ['过滤', '震级', '阈值', '信息事件', '来源', '不接收', '不过滤'],
    ),
    _SettingsCategoryInfo(
      category: _SettingsCategory.advanced,
      title: '高级',
      subtitle: '回放与开发工具',
      icon: Icons.tune_outlined,
      accent: Color(0xFFAEB8CC),
      keywords: ['高级', 'nied', '回放', '时间', '步长', '调试', '开发'],
    ),
  ];

  String _magLabel(double v) {
    if (v == -1) return '不接收';
    if (v == 0) return '不过滤';
    switch (v) {
      case 0:
        return '不过滤';
      case 1.0:
        return 'M 1.0';
      case 1.5:
        return 'M 1.5';
      case 2.0:
        return 'M 2.0';
      case 2.5:
        return 'M 2.5';
      case 3.0:
        return 'M 3.0';
      case 3.5:
        return 'M 3.5';
      case 4.0:
        return 'M 4.0';
      case 4.5:
        return 'M 4.5';
      case 5.0:
        return 'M 5.0';
      default:
        return 'M $v';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final tts = TtsService();
    await tts.init();
    final ttsVoices = await tts.loadVoices();
    if (!mounted) return;
    setState(() {
      _fanServerIndex = prefs.getInt(_fanServerKey) ?? 0;
      _tileKey = MapConfig.normalizeBaseTileKey(
        prefs.getString(_tileKeyKey) ?? 'petalLight',
      );
      _overlayCloud = prefs.getBool(_overlayCloudKey) ?? false;
      _overlayWind = prefs.getBool(_overlayWindKey) ?? false;
      _overlayRain = prefs.getBool(_overlayRainKey) ?? false;
      _overlayCnContour = prefs.getBool(_overlayCnContourKey) ?? false;
      _overlayJmaVolcano = prefs.getBool(_overlayJmaVolcanoKey) ?? false;
      _overlayTyphoon = prefs.getBool(_overlayTyphoonKey) ?? true;
      _overlayFdsnEarthScope =
          prefs.getBool(_overlayFdsnEarthScopeKey) ?? false;
      _overlayFdsnGeofon = prefs.getBool(_overlayFdsnGeofonKey) ?? false;
      _fdsnStationLimit = FdsnMotionService.normalizeStationLimit(
        prefs.getInt(_fdsnStationLimitKey) ??
            FdsnMotionService.defaultStationLimit,
      );
      _niedDataSource = prefs.getString(_niedDataSourceKey) ?? 'lmoni';
      _niedReplayEnabled = prefs.getBool(_niedReplayEnabledKey) ?? false;
      _niedReplayStart =
          prefs.getString(_niedReplayStartKey) ?? '2026-05-30 23:34:00';
      _niedReplayStepSeconds = prefs.getInt(_niedReplayStepKey) ?? 1;
      _shakeSensitivity = prefs.getInt(_shakeSensitivityKey) ?? 2;
      _tremStationEnabled =
          prefs.getBool(QuakeMapView.tremStationEnabledPreferenceKey) ?? true;
      _hideGridOnEew = prefs.getBool(_hideGridOnEewKey) ?? false;
      _sideInfoAutoShowBeta = prefs.getBool(_sideInfoAutoShowBetaKey) ?? true;
      _showEpicenter = prefs.getBool(_showEpicenterKey) ?? false;
      _weatherMarqueeEnabled =
          prefs.getBool(_weatherMarqueeEnabledKey) ?? false;
      _weatherLocalOnly = prefs.getBool(_weatherLocalOnlyKey) ?? false;
      _weatherLocalLevel = prefs.getString(_weatherLocalLevelKey) ?? 'county';
      _ttsEnabled = tts.enabled;
      _ttsEventEnabled = tts.eventEnabled;
      _ttsCountdownEnabled = tts.countdownEnabled;
      _ttsUpdateEnabled = tts.updateEnabled;
      _ttsVoiceId = ttsVoices.any((voice) => voice.id == tts.voiceId)
          ? tts.voiceId
          : '';
      _ttsSpeechRate = tts.speechRate;
      _ttsPitch = tts.pitch;
      _ttsVoices = ttsVoices;
      _gptSovitsEnabled = tts.gptSovitsEnabled;
      _gptSovitsUrlController.text = tts.gptSovitsUrl;
      _gptSovitsRefAudioController.text = tts.gptSovitsRefAudioPath;
      _gptSovitsPromptTextController.text = tts.gptSovitsPromptText;
      _mapViewLat = prefs.getDouble(_mapViewLatKey);
      _mapViewLng = prefs.getDouble(_mapViewLngKey);
      for (final source in QuakeProvider.infoMagFilterSources) {
        final key = '$_magFilterPrefix${source.name}';
        final val = prefs.getDouble(key) ?? 0;
        if (val != 0) _sourceMagFilters[source.name] = val;
      }
      _initialized = true;
    });
    QuakeMapView.niedSourceNotifier.value = _niedDataSource;
    QuakeMapView.shakeSensitivityNotifier.value = _shakeSensitivity;
    QuakeMapView.tremStationEnabledNotifier.value = _tremStationEnabled;
    QuakeMapView.fdsnStationLimitNotifier.value = _fdsnStationLimit;
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value = _sideInfoAutoShowBeta;
    UiRuntimeFlags.weatherMarqueeEnabledNotifier.value = _weatherMarqueeEnabled;
    _niedReplayStartController.text = _niedReplayStart;
    _syncNiedReplayConfig();
    final mapState = context.read<MapStateProvider>();
    mapState.setTileKey(_tileKey);
    mapState.setOverlayEnabled('cloudLayer', _overlayCloud);
    mapState.setOverlayEnabled('windLayer', _overlayWind);
    mapState.setOverlayEnabled('rainLayer', _overlayRain);
    mapState.setOverlayEnabled('cnContour', _overlayCnContour);
    mapState.setOverlayEnabled('volcanoLayer', _overlayJmaVolcano);
    mapState.setOverlayEnabled('typhoonLayer', _overlayTyphoon);
    mapState.setOverlayEnabled('fdsnEarthScope', _overlayFdsnEarthScope);
    mapState.setOverlayEnabled('fdsnGeofon', _overlayFdsnGeofon);
    mapState.setShowEstimatedEpicenter(_showEpicenter);
    context.read<QuakeProvider>().setTyphoonLayerEnabled(_overlayTyphoon);
    context.read<QuakeProvider>().setWeatherLocalOnly(
      _weatherLocalOnly,
      persist: false,
    );
    context.read<QuakeProvider>().setWeatherLocalAdminLevel(
      _weatherLocalLevel,
      persist: false,
    );
  }

  @override
  void dispose() {
    _niedReplayStartController.dispose();
    _settingsSearchController.dispose();
    _gptSovitsUrlController.dispose();
    _gptSovitsRefAudioController.dispose();
    _gptSovitsPromptTextController.dispose();
    super.dispose();
  }

  Future<void> _saveFanServer(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fanServerKey, index);
  }

  Future<void> _saveTileKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tileKeyKey, key);
  }

  Future<void> _saveOverlayState(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
  }

  Future<void> _saveFdsnStationLimit(int limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fdsnStationLimitKey, limit);
  }

  Future<void> _saveSourceMagFilter(String sourceName, double val) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_magFilterPrefix$sourceName';
    if (val == 0) {
      await prefs.remove(key);
    } else {
      await prefs.setDouble(key, val);
    }
  }

  Future<void> _saveNiedDataSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_niedDataSourceKey, source);
  }

  Future<void> _saveNiedReplayEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_niedReplayEnabledKey, enabled);
  }

  Future<void> _saveNiedReplayStart(String start) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_niedReplayStartKey, start);
  }

  Future<void> _saveNiedReplayStep(int stepSeconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_niedReplayStepKey, stepSeconds);
  }

  void _syncNiedReplayConfig() {
    final startJst = _parseNiedReplayTime(_niedReplayStart);
    QuakeMapView.niedReplayNotifier.value =
        _niedReplayEnabled && startJst != null
        ? NiedReplayConfig(
            enabled: true,
            startJst: startJst,
            stepSeconds: _niedReplayStepSeconds,
          )
        : const NiedReplayConfig.disabled();
  }

  DateTime? _parseNiedReplayTime(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll('/', '-').replaceFirst(' ', 'T');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveShakeSensitivity(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_shakeSensitivityKey, level);
  }

  Future<void> _saveTremStationEnabled(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(QuakeMapView.tremStationEnabledPreferenceKey, val);
  }

  Future<void> _saveHideGridOnEew(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideGridOnEewKey, val);
  }

  Future<void> _saveSideInfoAutoShowBeta(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sideInfoAutoShowBetaKey, val);
  }

  Future<void> _saveShowEpicenter(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showEpicenterKey, val);
  }

  Future<void> _saveWeatherMarqueeEnabled(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_weatherMarqueeEnabledKey, val);
  }

  Future<void> _saveWeatherLocalOnly(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_weatherLocalOnlyKey, val);
  }

  Future<void> _saveWeatherLocalLevel(String level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weatherLocalLevelKey, level);
  }

  Future<void> _saveTtsConfig({
    bool? enabled,
    bool? eventEnabled,
    bool? countdownEnabled,
    bool? updateEnabled,
    String? voiceId,
    double? speechRate,
    double? pitch,
    bool? gptSovitsEnabled,
    String? gptSovitsUrl,
    String? gptSovitsRefAudioPath,
    String? gptSovitsPromptText,
  }) async {
    await TtsService().configure(
      enabled: enabled,
      eventEnabled: eventEnabled,
      countdownEnabled: countdownEnabled,
      updateEnabled: updateEnabled,
      voiceId: voiceId,
      speechRate: speechRate,
      pitch: pitch,
      gptSovitsEnabled: gptSovitsEnabled,
      gptSovitsUrl: gptSovitsUrl,
      gptSovitsRefAudioPath: gptSovitsRefAudioPath,
      gptSovitsPromptText: gptSovitsPromptText,
    );
  }

  Future<void> _checkGptSovitsConnection() async {
    if (!mounted) return;
    if (_gptSovitsRefAudioController.text.trim().isEmpty ||
        _gptSovitsPromptTextController.text.trim().isEmpty) {
      setState(() => _gptSovitsStatus = -2); // -2 = 未配置
      return;
    }
    setState(() => _gptSovitsStatus = 1);
    try {
      final ok = await TtsService().testGptSovitsConnection(
        url: _gptSovitsUrlController.text.trim(),
        refAudioPath: _gptSovitsRefAudioController.text.trim(),
        promptText: _gptSovitsPromptTextController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _gptSovitsStatus = ok ? 2 : -1);
    } catch (_) {
      if (!mounted) return;
      setState(() => _gptSovitsStatus = -1);
    }
  }

  Future<void> _saveMapViewCenter(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_mapViewLatKey, lat);
    await prefs.setDouble(_mapViewLngKey, lng);
    if (!mounted) return;
    setState(() {
      _mapViewLat = lat;
      _mapViewLng = lng;
    });
    context.read<QuakeProvider>().setWeatherLocalOnly(
      _weatherLocalOnly,
      persist: false,
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _mapCenterText() {
    if (_mapViewLat == null || _mapViewLng == null) return '当前：跟随系统默认';
    return '当前：${_mapViewLat!.toStringAsFixed(4)}, ${_mapViewLng!.toStringAsFixed(4)}';
  }

  Future<void> _autoLocateMapCenter() async {
    try {
      final pos = await LocationService().requestCurrentPosition();
      if (pos == null) {
        final status = LocationService().statusListenable.value;
        if (status == LocationServiceStatus.serviceDisabled) {
          _showToast('定位服务未开启');
        } else if (status == LocationServiceStatus.permissionDenied) {
          _showToast('定位权限未授予');
        } else {
          _showToast('自动获取定位失败');
        }
        return;
      }

      await _saveMapViewCenter(pos.latitude, pos.longitude);
      _showToast(
        '已更新默认视角：${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
      );
    } catch (e) {
      _showToast('自动获取定位失败: $e');
    }
  }

  Future<void> _openManualCenterDialog() async {
    final latCtl = TextEditingController(
      text: _mapViewLat?.toStringAsFixed(6) ?? '',
    );
    final lngCtl = TextEditingController(
      text: _mapViewLng?.toStringAsFixed(6) ?? '',
    );
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 24,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _borderColor),
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.edit_location_alt_outlined,
                          color: _accentColor,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '手动输入定位',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '请输入经纬度，保存后将作为本地预警定位参考。',
                      style: TextStyle(color: _mutedTextColor, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: latCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: '纬度 (Latitude)',
                        labelStyle: const TextStyle(color: _mutedTextColor),
                        filled: true,
                        fillColor: _fieldColor,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _accentColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: lngCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: '经度 (Longitude)',
                        labelStyle: const TextStyle(color: _mutedTextColor),
                        filled: true,
                        fillColor: _fieldColor,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _accentColor),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: _dividerColor),
                                foregroundColor: Colors.white70,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('取消'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentColor.withValues(
                                  alpha: 0.22,
                                ),
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: _accentColor),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                final lat = double.tryParse(latCtl.text.trim());
                                final lng = double.tryParse(lngCtl.text.trim());
                                if (lat == null || lng == null) {
                                  setDialogState(
                                    () => errorText = '请输入有效的数字坐标',
                                  );
                                  return;
                                }
                                if (lat < -90 || lat > 90) {
                                  setDialogState(
                                    () => errorText = '纬度范围必须在 -90 ~ 90',
                                  );
                                  return;
                                }
                                if (lng < -180 || lng > 180) {
                                  setDialogState(
                                    () => errorText = '经度范围必须在 -180 ~ 180',
                                  );
                                  return;
                                }
                                await _saveMapViewCenter(lat, lng);
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                _showToast(
                                  '已保存默认视角：${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                                );
                              },
                              child: const Text('保存'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    latCtl.dispose();
    lngCtl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020208),
      appBar: AppBar(
        backgroundColor: _appBarColor,
        elevation: 0,
        titleSpacing: 4,
        title: const Text(
          '设置中心',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: _accentColor),
      ),
      body: Stack(
        children: [
          const AppPageBackground(),
          if (_initialized)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 860;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSettingsHeader(),
                          const SizedBox(height: 14),
                          if (!wide) ...[
                            _buildCompactCategoryBar(),
                            const SizedBox(height: 12),
                          ],
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (wide) ...[
                                  SizedBox(
                                    width: 228,
                                    child: _buildCategoryNavigation(),
                                  ),
                                  const SizedBox(width: 14),
                                ],
                                Expanded(child: _buildSettingsContent()),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildSettingsHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '应用设置',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${_categories.length} 个分类',
              style: const TextStyle(color: _mutedTextColor, fontSize: 12),
            ),
          ],
        );
        final search = SizedBox(
          width: compact ? double.infinity : 340,
          height: 42,
          child: TextField(
            controller: _settingsSearchController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: (value) => setState(() => _settingsQuery = value.trim()),
            decoration: InputDecoration(
              hintText: '搜索设置',
              hintStyle: const TextStyle(color: _mutedTextColor),
              prefixIcon: const Icon(
                Icons.search,
                size: 19,
                color: _mutedTextColor,
              ),
              suffixIcon: _settingsQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _settingsSearchController.clear();
                        setState(() => _settingsQuery = '');
                      },
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
              filled: true,
              fillColor: _fieldColor,
              contentPadding: EdgeInsets.zero,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _accentColor),
              ),
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 12), search],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            search,
          ],
        );
      },
    );
  }

  Widget _buildCategoryNavigation() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _dividerColor),
      ),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final info in _categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildCategoryButton(info, expanded: true),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactCategoryBar() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          return _buildCategoryButton(_categories[index], expanded: false);
        },
      ),
    );
  }

  Widget _buildCategoryButton(
    _SettingsCategoryInfo info, {
    required bool expanded,
  }) {
    final selected =
        _settingsQuery.isEmpty && _selectedCategory == info.category;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () {
          _settingsSearchController.clear();
          setState(() {
            _settingsQuery = '';
            _selectedCategory = info.category;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: expanded ? 58 : 42,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 13),
          decoration: BoxDecoration(
            color: selected ? info.accent.withValues(alpha: 0.13) : null,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? info.accent.withValues(alpha: 0.48)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(
                info.icon,
                size: 19,
                color: selected ? info.accent : Colors.white60,
              ),
              const SizedBox(width: 10),
              if (expanded)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _mutedTextColor,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  info.title,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent() {
    final matches = _settingsQuery.isEmpty
        ? const <_SettingsCategoryInfo>[]
        : _categories.where(_categoryMatchesQuery).toList(growable: false);
    final activeInfo = _categoryInfo(_selectedCategory);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color.fromRGBO(5, 7, 18, 0.76),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color:
                        (_settingsQuery.isEmpty
                                ? activeInfo.accent
                                : _accentColor)
                            .withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _settingsQuery.isEmpty ? activeInfo.icon : Icons.search,
                    color: _settingsQuery.isEmpty
                        ? activeInfo.accent
                        : _accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _settingsQuery.isEmpty ? activeInfo.title : '搜索结果',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _settingsQuery.isEmpty
                            ? activeInfo.subtitle
                            : matches.isEmpty
                            ? '未找到“$_settingsQuery”'
                            : '${matches.length} 个相关分类',
                        style: const TextStyle(
                          color: _mutedTextColor,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _dividerColor),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _settingsQuery.isEmpty
                  ? _buildCategoryScrollView(
                      key: ValueKey(_selectedCategory),
                      categories: [_selectedCategory],
                    )
                  : matches.isEmpty
                  ? const _EmptySettingsSearch()
                  : _buildCategoryScrollView(
                      key: ValueKey(_settingsQuery),
                      categories: matches
                          .map((info) => info.category)
                          .toList(growable: false),
                      showCategoryHeaders: true,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryScrollView({
    required Key key,
    required List<_SettingsCategory> categories,
    bool showCategoryHeaders = false,
  }) {
    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (var index = 0; index < categories.length; index++) ...[
          if (showCategoryHeaders)
            _buildSearchCategoryHeader(_categoryInfo(categories[index])),
          ..._buildCategoryPanels(categories[index]),
          if (index != categories.length - 1) const SizedBox(height: 22),
        ],
      ],
    );
  }

  Widget _buildSearchCategoryHeader(_SettingsCategoryInfo info) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 9),
      child: Row(
        children: [
          Icon(info.icon, size: 16, color: info.accent),
          const SizedBox(width: 7),
          Text(
            info.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  bool _categoryMatchesQuery(_SettingsCategoryInfo info) {
    final query = _settingsQuery.toLowerCase();
    final values = [info.title, info.subtitle, ...info.keywords];
    if (info.category == _SettingsCategory.filter) {
      values.addAll(
        QuakeProvider.infoMagFilterSources.expand(
          (source) => [source.name, source.displayName],
        ),
      );
    }
    return values.any((value) => value.toLowerCase().contains(query));
  }

  _SettingsCategoryInfo _categoryInfo(_SettingsCategory category) {
    return _categories.firstWhere((info) => info.category == category);
  }

  List<Widget> _buildCategoryPanels(_SettingsCategory category) {
    switch (category) {
      case _SettingsCategory.data:
        return [
          _buildSectionPanel(
            icon: Icons.dns_outlined,
            title: '连接来源',
            children: [_buildFanServerSelector()],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.sensors_outlined,
            title: '实时强震监测',
            children: [
              _buildNiedDataSourceSelector(),
              const _SettingsDivider(),
              _buildTremStationEnabledSwitch(),
              const _SettingsDivider(),
              _buildShakeSensitivitySelector(),
            ],
          ),
        ];
      case _SettingsCategory.map:
        return [
          _buildSectionPanel(
            icon: Icons.layers_outlined,
            title: '地图外观',
            children: [
              _buildTileSelector(),
              const _SettingsDivider(),
              _buildMapOverlaySelector(),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.my_location_outlined,
            title: '地图位置',
            children: [_buildMapCenterControls()],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.public_outlined,
            title: '全球测站',
            children: [
              _buildFdsnStationSelector(),
              const _SettingsDivider(),
              _buildFdsnStationLimitSelector(),
            ],
          ),
        ];
      case _SettingsCategory.alert:
        return [
          _buildSectionPanel(
            icon: Icons.warning_amber_outlined,
            title: '气象预警',
            children: [
              _buildWeatherAlarmScopeSelector(),
              if (_weatherLocalOnly) ...[
                const _SettingsDivider(),
                _buildWeatherAlarmLocalLevelSelector(),
              ],
              const _SettingsDivider(),
              _buildWeatherMarqueeEnabledSwitch(),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.visibility_outlined,
            title: '界面行为',
            children: [
              _buildHideGridOnEewSwitch(),
              const _SettingsDivider(),
              _buildSideInfoAutoShowSwitch(),
              const _SettingsDivider(),
              _buildEpicenterShowSwitch(),
            ],
          ),
        ];
      case _SettingsCategory.voice:
        return [
          _buildSectionPanel(
            icon: Icons.record_voice_over_outlined,
            title: '语音播报',
            children: [_buildTtsSettings()],
          ),
        ];
      case _SettingsCategory.filter:
        return [
          _buildSectionPanel(
            icon: Icons.filter_alt_outlined,
            title: '信息事件震级过滤',
            children: [_buildMagFilterList()],
          ),
        ];
      case _SettingsCategory.advanced:
        return [
          _buildSectionPanel(
            icon: Icons.history_toggle_off_outlined,
            title: 'NIED 回放',
            children: [_buildNiedReplayControls()],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.developer_mode_outlined,
            title: '开发工具',
            children: [_buildDebugPageEntry()],
          ),
        ];
    }
  }

  Widget _buildSectionPanel({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _accentColor, size: 18),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildFanServerSelector() {
    return _buildSettingRow(
      title: 'FAN 默认服务器',
      subtitle: '选择 FAN 数据源优先连接的服务器',
      leading: Icons.dns_outlined,
      control: _buildDropdown<int>(
        value: _fanServerIndex,
        options: List.generate(
          FanService.serverOptions.length,
          (i) => _SelectOption(i, FanService.serverOptions[i]),
        ),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _fanServerIndex = val);
          _saveFanServer(val);
          SourceManager().getSource<FanService>()?.setDefaultServerIndex(val);
        },
      ),
    );
  }

  Widget _buildTileSelector() {
    return _buildSettingRow(
      title: '地图底图',
      subtitle: '调整主地图底图样式',
      leading: Icons.layers_outlined,
      control: _buildDropdown<String>(
        value: _tileKey,
        options: MapConfig.baseTileOptions.entries
            .map((entry) => _SelectOption(entry.value, entry.key))
            .toList(),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _tileKey = val);
          _saveTileKey(val);
          context.read<MapStateProvider>().setTileKey(val);
        },
      ),
    );
  }

  Widget _buildMapOverlaySelector() {
    return _buildSettingRow(
      title: '叠加图层',
      subtitle: '实况云图/风场/降水、中国等高线与火山情报叠加层',
      leading: Icons.layers_outlined,
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _buildOverlayToggle(
            label: '实况云图',
            selected: _overlayCloud,
            onTap: (val) {
              setState(() => _overlayCloud = val);
              _saveOverlayState(_overlayCloudKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'cloudLayer',
                val,
              );
            },
          ),
          _buildOverlayToggle(
            label: '实况风场',
            selected: _overlayWind,
            onTap: (val) {
              setState(() => _overlayWind = val);
              _saveOverlayState(_overlayWindKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'windLayer',
                val,
              );
            },
          ),
          _buildOverlayToggle(
            label: '实况降水',
            selected: _overlayRain,
            onTap: (val) {
              setState(() => _overlayRain = val);
              _saveOverlayState(_overlayRainKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'rainLayer',
                val,
              );
            },
          ),
          _buildOverlayToggle(
            label: '中国等高线',
            selected: _overlayCnContour,
            onTap: (val) {
              setState(() => _overlayCnContour = val);
              _saveOverlayState(_overlayCnContourKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'cnContour',
                val,
              );
            },
          ),
          _buildOverlayToggle(
            label: 'JMA 火山',
            selected: _overlayJmaVolcano,
            onTap: (val) {
              setState(() => _overlayJmaVolcano = val);
              _saveOverlayState(_overlayJmaVolcanoKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'volcanoLayer',
                val,
              );
            },
          ),
          _buildOverlayToggle(
            label: '台风路径',
            selected: _overlayTyphoon,
            onTap: (val) {
              setState(() => _overlayTyphoon = val);
              _saveOverlayState(_overlayTyphoonKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'typhoonLayer',
                val,
              );
              context.read<QuakeProvider>().setTyphoonLayerEnabled(val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayToggle({
    required String label,
    required bool selected,
    required ValueChanged<bool> onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onTap(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accentColor.withValues(alpha: 0.22) : _fieldColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _accentColor : _dividerColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMapCenterControls() {
    return _buildSettingRow(
      title: '默认视角定位',
      subtitle: '可自动获取定位，或手动输入经纬度；${_mapCenterText()}',
      leading: Icons.my_location_outlined,
      control: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 290;
          final buttons = [
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: _accentColor.withValues(alpha: 0.7),
                    ),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _autoLocateMapCenter,
                  icon: const Icon(Icons.gps_fixed, size: 16),
                  label: const Text('自动定位'),
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: _accentColor.withValues(alpha: 0.7),
                    ),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _openManualCenterDialog,
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                  label: const Text('手动输入'),
                ),
              ),
            ),
          ];

          if (vertical) {
            return Column(
              children: [buttons[0], const SizedBox(height: 8), buttons[1]],
            );
          }

          return Row(
            children: [buttons[0], const SizedBox(width: 8), buttons[1]],
          );
        },
      ),
    );
  }

  Widget _buildFdsnStationSelector() {
    return _buildSettingRow(
      title: 'FDSN 测站',
      subtitle: '显示 EarthScope / GEOFON 测站点位；实时包由应用内 SeedLink 连接接收',
      leading: Icons.public_outlined,
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _buildOverlayToggle(
            label: 'EarthScope',
            selected: _overlayFdsnEarthScope,
            onTap: (val) {
              setState(() => _overlayFdsnEarthScope = val);
              _saveOverlayState(_overlayFdsnEarthScopeKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'fdsnEarthScope',
                val,
              );
            },
          ),
          _buildOverlayToggle(
            label: 'GEOFON',
            selected: _overlayFdsnGeofon,
            onTap: (val) {
              setState(() => _overlayFdsnGeofon = val);
              _saveOverlayState(_overlayFdsnGeofonKey, val);
              context.read<MapStateProvider>().setOverlayEnabled(
                'fdsnGeofon',
                val,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFdsnStationLimitSelector() {
    return _buildSettingRow(
      title: '连接上限',
      subtitle: '限制应用内 SeedLink 最多连接的全球实时台站数量',
      leading: Icons.hub_outlined,
      control: _buildDropdown<int>(
        value: _fdsnStationLimit,
        options: FdsnMotionService.stationLimitOptions
            .map((limit) => _SelectOption(limit, '$limit'))
            .toList(growable: false),
        onChanged: (limit) {
          if (limit == null) return;
          final normalized = FdsnMotionService.normalizeStationLimit(limit);
          setState(() => _fdsnStationLimit = normalized);
          _saveFdsnStationLimit(normalized);
          QuakeMapView.fdsnStationLimitNotifier.value = normalized;
        },
      ),
    );
  }

  Widget _buildNiedDataSourceSelector() {
    const options = [
      ('lmoni', 'Lmoni'),
      ('kmoni', 'KMONI'),
      ('yahoo', 'Yahoo'),
    ];
    return _buildSettingRow(
      title: 'NIED 数据源',
      subtitle: '切换强震监测数据输入来源',
      leading: Icons.public_outlined,
      control: _buildSegmentedSelector<String>(
        value: _niedDataSource,
        options: options.map((opt) => _SelectOption(opt.$1, opt.$2)).toList(),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _niedDataSource = val);
          _saveNiedDataSource(val);
          QuakeMapView.niedSourceNotifier.value = val;
        },
      ),
    );
  }

  Widget _buildNiedReplayControls() {
    final timeValid = _parseNiedReplayTime(_niedReplayStart) != null;
    return ExcludeSemantics(
      child: Column(
        children: [
          _buildSettingRow(
            title: 'NIED 回放',
            subtitle: '按 JST 时间回放当前 NIED 数据源',
            leading: Icons.history_toggle_off_outlined,
            control: Align(
              alignment: Alignment.centerRight,
              child: Switch(
                value: _niedReplayEnabled,
                activeThumbColor: _accentColor,
                activeTrackColor: _accentColor.withValues(alpha: 0.38),
                inactiveThumbColor: Colors.white70,
                inactiveTrackColor: Colors.white24,
                onChanged: (val) {
                  setState(() => _niedReplayEnabled = val);
                  _saveNiedReplayEnabled(val);
                  _syncNiedReplayConfig();
                },
              ),
            ),
          ),
          if (_niedReplayEnabled) ...[
            const _SettingsDivider(),
            _buildSettingRow(
              title: '回放起点',
              subtitle: timeValid
                  ? '格式: yyyy-MM-dd HH:mm:ss'
                  : '时间格式无效，例如: 2026-05-30 23:34:00',
              leading: Icons.schedule_outlined,
              control: TextField(
                controller: _niedReplayStartController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _fieldColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: timeValid ? _dividerColor : Colors.redAccent,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: timeValid ? _accentColor : Colors.redAccent,
                    ),
                  ),
                ),
                onChanged: (val) {
                  setState(() => _niedReplayStart = val);
                  _saveNiedReplayStart(val);
                  _syncNiedReplayConfig();
                },
              ),
            ),
            const _SettingsDivider(),
            _buildSettingRow(
              title: '回放步长',
              subtitle: '每秒回放推进的数据时间步长',
              leading: Icons.speed_outlined,
              control: _buildSegmentedSelector<int>(
                value: _niedReplayStepSeconds,
                options: const [
                  _SelectOption(1, '1 s'),
                  _SelectOption(5, '5 s'),
                  _SelectOption(10, '10 s'),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _niedReplayStepSeconds = val);
                  _saveNiedReplayStep(val);
                  _syncNiedReplayConfig();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShakeSensitivitySelector() {
    const options = [(1, '低灵敏度'), (2, '标准（推荐）'), (3, '高灵敏度')];
    return _buildSettingRow(
      title: '摇晃检测灵敏度',
      subtitle: '影响 NIED / KMA / TREM 的触发阈值',
      leading: Icons.speed_outlined,
      control: _buildSegmentedSelector<int>(
        value: _shakeSensitivity,
        options: options.map((opt) => _SelectOption(opt.$1, opt.$2)).toList(),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _shakeSensitivity = val);
          _saveShakeSensitivity(val);
          QuakeMapView.shakeSensitivityNotifier.value = val;
        },
      ),
    );
  }

  Widget _buildTremStationEnabledSwitch() {
    return _buildSettingRow(
      title: 'TREM 测站连接',
      subtitle: '关闭后不连接 ExpTech TREM 测站接口，也不刷新 TREM 测站图层',
      leading: Icons.sensors_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _tremStationEnabled,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _tremStationEnabled = val);
            _saveTremStationEnabled(val);
            QuakeMapView.tremStationEnabledNotifier.value = val;
          },
        ),
      ),
    );
  }

  Widget _buildWeatherAlarmScopeSelector() {
    return _buildSettingRow(
      title: '气象预警接收范围',
      subtitle: '在“全部预警”和“当地预警”之间切换',
      leading: Icons.place_outlined,
      control: _buildSegmentedSelector<bool>(
        value: _weatherLocalOnly,
        options: const [
          _SelectOption(false, '全部预警'),
          _SelectOption(true, '当地预警'),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() => _weatherLocalOnly = val);
          _saveWeatherLocalOnly(val);
          context.read<QuakeProvider>().setWeatherLocalOnly(val);
        },
      ),
    );
  }

  Widget _buildWeatherAlarmLocalLevelSelector() {
    final provider = context.watch<QuakeProvider>();
    final province = provider.weatherDetectedProvince;
    return _buildSettingRow(
      title: '当地气象预警级别',
      subtitle: province != null
          ? '当前区域：$province — 按行政层级过滤（省 / 市 / 县）'
          : '按行政层级过滤（省 / 市 / 县），仅在当地预警模式生效',
      leading: Icons.account_tree_outlined,
      control: _buildSegmentedSelector<String>(
        value: _weatherLocalLevel,
        options: const [
          _SelectOption('province', '省级'),
          _SelectOption('city', '市级'),
          _SelectOption('county', '县级'),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() => _weatherLocalLevel = val);
          _saveWeatherLocalLevel(val);
          context.read<QuakeProvider>().setWeatherLocalAdminLevel(val);
        },
      ),
    );
  }

  Widget _buildWeatherMarqueeEnabledSwitch() {
    return _buildSettingRow(
      title: '显示天气预警字幕',
      subtitle: '在地图顶部显示天气预警跑马灯；默认关闭',
      leading: Icons.subtitles_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _weatherMarqueeEnabled,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _weatherMarqueeEnabled = val);
            _saveWeatherMarqueeEnabled(val);
            UiRuntimeFlags.weatherMarqueeEnabledNotifier.value = val;
          },
        ),
      ),
    );
  }

  Widget _buildHideGridOnEewSwitch() {
    return _buildSettingRow(
      title: '预警时隐藏网格',
      subtitle: '地震预警触发时隐藏测站闪烁网格',
      leading: Icons.grid_off_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _hideGridOnEew,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _hideGridOnEew = val);
            _saveHideGridOnEew(val);
          },
        ),
      ),
    );
  }

  Widget _buildSideInfoAutoShowSwitch() {
    return _buildSettingRow(
      title: '侧边自动显示信息（beta）',
      subtitle: '弱反/检知/S-net >= 1 时自动弹出信息卡片，稍后自动收起',
      leading: Icons.view_sidebar_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _sideInfoAutoShowBeta,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _sideInfoAutoShowBeta = val);
            _saveSideInfoAutoShowBeta(val);
            UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value = val;
          },
        ),
      ),
    );
  }

  Widget _buildEpicenterShowSwitch() {
    return _buildSettingRow(
      title: '推算震中显示（beta）',
      subtitle: 'NIED 检测时在地图上显示网格搜索推算的震中位置',
      leading: Icons.crisis_alert_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _showEpicenter,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _showEpicenter = val);
            _saveShowEpicenter(val);
            context.read<MapStateProvider>().setShowEstimatedEpicenter(val);
          },
        ),
      ),
    );
  }

  Widget _buildTtsSettings() {
    final voiceOptions = _ttsVoices.isEmpty
        ? const [TtsVoiceOption.systemDefault]
        : _ttsVoices;
    final selectedVoice = voiceOptions.any((voice) => voice.id == _ttsVoiceId)
        ? _ttsVoiceId
        : '';

    return Column(
      children: [
        _buildSettingRow(
          title: '语音播报',
          subtitle: 'SREV 音效播放后，再播报事件文字。',
          leading: Icons.record_voice_over_outlined,
          control: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: _ttsEnabled,
              activeThumbColor: _accentColor,
              activeTrackColor: _accentColor.withValues(alpha: 0.38),
              inactiveThumbColor: Colors.white70,
              inactiveTrackColor: Colors.white24,
              onChanged: (val) {
                setState(() => _ttsEnabled = val);
                _saveTtsConfig(enabled: val);
              },
            ),
          ),
        ),
        const _SettingsDivider(),
        // GPT-SoVITS 切换
        _buildSettingRow(
          title: 'GPT-SoVITS 语音合成',
          subtitle: '启用后将通过本地 GPT-SoVITS-V4 服务生成语音。',
          leading: Icons.smart_toy_outlined,
          control: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: _gptSovitsEnabled,
              activeThumbColor: _accentColor,
              activeTrackColor: _accentColor.withValues(alpha: 0.38),
              inactiveThumbColor: Colors.white70,
              inactiveTrackColor: Colors.white24,
              onChanged: (val) {
                setState(() => _gptSovitsEnabled = val);
                _saveTtsConfig(gptSovitsEnabled: val);
              },
            ),
          ),
        ),
        if (_gptSovitsEnabled) ...[
          _buildSettingRow(
            title: '服务地址',
            subtitle: 'GPT-SoVITS API 地址，默认 http://localhost:9880',
            leading: Icons.link,
            control: SizedBox(
              width: 260,
              child: TextField(
                controller: _gptSovitsUrlController,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _accentColor),
                  ),
                ),
                onChanged: (val) {
                  _saveTtsConfig(gptSovitsUrl: val);
                },
              ),
            ),
          ),
          _buildSettingRow(
            title: '参考音频',
            subtitle: 'GPT-SoVITS 参考音频 WAV 路径',
            leading: Icons.audiotrack,
            control: SizedBox(
              width: 260,
              child: TextField(
                controller: _gptSovitsRefAudioController,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _accentColor),
                  ),
                ),
                onChanged: (val) {
                  _saveTtsConfig(gptSovitsRefAudioPath: val);
                },
              ),
            ),
          ),
          _buildSettingRow(
            title: '参考文本',
            subtitle: '参考音频对应的文本内容',
            leading: Icons.text_fields,
            control: SizedBox(
              width: 260,
              child: TextField(
                controller: _gptSovitsPromptTextController,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _accentColor),
                  ),
                ),
                onChanged: (val) {
                  _saveTtsConfig(gptSovitsPromptText: val);
                },
              ),
            ),
          ),
          // 连接状态
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _gptSovitsStatus == 2
                        ? Colors.green
                        : _gptSovitsStatus == -1
                        ? Colors.red
                        : Colors.grey,
                  ),
                ),
                Text(
                  _gptSovitsStatus == 2
                      ? '已连接'
                      : _gptSovitsStatus == -1
                      ? '不可达'
                      : _gptSovitsStatus == -2
                      ? '未配置'
                      : _gptSovitsStatus == 1
                      ? '检查中...'
                      : '未检测',
                  style: TextStyle(
                    fontSize: 12,
                    color: _gptSovitsStatus == 2
                        ? Colors.green.shade300
                        : _gptSovitsStatus == -1
                        ? Colors.red.shade300
                        : _gptSovitsStatus == -2
                        ? Colors.orange.shade300
                        : _mutedTextColor,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 28,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _gptSovitsStatus == 1
                        ? null
                        : _checkGptSovitsConnection,
                    child: const Text('检测', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          const _SettingsDivider(),
        ],
        _buildSettingRow(
          title: '播报内容',
          subtitle: '可分别控制事件说明、倒计时和更新报文。',
          leading: Icons.campaign_outlined,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMiniSwitch(
                label: '事件',
                value: _ttsEventEnabled,
                onChanged: (val) {
                  setState(() => _ttsEventEnabled = val);
                  _saveTtsConfig(eventEnabled: val);
                },
              ),
              const SizedBox(height: 8),
              _buildMiniSwitch(
                label: '倒计时',
                value: _ttsCountdownEnabled,
                onChanged: (val) {
                  setState(() => _ttsCountdownEnabled = val);
                  _saveTtsConfig(countdownEnabled: val);
                },
              ),
              const SizedBox(height: 8),
              _buildMiniSwitch(
                label: '更新报',
                value: _ttsUpdateEnabled,
                onChanged: (val) {
                  setState(() => _ttsUpdateEnabled = val);
                  _saveTtsConfig(updateEnabled: val);
                },
              ),
            ],
          ),
        ),
        const _SettingsDivider(),
        _buildSettingRow(
          title: '语音音色',
          subtitle: '可选择系统已安装的 TTS 语音；没有合适选项时使用系统默认。',
          leading: Icons.graphic_eq_outlined,
          control: _buildDropdown<String>(
            value: selectedVoice,
            options: voiceOptions
                .map((voice) => _SelectOption(voice.id, voice.label))
                .toList(),
            onChanged: (val) {
              if (val == null) return;
              setState(() => _ttsVoiceId = val);
              _saveTtsConfig(voiceId: val);
            },
          ),
        ),
        const _SettingsDivider(),
        _buildSettingRow(
          title: '语速',
          subtitle: '调低会更清楚，调高会更紧凑。',
          leading: Icons.speed_outlined,
          control: _buildTtsSlider(
            value: _ttsSpeechRate,
            min: 0.35,
            max: 0.85,
            label: _ttsSpeechRate.toStringAsFixed(2),
            onChanged: (val) {
              setState(() => _ttsSpeechRate = val);
              _saveTtsConfig(speechRate: val);
            },
          ),
        ),
        const _SettingsDivider(),
        _buildSettingRow(
          title: '音调',
          subtitle: '用于微调语音明亮度。',
          leading: Icons.tune_outlined,
          control: _buildTtsSlider(
            value: _ttsPitch,
            min: 0.75,
            max: 1.35,
            label: _ttsPitch.toStringAsFixed(2),
            onChanged: (val) {
              setState(() => _ttsPitch = val);
              _saveTtsConfig(pitch: val);
            },
          ),
        ),
        const _SettingsDivider(),
        _buildSettingRow(
          title: '试听',
          subtitle: '立即用当前配置播放一段测试语音。',
          leading: Icons.play_circle_outline,
          control: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 150,
              height: 40,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _accentColor),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  TtsService().speak('RhythmQuake 语音播报测试。', interrupt: true);
                },
                child: const Text('播放测试'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: value ? _accentColor : _dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: value ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: _accentColor,
            activeTrackColor: _accentColor.withValues(alpha: 0.38),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTtsSlider({
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            activeColor: _accentColor,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMagFilterList() {
    final sources = QuakeProvider.infoMagFilterSources;
    return Column(
      children: List.generate(sources.length, (index) {
        final source = sources[index];
        final sourceName = source.name;
        final currentVal = _sourceMagFilters[sourceName] ?? 0;
        final displayName = source.displayName;
        return Column(
          children: [
            _buildSettingRow(
              title: displayName,
              subtitle: '低于阈值的信息事件不会显示',
              leading: Icons.timeline_outlined,
              control: _buildDropdown<double>(
                value: magOptions.contains(currentVal) ? currentVal : 0,
                options: magOptions
                    .map((opt) => _SelectOption(opt, _magLabel(opt)))
                    .toList(),
                width: 148,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    if (val == 0) {
                      _sourceMagFilters.remove(sourceName);
                    } else {
                      _sourceMagFilters[sourceName] = val;
                    }
                  });
                  _saveSourceMagFilter(sourceName, val);
                  context.read<QuakeProvider>().setSourceInfoMagFilter(
                    source,
                    val,
                  );
                },
              ),
            ),
            if (index != sources.length - 1) const _SettingsDivider(),
          ],
        );
      }),
    );
  }

  Widget _buildDebugPageEntry() {
    return _buildSettingRow(
      title: '调试页面',
      subtitle: '进入应用调试页面',
      leading: Icons.developer_mode_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 160,
          height: 40,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _accentColor),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugPage()),
              );
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('打开调试页'),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String subtitle,
    required IconData leading,
    required Widget control,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final titleBlock = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accentColor.withValues(alpha: 0.18)),
              ),
              child: Icon(leading, size: 18, color: _accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _mutedTextColor,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleBlock, const SizedBox(height: 12), control],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 330),
              child: control,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<_SelectOption<T>> options,
    required ValueChanged<T?> onChanged,
    double? width,
  }) {
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: InputDecoration(
          filled: true,
          fillColor: _fieldColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _dividerColor),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: const Color(0xFF101327),
            iconEnabledColor: _accentColor,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            alignment: Alignment.centerLeft,
            items: options.map((option) {
              return DropdownMenuItem<T>(
                value: option.value,
                child: Text(option.label, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedSelector<T>({
    required T value,
    required List<_SelectOption<T>> options,
    required ValueChanged<T?> onChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumn = constraints.maxWidth < 300;
        Widget buildItem(_SelectOption<T> option) {
          final selected = option.value == value;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onChanged(option.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 40,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected
                    ? _accentColor.withValues(alpha: 0.22)
                    : _fieldColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? _accentColor : _dividerColor,
                ),
              ),
              child: Text(
                option.label,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }

        if (useColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(options.length, (index) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == options.length - 1 ? 0 : 6,
                ),
                child: buildItem(options[index]),
              );
            }),
          );
        }

        return Row(
          children: List.generate(options.length, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == options.length - 1 ? 0 : 6,
                ),
                child: buildItem(options[index]),
              ),
            );
          }),
        );
      },
    );
  }
}

class _SelectOption<T> {
  final T value;
  final String label;

  const _SelectOption(this.value, this.label);
}

enum _SettingsCategory { data, map, alert, voice, filter, advanced }

class _SettingsCategoryInfo {
  final _SettingsCategory category;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<String> keywords;

  const _SettingsCategoryInfo({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.keywords,
  });
}

class _EmptySettingsSearch extends StatelessWidget {
  const _EmptySettingsSearch();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_outlined, color: Colors.white38, size: 34),
          SizedBox(height: 10),
          Text(
            '没有匹配的设置',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        thickness: 1,
        color: _SettingsPageState._dividerColor,
      ),
    );
  }
}
