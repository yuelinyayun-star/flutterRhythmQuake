import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../providers/notification_settings_provider.dart';
import '../../providers/background_settings_provider.dart';
import '../../models/notification_event_settings.dart';
import '../../services/location_service.dart';
import '../../services/background_service.dart';
import '../../services/tts_service.dart';
import '../../services/sources/fan_service.dart';
import '../../services/sources/whews_service.dart';
import '../../services/sources/nowquake_cenc_intensity_service.dart';
import '../../services/sources/fdsn_motion_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/source_manager.dart';
import '../../services/sources/eqlist/eqlist_manager.dart';
import '../../services/wauth_service.dart';
import '../map/map_config.dart';
import '../map/quake_map_view.dart';
import '../../models/quake_message.dart';
import 'app_page_background.dart';
import 'debug_page.dart';
import 'ui_runtime_flags.dart';
import 'package:flutter/foundation.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  _SettingsCategory _selectedCategory = _SettingsCategory.data;
  String _settingsQuery = '';
  bool _fanEnabled = true;
  bool _whewsEnabled = false;
  bool _whewsNiedEnabled = false;
  bool _whewsSnetEnabled = false;
  bool _whewsKmaEnabled = false;
  final WAuthService _wauthService = WAuthService();
  String? _wauthAccessToken;
  Map<String, dynamic>? _wauthUserInfo;
  bool _wauthBusy = false;
  bool _wauthBrowserOpened = false;
  bool _wauthVerifying = false;
  bool _whewsApiAuthorized = false;
  String? _wauthError;
  bool _nowQuakeCencIrEnabled = true;
  bool _cencCmtEnabled = true;
  bool _usgsCmtEnabled = true;
  bool _jmaCmtEnabled = true;
  bool _fnetCmtEnabled = true;
  bool _hinetAquaCmtEnabled = true;
  bool _wolfxEnabled = true;
  bool _wolfxSeisJsEnabled = true;
  bool _p2pquakeEnabled = true;
  bool _kmaPewsEnabled = true;
  bool _pAlertEnabled = true;
  bool _niedMonitorEnabled = true;
  bool _niedLpgmEnabled = true;
  bool _snetEnabled = true;
  bool _fdsnSeedLinkEnabled = false;
  int _fanServerIndex = 0;
  String _tileKey = 'petalLight';
  bool _overlayCloud = false;
  bool _overlayWind = false;
  bool _overlayRain = false;
  bool _overlayRadarChina = false;
  bool _overlaySatelliteCloud = false;
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
  bool _displayShindo0 = false;
  int _kmaIntensityHoldFrames = 1;
  bool _hideGridOnEew = false;
  bool _sideInfoAutoShowBeta = true;
  bool _showEpicenter = false;
  static const String _showEpicenterKey = 'show_estimated_epicenter';
  bool _weatherMarqueeEnabled = false;
  bool _weatherLocalOnly = true;
  String _weatherLocalLevel = 'county';
  bool _ttsEnabled = false;
  bool _ttsEventEnabled = false;
  bool _ttsCountdownEnabled = false;
  bool _ttsUpdateEnabled = false;
  bool? _notificationPermissionGranted;
  bool _notificationPermissionBusy = false;
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
  final TextEditingController _infoActionWhitelistController =
      TextEditingController();
  final TextEditingController _fanApiKeyController = TextEditingController();
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
  static const String _overlayRadarChinaKey = 'map_overlay_radarChinaLayer';
  static const String _overlaySatelliteCloudKey =
      'map_overlay_satelliteCloudLayer';
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
  static const String _fanEnabledKey = QuakeMapView.fanEnabledPreferenceKey;
  static const String _whewsEnabledKey = 'api_source_whews_enabled';
  static const String _whewsNiedEnabledKey =
      QuakeMapView.whewsNiedEnabledPreferenceKey;
  static const String _whewsSnetEnabledKey =
      QuakeMapView.whewsSnetEnabledPreferenceKey;
  static const String _whewsKmaEnabledKey =
      QuakeMapView.whewsKmaEnabledPreferenceKey;
  static const String _nowQuakeCencIrEnabledKey =
      NowQuakeCencIntensityService.preferenceKey;
  static const String _cencCmtEnabledKey = 'api_source_cenc_cmt_enabled';
  static const String _usgsCmtEnabledKey = 'api_source_usgs_cmt_enabled';
  static const String _jmaCmtEnabledKey = 'api_source_jma_cmt_enabled';
  static const String _fnetCmtEnabledKey = 'api_source_fnet_cmt_enabled';
  static const String _hinetAquaCmtEnabledKey =
      'api_source_hinet_aqua_cmt_enabled';
  static const String _wolfxEnabledKey = QuakeMapView.wolfxEnabledPreferenceKey;
  static const String _wolfxSeisJsEnabledKey =
      QuakeMapView.wolfxSeisJsEnabledPreferenceKey;
  static const String _p2pquakeEnabledKey =
      QuakeMapView.p2pquakeEnabledPreferenceKey;
  static const String _kmaPewsEnabledKey =
      QuakeMapView.kmaPewsEnabledPreferenceKey;
  static const String _pAlertEnabledKey =
      QuakeMapView.pAlertEnabledPreferenceKey;
  static const String _niedMonitorEnabledKey =
      QuakeMapView.niedMonitorEnabledPreferenceKey;
  static const String _niedLpgmEnabledKey =
      QuakeMapView.niedLpgmEnabledPreferenceKey;
  static const String _snetEnabledKey = QuakeMapView.snetEnabledPreferenceKey;
  static const String _fdsnSeedLinkEnabledKey =
      QuakeMapView.fdsnSeedLinkEnabledPreferenceKey;

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
      title: 'API与数据源',
      subtitle: '接口开关、数据源和过滤',
      icon: Icons.hub_outlined,
      accent: Color(0xFF62C6FF),
      keywords: [
        'api',
        'whews',
        'wauth',
        '账号',
        '授权',
        'fan',
        'nowquake',
        'cenc-ir',
        '烈度速报',
        'wolfx',
        'p2pquake',
        'kma',
        'pews',
        'p-alert',
        'palert',
        'trem',
        'rts',
        'nied',
        'lmoni',
        'kmoni',
        'yahoo',
        's-net',
        'fdsn',
        'seedlink',
        '摇晃',
        '灵敏度',
        '过滤',
      ],
    ),
    _SettingsCategoryInfo(
      category: _SettingsCategory.map,
      title: '地图与通知',
      subtitle: '底图、图层、定位和通知',
      icon: Icons.map_outlined,
      accent: Color(0xFF72D6B1),
      keywords: [
        '地图',
        '底图',
        '图层',
        '云图',
        '卫星',
        '西太',
        '东南沿海',
        '风场',
        '降水',
        '雷达',
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
        '通知',
        '推送',
        '提醒',
      ],
    ),
    _SettingsCategoryInfo(
      category: _SettingsCategory.alert,
      title: '气象火山预警',
      subtitle: '气象预警与信息显示',
      icon: Icons.crisis_alert_outlined,
      accent: Color(0xFFFFC66D),
      keywords: [
        '预警',
        '气象',
        '火山',
        '信息显示',
        '云图',
        '风场',
        '降水',
        '等高线',
        '台风',
        '当地',
        '省级',
        '市级',
        '县级',
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
      category: _SettingsCategory.advanced,
      title: '高级',
      subtitle: '界面行为与开发工具',
      icon: Icons.tune_outlined,
      accent: Color(0xFFAEB8CC),
      keywords: ['高级', '网格', '侧边', '震中', '调试', '开发'],
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
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _refreshNotificationPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationPermission();
      if (_wauthAccessToken != null && !_wauthBusy && !_wauthVerifying) {
        _confirmSavedWAuthLogin();
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final tts = TtsService();
    await tts.init();
    final ttsVoices = await tts.loadVoices();
    final savedWAuthAccessToken = prefs
        .getString(WAuthService.accessTokenPreferenceKey)
        ?.trim();
    if (!mounted) return;
    setState(() {
      _fanEnabled = prefs.getBool(_fanEnabledKey) ?? true;
      _whewsEnabled = prefs.getBool(_whewsEnabledKey) ?? false;
      _whewsNiedEnabled = prefs.getBool(_whewsNiedEnabledKey) ?? false;
      _whewsSnetEnabled = prefs.getBool(_whewsSnetEnabledKey) ?? false;
      _whewsKmaEnabled = prefs.getBool(_whewsKmaEnabledKey) ?? false;
      _nowQuakeCencIrEnabled = prefs.getBool(_nowQuakeCencIrEnabledKey) ?? true;
      _cencCmtEnabled = prefs.getBool(_cencCmtEnabledKey) ?? true;
      _usgsCmtEnabled = prefs.getBool(_usgsCmtEnabledKey) ?? true;
      _jmaCmtEnabled = prefs.getBool(_jmaCmtEnabledKey) ?? true;
      _fnetCmtEnabled = prefs.getBool(_fnetCmtEnabledKey) ?? true;
      _hinetAquaCmtEnabled = prefs.getBool(_hinetAquaCmtEnabledKey) ?? true;
      _wolfxEnabled = prefs.getBool(_wolfxEnabledKey) ?? true;
      _wolfxSeisJsEnabled = prefs.getBool(_wolfxSeisJsEnabledKey) ?? true;
      _p2pquakeEnabled = prefs.getBool(_p2pquakeEnabledKey) ?? true;
      _kmaPewsEnabled = prefs.getBool(_kmaPewsEnabledKey) ?? true;
      _pAlertEnabled = prefs.getBool(_pAlertEnabledKey) ?? true;
      _niedMonitorEnabled = prefs.getBool(_niedMonitorEnabledKey) ?? true;
      _niedLpgmEnabled = prefs.getBool(_niedLpgmEnabledKey) ?? true;
      _snetEnabled = prefs.getBool(_snetEnabledKey) ?? true;
      _fdsnSeedLinkEnabled = prefs.getBool(_fdsnSeedLinkEnabledKey) ?? false;
      _fanApiKeyController.text =
          prefs.getString(FanService.apiKeyPreferenceKey) ?? '';
      _wauthAccessToken = savedWAuthAccessToken?.isEmpty == false
          ? savedWAuthAccessToken
          : null;
      _wauthUserInfo = null;
      _wauthVerifying = false;
      _tileKey = MapConfig.normalizeBaseTileKey(
        prefs.getString(_tileKeyKey) ?? 'petalLight',
      );
      _overlayCloud = prefs.getBool(_overlayCloudKey) ?? false;
      _overlayWind = prefs.getBool(_overlayWindKey) ?? false;
      _overlayRain = prefs.getBool(_overlayRainKey) ?? false;
      _overlayRadarChina = prefs.getBool(_overlayRadarChinaKey) ?? false;
      _overlaySatelliteCloud =
          prefs.getBool(_overlaySatelliteCloudKey) ?? false;
      _overlayCnContour = prefs.getBool(_overlayCnContourKey) ?? false;
      _overlayJmaVolcano = prefs.getBool(_overlayJmaVolcanoKey) ?? false;
      _overlayTyphoon = prefs.getBool(_overlayTyphoonKey) ?? false;
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
      _displayShindo0 =
          prefs.getBool(QuakeMapView.displayShindo0PreferenceKey) ?? false;
      _kmaIntensityHoldFrames =
          prefs.getInt(QuakeMapView.kmaIntensityHoldPreferenceKey) ?? 1;
      _hideGridOnEew = prefs.getBool(_hideGridOnEewKey) ?? false;
      _sideInfoAutoShowBeta = prefs.getBool(_sideInfoAutoShowBetaKey) ?? true;
      _showEpicenter = prefs.getBool(_showEpicenterKey) ?? false;
      _weatherMarqueeEnabled =
          prefs.getBool(_weatherMarqueeEnabledKey) ?? false;
      _weatherLocalOnly = prefs.getBool(_weatherLocalOnlyKey) ?? true;
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
      _infoActionWhitelistController.text =
          prefs.getString(QuakeProvider.infoActionWhitelistPreferenceKey) ?? '';
      _initialized = true;
    });
    QuakeMapView.niedSourceNotifier.value = _niedDataSource;
    QuakeMapView.shakeSensitivityNotifier.value = _shakeSensitivity;
    QuakeMapView.wolfxSeisJsEnabledNotifier.value = _wolfxSeisJsEnabled;
    QuakeMapView.kmaPewsEnabledNotifier.value = _kmaPewsEnabled;
    QuakeMapView.pAlertEnabledNotifier.value = _pAlertEnabled;
    QuakeMapView.niedMonitorEnabledNotifier.value = _niedMonitorEnabled;
    QuakeMapView.niedLpgmEnabledNotifier.value = _niedLpgmEnabled;
    QuakeMapView.tremStationEnabledNotifier.value = _tremStationEnabled;
    QuakeMapView.displayShindo0Notifier.value = _displayShindo0;
    QuakeMapView.kmaIntensityHoldNotifier.value = _kmaIntensityHoldFrames;
    QuakeMapView.snetEnabledNotifier.value = _snetEnabled;
    QuakeMapView.fdsnSeedLinkEnabledNotifier.value = _fdsnSeedLinkEnabled;
    QuakeMapView.whewsApiTokenNotifier.value =
        prefs.getString(WAuthService.apiTokenPreferenceKey) ?? '';
    QuakeMapView.whewsNiedEnabledNotifier.value = false;
    QuakeMapView.whewsSnetEnabledNotifier.value = false;
    QuakeMapView.whewsKmaEnabledNotifier.value = false;
    QuakeMapView.fdsnStationLimitNotifier.value = _fdsnStationLimit;
    SourceManager().setSourceEnabled('FAN', _fanEnabled);
    SourceManager().setSourceEnabled('WHEWS', false);
    SourceManager().setSourceEnabled('NowQuake', _nowQuakeCencIrEnabled);
    if (!_cencCmtEnabled) EqlistManager().cencCmt.stop();
    if (!_usgsCmtEnabled) EqlistManager().usgsCmt.stop();
    if (!_jmaCmtEnabled) EqlistManager().jmaCmt.stop();
    if (!_fnetCmtEnabled) EqlistManager().fnetCmt.stop();
    if (!_hinetAquaCmtEnabled) EqlistManager().hinetAquaCmt.stop();
    SourceManager().setSourceEnabled('Wolfx', _wolfxEnabled);
    SourceManager().setSourceEnabled('P2P', _p2pquakeEnabled);
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value = _sideInfoAutoShowBeta;
    UiRuntimeFlags.weatherMarqueeEnabledNotifier.value = _weatherMarqueeEnabled;
    _niedReplayStartController.text = _niedReplayStart;
    _syncNiedReplayConfig();
    final mapState = context.read<MapStateProvider>();
    mapState.setTileKey(_tileKey);
    mapState.setOverlayEnabled('cloudLayer', _overlayCloud);
    mapState.setOverlayEnabled('windLayer', _overlayWind);
    mapState.setOverlayEnabled('rainLayer', _overlayRain);
    mapState.setOverlayEnabled('radarChinaLayer', _overlayRadarChina);
    mapState.setOverlayEnabled('satelliteCloudLayer', _overlaySatelliteCloud);
    mapState.setOverlayEnabled('cnContour', _overlayCnContour);
    mapState.setOverlayEnabled('volcanoLayer', _overlayJmaVolcano);
    mapState.setOverlayEnabled('typhoonLayer', _overlayTyphoon);
    mapState.setOverlayEnabled('fdsnEarthScope', _overlayFdsnEarthScope);
    mapState.setOverlayEnabled('fdsnGeofon', _overlayFdsnGeofon);
    mapState.setShowEstimatedEpicenter(_showEpicenter);
    context.read<QuakeProvider>().setWeatherLocalOnly(
      _weatherLocalOnly,
      persist: false,
    );
    context.read<QuakeProvider>().setWeatherLocalAdminLevel(
      _weatherLocalLevel,
      persist: false,
    );
    if (_wauthAccessToken != null) {
      await _confirmSavedWAuthLogin();
    } else {
      await prefs.remove(WAuthService.userInfoPreferenceKey);
      await _disableWhewsSources();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _niedReplayStartController.dispose();
    _settingsSearchController.dispose();
    _fanApiKeyController.dispose();
    _gptSovitsUrlController.dispose();
    _gptSovitsRefAudioController.dispose();
    _gptSovitsPromptTextController.dispose();
    _wauthService.close();
    super.dispose();
  }

  bool get _isAndroidNotificationPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _refreshNotificationPermission() async {
    if (!_isAndroidNotificationPlatform) return;
    final granted = await BackgroundService().areNotificationsEnabled();
    if (!mounted) return;
    setState(() => _notificationPermissionGranted = granted);
  }

  Future<bool> _ensureNotificationPermission() async {
    if (!_isAndroidNotificationPlatform) return true;
    if (_notificationPermissionGranted == true) return true;
    if (_notificationPermissionBusy) return false;

    setState(() => _notificationPermissionBusy = true);
    final requested = await BackgroundService().requestNotificationPermission();
    final granted =
        requested == true ||
        await BackgroundService().areNotificationsEnabled() == true;
    if (!mounted) return granted;
    setState(() {
      _notificationPermissionBusy = false;
      _notificationPermissionGranted = granted;
    });
    if (!granted) {
      _showNotificationPermissionDeniedMessage();
    }
    return granted;
  }

  void _showNotificationPermissionDeniedMessage() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('系统通知权限未开启，通知功能不会生效。'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '系统设置',
          onPressed: _openNotificationSettings,
        ),
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    final opened = await BackgroundService().openNotificationSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法打开系统通知设置。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _changeNotificationSetting(
    Future<void> Function({bool? notification, bool? sound, bool? focus})
    onChanged, {
    bool? notification,
    bool? sound,
    bool? focus,
  }) async {
    if (notification == true && !await _ensureNotificationPermission()) return;
    await onChanged(notification: notification, sound: sound, focus: focus);
  }

  Future<void> _setBackgroundNotificationsEnabled(
    BackgroundSettingsProvider settings,
    bool enabled,
  ) async {
    if (enabled && !await _ensureNotificationPermission()) return;
    await settings.setEnabled(enabled);
  }

  Future<void> _saveFanServer(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fanServerKey, index);
  }

  Future<void> _saveFanApiKey() async {
    final apiKey = _fanApiKeyController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (apiKey.isEmpty) {
      await prefs.remove(FanService.apiKeyPreferenceKey);
    } else {
      await prefs.setString(FanService.apiKeyPreferenceKey, apiKey);
    }
    SourceManager().getSource<FanService>()?.setApiKey(apiKey);
    if (!mounted) return;
    setState(() => _fanApiKeyController.text = apiKey);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          apiKey.isEmpty ? 'FAN Studio API Key 已清除' : 'FAN Studio API Key 已保存',
        ),
      ),
    );
  }

  String _wauthUserLabel(Map<String, dynamic> userInfo) {
    for (final key in const [
      'name',
      'preferred_username',
      'username',
      'email',
      'sub',
    ]) {
      final value = userInfo[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '已授权用户';
  }

  String _wauthErrorText(Object error) {
    if (error is WAuthApiException) {
      if (error.statusCode == 408) return '连接 WAuth 服务超时，请检查网络后重试。';
      if (error.statusCode == 0) return '无法连接 WAuth 服务，请检查网络后重试。';
      return error.message;
    }
    if (error is FormatException) return error.message;
    return '授权失败，请稍后重试。';
  }

  void _showWAuthMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _removeSavedWAuthLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(WAuthService.accessTokenPreferenceKey);
    await prefs.remove(WAuthService.apiTokenPreferenceKey);
    await prefs.remove(WAuthService.legacySessionTokenPreferenceKey);
    await prefs.remove(WAuthService.userInfoPreferenceKey);
  }

  Future<void> _confirmSavedWAuthLogin() async {
    final accessToken = _wauthAccessToken;
    if (accessToken == null || accessToken.isEmpty || _wauthVerifying) return;
    if (mounted) {
      setState(() {
        _wauthVerifying = true;
        _wauthUserInfo = null;
        _wauthError = null;
      });
    }
    try {
      final authorized = await _wauthService.requireAuthorizedAccessToken(
        accessToken,
      );
      final prefs = await SharedPreferences.getInstance();
      final apiToken = prefs.getString(WAuthService.apiTokenPreferenceKey);
      final apiAuthorized = await _wauthService
          .requireAuthorizedApiToken(apiToken)
          .then((_) => true)
          .catchError((_) => false);
      await prefs.setString(
        WAuthService.userInfoPreferenceKey,
        jsonEncode(authorized.userInfo),
      );
      await prefs.setBool(
        WhewsService.apiAuthorizedPreferenceKey,
        apiAuthorized,
      );
      if (!apiAuthorized) await _disableWhewsSources();
      if (apiAuthorized) {
        SourceManager().setSourceEnabled('WHEWS', _whewsEnabled);
        QuakeMapView.whewsNiedEnabledNotifier.value = _whewsNiedEnabled;
        QuakeMapView.whewsSnetEnabledNotifier.value = _whewsSnetEnabled;
        QuakeMapView.whewsKmaEnabledNotifier.value = _whewsKmaEnabled;
      }
      if (!mounted) return;
      setState(() {
        _wauthUserInfo = authorized.userInfo;
        _whewsApiAuthorized = apiAuthorized;
        _wauthError = null;
      });
    } on WAuthApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _removeSavedWAuthLogin();
        await _disableWhewsSources();
        if (!mounted) return;
        setState(() {
          _wauthAccessToken = null;
          _wauthUserInfo = null;
          _wauthError = 'WAuth 登录已失效，请重新登录。';
        });
      } else {
        _whewsApiAuthorized = false;
        await _disableWhewsSources();
        if (!mounted) return;
        setState(() {
          _wauthUserInfo = null;
          _wauthError = '无法确认 WAuth 授权状态，API 保持关闭。';
        });
      }
    } catch (_) {
      _whewsApiAuthorized = false;
      await _disableWhewsSources();
      if (mounted) {
        setState(() {
          _wauthUserInfo = null;
          _wauthError = '无法确认 WAuth 授权状态，API 保持关闭。';
        });
      }
    } finally {
      if (mounted) setState(() => _wauthVerifying = false);
    }
  }

  Future<void> _disableWhewsSources() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_whewsEnabledKey, false);
    await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
    await prefs.setBool(_whewsNiedEnabledKey, false);
    await prefs.setBool(_whewsSnetEnabledKey, false);
    await prefs.setBool(_whewsKmaEnabledKey, false);
    SourceManager().setSourceEnabled('WHEWS', false);
    QuakeMapView.whewsNiedEnabledNotifier.value = false;
    QuakeMapView.whewsSnetEnabledNotifier.value = false;
    QuakeMapView.whewsKmaEnabledNotifier.value = false;
    if (!mounted) return;
    setState(() {
      _whewsEnabled = false;
      _whewsNiedEnabled = false;
      _whewsSnetEnabled = false;
      _whewsKmaEnabled = false;
    });
  }

  bool _canEnableWhews() {
    if (_whewsApiAuthorized) return true;
    _showWAuthMessage('WHEWS API 需要先完成 WAuth API 授权。');
    return false;
  }

  Future<void> _startWAuthAuthorization() async {
    if (_wauthBusy) return;
    setState(() {
      _wauthBusy = true;
      _wauthBrowserOpened = false;
      _wauthError = null;
    });
    _showWAuthMessage('正在打开 WAuth 登录页面…');
    try {
      final session = await _wauthService.createGatewaySession();
      final launched = await launchUrl(
        session.authorizationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const WAuthApiException(statusCode: 0, message: '无法打开系统浏览器。');
      }
      if (!mounted) return;
      setState(() => _wauthBrowserOpened = true);
      _showWAuthMessage('请在浏览器中完成 WAuth 登录。');
      final result = await _wauthService.waitForGatewayResult(
        state: session.state,
        timeout: Duration(seconds: session.expiresIn ?? 600),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        WAuthService.accessTokenPreferenceKey,
        result.token.accessToken,
      );
      final apiToken = result.token.apiToken;
      if (apiToken == null || apiToken.isEmpty) {
        await prefs.remove(WAuthService.apiTokenPreferenceKey);
      } else {
        await prefs.setString(WAuthService.apiTokenPreferenceKey, apiToken);
      }
      await prefs.remove(WAuthService.legacySessionTokenPreferenceKey);
      await prefs.setString(
        WAuthService.userInfoPreferenceKey,
        jsonEncode(result.userInfo),
      );
      if (!mounted) return;
      QuakeMapView.whewsApiTokenNotifier.value = apiToken ?? '';
      SourceManager().getSource<WhewsService>()?.setApiToken(apiToken ?? '');
      setState(() {
        _wauthAccessToken = result.token.accessToken;
        _wauthUserInfo = result.userInfo;
        _wauthError = null;
      });
      await _confirmSavedWAuthLogin();
      _showWAuthMessage('WAuth 授权成功。');
    } catch (error) {
      if (!mounted) return;
      final message = _wauthErrorText(error);
      setState(() => _wauthError = message);
      _showWAuthMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _wauthBusy = false;
          _wauthBrowserOpened = false;
        });
      }
    }
  }

  Future<void> _clearWAuthAuthorization() async {
    await _removeSavedWAuthLogin();
    QuakeMapView.whewsApiTokenNotifier.value = '';
    SourceManager().getSource<WhewsService>()?.setApiToken('');
    await _disableWhewsSources();
    if (!mounted) return;
    setState(() {
      _wauthAccessToken = null;
      _wauthUserInfo = null;
      _wauthError = null;
    });
  }

  Future<void> _saveTileKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tileKeyKey, key);
  }

  Future<void> _saveOverlayState(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
  }

  Future<void> _saveApiSourceEnabled(String key, bool enabled) async {
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

  Future<void> _saveInfoActionWhitelist(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      QuakeProvider.infoActionWhitelistPreferenceKey,
      value.trim(),
    );
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

  Future<void> _saveDisplayShindo0(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(QuakeMapView.displayShindo0PreferenceKey, val);
  }

  Future<void> _saveKmaIntensityHold(int frames) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(QuakeMapView.kmaIntensityHoldPreferenceKey, frames);
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
    LocationService().setCurrentLatLng(lat, lng);
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
    if (_mapViewLat == null || _mapViewLng == null) return '当前：未设置（跟随系统定位）';
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
        '已更新所在地：${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}${_locationSourceTag()}',
      );
    } catch (e) {
      _showToast('自动获取定位失败: $e');
    }
  }

  /// 自动定位结果的来源标签，便于区分 GPS 定位与 IP 兜底定位。
  String _locationSourceTag() {
    final svc = LocationService();
    switch (LocationService().currentSource) {
      case LocationSource.ipFallback:
        final region = svc.ipRegion;
        return region == null || region.isEmpty
            ? '（IP 兜底定位）'
            : '（IP 兜底定位：$region）';
      case LocationSource.native:
        final region = svc.bestRegionLabel;
        return region == null || region.isEmpty
            ? '（GPS 定位）'
            : '（GPS 定位：$region）';
      case LocationSource.manual:
      case LocationSource.unknown:
        return '';
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
                      '请输入经纬度，保存后将作为所在地（本地预警与距离计算的参考点）。',
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
                                  '已保存所在地：${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
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
                      final bool isMobile =
                          defaultTargetPlatform == TargetPlatform.android ||
                          defaultTargetPlatform == TargetPlatform.iOS;
                      final wide = !isMobile && constraints.maxWidth >= 860;
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
            icon: Icons.key_outlined,
            title: '账号与 API 授权',
            children: [
              _buildFanApiKeySetting(),
              const _SettingsDivider(),
              _buildWAuthSetting(),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.power_settings_new_outlined,
            title: 'API/数据接口开关',
            children: [_buildApiInterfaceSwitches()],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.tune_outlined,
            title: 'API/数据接口选项',
            children: [
              _buildFanServerSelector(),
              const _SettingsDivider(),
              _buildNiedDataSourceSelector(),
              const _SettingsDivider(),
              _buildNiedReplayControls(),
              const _SettingsDivider(),
              _buildShakeSensitivitySelector(),
              const _SettingsDivider(),
              _buildDisplayShindo0Switch(),
              const _SettingsDivider(),
              _buildKmaIntensityHoldSelector(),
              const _SettingsDivider(),
              _buildFdsnStationSelector(),
              const _SettingsDivider(),
              _buildFdsnStationLimitSelector(),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.filter_alt_outlined,
            title: '信息事件震级过滤',
            children: [_buildMagFilterList()],
          ),
        ];
      case _SettingsCategory.map:
        return [
          _buildSectionPanel(
            icon: Icons.layers_outlined,
            title: '地图外观',
            children: [_buildTileSelector()],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.my_location_outlined,
            title: '所在地定位',
            children: [_buildMapCenterControls()],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.map_outlined,
            title: '视野切换',
            children: [_buildDefaultViewControls()],
          ),
          const SizedBox(height: 12),
          _buildSectionPanel(
            icon: Icons.notifications_outlined,
            title: '轻通知',
            children: [_buildNotificationSettings()],
          ),
        ];
      case _SettingsCategory.alert:
        return [
          _buildSectionPanel(
            icon: Icons.layers_outlined,
            title: '信息显示',
            children: [_buildMapOverlaySelector()],
          ),
          const SizedBox(height: 12),
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

  Widget _buildApiInterfaceSwitches() {
    final rows = [
      _buildApiSwitch(
        title: 'FAN Studio',
        value: _fanEnabled,
        onChanged: (val) {
          setState(() => _fanEnabled = val);
          _saveApiSourceEnabled(_fanEnabledKey, val);
          SourceManager().setSourceEnabled('FAN', val);
        },
      ),
      _buildApiSwitch(
        title: 'WHEWS 地震预警/情报',
        value: _whewsEnabled,
        onChanged: (val) {
          if (val && !_canEnableWhews()) return;
          setState(() => _whewsEnabled = val);
          _saveApiSourceEnabled(_whewsEnabledKey, val);
          SourceManager().setSourceEnabled('WHEWS', val);
        },
      ),
      _buildApiSwitch(
        title: 'NowQuake',
        value: _nowQuakeCencIrEnabled,
        onChanged: (val) {
          setState(() => _nowQuakeCencIrEnabled = val);
          _saveApiSourceEnabled(_nowQuakeCencIrEnabledKey, val);
          SourceManager().setSourceEnabled('NowQuake', val);
        },
      ),
      _buildApiSwitch(
        title: 'CENC 震源机制解 (CMT)',
        value: _cencCmtEnabled,
        onChanged: (val) {
          setState(() => _cencCmtEnabled = val);
          _saveApiSourceEnabled(_cencCmtEnabledKey, val);
          if (val) {
            EqlistManager().cencCmt.start();
          } else {
            EqlistManager().cencCmt.stop();
          }
        },
      ),
      _buildApiSwitch(
        title: 'USGS 震源机制解 (CMT)',
        value: _usgsCmtEnabled,
        onChanged: (val) {
          setState(() => _usgsCmtEnabled = val);
          _saveApiSourceEnabled(_usgsCmtEnabledKey, val);
          if (val) {
            EqlistManager().usgsCmt.start();
          } else {
            EqlistManager().usgsCmt.stop();
          }
        },
      ),
      _buildApiSwitch(
        title: 'JMA 震源机制解 (CMT)',
        value: _jmaCmtEnabled,
        onChanged: (val) {
          setState(() => _jmaCmtEnabled = val);
          _saveApiSourceEnabled(_jmaCmtEnabledKey, val);
          if (val) {
            EqlistManager().jmaCmt.start();
          } else {
            EqlistManager().jmaCmt.stop();
          }
        },
      ),
      _buildApiSwitch(
        title: 'F-net 震源机制解 (CMT)',
        value: _fnetCmtEnabled,
        onChanged: (val) {
          setState(() => _fnetCmtEnabled = val);
          _saveApiSourceEnabled(_fnetCmtEnabledKey, val);
          if (val) {
            EqlistManager().fnetCmt.start();
          } else {
            EqlistManager().fnetCmt.stop();
          }
        },
      ),
      _buildApiSwitch(
        title: 'Hi-net AQUA 震源机制解 (CMT)',
        value: _hinetAquaCmtEnabled,
        onChanged: (val) {
          setState(() => _hinetAquaCmtEnabled = val);
          _saveApiSourceEnabled(_hinetAquaCmtEnabledKey, val);
          if (val) {
            EqlistManager().hinetAquaCmt.start();
          } else {
            EqlistManager().hinetAquaCmt.stop();
          }
        },
      ),
      _buildApiSwitch(
        title: 'Wolfx Project',
        value: _wolfxEnabled,
        onChanged: (val) {
          setState(() => _wolfxEnabled = val);
          _saveApiSourceEnabled(_wolfxEnabledKey, val);
          SourceManager().setSourceEnabled('Wolfx', val);
        },
      ),
      _buildApiSwitch(
        title: 'Wolfx SeisJS',
        value: _wolfxSeisJsEnabled,
        onChanged: (val) {
          setState(() => _wolfxSeisJsEnabled = val);
          _saveApiSourceEnabled(_wolfxSeisJsEnabledKey, val);
          QuakeMapView.wolfxSeisJsEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'P2PQuake',
        value: _p2pquakeEnabled,
        onChanged: (val) {
          setState(() => _p2pquakeEnabled = val);
          _saveApiSourceEnabled(_p2pquakeEnabledKey, val);
          SourceManager().setSourceEnabled('P2P', val);
        },
      ),
      _buildApiSwitch(
        title: 'KMA PEWS',
        value: _kmaPewsEnabled,
        onChanged: (val) {
          setState(() => _kmaPewsEnabled = val);
          _saveApiSourceEnabled(_kmaPewsEnabledKey, val);
          QuakeMapView.kmaPewsEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'P-Alert',
        value: _pAlertEnabled,
        onChanged: (val) {
          setState(() => _pAlertEnabled = val);
          _saveApiSourceEnabled(_pAlertEnabledKey, val);
          QuakeMapView.pAlertEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'TREM RTS',
        value: _tremStationEnabled,
        onChanged: (val) {
          setState(() => _tremStationEnabled = val);
          _saveTremStationEnabled(val);
          QuakeMapView.tremStationEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'NIED 強震モニタ',
        value: _niedMonitorEnabled,
        onChanged: (val) {
          setState(() => _niedMonitorEnabled = val);
          _saveApiSourceEnabled(_niedMonitorEnabledKey, val);
          QuakeMapView.niedMonitorEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'NIED 長周期地震動モニタ',
        value: _niedLpgmEnabled,
        onChanged: (val) {
          setState(() => _niedLpgmEnabled = val);
          _saveApiSourceEnabled(_niedLpgmEnabledKey, val);
          QuakeMapView.niedLpgmEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'S-net 日本海溝海底地震津波観測網',
        value: _snetEnabled,
        onChanged: (val) {
          setState(() => _snetEnabled = val);
          _saveApiSourceEnabled(_snetEnabledKey, val);
          QuakeMapView.snetEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'WHEWS NIED 实时测站',
        value: _whewsNiedEnabled,
        onChanged: (val) {
          if (val && !_canEnableWhews()) return;
          setState(() => _whewsNiedEnabled = val);
          _saveApiSourceEnabled(_whewsNiedEnabledKey, val);
          QuakeMapView.whewsNiedEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'WHEWS S-Net 实时测站',
        value: _whewsSnetEnabled,
        onChanged: (val) {
          if (val && !_canEnableWhews()) return;
          setState(() => _whewsSnetEnabled = val);
          _saveApiSourceEnabled(_whewsSnetEnabledKey, val);
          QuakeMapView.whewsSnetEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'WHEWS KMA 实时测站',
        value: _whewsKmaEnabled,
        onChanged: (val) {
          if (val && !_canEnableWhews()) return;
          setState(() => _whewsKmaEnabled = val);
          _saveApiSourceEnabled(_whewsKmaEnabledKey, val);
          QuakeMapView.whewsKmaEnabledNotifier.value = val;
        },
      ),
      _buildApiSwitch(
        title: 'FDSN / SeedLink 实时测站',
        value: _fdsnSeedLinkEnabled,
        onChanged: (val) {
          setState(() => _fdsnSeedLinkEnabled = val);
          _saveApiSourceEnabled(_fdsnSeedLinkEnabledKey, val);
          QuakeMapView.fdsnSeedLinkEnabledNotifier.value = val;
        },
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1) const _SettingsDivider(),
        ],
      ],
    );
  }

  Widget _buildApiSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildSettingRow(
      title: title,
      subtitle: value ? '已启用，允许建立数据连接' : '已关闭，不建立数据连接',
      leading: value ? Icons.link_outlined : Icons.link_off_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: value,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFanServerSelector() {
    return _buildSettingRow(
      title: 'FAN Studio 默认服务器',
      subtitle: '选择 FAN Studio 数据源优先连接的服务器',
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

  Widget _buildFanApiKeySetting() {
    return _buildSettingRow(
      title: 'FAN Studio API Key',
      subtitle: '用于 FAN Studio 鉴权；留空时按未认证模式连接',
      leading: Icons.key_outlined,
      control: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _fanApiKeyController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onSubmitted: (_) => _saveFanApiKey(),
              decoration: InputDecoration(
                hintText: '未设置',
                hintStyle: const TextStyle(color: Colors.white38),
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
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '保存 FAN Studio API Key',
            onPressed: _saveFanApiKey,
            icon: const Icon(Icons.save_outlined),
            color: _accentColor,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildWAuthSetting() {
    final userInfo = _wauthUserInfo;
    final authenticated =
        userInfo != null && _wauthAccessToken != null && !_wauthVerifying;
    final status = _wauthBusy
        ? _wauthBrowserOpened
              ? '等待在浏览器中完成 WAuth 登录'
              : '正在连接 WAuth 登录服务'
        : _wauthVerifying
        ? '正在确认 WAuth 授权状态；API 保持关闭'
        : authenticated
        ? '已登录：${_wauthUserLabel(userInfo)}'
        : _wauthError != null
        ? _wauthError!
        : '未登录时 WAuth 业务 API 不可开启';
    return _buildSettingRow(
      title: 'WAuth 账号授权',
      subtitle: status,
      leading: _wauthBusy || _wauthVerifying
          ? Icons.hourglass_top_outlined
          : authenticated
          ? Icons.verified_user_outlined
          : Icons.account_circle_outlined,
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (_wauthAccessToken != null)
            IconButton(
              tooltip: '退出 WAuth 登录',
              onPressed: _wauthBusy || _wauthVerifying
                  ? null
                  : _clearWAuthAuthorization,
              icon: const Icon(Icons.logout_outlined),
              color: Colors.white70,
            ),
          SizedBox(
            width: 160,
            height: 40,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: _accentColor.withValues(
                    alpha: _wauthBusy || _wauthVerifying ? 0.35 : 1,
                  ),
                ),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white54,
              ),
              onPressed: _wauthBusy || _wauthVerifying
                  ? null
                  : _startWAuthAuthorization,
              icon: _wauthBusy || _wauthVerifying
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Colors.white70,
                      ),
                    )
                  : Icon(
                      authenticated
                          ? Icons.refresh_outlined
                          : Icons.login_outlined,
                      size: 16,
                    ),
              label: Text(
                _wauthBusy
                    ? _wauthBrowserOpened
                          ? '等待登录'
                          : '正在打开'
                    : _wauthVerifying
                    ? '检查中'
                    : authenticated
                    ? '重新登录'
                    : '登录',
              ),
            ),
          ),
        ],
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
    final rows = [
      _buildInfoLayerSwitch(
        title: '实况云图',
        value: _overlayCloud,
        leading: Icons.cloud_outlined,
        onChanged: (val) {
          setState(() => _overlayCloud = val);
          _saveOverlayState(_overlayCloudKey, val);
          context.read<MapStateProvider>().setOverlayEnabled('cloudLayer', val);
        },
      ),
      _buildInfoLayerSwitch(
        title: '实况风场',
        value: _overlayWind,
        leading: Icons.air,
        onChanged: (val) {
          setState(() => _overlayWind = val);
          _saveOverlayState(_overlayWindKey, val);
          context.read<MapStateProvider>().setOverlayEnabled('windLayer', val);
        },
      ),
      _buildInfoLayerSwitch(
        title: '实况降水',
        value: _overlayRain,
        leading: Icons.water_drop_outlined,
        onChanged: (val) {
          setState(() => _overlayRain = val);
          _saveOverlayState(_overlayRainKey, val);
          context.read<MapStateProvider>().setOverlayEnabled('rainLayer', val);
        },
      ),
      _buildInfoLayerSwitch(
        title: '全国雷达',
        value: _overlayRadarChina,
        leading: Icons.radar,
        onChanged: (val) {
          setState(() => _overlayRadarChina = val);
          _saveOverlayState(_overlayRadarChinaKey, val);
          context.read<MapStateProvider>().setOverlayEnabled(
            'radarChinaLayer',
            val,
          );
        },
      ),
      _buildInfoLayerSwitch(
        title: '东南沿海及西太卫星云图',
        value: _overlaySatelliteCloud,
        leading: Icons.cloud_queue_outlined,
        onChanged: (val) {
          setState(() => _overlaySatelliteCloud = val);
          _saveOverlayState(_overlaySatelliteCloudKey, val);
          context.read<MapStateProvider>().setOverlayEnabled(
            'satelliteCloudLayer',
            val,
          );
        },
      ),
      _buildInfoLayerSwitch(
        title: '中国等高线',
        value: _overlayCnContour,
        leading: Icons.terrain_outlined,
        onChanged: (val) {
          setState(() => _overlayCnContour = val);
          _saveOverlayState(_overlayCnContourKey, val);
          context.read<MapStateProvider>().setOverlayEnabled('cnContour', val);
        },
      ),
      _buildInfoLayerSwitch(
        title: 'JMA 火山',
        value: _overlayJmaVolcano,
        leading: Icons.local_fire_department_outlined,
        onChanged: (val) {
          setState(() => _overlayJmaVolcano = val);
          _saveOverlayState(_overlayJmaVolcanoKey, val);
          context.read<MapStateProvider>().setOverlayEnabled(
            'volcanoLayer',
            val,
          );
        },
      ),
      _buildInfoLayerSwitch(
        title: '台风路径',
        value: _overlayTyphoon,
        leading: Icons.storm_outlined,
        onChanged: (val) {
          setState(() => _overlayTyphoon = val);
          _saveOverlayState(_overlayTyphoonKey, val);
          context.read<MapStateProvider>().setOverlayEnabled(
            'typhoonLayer',
            val,
          );
          context.read<QuakeProvider>().setTyphoonLayerEnabled(val);
        },
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1) const _SettingsDivider(),
        ],
      ],
    );
  }

  Widget _buildInfoLayerSwitch({
    required String title,
    required bool value,
    required IconData leading,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildSettingRow(
      title: title,
      subtitle: value ? '已启用，显示该信息' : '已关闭，隐藏该信息',
      leading: leading,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: value,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: onChanged,
        ),
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
      title: '所在地定位',
      subtitle: '本地预警与距离计算的参考点；可自动定位或手动输入经纬度。${_mapCenterText()}',
      leading: Icons.my_location_outlined,
      control: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 290;
          final buttonA = SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _accentColor.withValues(alpha: 0.7)),
                foregroundColor: Colors.white,
              ),
              onPressed: _autoLocateMapCenter,
              icon: const Icon(Icons.gps_fixed, size: 16),
              label: const Text('自动定位'),
            ),
          );
          final buttonB = SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _accentColor.withValues(alpha: 0.7)),
                foregroundColor: Colors.white,
              ),
              onPressed: _openManualCenterDialog,
              icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
              label: const Text('手动输入'),
            ),
          );

          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [buttonA, const SizedBox(height: 8), buttonB],
            );
          }

          return Row(
            children: [
              Expanded(child: buttonA),
              const SizedBox(width: 8),
              Expanded(child: buttonB),
            ],
          );
        },
      ),
    );
  }

  /// 把地图切换到“所在地视野”。未设置所在地时提示。
  void _switchToLocationView() {
    final ok = context.read<MapStateProvider>().moveToLocationView();
    if (!ok) _showToast('未设置所在地，请先在上方设置所在地');
  }

  /// 把地图切换到“默认视野”（系统默认中心）。
  void _switchToDefaultView() {
    context.read<MapStateProvider>().moveToSystemDefaultView();
  }

  Widget _buildDefaultViewControls() {
    final mapState = context.watch<MapStateProvider>();
    final selectedMode = mapState.preferredViewMode;
    return _buildSettingRow(
      title: '视野切换',
      subtitle: '在所在地视野与默认视野之间切换地图。所在地视野需先在上方设置所在地。',
      leading: Icons.swap_horiz_outlined,
      control: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 300;
          final buttonA = _buildViewModeButton(
            label: '所在地视野',
            icon: Icons.my_location,
            selected: selectedMode == 'location',
            onTap: _switchToLocationView,
          );
          final buttonB = _buildViewModeButton(
            label: '默认视野',
            icon: Icons.public_outlined,
            selected: selectedMode == 'system_default',
            onTap: _switchToDefaultView,
          );
          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [buttonA, const SizedBox(height: 8), buttonB],
            );
          }
          return Row(
            children: [
              Expanded(child: buttonA),
              const SizedBox(width: 8),
              Expanded(child: buttonB),
            ],
          );
        },
      ),
    );
  }

  Widget _buildViewModeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? _accentColor.withValues(alpha: 0.22) : _fieldColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _accentColor : _dividerColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSettings() {
    final settings = context.watch<NotificationSettingsProvider>();
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isAndroidNotificationPlatform) ...[
          _buildNotificationPermissionStatus(),
          const SizedBox(height: 14),
        ],
        _buildNotificationGroup(
          title: '收到地震预警（警报）时',
          subtitle: '预估烈度/震度达到警报阈值',
          settings: settings.onEewWarn,
          onChanged: ({notification, sound, focus}) =>
              _changeNotificationSetting(
                settings.setEewWarn,
                notification: notification,
                sound: sound,
                focus: focus,
              ),
        ),
        const SizedBox(height: 14),
        _buildNotificationGroup(
          title: '收到任意地震预警时',
          subtitle: '包括普通 EEW 更新、取消报',
          settings: settings.onEew,
          onChanged: ({notification, sound, focus}) =>
              _changeNotificationSetting(
                settings.setEew,
                notification: notification,
                sound: sound,
                focus: focus,
              ),
        ),
        const SizedBox(height: 14),
        _buildNotificationGroup(
          title: '收到地震信息时',
          subtitle: 'CENC / JMA / USGS 等机构的地震情报',
          settings: settings.onReport,
          onChanged: ({notification, sound, focus}) =>
              _changeNotificationSetting(
                settings.setOnReport,
                notification: notification,
                sound: sound,
                focus: focus,
              ),
        ),
        if (isMobile) ...[
          const SizedBox(height: 20),
          _buildBackgroundNotificationSettings(),
        ],
      ],
    );
  }

  Widget _buildNotificationPermissionStatus() {
    final granted = _notificationPermissionGranted;
    final color = granted == true
        ? const Color(0xFF69D18A)
        : granted == false
        ? const Color(0xFFFFB866)
        : Colors.white60;
    final label = granted == true
        ? '已授权'
        : granted == false
        ? '未授权'
        : '检测中';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            granted == true
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '系统通知权限：$label',
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (granted == false)
                  Text(
                    '未授权时，轻通知和后台通知均无法显示。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          if (granted == false) ...[
            TextButton(
              onPressed: _notificationPermissionBusy
                  ? null
                  : _ensureNotificationPermission,
              child: Text(_notificationPermissionBusy ? '申请中' : '申请权限'),
            ),
            IconButton(
              tooltip: '打开系统通知设置',
              onPressed: _openNotificationSettings,
              icon: const Icon(Icons.settings_outlined, size: 19),
            ),
          ] else if (granted == null)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildBackgroundNotificationSettings() {
    final bg = context.watch<BackgroundSettingsProvider>();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.phone_android_outlined,
                size: 18,
                color: _accentColor,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '后台通知（移动端）',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: bg.enabled,
                onChanged: (v) => _setBackgroundNotificationsEnabled(bg, v),
                activeThumbColor: Colors.white,
              ),
            ],
          ),
          Text(
            '切到后台时仅保留 EEW / 信息数据源，关闭地图/测站等高功耗功能，并通过系统通知推送事件。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11.5,
            ),
          ),
          if (bg.enabled) ...[
            const Divider(height: 1, color: _dividerColor),
            _buildBackgroundSwitch(
              label: '信息事件通知',
              value: bg.reportEnabled,
              onChanged: bg.setReportEnabled,
            ),
            const Divider(height: 1, color: _dividerColor),
            _buildBackgroundSwitch(
              label: '地震预警（EEW）通知',
              value: bg.eewEnabled,
              onChanged: bg.setEewEnabled,
            ),
            if (bg.eewEnabled) ...[
              const Divider(height: 1, color: _dividerColor),
              _buildBackgroundIntensitySelector(bg),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBackgroundSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: value ? Colors.white : Colors.white70,
                  fontSize: 12.5,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: _accentColor,
              activeThumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              inactiveThumbColor: Colors.white70,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundIntensitySelector(BackgroundSettingsProvider bg) {
    final options = [0.0, 3.0, 4.0, 5.0, 6.0];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EEW 通知阈值',
            style: TextStyle(
              color: bg.eewEnabled ? Colors.white : Colors.white70,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((value) {
              final selected = bg.eewMinIntensity == value;
              return ChoiceChip(
                label: Text(BackgroundSettingsProvider.intensityLabel(value)),
                selected: selected,
                onSelected: (_) => bg.setEewMinIntensity(value),
                selectedColor: _accentColor.withValues(alpha: 0.35),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                labelStyle: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected
                      ? _accentColor.withValues(alpha: 0.65)
                      : _dividerColor,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationGroup({
    required String title,
    required String subtitle,
    required NotificationEventSettings settings,
    required Future<void> Function({
      bool? notification,
      bool? sound,
      bool? focus,
    })
    onChanged,
    bool notificationDisabled = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 4),
          _buildSimpleSwitch(
            label: '通知',
            icon: Icons.notifications_outlined,
            value: settings.notification,
            onChanged: notificationDisabled
                ? null
                : (v) => onChanged(notification: v),
          ),
          const Divider(height: 1, color: _dividerColor),
          _buildSimpleSwitch(
            label: '声音',
            icon: Icons.volume_up_outlined,
            value: settings.sound,
            onChanged: (v) => onChanged(sound: v),
          ),
          const Divider(height: 1, color: _dividerColor),
          _buildSimpleSwitch(
            label: '聚焦',
            icon: Icons.center_focus_strong_outlined,
            value: settings.focus,
            onChanged: (v) => onChanged(focus: v),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleSwitch({
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: value ? _accentColor : Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: value ? Colors.white : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: _accentColor,
              activeThumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              inactiveThumbColor: Colors.white70,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
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
      title: 'NIED 強震モニタ 数据源',
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

  Widget _buildDisplayShindo0Switch() {
    return _buildSettingRow(
      title: '显示低烈度数字',
      subtitle: 'NIED / TREM / P-Alert 显示震度0，KMA 显示 MMI 1',
      leading: Icons.looks_one_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _displayShindo0,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _displayShindo0 = val);
            _saveDisplayShindo0(val);
            QuakeMapView.displayShindo0Notifier.value = val;
          },
        ),
      ),
    );
  }

  Widget _buildKmaIntensityHoldSelector() {
    return _buildSettingRow(
      title: 'KMA 加速度保持',
      subtitle: '保留最近时段内的最高 MMI 显示',
      leading: Icons.timer_outlined,
      control: _buildSegmentedSelector<int>(
        value: _kmaIntensityHoldFrames,
        options: const [
          _SelectOption(1, '实时'),
          _SelectOption(5, '5秒'),
          _SelectOption(10, '10秒'),
          _SelectOption(30, '30秒'),
          _SelectOption(60, '60秒'),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() => _kmaIntensityHoldFrames = val);
          _saveKmaIntensityHold(val);
          QuakeMapView.kmaIntensityHoldNotifier.value = val;
        },
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
      title: '打开侧栏常驻',
      subtitle: '在主界面右侧常驻显示信息侧栏',
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
      children: [
        ...List.generate(sources.length, (index) {
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
        const _SettingsDivider(),
        _buildSettingRow(
          title: '信息事件地点白名单',
          subtitle: '使用 | 分隔地点关键词；命中后可绕过震级阈值，但“不接收”仍然优先',
          leading: Icons.playlist_add_check_outlined,
          control: SizedBox(
            height: 40,
            child: TextField(
              controller: _infoActionWhitelistController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: (value) {
                _saveInfoActionWhitelist(value);
                context.read<QuakeProvider>().setInfoActionWhitelist(value);
              },
              decoration: InputDecoration(
                hintText: '例如：四川|重庆|日本',
                hintStyle: const TextStyle(color: _mutedTextColor),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.18),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _accentColor),
                ),
              ),
            ),
          ),
        ),
      ],
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
