import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../providers/notification_settings_provider.dart';
import '../../providers/background_settings_provider.dart';
import '../../providers/page_background_provider.dart';
import '../../models/notification_event_settings.dart';
import '../../services/location_service.dart';
import '../../services/background_service.dart';
import '../../services/tts_service.dart';
import '../../services/sources/fan_service.dart';
import '../../services/sources/whews_service.dart';
import '../../services/sources/jian_service.dart';
import '../../services/sources/nowquake_cenc_intensity_service.dart';
import '../../services/sources/fdsn_motion_service.dart';
import '../../core/fdsn_intensity.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/source_manager.dart';
import '../../services/sources/eqlist/eqlist_manager.dart';
import '../../services/wauth_service.dart';
import '../../services/wauth_credential_store.dart';
import '../map/map_config.dart';
import '../map/quake_map_view.dart';
import '../../models/quake_message.dart';
import 'app_page_background.dart';
import 'android_background_power_settings.dart';
import 'debug_page.dart';
import 'manual_location_dialog.dart';
import 'obs_automation_presets_page.dart';
import 'ui_runtime_flags.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.onBack,
    this.contentTopInset = 0,
    this.weatherOnly = false,
  });

  final VoidCallback? onBack;
  final double contentTopInset;
  final bool weatherOnly;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  void _requestForegroundConnectionReload({bool force = false}) {
    unawaited(BackgroundService().requestSourceReload(force: force));
  }

  _SettingsCategory _selectedCategory = _SettingsCategory.data;
  String _settingsQuery = '';
  bool _fanEnabled = true;
  bool _whewsEnabled = false;
  bool _jianEnabled = false;
  bool _whewsNiedEnabled = false;
  bool _whewsSnetEnabled = false;
  bool _whewsKmaEnabled = false;
  final WAuthService _wauthService = WAuthService();
  String? _wauthAccessToken;
  Map<String, dynamic>? _wauthUserInfo;
  bool _wauthBusy = false;
  bool _wauthBrowserOpened = false;
  bool _wauthVerifying = false;
  bool _wauthRestoredFromStorage = false;
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
  bool _overlayJmaRadar = false;
  bool _overlaySatelliteCloud = false;
  bool _overlayCnContour = false;
  bool _overlayCnFault = false;
  bool _overlayJpFault = false;
  bool _overlayJmaVolcano = false;
  bool _overlayTyphoon = false;
  bool _overlayWeatherStation = false;
  bool _overlayWeatherAlert = false;
  String _weatherStationMode = 'auto';
  bool _overlayFdsnEarthScope = false;
  bool _overlayFdsnGeofon = false;
  int _fdsnStationLimit = FdsnMotionService.defaultStationLimit;
  final Map<String, double> _sourceMagFilters = {};
  String _niedDataSource = 'lmoni';
  String _kmaDataSource = 'pews';
  String _snetDataSource = 'msil';
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
  static const String _overlayJmaRadarKey = 'map_overlay_jmaRadarLayer';
  static const String _overlaySatelliteCloudKey =
      'map_overlay_satelliteCloudLayer';
  static const String _overlayCnContourKey = 'map_overlay_cnContour';
  static const String _overlayCnFaultKey = 'map_overlay_cnFault';
  static const String _overlayJpFaultKey = 'map_overlay_jpFault';
  static const String _overlayJmaVolcanoKey = 'map_overlay_volcanoLayer';
  static const String _overlayTyphoonKey = 'map_overlay_typhoonLayer';
  static const String _overlayWeatherStationKey =
      'map_overlay_weatherStationLayer';
  static const String _overlayWeatherAlertKey = 'map_overlay_weatherAlertLayer';
  static const String _weatherStationModeKey = 'map_overlay_weatherStationMode';
  static const String _overlayFdsnEarthScopeKey = 'map_overlay_fdsnEarthScope';
  static const String _overlayFdsnGeofonKey = 'map_overlay_fdsnGeofon';
  static const String _fdsnStationLimitKey =
      FdsnMotionService.stationLimitPreferenceKey;
  static const String _magFilterPrefix = 'source_mag_filter_';
  static const String _niedDataSourceKey = 'nied_data_source';
  static const String _kmaDataSourceKey =
      QuakeMapView.kmaDataSourcePreferenceKey;
  static const String _snetDataSourceKey =
      QuakeMapView.snetDataSourcePreferenceKey;
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

  /// HTML uses rgba(36,36,38,0.40) + blur(22px). Flutter BackdropFilter
  /// composites darker, so keep a lighter fill + milder sigma to match.
  static const Color _panelColor = Color.fromRGBO(48, 48, 52, 0.28);
  static const double _panelBlurSigma = 14;
  static const Color _fieldColor = Color.fromRGBO(255, 255, 255, 0.09);
  static const Color _borderColor = Color.fromRGBO(255, 255, 255, 0.16);
  static const Color _dividerColor = Color.fromRGBO(255, 255, 255, 0.10);
  static const Color _mutedTextColor = Color.fromRGBO(255, 255, 255, 0.58);

  /// Left “应用设置” header and right category title share this height
  /// so their bottom dividers line up across the vertical split.
  static const double _panelHeaderHeight = 78;
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
        '断层',
        '中国断层',
        '日本断层',
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
        '雷达',
        'jma',
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
      keywords: [
        '高级',
        '网格',
        '侧边',
        '震中',
        '调试',
        '开发',
        '背景',
        '自定义背景',
        'obs',
        '自动化',
        '自动录制',
        '回放',
        'replay buffer',
        '预设',
      ],
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
    // The weather shortcut only references live controls. Opening it must not
    // initialize TTS, log in, reload sources, or reapply unrelated preferences.
    if (widget.weatherOnly) return;
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
    WAuthCredentials credentials;
    try {
      credentials = await _wauthService.credentialStore.readAndMigrate(
        preferences: prefs,
      );
    } catch (_) {
      credentials = const WAuthCredentials();
    }
    final savedWAuthAccessToken = credentials.accessToken.trim();
    Map<String, dynamic>? cachedWAuthUserInfo;
    if (savedWAuthAccessToken.isNotEmpty) {
      cachedWAuthUserInfo = _readCachedWAuthUserInfo(prefs);
    }
    if (!mounted) return;
    setState(() {
      _fanEnabled = prefs.getBool(_fanEnabledKey) ?? true;
      _whewsEnabled = prefs.getBool(_whewsEnabledKey) ?? false;
      _jianEnabled = prefs.getBool(JianService.enabledPreferenceKey) ?? false;
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
      _wauthAccessToken = savedWAuthAccessToken.isNotEmpty
          ? savedWAuthAccessToken
          : null;
      _wauthUserInfo = cachedWAuthUserInfo;
      _wauthVerifying = false;
      _wauthRestoredFromStorage = savedWAuthAccessToken.isNotEmpty;
      _whewsApiAuthorized =
          prefs.getBool(WhewsService.apiAuthorizedPreferenceKey) ?? false;
      _tileKey = MapConfig.normalizeBaseTileKey(
        prefs.getString(_tileKeyKey) ?? 'petalLight',
      );
      _overlayCloud = prefs.getBool(_overlayCloudKey) ?? false;
      _overlayWind = prefs.getBool(_overlayWindKey) ?? false;
      _overlayRain = prefs.getBool(_overlayRainKey) ?? false;
      _overlayRadarChina = prefs.getBool(_overlayRadarChinaKey) ?? false;
      _overlayJmaRadar = prefs.getBool(_overlayJmaRadarKey) ?? false;
      _overlaySatelliteCloud =
          prefs.getBool(_overlaySatelliteCloudKey) ?? false;
      _overlayCnContour = prefs.getBool(_overlayCnContourKey) ?? false;
      _overlayCnFault = prefs.getBool(_overlayCnFaultKey) ?? false;
      _overlayJpFault = prefs.getBool(_overlayJpFaultKey) ?? false;
      _overlayJmaVolcano = prefs.getBool(_overlayJmaVolcanoKey) ?? false;
      _overlayTyphoon = prefs.getBool(_overlayTyphoonKey) ?? false;
      _overlayWeatherStation =
          prefs.getBool(_overlayWeatherStationKey) ?? false;
      _overlayWeatherAlert = prefs.getBool(_overlayWeatherAlertKey) ?? true;
      _weatherStationMode = prefs.getString(_weatherStationModeKey) ?? 'auto';
      _overlayFdsnEarthScope =
          prefs.getBool(_overlayFdsnEarthScopeKey) ?? false;
      _overlayFdsnGeofon = prefs.getBool(_overlayFdsnGeofonKey) ?? false;
      _fdsnStationLimit = FdsnMotionService.normalizeStationLimit(
        prefs.getInt(_fdsnStationLimitKey) ??
            FdsnMotionService.defaultStationLimit,
      );
      FdsnIntensity.scale.value = FdsnIntensity.parseScale(
        prefs.getString(FdsnIntensity.preferenceKey),
      );
      _niedDataSource = prefs.getString(_niedDataSourceKey) ?? 'lmoni';
      final savedKmaDataSource = prefs.getString(_kmaDataSourceKey);
      _kmaDataSource = switch (savedKmaDataSource) {
        'fan' => 'fan',
        'whews' => 'whews',
        _ => 'pews',
      };
      _snetDataSource = prefs.getString(_snetDataSourceKey) == 'whews'
          ? 'whews'
          : 'msil';
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
        final hasSavedValue = prefs.containsKey(key);
        final val = hasSavedValue
            ? (prefs.getDouble(key) ?? 0.0)
            : source == QuakeSourceType.unadapted
            ? -1.0
            : 0.0;
        if (val != 0 ||
            (source == QuakeSourceType.unadapted && hasSavedValue)) {
          _sourceMagFilters[source.name] = val;
        }
      }
      _infoActionWhitelistController.text =
          prefs.getString(QuakeProvider.infoActionWhitelistPreferenceKey) ?? '';
      _initialized = true;
    });
    QuakeMapView.niedSourceNotifier.value = _niedDataSource;
    QuakeMapView.kmaSourceNotifier.value = _kmaDataSource;
    QuakeMapView.snetSourceNotifier.value = _snetDataSource;
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
    QuakeMapView.whewsApiTokenNotifier.value = credentials.apiToken;
    QuakeMapView.whewsNiedEnabledNotifier.value = false;
    QuakeMapView.whewsSnetEnabledNotifier.value = false;
    QuakeMapView.whewsKmaEnabledNotifier.value = false;
    QuakeMapView.fdsnStationLimitNotifier.value = _fdsnStationLimit;
    SourceManager().setSourceEnabled('FAN', _fanEnabled);
    SourceManager().setSourceEnabled('WHEWS', false);
    SourceManager().setSourceEnabled('NowQuake', _nowQuakeCencIrEnabled);
    SourceManager().setSourceEnabled(JianService.sourceName, _jianEnabled);
    if (!_cencCmtEnabled) EqlistManager().cencCmt.stop();
    if (!_usgsCmtEnabled) EqlistManager().usgsCmt.stop();
    if (!_jmaCmtEnabled) EqlistManager().jmaCmt.stop();
    if (!_fnetCmtEnabled) EqlistManager().fnetCmt.stop();
    if (!_hinetAquaCmtEnabled) EqlistManager().hinetAquaCmt.stop();
    SourceManager().setSourceEnabled('Wolfx', _wolfxEnabled);
    SourceManager().setSourceEnabled('P2P', _p2pquakeEnabled);
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value = _sideInfoAutoShowBeta;
    UiRuntimeFlags.hideGridOnEewNotifier.value = _hideGridOnEew;
    UiRuntimeFlags.weatherMarqueeEnabledNotifier.value = _weatherMarqueeEnabled;
    _niedReplayStartController.text = _niedReplayStart;
    _syncNiedReplayConfig();
    final mapState = context.read<MapStateProvider>();
    mapState.setTileKey(_tileKey);
    mapState.setOverlayEnabled('cloudLayer', _overlayCloud);
    mapState.setOverlayEnabled('windLayer', _overlayWind);
    mapState.setOverlayEnabled('rainLayer', _overlayRain);
    mapState.setOverlayEnabled('radarChinaLayer', _overlayRadarChina);
    mapState.setOverlayEnabled('jmaRadarLayer', _overlayJmaRadar);
    mapState.setOverlayEnabled('satelliteCloudLayer', _overlaySatelliteCloud);
    mapState.setOverlayEnabled('cnContour', _overlayCnContour);
    mapState.setOverlayEnabled('cnFault', _overlayCnFault);
    mapState.setOverlayEnabled('jpFault', _overlayJpFault);
    mapState.setOverlayEnabled('volcanoLayer', _overlayJmaVolcano);
    mapState.setOverlayEnabled('typhoonLayer', _overlayTyphoon);
    mapState.setOverlayEnabled('weatherStationLayer', _overlayWeatherStation);
    mapState.setOverlayEnabled('weatherAlertLayer', _overlayWeatherAlert);
    mapState.setWeatherStationMode(_weatherStationMode);
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
      _wauthRestoredFromStorage = false;
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
    if (enabled) {
      // 先让 Android 前台服务实际启动；启动失败时保留主 isolate 连接，避免出现数据空档。
      await settings.setEnabled(true);
      await BackgroundService().startForegroundService();
      if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
        SourceManager().stopAll();
        EqlistManager().stopOfficialHttpServices();
      }
    } else {
      // 先停止 Android 前台服务，再恢复主 isolate，避免两套连接同时运行。
      await BackgroundService().stopForegroundService(force: true);
      await settings.setEnabled(false);
      if (settings.autoStartOnBoot) {
        await settings.setAutoStartOnBoot(false);
        await BackgroundService().setAutoStartOnBoot(false);
      }
      // 关闭前台连接后恢复桌面/前台的主 isolate 连接路径。
      SourceManager().startAll();
      EqlistManager().startOfficialHttpServices();
    }
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

  Map<String, dynamic>? _readCachedWAuthUserInfo(SharedPreferences prefs) {
    final raw = prefs.getString(WAuthService.userInfoPreferenceKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
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
    await _wauthService.credentialStore.clear(preferences: prefs);
    await prefs.remove(WAuthService.legacySessionTokenPreferenceKey);
    await prefs.remove(WAuthService.userInfoPreferenceKey);
  }

  Future<void> _confirmSavedWAuthLogin() async {
    if (_wauthVerifying) return;
    final prefs = await SharedPreferences.getInstance();
    final cachedUserInfo = _wauthUserInfo ?? _readCachedWAuthUserInfo(prefs);
    final previousApiAuthorized =
        _whewsApiAuthorized ||
        (prefs.getBool(WhewsService.apiAuthorizedPreferenceKey) ?? false);
    if (mounted) {
      setState(() {
        _wauthVerifying = true;
        if (cachedUserInfo != null) {
          _wauthUserInfo = cachedUserInfo;
        }
        if (_wauthAccessToken != null) {
          _wauthRestoredFromStorage = true;
        }
      });
    }

    WAuthStoredAuthorization status;
    try {
      status = await _wauthService.inspectStoredAuthorization(
        preferences: prefs,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _wauthVerifying = false;
          if (_wauthAccessToken != null) {
            _wauthRestoredFromStorage = true;
          }
          _wauthError = 'WAuth 校验暂不可用，已保留本地登录状态。';
        });
      }
      await _restoreCachedWhewsSources(
        preferences: prefs,
        keepEnabled: previousApiAuthorized,
      );
      return;
    }

    if (!status.hasCredentials) {
      if (mounted) setState(() => _wauthVerifying = false);
      return;
    }

    try {
      if (status.shouldForgetLogin) {
        await _removeSavedWAuthLogin();
        await _disableWhewsSources();
        if (!mounted) return;
        setState(() {
          _wauthAccessToken = null;
          _wauthUserInfo = null;
          _wauthRestoredFromStorage = false;
          _whewsApiAuthorized = false;
          _wauthError = 'WAuth 登录已失效，请重新登录。';
        });
        return;
      }

      final userInfo = status.userInfo ?? cachedUserInfo;
      if (status.accessAuthorized && status.userInfo != null) {
        await prefs.setString(
          WAuthService.userInfoPreferenceKey,
          jsonEncode(status.userInfo),
        );
      }

      if (status.apiAuthorized) {
        await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, true);
        await _enableWhewsSources(
          apiToken: status.credentials.apiToken,
          preferences: prefs,
        );
      } else if (status.hasTransientVerificationFailure) {
        await _restoreCachedWhewsSources(
          preferences: prefs,
          keepEnabled: previousApiAuthorized,
        );
      } else {
        await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
        await _disableWhewsSources();
      }

      if (!mounted) return;
      setState(() {
        _wauthAccessToken = status.credentials.accessToken;
        _wauthUserInfo = userInfo;
        _wauthRestoredFromStorage = true;
        _whewsApiAuthorized = status.apiAuthorized
            ? true
            : (status.hasTransientVerificationFailure
                  ? previousApiAuthorized
                  : false);
        _wauthError = status.apiAuthorized
            ? null
            : (status.hasTransientVerificationFailure
                  ? 'WAuth API 暂不可用，已保留本地登录状态。'
                  : '无法确认 WAuth API 授权状态。');
      });
    } finally {
      if (mounted) setState(() => _wauthVerifying = false);
    }
  }

  Future<void> _enableWhewsSources({
    required String apiToken,
    required SharedPreferences preferences,
  }) async {
    QuakeMapView.whewsApiTokenNotifier.value = apiToken;
    SourceManager().getSource<WhewsService>()?.setApiToken(apiToken);
    SourceManager().setSourceEnabled(
      'WHEWS',
      preferences.getBool(_whewsEnabledKey) ?? _whewsEnabled,
    );
    _requestForegroundConnectionReload();
    QuakeMapView.whewsNiedEnabledNotifier.value =
        preferences.getBool(_whewsNiedEnabledKey) ?? _whewsNiedEnabled;
    QuakeMapView.whewsSnetEnabledNotifier.value =
        preferences.getBool(_whewsSnetEnabledKey) ?? _whewsSnetEnabled;
    QuakeMapView.whewsKmaEnabledNotifier.value =
        preferences.getBool(_whewsKmaEnabledKey) ?? _whewsKmaEnabled;
    await BackgroundService().stopForegroundService();
  }

  Future<void> _restoreCachedWhewsSources({
    required SharedPreferences preferences,
    required bool keepEnabled,
  }) async {
    if (!keepEnabled) return;
    WAuthCredentials credentials;
    try {
      credentials = await _wauthService.credentialStore.readAndMigrate(
        preferences: preferences,
      );
    } catch (_) {
      return;
    }
    if (!credentials.isComplete) return;
    await _enableWhewsSources(
      apiToken: credentials.apiToken,
      preferences: preferences,
    );
  }

  Future<void> _disableWhewsSources() async {
    final prefs = await SharedPreferences.getInstance();
    final fallbackNied = _niedDataSource == 'whews';
    final fallbackSnet = _snetDataSource == 'whews';
    final fallbackKma = _kmaDataSource == 'whews';
    if (fallbackNied) await prefs.setString(_niedDataSourceKey, 'lmoni');
    if (fallbackSnet) await prefs.setString(_snetDataSourceKey, 'msil');
    if (fallbackKma) await prefs.setString(_kmaDataSourceKey, 'pews');
    await prefs.setBool(_whewsEnabledKey, false);
    await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
    await prefs.setBool(_whewsNiedEnabledKey, false);
    await prefs.setBool(_whewsSnetEnabledKey, false);
    await prefs.setBool(_whewsKmaEnabledKey, false);
    SourceManager().setSourceEnabled('WHEWS', false);
    _requestForegroundConnectionReload();
    await BackgroundService().stopForegroundService();
    if (fallbackNied) QuakeMapView.niedSourceNotifier.value = 'lmoni';
    if (fallbackSnet) QuakeMapView.snetSourceNotifier.value = 'msil';
    if (fallbackKma) QuakeMapView.kmaSourceNotifier.value = 'pews';
    QuakeMapView.whewsNiedEnabledNotifier.value = false;
    QuakeMapView.whewsSnetEnabledNotifier.value = false;
    QuakeMapView.whewsKmaEnabledNotifier.value = false;
    if (!mounted) return;
    setState(() {
      _whewsEnabled = false;
      _whewsNiedEnabled = false;
      _whewsSnetEnabled = false;
      _whewsKmaEnabled = false;
      if (fallbackNied) _niedDataSource = 'lmoni';
      if (fallbackSnet) _snetDataSource = 'msil';
      if (fallbackKma) _kmaDataSource = 'pews';
    });
  }

  bool _canEnableWhews() {
    if (_whewsApiAuthorized) return true;
    _showWAuthMessage('WHEWS API 需要先完成 WAuth API 授权。');
    return false;
  }

  Future<void> _setNiedDataSource(String source) async {
    setState(() => _niedDataSource = source);
    await _saveNiedDataSource(source);
    if (!mounted || _niedDataSource != source) return;
    QuakeMapView.niedSourceNotifier.value = source;
  }

  Future<void> _setKmaDataSource(String source) async {
    setState(() => _kmaDataSource = source);
    await _saveKmaDataSource(source);
    if (!mounted || _kmaDataSource != source) return;
    QuakeMapView.kmaSourceNotifier.value = source;
  }

  Future<void> _setSnetDataSource(String source) async {
    setState(() => _snetDataSource = source);
    await _saveSnetDataSource(source);
    if (!mounted || _snetDataSource != source) return;
    QuakeMapView.snetSourceNotifier.value = source;
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
      final apiToken = result.token.apiToken;
      if (apiToken == null || apiToken.isEmpty) {
        throw const WAuthApiException(
          statusCode: 401,
          message: 'WAuth 登录未返回 API token，受保护数据源保持关闭。',
        );
      }
      await _wauthService.credentialStore.write(
        accessToken: result.token.accessToken,
        apiToken: apiToken,
        preferences: prefs,
      );
      await prefs.remove(WAuthService.legacySessionTokenPreferenceKey);
      await prefs.setString(
        WAuthService.userInfoPreferenceKey,
        jsonEncode(result.userInfo),
      );
      if (!mounted) return;
      QuakeMapView.whewsApiTokenNotifier.value = apiToken;
      SourceManager().getSource<WhewsService>()?.setApiToken(apiToken);
      _requestForegroundConnectionReload(force: true);
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
    _requestForegroundConnectionReload();
    await _disableWhewsSources();
    if (!mounted) return;
    setState(() {
      _wauthAccessToken = null;
      _wauthUserInfo = null;
      _wauthRestoredFromStorage = false;
      _whewsApiAuthorized = false;
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
      // 保留未适配机构的显式“不过滤”，否则下次启动会恢复默认不接收。
      if (sourceName == QuakeSourceType.unadapted.name) {
        await prefs.setDouble(key, 0);
      } else {
        await prefs.remove(key);
      }
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

  Future<void> _saveKmaDataSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kmaDataSourceKey, source);
  }

  Future<void> _saveSnetDataSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snetDataSourceKey, source);
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
    final coordinates = await showDialog<ManualLocationCoordinates>(
      context: context,
      builder: (_) =>
          ManualLocationDialog(latitude: _mapViewLat, longitude: _mapViewLng),
    );
    if (coordinates == null || !mounted) return;
    await _saveMapViewCenter(coordinates.latitude, coordinates.longitude);
    _showToast(
      '已保存所在地：${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}',
    );
  }

  /// Design canvas (logical px) — landscape panel ≈ 16:9.
  /// Scales uniformly to fill the window (minus outer inset); aspect stays fixed.
  static const double _designPanelWidth = 1180;
  static const double _designPanelHeight = 660;
  static const double _designNavWidth = 228; // ≈ 19.3% of panel width
  static const double _desktopOuterInset = 14;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        context.read<MapStateProvider>(),
        context.read<QuakeProvider>().weatherListenable,
        UiRuntimeFlags.weatherMarqueeEnabledNotifier,
      ]),
      builder: (context, _) {
        if (_initialized || widget.weatherOnly) _readLiveWeatherSettings();
        return widget.weatherOnly
            ? _buildWeatherShortcut()
            : _buildPage(context);
      },
    );
  }

  void _readLiveWeatherSettings() {
    final map = context.read<MapStateProvider>();
    _overlayCloud = map.isOverlayEnabled('cloudLayer');
    _overlayWind = map.isOverlayEnabled('windLayer');
    _overlayRain = map.isOverlayEnabled('rainLayer');
    _overlayRadarChina = map.isOverlayEnabled('radarChinaLayer');
    _overlayJmaRadar = map.isOverlayEnabled('jmaRadarLayer');
    _overlaySatelliteCloud = map.isOverlayEnabled('satelliteCloudLayer');
    _overlayTyphoon = map.isOverlayEnabled('typhoonLayer');
    _overlayWeatherStation = map.isOverlayEnabled('weatherStationLayer');
    _overlayWeatherAlert = map.isOverlayEnabled('weatherAlertLayer');
    _weatherStationMode = map.weatherStationMode;
    _weatherLocalOnly = context.read<QuakeProvider>().weatherLocalOnly;
    _weatherLocalLevel = context.read<QuakeProvider>().weatherLocalAdminLevel;
    _weatherMarqueeEnabled = UiRuntimeFlags.weatherMarqueeEnabledNotifier.value;
  }

  Widget _buildWeatherShortcut() => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Material(
        color: const Color(0xD91C2328),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '气象图层与预警',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _buildMapOverlaySelector(weatherOnly: true),
                    const _SettingsDivider(),
                    _buildWeatherAlarmScopeSelector(),
                    if (_weatherLocalOnly)
                      _buildWeatherAlarmLocalLevelSelector(),
                    _buildWeatherMarqueeEnabledSwitch(),
                    if (_overlayWeatherStation)
                      _buildWeatherStationModeSelector(),
                    _buildWeatherAlertMapLayerSwitch(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020208),
      body: Stack(
        children: [
          const AppPageBackground(),
          if (_initialized)
            SafeArea(
              minimum: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + widget.contentTopInset,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sideBySide = constraints.maxWidth >= 600;
                  if (!sideBySide) {
                    return Padding(
                      padding: const EdgeInsets.all(14),
                      child: _buildUnifiedPanel(sideBySide: false),
                    );
                  }

                  final maxW = (constraints.maxWidth - _desktopOuterInset * 2)
                      .clamp(0.0, double.infinity);
                  final maxH = (constraints.maxHeight - _desktopOuterInset * 2)
                      .clamp(0.0, double.infinity);
                  if (maxW <= 0 || maxH <= 0) {
                    return const SizedBox.shrink();
                  }
                  // Keep the baseline scale while letting the wider axis expand.
                  final scale = math.min(
                    maxW / _designPanelWidth,
                    maxH / _designPanelHeight,
                  );
                  final panelW = maxW;
                  final panelH = maxH;
                  final logicalPanelWidth = panelW / scale;
                  final logicalPanelHeight = panelH / scale;

                  return Center(
                    child: SizedBox(
                      width: panelW,
                      height: panelH,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          minWidth: logicalPanelWidth,
                          maxWidth: logicalPanelWidth,
                          minHeight: logicalPanelHeight,
                          maxHeight: logicalPanelHeight,
                          child: Transform.scale(
                            scale: scale,
                            child: SizedBox(
                              width: logicalPanelWidth,
                              height: logicalPanelHeight,
                              child: MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  size: Size(
                                    logicalPanelWidth,
                                    logicalPanelHeight,
                                  ),
                                  padding: EdgeInsets.zero,
                                  viewPadding: EdgeInsets.zero,
                                ),
                                child: _buildUnifiedPanel(sideBySide: true),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildUnifiedPanel({required bool sideBySide}) {
    final body = sideBySide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _designNavWidth,
                child: _buildCategoryNavigation(compactGrid: false),
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: _dividerColor,
              ),
              Expanded(child: _buildSettingsContent()),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCategoryNavigation(compactGrid: true),
              const Divider(height: 1, thickness: 1, color: _dividerColor),
              Expanded(child: _buildSettingsContent()),
            ],
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _panelBlurSigma,
          sigmaY: _panelBlurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // Match HTML inset top highlight without overriding panel fill.
          child: Stack(
            children: [
              body,
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: IgnorePointer(
                  child: ColoredBox(color: Color.fromRGBO(255, 255, 255, 0.08)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryNavigation({required bool compactGrid}) {
    final head = SizedBox(
      height: _panelHeaderHeight,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed:
                        widget.onBack ?? () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 20),
                    color: _accentColor,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '应用设置',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _HeaderFadeDivider(),
          ),
        ],
      ),
    );

    if (compactGrid) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _categories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 44,
              ),
              itemBuilder: (context, index) {
                return _buildCategoryButton(
                  _categories[index],
                  expanded: false,
                  fillWidth: true,
                );
              },
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            children: [
              for (final info in _categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildCategoryButton(info, expanded: true),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryButton(
    _SettingsCategoryInfo info, {
    required bool expanded,
    bool fillWidth = false,
  }) {
    final selected =
        _settingsQuery.isEmpty && _selectedCategory == info.category;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          _settingsSearchController.clear();
          setState(() {
            _settingsQuery = '';
            _selectedCategory = info.category;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: expanded ? 58 : 44,
          width: fillWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      info.accent.withValues(alpha: 0.14),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? info.accent.withValues(alpha: 0.42)
                  : Colors.transparent,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: (expanded || fillWidth)
                ? MainAxisSize.max
                : MainAxisSize.min,
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
              else if (fillWidth)
                Expanded(
                  child: Text(
                    info.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _panelHeaderHeight,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                          _settingsQuery.isEmpty
                              ? activeInfo.icon
                              : Icons.search,
                          color: _settingsQuery.isEmpty
                              ? activeInfo.accent
                              : _accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _settingsQuery.isEmpty
                                  ? activeInfo.title
                                  : '搜索结果',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
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
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: _HeaderFadeDivider(),
              ),
            ],
          ),
        ),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
          _buildSectionPanel(
            icon: Icons.power_settings_new_outlined,
            title: 'API/数据接口开关',
            children: [_buildApiInterfaceSwitches()],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
          _buildSectionPanel(
            icon: Icons.tune_outlined,
            title: 'API/数据接口选项',
            children: [
              _buildFanServerSelector(),
              const _SettingsDivider(),
              _buildNiedDataSourceSelector(),
              const _SettingsDivider(),
              _buildKmaDataSourceSelector(),
              const _SettingsDivider(),
              _buildSnetDataSourceSelector(),
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
              const _SettingsDivider(),
              _buildFdsnIntensitySelector(),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
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
            children: [
              _buildTileSelector(),
              const _SettingsDivider(),
              _buildInfoLayerSwitch(
                title: '中国断层',
                value: _overlayCnFault,
                leading: Icons.show_chart,
                onChanged: (val) {
                  setState(() => _overlayCnFault = val);
                  _saveOverlayState(_overlayCnFaultKey, val);
                  context.read<MapStateProvider>().setOverlayEnabled(
                    'cnFault',
                    val,
                  );
                },
              ),
              const _SettingsDivider(),
              _buildInfoLayerSwitch(
                title: '日本断层',
                subtitle: '来源：日本产总研地质调查综合中心（GSJ）活断层数据库；概略位置',
                value: _overlayJpFault,
                leading: Icons.show_chart,
                onChanged: (val) {
                  setState(() => _overlayJpFault = val);
                  _saveOverlayState(_overlayJpFaultKey, val);
                  context.read<MapStateProvider>().setOverlayEnabled(
                    'jpFault',
                    val,
                  );
                },
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
          _buildSectionPanel(
            icon: Icons.my_location_outlined,
            title: '所在地定位',
            children: [_buildMapCenterControls()],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
          _buildSectionPanel(
            icon: Icons.map_outlined,
            title: '视野切换',
            children: [_buildDefaultViewControls()],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
          _buildSectionPanel(
            icon: Icons.warning_amber_outlined,
            title: '气象预警与实况',
            children: [
              _buildWeatherAlarmScopeSelector(),
              if (_weatherLocalOnly) ...[
                const _SettingsDivider(),
                _buildWeatherAlarmLocalLevelSelector(),
              ],
              const _SettingsDivider(),
              _buildWeatherMarqueeEnabledSwitch(),
              const _SettingsDivider(),
              _buildWeatherStationLayerSwitch(),
              if (_overlayWeatherStation) ...[
                const _SettingsDivider(),
                _buildWeatherStationModeSelector(),
              ],
              const _SettingsDivider(),
              _buildWeatherAlertMapLayerSwitch(),
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
              const _SettingsDivider(),
              _buildPageBackgroundSettings(),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
          _buildSectionPanel(
            icon: Icons.account_tree_outlined,
            title: '自动化',
            children: [_buildObsAutomationEntry()],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _dividerColor),
          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
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
    );
  }

  Widget _buildApiInterfaceSwitches() {
    final rows = [
      _buildApiSwitch(
        title: 'Jian Project 地震预警/情报',
        value: _jianEnabled,
        onChanged: (val) async {
          setState(() => _jianEnabled = val);
          await _saveApiSourceEnabled(JianService.enabledPreferenceKey, val);
          SourceManager().setSourceEnabled(JianService.sourceName, val);
          _requestForegroundConnectionReload();
        },
      ),
      _buildApiSwitch(
        title: 'FAN Studio',
        value: _fanEnabled,
        onChanged: (val) {
          setState(() => _fanEnabled = val);
          _saveApiSourceEnabled(_fanEnabledKey, val);
          SourceManager().setSourceEnabled('FAN', val);
          _requestForegroundConnectionReload();
        },
      ),
      _buildApiSwitch(
        title: 'WHEWS 地震预警/情报',
        value: _whewsEnabled,
        onChanged: (val) async {
          if (val && !_canEnableWhews()) return;
          setState(() => _whewsEnabled = val);
          await _saveApiSourceEnabled(_whewsEnabledKey, val);
          SourceManager().setSourceEnabled('WHEWS', val);
          _requestForegroundConnectionReload();
          await BackgroundService().stopForegroundService();
        },
      ),
      _buildApiSwitch(
        title: 'NowQuake',
        value: _nowQuakeCencIrEnabled,
        onChanged: (val) {
          setState(() => _nowQuakeCencIrEnabled = val);
          _saveApiSourceEnabled(_nowQuakeCencIrEnabledKey, val);
          SourceManager().setSourceEnabled('NowQuake', val);
          _requestForegroundConnectionReload();
        },
      ),
      _buildApiSwitch(
        title: 'CENC 震源机制解 (CMT)',
        value: _cencCmtEnabled,
        onChanged: (val) {
          setState(() => _cencCmtEnabled = val);
          _saveApiSourceEnabled(_cencCmtEnabledKey, val);
          if (BackgroundService()
              .isAndroidConnectionHostedByForegroundService) {
            EqlistManager().cencCmt.stop();
            _requestForegroundConnectionReload();
          } else if (val) {
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
          if (BackgroundService()
              .isAndroidConnectionHostedByForegroundService) {
            EqlistManager().usgsCmt.stop();
            _requestForegroundConnectionReload();
          } else if (val) {
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
          if (BackgroundService()
              .isAndroidConnectionHostedByForegroundService) {
            EqlistManager().jmaCmt.stop();
            _requestForegroundConnectionReload();
          } else if (val) {
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
          if (BackgroundService()
              .isAndroidConnectionHostedByForegroundService) {
            EqlistManager().fnetCmt.stop();
            _requestForegroundConnectionReload();
          } else if (val) {
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
          if (BackgroundService()
              .isAndroidConnectionHostedByForegroundService) {
            EqlistManager().hinetAquaCmt.stop();
            _requestForegroundConnectionReload();
          } else if (val) {
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
          _requestForegroundConnectionReload();
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
          _requestForegroundConnectionReload();
        },
      ),
      _buildApiSwitch(
        title: 'KMA 实时测站',
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
        onChanged: (val) async {
          if (val && !_canEnableWhews()) return;
          if (!val && _niedDataSource == 'whews') {
            _setNiedDataSource('lmoni');
          }
          setState(() => _whewsNiedEnabled = val);
          await _saveApiSourceEnabled(_whewsNiedEnabledKey, val);
          QuakeMapView.whewsNiedEnabledNotifier.value = val;
          await BackgroundService().stopForegroundService();
        },
      ),
      _buildApiSwitch(
        title: 'WHEWS S-Net 实时测站',
        value: _whewsSnetEnabled,
        onChanged: (val) async {
          if (val && !_canEnableWhews()) return;
          if (!val && _snetDataSource == 'whews') {
            _setSnetDataSource('msil');
          }
          setState(() => _whewsSnetEnabled = val);
          await _saveApiSourceEnabled(_whewsSnetEnabledKey, val);
          QuakeMapView.whewsSnetEnabledNotifier.value = val;
          await BackgroundService().stopForegroundService();
        },
      ),
      _buildApiSwitch(
        title: 'WHEWS KMA 实时测站',
        value: _whewsKmaEnabled,
        onChanged: (val) async {
          if (val && !_canEnableWhews()) return;
          if (!val && _kmaDataSource == 'whews') {
            _setKmaDataSource('pews');
          }
          setState(() => _whewsKmaEnabled = val);
          await _saveApiSourceEnabled(_whewsKmaEnabledKey, val);
          QuakeMapView.whewsKmaEnabledNotifier.value = val;
          await BackgroundService().stopForegroundService();
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

  String _wauthSettingSubtitle() {
    if (_wauthBusy) {
      return _wauthBrowserOpened ? '等待在浏览器中完成 WAuth 登录' : '正在连接 WAuth 登录服务';
    }
    final hasSavedLogin =
        _wauthAccessToken != null || _wauthRestoredFromStorage;
    if (hasSavedLogin) {
      final userInfo = _wauthUserInfo;
      final loginLabel = userInfo != null
          ? '已登录：${_wauthUserLabel(userInfo)}'
          : '已登录';
      if (_wauthError != null && _wauthError!.isNotEmpty) {
        return '$loginLabel。$_wauthError';
      }
      return loginLabel;
    }
    return _wauthError ?? '未登录时 WAuth 业务 API 不可开启';
  }

  Widget _buildWAuthSetting() {
    final hasSavedLogin =
        _wauthAccessToken != null || _wauthRestoredFromStorage;
    final status = _wauthSettingSubtitle();
    return _buildSettingRow(
      title: 'WAuth 账号授权',
      subtitle: status,
      leading: _wauthBusy
          ? Icons.hourglass_top_outlined
          : hasSavedLogin
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
            child: _buildGlassActionButton(
              label: _wauthBusy
                  ? _wauthBrowserOpened
                        ? '等待登录'
                        : '正在打开'
                  : hasSavedLogin
                  ? '重新登录'
                  : '登录',
              icon: _wauthBusy
                  ? null
                  : (hasSavedLogin
                        ? Icons.refresh_outlined
                        : Icons.login_outlined),
              busy: _wauthBusy,
              emphasized: true,
              onPressed: _wauthBusy ? null : _startWAuthAuthorization,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTileSelector() {
    return _buildSettingRow(
      title: '地图底图',
      subtitle: _tileKey == MapConfig.vectorBasemapKey
          ? null
          : '调整主地图底图样式',
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

  Widget _buildMapOverlaySelector({bool weatherOnly = false}) {
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
        title: 'JMA 雷达',
        value: _overlayJmaRadar,
        leading: Icons.radar,
        onChanged: (val) {
          setState(() => _overlayJmaRadar = val);
          _saveOverlayState(_overlayJmaRadarKey, val);
          context.read<MapStateProvider>().setOverlayEnabled(
            'jmaRadarLayer',
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
      if (!weatherOnly)
        _buildInfoLayerSwitch(
          title: '中国等高线',
          value: _overlayCnContour,
          leading: Icons.terrain_outlined,
          onChanged: (val) {
            setState(() => _overlayCnContour = val);
            _saveOverlayState(_overlayCnContourKey, val);
            context.read<MapStateProvider>().setOverlayEnabled(
              'cnContour',
              val,
            );
          },
        ),
      if (!weatherOnly)
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
      _buildInfoLayerSwitch(
        title: '气象站实况',
        value: _overlayWeatherStation,
        leading: Icons.cloud_sync_outlined,
        onChanged: (val) {
          setState(() => _overlayWeatherStation = val);
          _saveOverlayState(_overlayWeatherStationKey, val);
          context.read<MapStateProvider>().setOverlayEnabled(
            'weatherStationLayer',
            val,
          );
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
    String? subtitle,
    required bool value,
    required IconData leading,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildSettingRow(
      title: title,
      subtitle: subtitle ?? (value ? '已启用，显示该信息' : '已关闭，隐藏该信息'),
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

  /// Shared frosted selectable chip / segment look.
  BoxDecoration _glassSelectableDecoration({required bool selected}) {
    return BoxDecoration(
      gradient: selected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                _accentColor.withValues(alpha: 0.34),
              ],
            )
          : null,
      color: selected ? null : Colors.white.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: selected
            ? _accentColor.withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.22),
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );
  }

  ButtonStyle _glassOutlinedButtonStyle({bool emphasize = false}) {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: emphasize
          ? _accentColor.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.11),
      side: BorderSide(
        color: emphasize
            ? _accentColor.withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.24),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildGlassActionButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool busy = false,
    bool emphasized = false,
  }) {
    final enabled = onPressed != null && !busy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _glassSelectableDecoration(selected: emphasized).copyWith(
            color: emphasized
                ? null
                : Colors.white.withValues(alpha: enabled ? 0.11 : 0.06),
            border: Border.all(
              color: emphasized
                  ? _accentColor.withValues(alpha: enabled ? 0.78 : 0.35)
                  : Colors.white.withValues(alpha: enabled ? 0.22 : 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white70,
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 16,
                  color: enabled ? Colors.white : Colors.white54,
                ),
              if (busy || icon != null) const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayToggle({
    required String label,
    required bool selected,
    required ValueChanged<bool> onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(!selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: _glassSelectableDecoration(selected: selected),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
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
              style: _glassOutlinedButtonStyle(),
              onPressed: _autoLocateMapCenter,
              icon: const Icon(Icons.gps_fixed, size: 16),
              label: const Text('自动定位'),
            ),
          );
          final buttonB = SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              style: _glassOutlinedButtonStyle(),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: _glassSelectableDecoration(selected: selected),
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
            if (_isAndroidNotificationPlatform) ...[
              const Divider(height: 1, color: _dividerColor),
              _buildBackgroundSwitch(
                label: '开机自动启动前台服务',
                value: bg.autoStartOnBoot,
                onChanged: (value) async {
                  try {
                    await BackgroundService().setAutoStartOnBoot(value);
                    await bg.setAutoStartOnBoot(value);
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('开机自启设置失败，请重试。')),
                    );
                  }
                },
              ),
              const Divider(height: 1, color: _dividerColor),
              const AndroidBackgroundPowerSettings(),
            ],
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
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => bg.setEewMinIntensity(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: _glassSelectableDecoration(selected: selected),
                    child: Text(
                      BackgroundSettingsProvider.intensityLabel(value),
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
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
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 8),
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

  Widget _buildFdsnIntensitySelector() => _buildSettingRow(
    title: 'FDSN 烈度显示',
    subtitle: '仪器烈度估算',
    leading: Icons.palette_outlined,
    control: ValueListenableBuilder<FdsnIntensityScale>(
      valueListenable: FdsnIntensity.scale,
      builder: (context, scale, child) => _buildDropdown<FdsnIntensityScale>(
        value: scale,
        options: const [
          _SelectOption(FdsnIntensityScale.mmi, 'MMI'),
          _SelectOption(FdsnIntensityScale.csis, '中国烈度（估算）'),
        ],
        onChanged: (value) async {
          if (value == null) return;
          FdsnIntensity.scale.value = value;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(FdsnIntensity.preferenceKey, value.name);
        },
      ),
    ),
  );

  Widget _buildNiedDataSourceSelector() {
    final options = [
      ('lmoni', 'Lmoni'),
      ('kmoni', 'KMONI'),
      ('yahoo', 'Yahoo'),
      if (_whewsApiAuthorized && _whewsNiedEnabled) ('whews', 'WHEWS'),
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
          _setNiedDataSource(val);
        },
      ),
    );
  }

  Widget _buildKmaDataSourceSelector() {
    final options = [
      ('pews', 'KMA-PEWS'),
      ('fan', 'FAN'),
      if (_whewsApiAuthorized && _whewsKmaEnabled) ('whews', 'WHEWS'),
    ];
    return _buildSettingRow(
      title: 'KMA 实时测站数据源',
      subtitle: '选择 KMA 测站实时数据输入来源',
      leading: Icons.sensors_outlined,
      control: _buildSegmentedSelector<String>(
        value: _kmaDataSource,
        options: options.map((opt) => _SelectOption(opt.$1, opt.$2)).toList(),
        onChanged: (val) {
          if (val == null) return;
          _setKmaDataSource(val);
        },
      ),
    );
  }

  Widget _buildSnetDataSourceSelector() {
    final options = [
      ('msil', 'MSIL'),
      if (_whewsApiAuthorized && _whewsSnetEnabled) ('whews', 'WHEWS'),
    ];
    return _buildSettingRow(
      title: 'S-Net 实时测站数据源',
      subtitle: '选择海底测站实时数据输入来源',
      leading: Icons.waves_outlined,
      control: _buildSegmentedSelector<String>(
        value: _snetDataSource,
        options: options.map((opt) => _SelectOption(opt.$1, opt.$2)).toList(),
        onChanged: (val) {
          if (val == null) return;
          _setSnetDataSource(val);
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
    final provider = context.read<QuakeProvider>();
    return ValueListenableBuilder<int>(
      valueListenable: provider.weatherListenable,
      builder: (context, _, child) {
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
      },
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

  Widget _buildWeatherStationLayerSwitch() {
    return _buildSettingRow(
      title: '气象站实况图层',
      subtitle: '在地图上绘制全国气象观测站实况，突出显示降水与雨量',
      leading: Icons.cloud_sync_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _overlayWeatherStation,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _overlayWeatherStation = val);
            _saveOverlayState(_overlayWeatherStationKey, val);
            context.read<MapStateProvider>().setOverlayEnabled(
              'weatherStationLayer',
              val,
            );
          },
        ),
      ),
    );
  }

  Widget _buildWeatherStationModeSelector() {
    return _buildSettingRow(
      title: '气象站展示要素',
      subtitle: '切换地图气象站的主要呈现数据',
      leading: Icons.tune_outlined,
      control: _buildSegmentedSelector<String>(
        value: _weatherStationMode,
        options: const [
          _SelectOption('auto', '综合(降雨优先)'),
          _SelectOption('rain', '降水雨量'),
          _SelectOption('temperature', '气温'),
          _SelectOption('wind', '风向风力'),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() => _weatherStationMode = val);
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString(_weatherStationModeKey, val);
          });
          context.read<MapStateProvider>().setWeatherStationMode(val);
        },
      ),
    );
  }

  Widget _buildWeatherAlertMapLayerSwitch() {
    return _buildSettingRow(
      title: '气象灾害预警图层',
      subtitle: '在地图上绘制全国突发气象灾害预警多边形区域与灾害等级色标',
      leading: Icons.notifications_active_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: _overlayWeatherAlert,
          activeThumbColor: _accentColor,
          activeTrackColor: _accentColor.withValues(alpha: 0.38),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          onChanged: (val) {
            setState(() => _overlayWeatherAlert = val);
            _saveOverlayState(_overlayWeatherAlertKey, val);
            context.read<MapStateProvider>().setOverlayEnabled(
              'weatherAlertLayer',
              val,
            );
          },
        ),
      ),
    );
  }

  Widget _buildHideGridOnEewSwitch() {
    return _buildSettingRow(
      title: '预警时隐藏网格与匹配推算',
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
            UiRuntimeFlags.hideGridOnEewNotifier.value = val;
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
      subtitle: 'NIED / P-Alert',
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
                    style: _glassOutlinedButtonStyle().copyWith(
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 12),
                      ),
                      foregroundColor: const WidgetStatePropertyAll(
                        Colors.white70,
                      ),
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
                style: _glassOutlinedButtonStyle(emphasize: true),
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
      decoration: _glassSelectableDecoration(selected: value),
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
          final currentVal =
              _sourceMagFilters[sourceName] ??
              (source == QuakeSourceType.unadapted ? -1 : 0);
          final displayName = source == QuakeSourceType.unadapted
              ? '未适配机构'
              : source.displayName;
          final subtitle = source == QuakeSourceType.unadapted
              ? '未登记机构的信息事件；默认不接收'
              : '低于阈值的信息事件不会显示';
          return Column(
            children: [
              _buildSettingRow(
                title: displayName,
                subtitle: subtitle,
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
                      if (val == 0 && source != QuakeSourceType.unadapted) {
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

  Widget _buildPageBackgroundSettings() {
    final pageBg = context.watch<PageBackgroundProvider>();
    final usingCustom = pageBg.useCustom && pageBg.hasCustomImage;
    final canEnableSaved = !usingCustom && pageBg.hasCustomImage;

    return _buildSettingRow(
      title: '自定义背景',
      subtitle: '${pageBg.statusLabel}；用于设置页与调试页',
      leading: Icons.wallpaper_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            _buildGlassActionButton(
              label: '选择图片',
              icon: Icons.image_outlined,
              emphasized: true,
              onPressed: kIsWeb ? null : _pickCustomPageBackground,
            ),
            _buildGlassActionButton(
              label: usingCustom ? '恢复默认' : (canEnableSaved ? '启用自定义' : '恢复默认'),
              icon: usingCustom || !canEnableSaved
                  ? Icons.restart_alt
                  : Icons.check_circle_outline,
              onPressed: usingCustom
                  ? () => _restoreDefaultPageBackground(pageBg)
                  : (canEnableSaved
                        ? () => _enableSavedCustomPageBackground(pageBg)
                        : null),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomPageBackground() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        _showPageBackgroundSnack('未能读取所选图片路径');
        return;
      }

      final ok = await context.read<PageBackgroundProvider>().setCustomImage(
        path,
      );
      if (!mounted) return;
      _showPageBackgroundSnack(ok ? '已应用自定义背景' : '应用自定义背景失败');
    } catch (e) {
      if (!mounted) return;
      _showPageBackgroundSnack('选择背景失败：$e');
    }
  }

  Future<void> _restoreDefaultPageBackground(
    PageBackgroundProvider pageBg,
  ) async {
    await pageBg.restoreDefault();
    if (!mounted) return;
    _showPageBackgroundSnack('已恢复默认背景');
  }

  Future<void> _enableSavedCustomPageBackground(
    PageBackgroundProvider pageBg,
  ) async {
    await pageBg.enableSavedCustom();
    if (!mounted) return;
    _showPageBackgroundSnack(pageBg.useCustom ? '已启用自定义背景' : '没有可用的自定义背景');
  }

  void _showPageBackgroundSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
            style: _glassOutlinedButtonStyle(emphasize: true),
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

  Widget _buildObsAutomationEntry() {
    return _buildSettingRow(
      title: 'OBS 自动化预设',
      subtitle: '编辑触发条件与录制、回放动作',
      leading: Icons.videocam_outlined,
      control: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 160,
          height: 40,
          child: OutlinedButton.icon(
            style: _glassOutlinedButtonStyle(emphasize: true),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ObsAutomationPresetsPage(),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('管理预设'),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    String? subtitle,
    required IconData leading,
    required Widget control,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final titleBlock = Row(
          crossAxisAlignment: subtitle == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accentColor.withValues(alpha: 0.28)),
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
                    if (subtitle != null) ...[
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
    const dropdownTextStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final selected = options.cast<_SelectOption<T>?>().firstWhere(
      (option) => option?.value == value,
      orElse: () => null,
    );
    final selectedLabel = selected?.label ?? value.toString();
    return SizedBox(
      width: width,
      height: 40,
      child: PopupMenuButton<T>(
        tooltip: '',
        padding: EdgeInsets.zero,
        color: const Color(0xFF23283D),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        onSelected: onChanged,
        itemBuilder: (context) {
          return options.map((option) {
            final isSelected = option.value == value;
            return PopupMenuItem<T>(
              value: option.value,
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                option.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: dropdownTextStyle.copyWith(
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _glassSelectableDecoration(selected: false).copyWith(
            color: _fieldColor,
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selectedLabel,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: dropdownTextStyle,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _accentColor,
                size: 20,
              ),
            ],
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
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 40,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: _glassSelectableDecoration(selected: selected),
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

/// Header rule that fades out at both ends.
class _HeaderFadeDivider extends StatelessWidget {
  const _HeaderFadeDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 1,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromRGBO(255, 255, 255, 0),
              Color.fromRGBO(255, 255, 255, 0.12),
              Color.fromRGBO(255, 255, 255, 0.12),
              Color.fromRGBO(255, 255, 255, 0),
            ],
            stops: [0.0, 0.18, 0.82, 1.0],
          ),
        ),
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
