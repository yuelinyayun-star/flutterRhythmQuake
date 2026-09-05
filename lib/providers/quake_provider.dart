/// 地震数据状态管理提供者
///
/// 本模块是应用的核心状态管理器，负责：
/// - 接收和处理来自各数据源的地震消息
/// - 管理活动预警和信息事件
/// - 计算距离和预估烈度
/// - 触发语音警报和窗口提醒
/// - 管理历史地震记录
///
/// ## 数据流程
///
/// 1. 数据源服务通过 EventBus 发布 QuakeMessage
/// 2. QuakeProvider 接收消息并计算距离/烈度
/// 3. 根据消息类型分发到预警列表或信息列表
/// 4. 触发相应的通知和语音警报
/// 5. 更新 UI 显示
///
/// ## 预警分类
///
/// - **预警事件**: 来自预警系统的紧急地震速报
/// - **信息事件**: 来自地震台网的正式测定结果
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show kIsWeb, mapEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/event_bus.dart';
import '../services/location_service.dart';
import '../services/tts_service.dart';
import '../services/sound_effect_service.dart';
import '../services/windows_manager.dart';
import '../services/database_helper.dart';
import '../services/ntp_service.dart';
import '../services/background_service.dart';
import '../services/background_event_processor.dart';
import '../services/obs_automation_input_service.dart';
import '../services/sources/source_manager.dart';
import '../services/sources/fan_service.dart';
import '../services/sources/nowquake_cenc_intensity_service.dart';
import '../core/local_weather_region.dart';
import '../services/sources/china_weather_alert_service.dart';
import '../services/sources/cma_local_weather_service.dart';
import '../services/sources/jma_local_weather_service.dart';
import '../services/epicenter_region_service.dart';
import '../services/sources/typhoon_service.dart';
import '../services/sources/wolfx_service.dart';
import '../services/sources/whews_service.dart';
import '../services/sources/p2pquake_service.dart';
import '../services/sources/mock_input_service.dart';
import '../services/sources/global_quake_service.dart';
import '../services/sources/eqlist/eqlist_manager.dart';
import '../services/quake_event_adapter.dart';
import '../core/intensity_calculator.dart';
import '../core/calculator.dart';
import '../core/travel_time_service.dart';
import '../models/quake_message.dart';
import '../models/unified_quake_data.dart';
import '../models/eew_event_group.dart';
import '../models/source_status.dart';
import '../models/cenc_ir_data.dart';
import '../models/weather_alarm.dart';
import '../models/typhoon_data.dart';
import '../models/tsunami_message.dart';
import '../models/jma_lpgm_bulletin.dart';
import '../core/utils/alert_voice_helper.dart';
import '../core/utils/quake_time.dart';

/// 活动预警事件
///
/// 表示一个正在显示的地震预警事件，包含距离和预估烈度信息。
/// 参考 kanameishi 的 EewEvent 类设计，支持同一事件的多次更新。
class ActiveWarning {
  /// 地震事件数据
  QuakeMessage event;

  /// 距离用户的距离 (km)
  double distance;

  /// 预估烈度
  double estimatedIntensity;

  /// 上次播报的倒计时秒数
  ///
  /// 用于避免重复播报相同的倒计时。
  int lastSpokenSeconds;

  /// 是否已静默
  bool mute;

  /// 自动移除定时器
  Timer? dismissTimer;

  /// 剩余显示时间（秒）
  ///
  /// 对于初始加载恢复的 EEW，已过去的时间需要从总超时中扣除。
  /// 为 null 时使用 timeoutSeconds（实时事件）。
  int? remainingSeconds;

  ActiveWarning({
    required this.event,
    required this.distance,
    required this.estimatedIntensity,
    this.lastSpokenSeconds = -1,
    this.mute = false,
    this.dismissTimer,
    this.remainingSeconds,
  });

  /// 更新事件数据
  ///
  /// 保留上一报的播报状态，避免重复播报。
  void update(QuakeMessage newEvent, double newDistance, double newIntensity) {
    final preservedOrigin = event.originTime;
    event = newEvent.copyWith(originTime: preservedOrigin);
    distance = newDistance;
    estimatedIntensity = newIntensity;
  }

  /// 获取过期时间（秒）
  ///
  /// 参考 kanameishi 的过期策略：
  /// - 取消报：20秒
  /// - 警报级 (isWarn)：max(震级, 6) * 60 秒
  /// - 普通：max(震级, 3) * 60 秒
  int get timeoutSeconds {
    if (event.isCanceled) return 20;
    final mag = event.magnitude;
    if (event.isWarn) return ((mag > 6 ? mag : 6) * 60).ceil();
    return ((mag > 3 ? mag : 3) * 60).ceil();
  }
}

/// 活动信息事件
///
/// 表示一个正在显示的地震信息事件（非预警）。
class ActiveInfoEvent {
  /// 地震事件数据
  final QuakeMessage event;

  /// 距离用户的距离 (km)
  final double distance;

  /// 预估烈度
  final double estimatedIntensity;

  /// 接收时间
  final DateTime receivedAt;

  ActiveInfoEvent({
    required this.event,
    required this.distance,
    required this.estimatedIntensity,
    required this.receivedAt,
  });
}

/// 地震数据提供者
///
/// 应用核心状态管理器，使用 ChangeNotifier 模式。
/// 管理所有地震相关的状态和业务逻辑。
class QuakeProvider with ChangeNotifier {
  /// 当前显示的事件
  QuakeMessage? _currentEvent;

  /// 当前事件距离用户的距离 (km)
  double _currentDistance = 0.0;

  /// 当前事件的预估烈度
  double _estimatedIntensity = 0.0;

  /// 上次播报的倒计时秒数
  int _lastSpokenSeconds = -1;

  /// P 波到达倒计时（秒），-1 表示未计算/不适用
  int _pCountdown = -1;

  /// S 波到达倒计时（秒），-1 表示未计算/不适用
  int _sCountdown = -1;

  /// 倒计时定时器
  Timer? _countdownTimer;

  /// 活动预警列表
  final List<ActiveWarning> _activeWarnings = [];

  /// 当前轮播索引
  int _currentWarningIndex = 0;

  /// 轮播定时器
  Timer? _carouselTimer;

  /// 信息事件自动关闭定时器
  Timer? _infoDismissTimer;

  /// 信息事件自动关闭时长（秒）
  static const int _infoDismissDuration = 120;

  /// 临时信息显示计时器（有预警时信息事件显示5秒后切回预警）
  Timer? _tempInfoDisplayTimer;

  /// 临时显示信息事件的时长（秒）
  static const int _tempInfoDisplayDuration = 10;

  /// 是否正在临时显示信息事件
  bool _isShowingTempInfo = false;

  /// 所有预警和信息事件过期时的回调
  void Function()? onAllEventsExpired;

  /// 统一事件被处理（首次收到或更新）时的回调
  ///
  /// 参数 [isUpdate] 为 true 表示这是同一事件的后续更新报。
  void Function(UnifiedQuakeData event, bool isUpdate)? onUnifiedEventNotified;

  /// 活动信息事件列表
  final List<ActiveInfoEvent> _activeInfoEvents = [];

  /// 实时传入的 CENC 烈度速报数据
  CencIrData? _realtimeCencIrData;

  /// 手动选择查看的 CENC 烈度速报数据
  CencIrData? _manualCencIrData;

  /// 当前是否正在显示手动选择的 CENC 烈度速报
  bool _isManualCencIrActive = false;

  /// 当前正在等待的手动详情请求。
  String? _pendingManualCencIrId;
  int _manualCencIrRequestSerial = 0;

  /// CENC 烈度速报列表缓存（供手动选择使用）
  List<Map<String, dynamic>> _cencIrList = [];
  List<Map<String, dynamic>> _fanCencIrList = [];
  List<Map<String, dynamic>> _nowQuakeCencIrList = [];
  final Set<String> _fanCencIrDetailFallbackIds = {};

  /// 气象预警数据
  WeatherAlarm? _weatherAlarm;
  Timer? _weatherAlarmExpiryTimer;
  WeatherAlarm? _chinaWeatherLocalAlarm;
  WeatherAlarm? _cmaStationWeatherAlarm;
  WeatherAlarm? _jmaStationWeatherAlarm;
  bool _weatherLocalOnly = true;
  String _weatherLocalAdminLevel = 'county';
  double? _weatherFallbackLat;
  double? _weatherFallbackLng;
  List<String> _weatherLocalKeywords = const [];
  final ChinaWeatherAlertService _chinaWeatherService =
      ChinaWeatherAlertService();
  List<TyphoonData> _activeTyphoons = const [];
  final TyphoonService _typhoonService = TyphoonService();
  bool _typhoonLayerEnabled = false;
  int _typhoonUpdateRevision = 0;

  /// JMA 海啸情报
  TsunamiMessage? _jmaTsunami;

  /// NMEFC 海啸预警
  TsunamiMessage? _nmefcTsunami;

  /// PTWC 海啸情报
  TsunamiMessage? _ptwcTsunami;

  /// NTWC 海啸情报
  TsunamiMessage? _ntwcTsunami;

  /// INCOIS 海啸情报
  TsunamiMessage? _incoisTsunami;

  /// 统一事件列表（新统一管道）
  final List<UnifiedQuakeData> _unifiedEvents = [];

  /// 统一地图事件快照的变更序号。
  ///
  /// 地图层不能只依赖事件对象的 hashCode 判断快照是否变化；事件被删除
  /// 后必须明确触发一次图层重建，避免 CustomPaint 保留已经移除的标记。
  int _unifiedMapRevision = 0;

  final List<EewEventGroup> _eewHistory = [];
  int _eewHistoryRevision = 0;
  int _flatHistorySignature = 0;
  static const String _eewHistoryPreferenceKey = 'unified_eew_history';
  static const int _maxPersistedEewHistoryGroups = 15;
  Timer? _eewHistoryPersistTimer;
  Future<void> _eewHistoryPersistChain = Future<void>.value();

  /// Domain-scoped listenables: status / weather / typhoon / history updates
  /// bump these instead of [notifyListeners], so unrelated UI stays idle.
  final ValueNotifier<int> sourceStatusListenable = ValueNotifier(0);
  final ValueNotifier<int> weatherListenable = ValueNotifier(0);
  final ValueNotifier<int> typhoonListenable = ValueNotifier(0);
  final ValueNotifier<int> historyListenable = ValueNotifier(0);

  List<EewEventGroup> get eewHistory => List.unmodifiable(_eewHistory);
  int get eewHistoryRevision => _eewHistoryRevision;

  void _notifySourceStatusSlice() {
    if (_disposed) return;
    sourceStatusListenable.value++;
  }

  void _notifyWeatherSlice() {
    if (_disposed) return;
    weatherListenable.value++;
  }

  void _notifyTyphoonSlice() {
    if (_disposed) return;
    _typhoonUpdateRevision++;
    typhoonListenable.value = _typhoonUpdateRevision;
  }

  void _notifyHistorySlice() {
    if (_disposed) return;
    historyListenable.value++;
  }

  /// 统一事件列表当前索引
  int _currentUnifiedIndex = 0;

  /// 统一事件流订阅列表
  final List<StreamSubscription> _unifiedSubscriptions = [];
  final Set<String> _foregroundCmtInitialized = <String>{};
  StreamSubscription<QuakeMessage>? _eventBusSubscription;
  StreamSubscription<SourceStatusUpdate>? _sourceStatusSubscription;
  bool _disposed = false;

  /// EEW 连续更新时，状态逐报写入，但 UI 最多约每 120ms 发布一次最新快照。
  /// 首报、警报升级、最终报和取消报会绕过合并立即发布。
  static const Duration _unifiedUiPublishInterval = Duration(milliseconds: 120);
  Timer? _unifiedUiPublishTimer;
  DateTime? _lastUnifiedUiPublishedAt;

  /// 同一 EEW 的普通更新报在短窗口内只对外派发最后一报的副作用。
  /// 数据状态与历史仍逐报保留；这里只合并音效/TTS/系统通知等外部动作。
  static const Duration _unifiedUpdateEffectDelay = Duration(milliseconds: 300);
  final Map<String, Timer> _unifiedUpdateEffectTimers = {};
  final Map<String, UnifiedQuakeData> _pendingUnifiedUpdateEffects = {};

  /// 统一事件自动轮播定时器
  Timer? _unifiedCarouselTimer;

  /// 统一 EEW 卡片的倒计时语音计时器。
  ///
  /// 仅负责语音，不发布 UI 状态，避免每秒触发统一卡片重建。
  Timer? _unifiedCountdownVoiceTimer;

  /// 每个统一 EEW 最近处理过的 S 波倒计时秒数。
  ///
  /// key 使用来源与事件 ID，防止不同来源的同名事件互相去重。
  final Map<String, int> _unifiedCountdownLastSpokenSeconds = {};

  // Keep countdown speech local: the reference's default "strongly felt"
  // thresholds are JMA shindo 3 and CSIS intensity 5 respectively.
  static const double _unifiedCountdownStrongShindoThreshold = 3.0;
  static const int _unifiedCountdownStrongCsisThreshold = 5;

  /// 统一事件每事件独立关闭定时器 (eventId → Timer)
  final Map<String, Timer> _unifiedDismissTimers = {};

  /// 已关闭的统一事件ID集合，防止重新出现
  final Set<String> _dismissedUnifiedIds = {};

  /// 已关闭时已经是正式/已核实测定的事件。
  /// 同一正式报文再次到达时不得反复覆盖关闭状态。
  final Set<String> _dismissedReviewedUnifiedIds = {};

  /// 无可靠更新时间的信息源已见事件，防止很久后的正文修正重新顶到主 UI。
  final Map<String, DateTime> _seenNoUpdateInfoEvents = {};
  static const String _seenNoUpdateInfoEventsKey = 'seen_no_update_info_events';
  static const Duration _seenNoUpdateInfoTtl = Duration(hours: 48);
  static const int _maxSeenNoUpdateInfoEvents = 500;

  /// USGS 信息事件主体内容去重缓存。
  /// key -> 最近一次看到的时间，超过 24 小时会清理，避免启动时旧/新数据混乱。
  final Map<String, DateTime> _seenUsgsInfoBodyKeys = {};
  static const String _seenUsgsInfoBodyKeysKey = 'seen_usgs_info_body_keys';

  /// EMSC 信息事件主体内容去重缓存。
  /// key -> 最近一次看到的时间，超过 24 小时会清理，避免启动时旧/新数据混乱。
  final Map<String, DateTime> _seenEmscInfoBodyKeys = {};
  static const String _seenEmscInfoBodyKeysKey = 'seen_emsc_info_body_keys';

  /// CWA 信息事件主体内容去重缓存。
  /// key -> 最近一次看到的时间，超过 24 小时会清理，避免 HTTP/FAN 双通道重复推 UI。
  final Map<String, DateTime> _seenCwaInfoBodyKeys = {};
  static const String _seenCwaInfoBodyKeysKey = 'seen_cwa_info_body_keys';

  /// 主 isolate 已实际接纳到统一 UI 的信息事件，用于 Android 后台 isolate
  /// 启动时跳过同一事件的重复首报。
  final Map<String, DateTime> _backgroundSeenUnifiedInfoEvents = {};
  static const Duration _backgroundSeenUnifiedInfoTtl = Duration(hours: 48);
  static const int _maxBackgroundSeenUnifiedInfoEvents = 1000;

  /// 主 isolate 已实际接纳的 EEW 最高报号及最近接纳时间。
  final Map<String, int> _backgroundAcceptedEewReportNums = {};
  final Map<String, DateTime> _backgroundAcceptedEewSeenAt = {};
  static const Duration _backgroundAcceptedEewTtl = Duration(hours: 24);
  static const int _maxBackgroundAcceptedEewEvents = 100;
  Timer? _backgroundSeenStatePersistTimer;
  bool _backgroundSeenStateDirty = false;

  /// 已关闭的旧管道事件ID集合，防止已关闭事件通过旧管道重新出现
  final Set<String> _dismissedLegacyIds = {};

  /// kanameishi 式 EEW 已过期事件记录: "source|eventId" → 最高 reportNum
  /// 防止已终止的旧报重新出现
  final Map<String, int> _ignoredEewIds = {};
  static const int _maxIgnoredEewIds = 10;
  final Set<String> _eewCautionAnnouncementIds = {};
  final Set<String> _eewWarnAnnouncementIds = {};
  final Map<TsunamiSource, int> _lastTsunamiStatusForSound = {};

  /// 是否正在显示信息事件
  bool get _legacyActiveQuakePipelineDisabled => true;

  bool _isShowingInfoEvent = false;

  /// 地震列表管理器
  final EqlistManager _eqlist = EqlistManager();
  Timer? _eqlistStartTimer;

  /// 扁平化的历史列表
  List<QuakeMessage> _flatHistory = [];

  /// 按数据源分组的历史记录
  Map<String, List<QuakeMessage>> get historyBySource =>
      _eqlist.getAllBuckets();

  /// 获取历史列表
  List<QuakeMessage> get historyList => _flatHistory;

  /// 震级过滤器
  double _magFilter = 0;

  /// 各信息事件源独立震级过滤器（source → 最低震级，0=不过滤）
  final Map<QuakeSourceType, double> _sourceInfoMagFilters = {
    // 未适配机构没有可靠的来源契约，首次使用时默认不接收。
    QuakeSourceType.unadapted: -1,
  };
  static const String _sourceMagFilterPrefix = 'source_mag_filter_';

  /// 信息事件地点白名单，语义与 kanameishi 的 actionWhiteList 一致。
  String _infoActionWhitelist = '';
  static const String infoActionWhitelistPreferenceKey =
      'info_action_whitelist';

  /// 是否显示旧事件更新报（默认关闭，过期信息事件不显示卡片）
  bool _showStaleInfoEvent = false;

  /// 获取是否显示旧事件更新报
  bool get showStaleInfoEvent => _showStaleInfoEvent;

  /// 设置是否显示旧事件更新报
  void setShowStaleInfoEvent(bool value) {
    _showStaleInfoEvent = value;
    notifyListeners();
  }

  /// 数据源过滤器
  Set<String> _sourceFilter = {
    'jmaEqlist',
    'cencEqlist',
    'usgsEqlist',
    'fssnEqlist',
    'kmaEqlist',
    'cwaEqlist',
    'emscEqlist',
  };

  double get magFilter => _magFilter;
  Set<String> get sourceFilter => _sourceFilter;

  /// 获取各信息事件源震级过滤器
  Map<QuakeSourceType, double> get sourceInfoMagFilters =>
      Map.unmodifiable(_sourceInfoMagFilters);

  String get infoActionWhitelist => _infoActionWhitelist;

  /// 获取支持独立震级过滤的信息事件源列表
  static List<QuakeSourceType> get infoMagFilterSources => [
    QuakeSourceType.cenc,
    QuakeSourceType.usgs,
    QuakeSourceType.cwa,
    QuakeSourceType.fssn,
    QuakeSourceType.p2p,
    QuakeSourceType.hko,
    QuakeSourceType.emsc,
    QuakeSourceType.bcsf,
    QuakeSourceType.gfz,
    QuakeSourceType.usp,
    QuakeSourceType.kma_eq,
    QuakeSourceType.ningxia,
    QuakeSourceType.guangxi,
    QuakeSourceType.shanxi,
    QuakeSourceType.beijing,
    QuakeSourceType.yunnan,
    QuakeSourceType.bmkg,
    QuakeSourceType.geonet,
    QuakeSourceType.tmd,
    QuakeSourceType.ingv,
    QuakeSourceType.nrcan,
    QuakeSourceType.mmd,
    QuakeSourceType.phivolcs,
    QuakeSourceType.sgc,
    QuakeSourceType.ga,
    QuakeSourceType.cenais,
    QuakeSourceType.unadapted,
  ];

  /// 设置指定信息事件源的震级阈值
  void setSourceInfoMagFilter(QuakeSourceType source, double threshold) {
    if (threshold == 0) {
      _sourceInfoMagFilters.remove(source);
    } else {
      _sourceInfoMagFilters[source] = threshold;
    }
    _rebuildFlat();
    _notifyHistorySlice();
  }

  void setInfoActionWhitelist(String value) {
    _infoActionWhitelist = value.trim();
    notifyListeners();
  }

  Future<void> _loadSourceInfoMagFilters() async {
    final prefs = await SharedPreferences.getInstance();
    _sourceInfoMagFilters.clear();
    _infoActionWhitelist =
        prefs.getString(infoActionWhitelistPreferenceKey)?.trim() ?? '';
    for (final source in infoMagFilterSources) {
      final key = '$_sourceMagFilterPrefix${source.name}';
      // 缺少 key 表示从未配置：未适配机构默认不接收；其他来源默认不过滤。
      if (source == QuakeSourceType.unadapted && !prefs.containsKey(key)) {
        _sourceInfoMagFilters[source] = -1;
        continue;
      }
      final threshold = prefs.getDouble(key);
      if (threshold != null && threshold != 0) {
        _sourceInfoMagFilters[source] = threshold;
      }
    }
    notifyListeners();
  }

  Future<void> setWeatherLocalOnly(bool value, {bool persist = true}) async {
    if (_weatherLocalOnly == value && !persist) {
      _rebuildWeatherLocalProfile();
      _syncChinaWeatherMode();
      _notifyWeatherSlice();
      return;
    }
    _weatherLocalOnly = value;
    // 避免模式切换后短暂显示旧来源（全局/本地）残留预警内容
    _weatherAlarm = null;
    _chinaWeatherLocalAlarm = null;
    _cmaStationWeatherAlarm = null;
    _jmaStationWeatherAlarm = null;
    _weatherAlarmExpiryTimer?.cancel();
    _weatherAlarmExpiryTimer = null;
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('weather_alarm_local_only', value);
    }
    if (_weatherLocalOnly) {
      _rebuildWeatherLocalProfile();
    }
    _syncChinaWeatherMode();
    _notifyWeatherSlice();
  }

  Future<void> setWeatherLocalAdminLevel(
    String level, {
    bool persist = true,
  }) async {
    final normalized = _normalizeWeatherLocalLevel(level);
    if (_weatherLocalAdminLevel == normalized && !persist) {
      _syncChinaWeatherMode();
      _notifyWeatherSlice();
      return;
    }
    _weatherLocalAdminLevel = normalized;
    // 层级切换后先清空旧告警，等待新层级结果回填
    if (_weatherLocalOnly) {
      _weatherAlarm = null;
      _chinaWeatherLocalAlarm = null;
      _cmaStationWeatherAlarm = null;
      _jmaStationWeatherAlarm = null;
      _weatherAlarmExpiryTimer?.cancel();
      _weatherAlarmExpiryTimer = null;
    }
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weather_alarm_local_level', normalized);
    }
    _syncChinaWeatherMode();
    _notifyWeatherSlice();
  }

  Future<void> _loadWeatherLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _weatherLocalOnly = prefs.getBool('weather_alarm_local_only') ?? true;
    _weatherLocalAdminLevel = _normalizeWeatherLocalLevel(
      prefs.getString('weather_alarm_local_level') ?? 'county',
    );
    _weatherFallbackLat = prefs.getDouble('map_view_lat');
    _weatherFallbackLng = prefs.getDouble('map_view_lng');
    _rebuildWeatherLocalProfile();
    _syncChinaWeatherMode();
    _notifyWeatherSlice();
  }

  void _rebuildWeatherLocalProfile() {
    final anchor = _localAnchor();
    final province = _inferProvince(anchor.$1, anchor.$2);
    _weatherLocalKeywords = _keywordsForProvince(province);
  }

  void _onUserLocationForWeather() {
    _rebuildWeatherLocalProfile();
    _syncChinaWeatherMode();
  }

  void syncCmaStationWeatherAlarms(CmaLocalWeatherObservation? observation) {
    if (!_weatherLocalOnly) {
      _cmaStationWeatherAlarm = null;
      _reconcileLocalWeatherAlarm();
      return;
    }
    final anchor = _localAnchor();
    if (!LocalWeatherRegion.usesChina(anchor.$1, anchor.$2)) {
      _cmaStationWeatherAlarm = null;
      _reconcileLocalWeatherAlarm();
      return;
    }
    _cmaStationWeatherAlarm = cmaBestWeatherAlarmForDisplay(observation);
    _reconcileLocalWeatherAlarm();
  }

  void syncJmaStationWeatherAlarms(JmaLocalWeatherObservation? observation) {
    if (!_weatherLocalOnly) {
      _jmaStationWeatherAlarm = null;
      _reconcileLocalWeatherAlarm();
      return;
    }
    final anchor = _localAnchor();
    if (!LocalWeatherRegion.usesJapan(anchor.$1, anchor.$2)) {
      _jmaStationWeatherAlarm = null;
      _reconcileLocalWeatherAlarm();
      return;
    }
    _jmaStationWeatherAlarm = jmaBestWeatherAlarmForDisplay(observation);
    _reconcileLocalWeatherAlarm();
  }

  void _reconcileLocalWeatherAlarm() {
    if (!_weatherLocalOnly) return;

    _weatherAlarmExpiryTimer?.cancel();
    _weatherAlarmExpiryTimer = null;

    final candidates = <WeatherAlarm>[
      if (_chinaWeatherLocalAlarm != null &&
          !_chinaWeatherLocalAlarm!.isExpired())
        _chinaWeatherLocalAlarm!,
      if (_cmaStationWeatherAlarm != null &&
          !_cmaStationWeatherAlarm!.isExpired())
        _cmaStationWeatherAlarm!,
      if (_jmaStationWeatherAlarm != null &&
          !_jmaStationWeatherAlarm!.isExpired())
        _jmaStationWeatherAlarm!,
    ];

    WeatherAlarm? next;
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final severityDiff = _weatherSeverityRank(b) - _weatherSeverityRank(a);
        if (severityDiff != 0) return severityDiff;
        final aTime = a.effectiveInstantUtc ?? a.receivedAtUtc;
        final bTime = b.effectiveInstantUtc ?? b.receivedAtUtc;
        return bTime.compareTo(aTime);
      });
      next = candidates.first;
    }

    _weatherAlarm = next;
    if (next != null) {
      final delay = next.validUntilUtc.difference(DateTime.now().toUtc());
      if (delay > Duration.zero) {
        final revisionKey = next.revisionKey;
        _weatherAlarmExpiryTimer = Timer(delay, () {
          if (_weatherAlarm?.revisionKey != revisionKey) return;
          _weatherAlarm = null;
          _weatherAlarmExpiryTimer = null;
          _notifyWeatherSlice();
        });
      } else {
        _weatherAlarm = null;
      }
    }

    if (_unifiedEvents.isEmpty) {
      final hadEvent = _currentEvent != null;
      _currentEvent = null;
      onAllEventsExpired?.call();
      if (hadEvent) notifyListeners();
    }
    _notifyWeatherSlice();
  }

  int _weatherSeverityRank(WeatherAlarm alarm) {
    switch (alarm.levelCode) {
      case '04':
        return 4;
      case '03':
        return 3;
      case '02':
        return 2;
      case '01':
        return 1;
      default:
        return 0;
    }
  }

  void _syncChinaWeatherMode() {
    final anchor = _localAnchor();
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _chinaWeatherService.stop();
      _chinaWeatherLocalAlarm = null;
      _reconcileLocalWeatherAlarm();
      return;
    }
    if (LocalWeatherRegion.usesJapan(anchor.$1, anchor.$2)) {
      _chinaWeatherService.stop();
      _chinaWeatherLocalAlarm = null;
      _cmaStationWeatherAlarm = null;
      _reconcileLocalWeatherAlarm();
      return;
    }

    _jmaStationWeatherAlarm = null;
    _chinaWeatherService.setLocalAnchor(anchor.$1, anchor.$2);
    _applyResolvedChinaWeatherArea(anchor.$1, anchor.$2);
    _chinaWeatherService.setProvinceKeywords(_weatherLocalKeywords);
    _chinaWeatherService.setAdminLevel(
      _toWeatherAdminLevel(_weatherLocalAdminLevel),
    );
    if (_weatherLocalOnly) {
      _chinaWeatherService.start(intervalSeconds: 90);
    } else {
      _chinaWeatherService.stop();
    }
  }

  void _applyResolvedChinaWeatherArea(double lat, double lng) {
    final cached = LocationService().resolvedAdminArea;
    if (cached != null && cached.isNotEmpty) {
      _chinaWeatherService.setResolvedAdminArea(cached);
      return;
    }

    final regions = EpicenterRegionService.instance;
    if (regions.isLoaded) {
      _chinaWeatherService.setResolvedAdminArea(
        regions.lookupChinaPlace(lat, lng),
      );
      return;
    }

    unawaited(() async {
      await regions.load();
      _chinaWeatherService.setResolvedAdminArea(
        regions.lookupChinaPlace(lat, lng),
      );
      if (_weatherLocalOnly) {
        await _chinaWeatherService.fetchNow();
      }
    }());
  }

  String _normalizeWeatherLocalLevel(String level) {
    switch (level) {
      case 'province':
      case 'city':
      case 'county':
        return level;
      default:
        return 'county';
    }
  }

  ChinaWeatherAdminLevel _toWeatherAdminLevel(String level) {
    switch (level) {
      case 'province':
        return ChinaWeatherAdminLevel.province;
      case 'city':
        return ChinaWeatherAdminLevel.city;
      case 'county':
      default:
        return ChinaWeatherAdminLevel.county;
    }
  }

  (double, double) _localAnchor() {
    final pos = LocationService().currentPosition;
    if (pos != null) return (pos.latitude, pos.longitude);
    final lat = _weatherFallbackLat ?? 29.30;
    final lng = _weatherFallbackLng ?? 120.09;
    return (lat, lng);
  }

  static const Map<String, (double, double)> _provinceCenters = {
    '北京': (39.93, 116.40),
    '天津': (39.14, 117.21),
    '河北': (38.05, 114.49),
    '山西': (37.87, 112.56),
    '内蒙古': (40.82, 111.67),
    '辽宁': (41.80, 123.38),
    '吉林': (43.88, 125.32),
    '黑龙江': (45.80, 126.53),
    '上海': (31.25, 121.49),
    '江苏': (32.06, 118.80),
    '浙江': (30.27, 120.15),
    '安徽': (31.87, 117.28),
    '福建': (26.05, 119.33),
    '江西': (28.68, 115.86),
    '山东': (36.65, 117.00),
    '河南': (34.76, 113.65),
    '湖北': (30.58, 114.30),
    '湖南': (28.21, 112.94),
    '广东': (23.12, 113.31),
    '广西': (22.81, 108.30),
    '海南': (20.02, 110.33),
    '重庆': (29.54, 106.53),
    '四川': (30.57, 104.07),
    '贵州': (26.63, 106.71),
    '云南': (25.04, 102.68),
    '西藏': (29.65, 91.12),
    '陕西': (34.34, 108.94),
    '甘肃': (36.06, 103.82),
    '青海': (36.62, 101.78),
    '宁夏': (38.47, 106.27),
    '新疆': (43.83, 87.63),
    '香港': (22.29, 114.19),
    '澳门': (22.19, 113.55),
    '台湾': (23.97, 120.96),
  };

  static const Map<String, List<String>> _provinceExtraKeywords = {
    '浙江': ['浙江', '浙江省', '杭州', '宁波', '温州', '金华', '义乌'],
    '江苏': ['江苏', '江苏省', '南京', '苏州', '无锡', '常州'],
    '上海': ['上海', '沪'],
    '安徽': ['安徽', '安徽省', '合肥'],
    '福建': ['福建', '福建省', '福州', '厦门'],
    '江西': ['江西', '江西省', '南昌'],
    '广东': ['广东', '广东省', '广州', '深圳'],
  };

  String? _inferProvince(double lat, double lng) {
    String? best;
    double bestDist = double.infinity;
    for (final entry in _provinceCenters.entries) {
      final d = QuakeCalculator.haversineDistance(
        lat,
        lng,
        entry.value.$1,
        entry.value.$2,
      );
      if (d < bestDist) {
        bestDist = d;
        best = entry.key;
      }
    }
    if (bestDist > 700) return null;
    return best;
  }

  List<String> _keywordsForProvince(String? province) {
    if (province == null || province.isEmpty) return const [];
    final base = <String>[province, '${province}省', '${province}市'];
    final extra = _provinceExtraKeywords[province] ?? const [];
    return [...base, ...extra];
  }

  /// 设置震级过滤器
  void setMagFilter(double v) {
    _magFilter = v;
    _rebuildFlat();
    _notifyHistorySlice();
  }

  /// 切换数据源过滤器
  void toggleSource(String key) {
    if (_sourceFilter.contains(key))
      _sourceFilter.remove(key);
    else
      _sourceFilter.add(key);
    _rebuildFlat();
    _notifyHistorySlice();
  }

  /// 更新数据源状态
  ///
  /// 用于手动更新特定数据源的连接状态。
  /// 通常在数据源服务初始化或状态变化时调用。
  ///
  /// 参数：
  /// - [sourceName]: 数据源名称
  /// - [status]: 新的连接状态
  void updateSourceStatus(String sourceName, SourceStatus status) {
    if (_sourceStatuses[sourceName] == status) return;
    _sourceStatuses[sourceName] = status;
    _notifySourceStatusSlice();
  }

  /// 数据源状态映射
  ///
  /// 记录各数据源的当前连接状态。
  final Map<String, SourceStatus> _sourceStatuses = {
    'Wolfx': SourceStatus.disconnected,
    'FAN': SourceStatus.disconnected,
    'P2P': SourceStatus.disconnected,
    'NIED': SourceStatus.disconnected,
    'KMA': SourceStatus.disconnected,
    'CENC': SourceStatus.disconnected,
    'HTTP': SourceStatus.disconnected,
    'CMT': SourceStatus.disconnected,
    'S-net': SourceStatus.disconnected,
    'TREM': SourceStatus.disconnected,
    'SeisJS': SourceStatus.disconnected,
    'P-Alert': SourceStatus.disconnected,
  };

  Map<String, SourceStatus> get sourceStatuses => _sourceStatuses;
  QuakeMessage? get currentEvent =>
      _legacyActiveQuakePipelineDisabled ? null : _currentEvent;
  double get currentDistance =>
      _legacyActiveQuakePipelineDisabled ? 0.0 : _currentDistance;
  double get estimatedIntensity =>
      _legacyActiveQuakePipelineDisabled ? 0.0 : _estimatedIntensity;

  /// 当前事件的 S 波到达倒计时（秒），<= 0 表示已到达或不可用
  int get sCountdown => _legacyActiveQuakePipelineDisabled ? -1 : _sCountdown;

  /// 当前事件的 P 波到达倒计时（秒），<= 0 表示已到达或不可用
  int get pCountdown => _legacyActiveQuakePipelineDisabled ? -1 : _pCountdown;

  WeatherAlarm? get weatherAlarm => _weatherAlarm;
  bool get weatherLocalOnly => _weatherLocalOnly;
  String? get weatherDetectedProvince => _chinaWeatherService.detectedProvince;
  String get weatherLocalAdminLevel => _weatherLocalAdminLevel;
  List<TyphoonData> get activeTyphoons => _activeTyphoons;
  int get typhoonUpdateRevision => _typhoonUpdateRevision;

  void setTyphoonLayerEnabled(bool enabled) {
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      final changed = _typhoonLayerEnabled != enabled;
      _typhoonLayerEnabled = enabled;
      if (!enabled && _activeTyphoons.isNotEmpty) {
        _activeTyphoons = const [];
        _notifyTyphoonSlice();
      } else if (changed) {
        _notifyTyphoonSlice();
      }
      return;
    }
    if (_typhoonLayerEnabled == enabled) {
      if (enabled) {
        if (!_typhoonService.isRunning) {
          _typhoonService.start();
        } else {
          _typhoonService.fetchNow();
        }
      }
      return;
    }
    _typhoonLayerEnabled = enabled;
    if (enabled) {
      _typhoonService.start();
      return;
    }
    _typhoonService.stop(clearState: true);
    if (_activeTyphoons.isNotEmpty) {
      _activeTyphoons = const [];
      _notifyTyphoonSlice();
    }
  }

  void ingestExternalTyphoons(List<TyphoonData> typhoons) {
    if (!_typhoonLayerEnabled) return;
    _acceptTyphoonSnapshot(typhoons);
  }

  void _acceptTyphoonSnapshot(List<TyphoonData> typhoons) {
    final nextSignature = Object.hashAll(
      typhoons.map((item) => item.signature),
    );
    final previousSignature = Object.hashAll(
      _activeTyphoons.map((item) => item.signature),
    );
    if (nextSignature == previousSignature &&
        typhoons.length == _activeTyphoons.length) {
      return;
    }
    _activeTyphoons = List.unmodifiable(typhoons);
    if (!BackgroundService().isInBackground) {
      SoundEffectService().play(
        'typhoonUpdate',
        cooldown: const Duration(seconds: 5),
      );
    }
    _notifyTyphoonSlice();
  }

  TsunamiMessage? get jmaTsunami => _jmaTsunami;
  TsunamiMessage? get nmefcTsunami => _nmefcTsunami;
  TsunamiMessage? get ptwcTsunami => _ptwcTsunami;
  TsunamiMessage? get ntwcTsunami => _ntwcTsunami;
  TsunamiMessage? get incoisTsunami => _incoisTsunami;

  List<ActiveWarning> get activeWarnings => _legacyActiveQuakePipelineDisabled
      ? const <ActiveWarning>[]
      : List.unmodifiable(_activeWarnings);
  int get currentWarningIndex =>
      _legacyActiveQuakePipelineDisabled ? 0 : _currentWarningIndex;
  int get activeWarningCount =>
      _legacyActiveQuakePipelineDisabled ? 0 : _activeWarnings.length;

  List<ActiveInfoEvent> get activeInfoEvents =>
      _legacyActiveQuakePipelineDisabled
      ? const <ActiveInfoEvent>[]
      : List.unmodifiable(_activeInfoEvents);
  CencIrData? get cencIrData {
    final realtime = _realtimeCencIrData;
    if (realtime != null) {
      if (realtime.source != CencIrDataSource.nowQuake ||
          _hasUnifiedCencIrEvent(realtime)) {
        return realtime;
      }
    }
    return _isManualCencIrActive ? _manualCencIrData : null;
  }

  CencIrData? get realtimeCencIrData => _realtimeCencIrData;
  CencIrData? get manualCencIrData =>
      _isManualCencIrActive ? _manualCencIrData : null;
  bool get isManualCencIrActive => manualCencIrData != null;
  List<Map<String, dynamic>> get cencIrList => List.unmodifiable(_cencIrList);
  int get activeInfoEventCount =>
      _legacyActiveQuakePipelineDisabled ? 0 : _activeInfoEvents.length;
  bool get isShowingInfoEvent =>
      _legacyActiveQuakePipelineDisabled ? false : _isShowingInfoEvent;
  bool get isShowingTempInfo =>
      _legacyActiveQuakePipelineDisabled ? false : _isShowingTempInfo;
  int get totalDisplayCount => _legacyActiveQuakePipelineDisabled
      ? 0
      : _activeWarnings.length + _activeInfoEvents.length;

  List<UnifiedQuakeData> get unifiedEvents => List.unmodifiable(_unifiedEvents);

  int get unifiedMapRevision => _unifiedMapRevision;
  int get currentUnifiedIndex => _currentUnifiedIndex;
  int get unifiedEventCount => _unifiedEvents.length;
  UnifiedQuakeData? get currentUnifiedEvent =>
      _unifiedEvents.isNotEmpty ? _unifiedEvents[_currentUnifiedIndex] : null;

  List<QuakeMessage> get unifiedMapEvents =>
      _unifiedEvents.map(_unifiedToMapMessage).toList();

  /// 将 JMA VXSE62 接入统一事件管道，保留完整原始 bulletin。
  void acceptJmaLpgm(JmaLpgmBulletin bulletin) {
    if (bulletin.isCanceled || !bulletin.isActive()) {
      clearJmaLpgm(bulletin.eventId);
      return;
    }
    _handleUnifiedEvent(_jmaLpgmToUnified(bulletin));
  }

  /// 清理指定 JMA 长周期事件，不影响普通 EEW、情报和波圈。
  void clearJmaLpgm(String eventId) {
    final key = eventId.trim();
    for (var index = _unifiedEvents.length - 1; index >= 0; index--) {
      final event = _unifiedEvents[index];
      if (!event.isJmaLpgm || (key.isNotEmpty && event.eventId != key)) {
        continue;
      }
      _removeUnifiedEvent(index);
    }
  }

  UnifiedQuakeData _jmaLpgmToUnified(JmaLpgmBulletin bulletin) {
    return UnifiedQuakeData(
      source: 'jmaLpgm',
      origin: 7,
      eventId: bulletin.eventId,
      isEew: false,
      timeZone: 9,
      titleText: '长周期地震动',
      reportNumText: bulletin.serial > 0 ? '第${bulletin.serial}报' : '',
      useShindo: false,
      maxIntensity: bulletin.maxLgInt.toString(),
      className: switch (bulletin.maxLgInt) {
        1 => 'yellow',
        2 => 'orange',
        3 => 'red',
        4 => 'purple',
        _ => 'gray',
      },
      hypocenter: bulletin.hypocenter,
      originTime: bulletin.originTime,
      reportTime: bulletin.reportTime,
      magnitude: bulletin.magnitude ?? -1,
      depth: bulletin.depthKm ?? -1,
      depthText: bulletin.depthKm == null
          ? ''
          : '深度 ${bulletin.depthKm!.toStringAsFixed(0)}km',
      lat: bulletin.latitude,
      lng: bulletin.longitude,
      apiTypeLabel: 'JMA · VXSE62',
      isJmaLpgm: true,
      jmaLpgmBulletin: bulletin,
    );
  }

  /// 是否应该显示气象警报UI
  /// 仅当预警和信息事件都为空时才显示
  bool get shouldShowWeatherAlarm =>
      _unifiedEvents.isEmpty && _weatherAlarm != null;

  void _acceptRemoteWeatherAlarm(WeatherAlarm alarm) {
    if (_weatherLocalOnly || alarm.isExpired()) return;
    final current = _weatherAlarm;
    if (current != null &&
        current.source != WeatherAlarmSource.chinaWeatherLocal &&
        current.source != WeatherAlarmSource.jmaLocal) {
      if (current.revisionKey == alarm.revisionKey) return;
      final currentTime = current.effectiveInstantUtc ?? current.receivedAtUtc;
      final incomingTime = alarm.effectiveInstantUtc ?? alarm.receivedAtUtc;
      if (incomingTime.isBefore(currentTime)) return;
    }

    _weatherAlarm = alarm;
    _weatherAlarmExpiryTimer?.cancel();
    final delay = alarm.validUntilUtc.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      _weatherAlarm = null;
    } else {
      final revisionKey = alarm.revisionKey;
      _weatherAlarmExpiryTimer = Timer(delay, () {
        if (_weatherAlarm?.revisionKey != revisionKey) return;
        _weatherAlarm = null;
        _weatherAlarmExpiryTimer = null;
        _notifyWeatherSlice();
      });
    }
    if (_unifiedEvents.isEmpty) {
      final hadEvent = _currentEvent != null;
      _currentEvent = null;
      onAllEventsExpired?.call();
      if (hadEvent) notifyListeners();
    }
    _notifyWeatherSlice();
  }

  @visibleForTesting
  void acceptRemoteWeatherAlarmForTest(WeatherAlarm alarm) {
    _weatherLocalOnly = false;
    _acceptRemoteWeatherAlarm(alarm);
  }

  void ingestExternalChinaWeatherAlarm(WeatherAlarm? alarm) {
    if (!_weatherLocalOnly) return;
    _chinaWeatherLocalAlarm = alarm;
    _reconcileLocalWeatherAlarm();
  }

  /// 构造函数
  ///
  /// 初始化事件监听和数据源状态订阅。
  QuakeProvider() {
    _loadWeatherLocalPrefs();
    LocationService().positionListenable.addListener(_onUserLocationForWeather);
    _startUnifiedEventsAfterSourcePrefs();

    _eqlist.onAnyUpdated = _rebuildFlat;
    _eqlist.onUsgsCurrentUpdated = _handleOfficialUsgsCurrent;
    _eqlist.onEmscCurrentUpdated = _handleOfficialEmscCurrent;
    _eqlist.onCwaCurrentUpdated = _handleOfficialCwaCurrent;
    _eqlist.onHttpStatusChanged = (connected) {
      updateSourceStatus(
        'HTTP',
        connected ? SourceStatus.connected : SourceStatus.error,
      );
    };
    _eqlist.onCmtStatusChanged = (connected) {
      updateSourceStatus(
        'CMT',
        connected ? SourceStatus.connected : SourceStatus.error,
      );
    };
    _eqlist.cencCmt.onListUpdated = _handleCencCmtList;
    _eqlist.usgsCmt.onListUpdated = _handleUsgsCmtList;
    _eqlist.jmaCmt.onListUpdated = _handleJmaCmtList;
    _eqlist.fnetCmt.onListUpdated = _handleFnetCmtList;
    _eqlist.hinetAquaCmt.onListUpdated = _handleHinetAquaCmtList;
    _scheduleEqlistStart();
    _rebuildFlat();

    _eventBusSubscription = QuakeEventBus().onNewEvent.listen(
      _handleNewQuake,
      onError: (e, stack) {
        final lines = stack.toString().split('\n');
        final short = lines.take(5).join('\n');
        print('EventBus error: $e\n$short');
      },
    );
    _sourceStatusSubscription = SourceManager().onStatusUpdate.listen((update) {
      final changed = _sourceStatuses[update.sourceName] != update.status;
      if (changed) {
        _sourceStatuses[update.sourceName] = update.status;
      }
      if (update.sourceName == 'NowQuake') {
        _syncFanCencIrFallbackRequests();
        _rebuildCencIrList();
      }
      if (changed) {
        _notifySourceStatusSlice();
      }
    });

    _unifiedSubscriptions.add(
      BackgroundService().onForegroundSourceStatus.listen((update) {
        final changed = _sourceStatuses[update.sourceName] != update.status;
        if (!changed) return;
        _sourceStatuses[update.sourceName] = update.status;
        _notifySourceStatusSlice();
      }),
    );

    final fanService = SourceManager().getSource<FanService>();
    if (fanService != null) {
      fanService.onCencIrData = (data) {
        final id = _cencIrDataId(data);
        final wasManualDetail = _fanCencIrDetailFallbackIds.remove(id);
        if (wasManualDetail) {
          if (_pendingManualCencIrId == id) {
            _pendingManualCencIrId = null;
            _updateManualCencIrData(data);
          }
          return;
        }
        if (_shouldUseNowQuakeRealtime) return;
        _updateRealtimeCencIrData(data);
      };
      fanService.onCencIrListUpdated = (list) {
        _fanCencIrList = _tagCencIrList(list, 'fan');
        _rebuildCencIrList();
      };
      fanService.onFssnListUpdated = (items) {
        _eqlist.updateFssnList(items);
      };
      fanService.onCencListUpdated = (items) {
        _eqlist.updateCencList(items);
      };
      fanService.onCwaListUpdated = (items) {
        _eqlist.updateCwaList(items);
      };
      fanService.onWeatherAlarm = (alarm) {
        _acceptRemoteWeatherAlarm(alarm);
      };
      fanService.onTyphoonUpdate = () {
        _notifyTyphoonSlice();
        if (_typhoonLayerEnabled) {
          _typhoonService.fetchNow();
        }
      };
    }

    final whewsService = SourceManager().getSource<WhewsService>();
    if (whewsService != null) {
      _unifiedSubscriptions.add(
        whewsService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
      whewsService.onWeatherAlarm = (alarm) {
        _acceptRemoteWeatherAlarm(alarm);
      };
      _unifiedSubscriptions.add(
        whewsService.onTsunamiEvent.listen(_handleTsunamiEvent),
      );
    }

    final nowQuakeCencIr = SourceManager()
        .getSource<NowQuakeCencIntensityService>();
    if (nowQuakeCencIr != null) {
      // CENC 实时图层依赖统一事件是否被接纳。这里必须在数据源启动前
      // 建立订阅，不能等待其它来源的异步偏好加载完成。
      _unifiedSubscriptions.add(
        nowQuakeCencIr.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
      nowQuakeCencIr.onCencIrData = (data) {
        if (!SourceManager().isSourceEnabled('NowQuake')) return;
        _updateRealtimeCencIrData(data, requireUnifiedEvent: true);
      };
      nowQuakeCencIr.onCencIrListUpdated = (list) {
        _nowQuakeCencIrList = _tagCencIrList(list, 'nowquake');
        _syncFanCencIrFallbackRequests();
        _rebuildCencIrList();
      };
      nowQuakeCencIr.onListAvailabilityChanged = _syncFanCencIrFallbackRequests;
    }

    _chinaWeatherService.onLocalAlarmChanged = (alarm) {
      if (!_weatherLocalOnly) return;
      _chinaWeatherLocalAlarm = alarm;
      _reconcileLocalWeatherAlarm();
    };

    _typhoonService.onActiveTyphoonsChanged = (typhoons) {
      if (!_typhoonLayerEnabled) return;
      _acceptTyphoonSnapshot(typhoons);
    };

    _unifiedSubscriptions.add(
      BackgroundService().onForegroundAuxData.listen((payload) {
        if (payload['kind'] == 'chinaWeatherAlarm') {
          final rawAlarm = payload['alarm'];
          ingestExternalChinaWeatherAlarm(
            rawAlarm is Map
                ? WeatherAlarm.fromMap(Map<dynamic, dynamic>.from(rawAlarm))
                : null,
          );
          return;
        }
        if (payload['kind'] != 'typhoon') return;
        final raw = payload['items'];
        if (raw is! List) return;
        final items = raw
            .whereType<Map>()
            .map(TyphoonData.fromMap)
            .whereType<TyphoonData>()
            .toList(growable: false);
        ingestExternalTyphoons(items);
      }),
    );
    BackgroundService().connectionHostingNotifier.addListener(
      _syncChinaWeatherMode,
    );
  }

  void _startUnifiedEventsAfterSourcePrefs() {
    Future.wait([
      _loadSourceInfoMagFilters(),
      _loadSeenNoUpdateInfoEvents(),
      _loadSeenUsgsInfoBodyKeys(),
      _loadSeenEmscInfoBodyKeys(),
      _loadSeenCwaInfoBodyKeys(),
      _loadBackgroundSeenState(),
      _loadEewHistory(),
      _loadInitialDatabaseHistory(),
    ]).whenComplete(_subscribeUnifiedEvents);
  }

  Future<void> _loadInitialDatabaseHistory() async {
    if (kIsWeb) return;
    try {
      final cachedQuakes = await DatabaseHelper().getHistory(limit: 50);
      if (_disposed || cachedQuakes.isEmpty) return;
      // 若当前内存列表为空，先用本地已有历史记录极速铺满左侧列表，实现 0.05 秒零白屏秒开
      if (_flatHistory.isEmpty) {
        _flatHistory = cachedQuakes;
        _notifyHistorySlice();
      }
    } catch (e) {
      debugPrint('QuakeProvider: load initial database history failed: $e');
    }
  }

  Future<void> _loadEewHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_eewHistoryPreferenceKey)?.trim() ?? '';
    if (encoded.isEmpty) return;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return;
      final restored = <EewEventGroup>[];
      for (final value in decoded) {
        if (value is! Map) continue;
        try {
          restored.add(EewEventGroup.fromMap(value));
        } on Object {
          // Ignore one malformed group without discarding the other records.
        }
      }
      _eewHistory
        ..clear()
        ..addAll(restored.take(_maxPersistedEewHistoryGroups));
      if (_eewHistory.isNotEmpty) {
        _eewHistoryRevision++;
        _notifyHistorySlice();
      }
    } on FormatException catch (error) {
      debugPrint('QuakeProvider: EEW history restore skipped: $error');
    } on Object catch (error) {
      debugPrint('QuakeProvider: EEW history restore failed: $error');
    }
  }

  void _schedulePersistEewHistory() {
    _eewHistoryPersistTimer?.cancel();
    _eewHistoryPersistTimer = Timer(const Duration(milliseconds: 250), () {
      _eewHistoryPersistTimer = null;
      _queuePersistEewHistory();
    });
  }

  void _queuePersistEewHistory() {
    final snapshot = _eewHistory
        .take(_maxPersistedEewHistoryGroups)
        .map((group) => group.toMap())
        .toList(growable: false);
    _eewHistoryPersistChain = _eewHistoryPersistChain.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_eewHistoryPreferenceKey, jsonEncode(snapshot));
    });
    unawaited(_eewHistoryPersistChain);
  }

  void _scheduleEqlistStart() {
    _eqlistStartTimer?.cancel();
    _eqlistStartTimer = Timer(const Duration(seconds: 4), () async {
      _eqlistStartTimer = null;
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _eqlist.start(
        jmaHttpEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService,
        usgsHttpEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService,
        emscHttpEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService,
        cencHttpEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService,
        cwaHttpEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService,
        cencCmtEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService &&
            (prefs.getBool('api_source_cenc_cmt_enabled') ?? true),
        usgsCmtEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService &&
            (prefs.getBool('api_source_usgs_cmt_enabled') ?? true),
        jmaCmtEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService &&
            (prefs.getBool('api_source_jma_cmt_enabled') ?? true),
        fnetCmtEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService &&
            (prefs.getBool('api_source_fnet_cmt_enabled') ?? true),
        hinetAquaCmtEnabled:
            !BackgroundService().isAndroidConnectionHostedByForegroundService &&
            (prefs.getBool('api_source_hinet_aqua_cmt_enabled') ?? true),
      );
    });
  }

  void _subscribeUnifiedEvents() {
    if (_disposed) return;

    final foregroundEvents = BackgroundService().onForegroundUnifiedEvent
        .listen((event) => _handleUnifiedEvent(event, alreadyAccepted: true));
    final foregroundTsunami = BackgroundService().onForegroundTsunamiEvent
        .listen(_handleTsunamiEvent);
    _unifiedSubscriptions.add(foregroundEvents);
    _unifiedSubscriptions.add(foregroundTsunami);
    _unifiedSubscriptions.add(
      BackgroundService().onForegroundQuakeEvent.listen(_handleNewQuake),
    );
    _unifiedSubscriptions.add(
      BackgroundService().onForegroundSourceList.listen(
        _handleForegroundSourceList,
      ),
    );
    _unifiedSubscriptions.add(
      BackgroundService().onForegroundCencIrData.listen((data) {
        _updateRealtimeCencIrData(
          data,
          requireUnifiedEvent: data.source == CencIrDataSource.nowQuake,
        );
      }),
    );
    _unifiedSubscriptions.add(
      BackgroundService().onForegroundWeatherAlarm.listen(
        _acceptRemoteWeatherAlarm,
      ),
    );
    _unifiedSubscriptions.add(
      BackgroundService().onForegroundCmtList.listen(_handleForegroundCmtList),
    );

    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      return;
    }

    final wolfxService = SourceManager().getSource<WolfxService>();
    if (wolfxService != null) {
      _unifiedSubscriptions.add(
        wolfxService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
      wolfxService.onJmaEqlistUpdated = (items) {
        _eqlist.updateJmaList(items);
      };
    }

    final fanService = SourceManager().getSource<FanService>();
    if (fanService != null) {
      _unifiedSubscriptions.add(
        fanService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    final p2pService = SourceManager().getSource<P2PQuakeService>();
    if (p2pService != null) {
      _unifiedSubscriptions.add(
        p2pService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    final mockService = SourceManager().getSource<MockInputService>();
    if (mockService != null) {
      _unifiedSubscriptions.add(
        mockService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    final globalQuakeService = SourceManager().getSource<GlobalQuakeService>();
    if (globalQuakeService != null) {
      _unifiedSubscriptions.add(
        globalQuakeService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    _subscribeTsunamiEvents();
  }

  void _handleForegroundCmtList(Map<String, dynamic> payload) {
    final source = payload['source']?.toString();
    final rawItems = payload['items'];
    if (source == null || rawItems is! List) return;
    final items = rawItems
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (items.isEmpty) return;
    final first = _foregroundCmtInitialized.add(source);
    switch (source) {
      case 'cencCmt':
        _handleLatestCmtCandidate(
          source: source,
          items: items,
          isFirstLoad: first,
        );
      case 'usgsCmt':
        _handleLatestCmtCandidate(
          source: source,
          items: items,
          isFirstLoad: first,
        );
      case 'jmaCmt':
        _handleLatestCmtCandidate(
          source: source,
          items: items,
          isFirstLoad: first,
        );
      case 'fnetCmt':
        _handleLatestCmtCandidate(
          source: source,
          items: items,
          isFirstLoad: first,
        );
      case 'hinetAquaCmt':
        _handleLatestCmtCandidate(
          source: source,
          items: items,
          isFirstLoad: first,
        );
    }
  }

  void _handleOfficialUsgsCurrent(Map<String, dynamic> data) {
    final event = QuakeEventAdapter.convert('usgsEqlist', data, 0);
    if (event != null) _handleUnifiedEvent(event);
  }

  void _handleOfficialEmscCurrent(Map<String, dynamic> data) {
    final event = QuakeEventAdapter.convert('emsc', data, 0);
    if (event != null) _handleUnifiedEvent(event);
  }

  void _handleOfficialCwaCurrent(Map<String, dynamic> data) {
    final event = QuakeEventAdapter.convert('cwaEqlist', data, 0);
    if (event != null) _handleUnifiedEvent(event);
  }

  void _handleForegroundSourceList(Map<String, dynamic> payload) {
    final source = payload['source']?.toString();
    final rawItems = payload['items'];
    if (source == null || rawItems is! List) return;
    final items = <QuakeMessage>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      try {
        items.add(QuakeMessage.fromMap(Map<String, dynamic>.from(raw)));
      } catch (_) {
        continue;
      }
    }
    switch (source) {
      case 'usgs':
        _eqlist.updateUsgsList(items);
        break;
      case 'emsc':
        _eqlist.updateEmscList(items);
        break;
      case 'cwa':
        _eqlist.updateCwaList(items);
        break;
      case 'jma':
        _eqlist.updateJmaList(items);
        break;
      case 'fssn':
        _eqlist.updateFssnList(items);
        break;
      case 'cenc':
        _eqlist.updateCencList(items);
        break;
    }
  }

  /// 处理 CENC CMT 列表更新
  ///
  /// 首次加载只填充 eqlist 桶（不推送主 UI），后续加载增量推送新/变化事件
  /// 到主统一 UI。自动/人工复核合并由 [CencCmtService] 完成。
  void _handleCencCmtList(List<Map<String, dynamic>> items) {
    _handleLatestCmtCandidate(
      source: 'cencCmt',
      items: items,
      isFirstLoad: !_eqlist.cencCmt.initialized,
    );
  }

  /// 处理 USGS CMT 列表更新
  ///
  /// 首次加载只填充 eqlist 桶（不推送主 UI），后续加载增量推送新/变化事件
  /// 到主统一 UI。reviewed/automatic 状态由 [UsgsCmtService] 提取。
  void _handleUsgsCmtList(List<Map<String, dynamic>> items) {
    _handleLatestCmtCandidate(
      source: 'usgsCmt',
      items: items,
      isFirstLoad: !_eqlist.usgsCmt.initialized,
    );
  }

  void _handleJmaCmtList(List<Map<String, dynamic>> items) {
    _handleLatestCmtCandidate(
      source: 'jmaCmt',
      items: items,
      isFirstLoad: !_eqlist.jmaCmt.initialized,
    );
  }

  void _handleFnetCmtList(List<Map<String, dynamic>> items) {
    _handleLatestCmtCandidate(
      source: 'fnetCmt',
      items: items,
      isFirstLoad: !_eqlist.fnetCmt.initialized,
    );
  }

  void _handleHinetAquaCmtList(List<Map<String, dynamic>> items) {
    _handleLatestCmtCandidate(
      source: 'hinetAquaCmt',
      items: items,
      isFirstLoad: !_eqlist.hinetAquaCmt.initialized,
    );
  }

  /// CMT 目录会返回一批历史解；同源当前球只允许最新发震时刻进入。
  void _handleLatestCmtCandidate({
    required String source,
    required List<Map<String, dynamic>> items,
    required bool isFirstLoad,
  }) {
    final event = _latestCmtCandidate(source, items);
    if (event == null) return;
    if (isFirstLoad) {
      final bucket = _unifiedListBucket(event);
      if (bucket != null) {
        _eqlist.upsertBucketItem(bucket, _unifiedToListMessage(event));
      }
      return;
    }
    _handleUnifiedEvent(event);
  }

  static UnifiedQuakeData? _latestCmtCandidate(
    String source,
    List<Map<String, dynamic>> items,
  ) {
    final candidates =
        items
            .map((item) => QuakeEventAdapter.convert(source, item, 0))
            .whereType<UnifiedQuakeData>()
            .toList()
          ..sort((a, b) {
            final aTime = a.originTime == null
                ? -1
                : QuakeTime.unifiedInstantUtc(a).millisecondsSinceEpoch;
            final bTime = b.originTime == null
                ? -1
                : QuakeTime.unifiedInstantUtc(b).millisecondsSinceEpoch;
            return bTime.compareTo(aTime);
          });
    return candidates.isEmpty ? null : candidates.first;
  }

  @visibleForTesting
  static UnifiedQuakeData? latestCmtCandidateForTest(
    String source,
    List<Map<String, dynamic>> items,
  ) => _latestCmtCandidate(source, items);

  void _subscribeTsunamiEvents() {
    final p2pService = SourceManager().getSource<P2PQuakeService>();
    if (p2pService != null) {
      _unifiedSubscriptions.add(
        p2pService.onTsunamiEvent.listen(_handleTsunamiEvent),
      );
    }

    final fanService = SourceManager().getSource<FanService>();
    if (fanService != null) {
      _unifiedSubscriptions.add(
        fanService.onTsunamiEvent.listen(_handleTsunamiEvent),
      );
    }

    final mockService = SourceManager().getSource<MockInputService>();
    if (mockService != null) {
      _unifiedSubscriptions.add(
        mockService.onTsunamiEvent.listen(_handleTsunamiEvent),
      );
    }
  }

  void _handleTsunamiEvent(TsunamiMessage tsunami) {
    final previous = _currentTsunami(tsunami.source);
    final accepted = _acceptTsunamiUpdate(previous, tsunami);
    if (accepted == null) return;

    final next = accepted.message;
    if (next.isInitialSnapshot) {
      _lastTsunamiStatusForSound[next.source] = next.status;
    } else if (accepted.shouldAlert) {
      final previousStatus = previous?.status;
      _playTsunamiSound(next);
      if (next.isActive ||
          !next.isCancellation ||
          (previous?.isActive ?? false)) {
        _speakTsunamiEvent(next, previousStatus: previousStatus);
      }
    }
    _setCurrentTsunami(next);
    notifyListeners();
  }

  TsunamiMessage? _currentTsunami(TsunamiSource source) {
    return switch (source) {
      TsunamiSource.jma => _jmaTsunami,
      TsunamiSource.nmefc => _nmefcTsunami,
      TsunamiSource.ptwc => _ptwcTsunami,
      TsunamiSource.ntwc => _ntwcTsunami,
      TsunamiSource.incois => _incoisTsunami,
    };
  }

  void _setCurrentTsunami(TsunamiMessage tsunami) {
    switch (tsunami.source) {
      case TsunamiSource.jma:
        _jmaTsunami = tsunami;
        break;
      case TsunamiSource.nmefc:
        _nmefcTsunami = tsunami;
        break;
      case TsunamiSource.ptwc:
        _ptwcTsunami = tsunami;
        break;
      case TsunamiSource.ntwc:
        _ntwcTsunami = tsunami;
        break;
      case TsunamiSource.incois:
        _incoisTsunami = tsunami;
        break;
    }
  }

  ({TsunamiMessage message, bool shouldAlert})? _acceptTsunamiUpdate(
    TsunamiMessage? previous,
    TsunamiMessage incoming,
  ) {
    if (previous == null) {
      return (message: incoming, shouldAlert: true);
    }

    final previousTime = previous.reportInstantUtc;
    final incomingTime = incoming.reportInstantUtc;
    if (previousTime != null && incomingTime == null) return null;
    if (previousTime != null &&
        incomingTime != null &&
        incomingTime.isBefore(previousTime)) {
      return null;
    }

    final sameReportTime =
        previousTime != null &&
        incomingTime != null &&
        incomingTime.isAtSameMomentAs(previousTime);
    if (!sameReportTime) {
      if (previousTime == null &&
          incomingTime == null &&
          _tsunamiStateSignature(previous) ==
              _tsunamiStateSignature(incoming)) {
        return null;
      }
      final shouldAlert =
          incoming.isActive || !incoming.isCancellation || previous.isActive;
      return (message: incoming, shouldAlert: shouldAlert);
    }

    final merged = _mergeSameTsunamiReport(previous, incoming);
    if (_tsunamiStateSignature(previous) == _tsunamiStateSignature(merged)) {
      return null;
    }
    return (
      message: merged,
      shouldAlert:
          _tsunamiOperationalSignature(previous) !=
          _tsunamiOperationalSignature(merged),
    );
  }

  TsunamiMessage _mergeSameTsunamiReport(
    TsunamiMessage previous,
    TsunamiMessage incoming,
  ) {
    if (incoming.isCancellation) {
      return incoming.copyWith(id: previous.id.isNotEmpty ? previous.id : null);
    }

    final areas = incoming.areas.isEmpty && incoming.isActive
        ? previous.areas
        : incoming.areas
              .map((area) {
                final oldArea = previous.areas
                    .cast<TsunamiAreaInfo?>()
                    .firstWhere(
                      (candidate) => candidate?.name == area.name,
                      orElse: () => null,
                    );
                if (oldArea == null) return area;
                return TsunamiAreaInfo(
                  name: area.name,
                  grade: area.grade,
                  height: area.height ?? oldArea.height,
                  description: _preferText(
                    area.description,
                    oldArea.description,
                  ),
                  arrivalTime: _preferText(
                    area.arrivalTime,
                    oldArea.arrivalTime,
                  ),
                  condition: _preferText(area.condition, oldArea.condition),
                  classNameOverride:
                      area.classNameOverride ?? oldArea.classNameOverride,
                );
              })
              .toList(growable: false);

    return incoming.copyWith(
      id: previous.id.isNotEmpty ? previous.id : null,
      title: incoming.title.isNotEmpty ? incoming.title : previous.title,
      titleText: incoming.titleText.isNotEmpty
          ? incoming.titleText
          : previous.titleText,
      areas: areas,
      epicenterLat: incoming.epicenterLat ?? previous.epicenterLat,
      epicenterLng: incoming.epicenterLng ?? previous.epicenterLng,
      magnitude: incoming.magnitude ?? previous.magnitude,
      depth: incoming.depth ?? previous.depth,
      epicenterName: incoming.epicenterName.isNotEmpty
          ? incoming.epicenterName
          : previous.epicenterName,
      originTime: incoming.originTime.isNotEmpty
          ? incoming.originTime
          : previous.originTime,
      observations: incoming.observations.isNotEmpty
          ? incoming.observations
          : previous.observations,
      htmlUrl: incoming.htmlUrl.isNotEmpty
          ? incoming.htmlUrl
          : previous.htmlUrl,
      earthquakeMapUrl: incoming.earthquakeMapUrl.isNotEmpty
          ? incoming.earthquakeMapUrl
          : previous.earthquakeMapUrl,
      amplitudeMapUrl: incoming.amplitudeMapUrl.isNotEmpty
          ? incoming.amplitudeMapUrl
          : previous.amplitudeMapUrl,
      coastalMapUrl: incoming.coastalMapUrl.isNotEmpty
          ? incoming.coastalMapUrl
          : previous.coastalMapUrl,
      isInitialSnapshot:
          previous.isInitialSnapshot && incoming.isInitialSnapshot,
    );
  }

  String? _preferText(String? incoming, String? previous) {
    return incoming?.trim().isNotEmpty == true ? incoming : previous;
  }

  String _tsunamiOperationalSignature(TsunamiMessage tsunami) {
    final areas =
        tsunami.areas
            .map(
              (area) => {
                'name': area.name,
                'grade': area.grade.name,
                'height': area.height,
              },
            )
            .toList()
          ..sort(
            (a, b) => '${a['name']}|${a['grade']}'.compareTo(
              '${b['name']}|${b['grade']}',
            ),
          );
    return jsonEncode({
      'source': tsunami.source.name,
      'status': tsunami.status,
      'areas': areas,
    });
  }

  String _tsunamiStateSignature(TsunamiMessage tsunami) {
    return jsonEncode({
      'id': tsunami.id,
      'reportTime': tsunami.reportTime,
      'title': tsunami.title,
      'titleText': tsunami.titleText,
      'operational': _tsunamiOperationalSignature(tsunami),
      'areaDetails': tsunami.areas
          .map(
            (area) => {
              'name': area.name,
              'description': area.description,
              'arrivalTime': area.arrivalTime,
              'condition': area.condition,
              'className': area.className,
            },
          )
          .toList(),
      'epicenterLat': tsunami.epicenterLat,
      'epicenterLng': tsunami.epicenterLng,
      'magnitude': tsunami.magnitude,
      'depth': tsunami.depth,
      'epicenterName': tsunami.epicenterName,
      'originTime': tsunami.originTime,
      'observations': tsunami.observations
          .map(
            (observation) => {
              'stationName': observation.stationName,
              'location': observation.location,
              'latitude': observation.latitude,
              'longitude': observation.longitude,
              'time': observation.time,
              'maxWaveHeight': observation.maxWaveHeight,
            },
          )
          .toList(),
      'htmlUrl': tsunami.htmlUrl,
      'earthquakeMapUrl': tsunami.earthquakeMapUrl,
      'amplitudeMapUrl': tsunami.amplitudeMapUrl,
      'coastalMapUrl': tsunami.coastalMapUrl,
      'className': tsunami.className,
    });
  }

  @visibleForTesting
  void handleTsunamiEventForTest(TsunamiMessage tsunami) {
    _handleTsunamiEvent(tsunami);
  }

  void _playTsunamiSound(TsunamiMessage tsunami) {
    final status = tsunami.status;
    final previous = _lastTsunamiStatusForSound[tsunami.source];
    _lastTsunamiStatusForSound[tsunami.source] = status;
    if (status <= 0) {
      final isCancel =
          tsunami.title.contains('解除') || tsunami.titleText.contains('解除');
      if (isCancel && previous != null && previous > 0) {
        SoundEffectService().play('tsunami${previous}cancel');
      }
      return;
    }
    if (previous == null || previous <= 0) {
      SoundEffectService().play('tsunami${status}issue');
    } else if (status != previous) {
      final key = status <= 2
          ? 'tsunami${status}switch'
          : 'tsunami${status}update';
      SoundEffectService().play(key);
    } else {
      SoundEffectService().play('tsunami${status}update');
    }
  }

  static const Map<String, QuakeSourceType> _unifiedToQst = {
    'jmaEew': QuakeSourceType.jma_fan,
    'cwaEew': QuakeSourceType.cwa_eew,
    'ceaEew': QuakeSourceType.cea,
    'scEew': QuakeSourceType.sc_eew,
    'fjEew': QuakeSourceType.fj_eew,
    'cqEew': QuakeSourceType.cq_eew,
    'kmaEew': QuakeSourceType.kma_eew_fan,
    'sa': QuakeSourceType.sa,
    'globalQuakeEew': QuakeSourceType.usgs,
    'jmaEqlist': QuakeSourceType.jma_fan,
    'p2pJmaEqlist': QuakeSourceType.p2p,
    'cwaEqlist': QuakeSourceType.cwa,
    'cencEqlist': QuakeSourceType.cenc,
    'nowQuakeCencIr': QuakeSourceType.cencIr,
    'kmaEqlist': QuakeSourceType.kma_eq,
    'usgsEqlist': QuakeSourceType.usgs,
    'fssnEqlist': QuakeSourceType.fssn,
    'fssnCmt': QuakeSourceType.fssnCmt,
    'hko': QuakeSourceType.hko,
    'emsc': QuakeSourceType.emsc,
    'emscEqlist': QuakeSourceType.emsc,
    'bcsf': QuakeSourceType.bcsf,
    'gfz': QuakeSourceType.gfz,
    'usp': QuakeSourceType.usp,
    'geonet': QuakeSourceType.geonet,
    'ningxia': QuakeSourceType.ningxia,
    'guangxi': QuakeSourceType.guangxi,
    'shanxi': QuakeSourceType.shanxi,
    'beijing': QuakeSourceType.beijing,
    'yunnan': QuakeSourceType.yunnan,
    'whews_bmkg': QuakeSourceType.bmkg,
    'whews_geonet': QuakeSourceType.geonet,
    'whews_tmd': QuakeSourceType.tmd,
    'whews_ingv': QuakeSourceType.ingv,
    'whews_nrcan': QuakeSourceType.nrcan,
    'whews_mmd': QuakeSourceType.mmd,
    'whews_phivolcs': QuakeSourceType.phivolcs,
    'whews_sgc': QuakeSourceType.sgc,
    'whews_ga': QuakeSourceType.ga,
    'whews_cenais': QuakeSourceType.cenais,
    'cencCmt': QuakeSourceType.cencCmt,
    'usgsCmt': QuakeSourceType.usgsCmt,
    'jmaCmt': QuakeSourceType.jmaCmt,
    'fnetCmt': QuakeSourceType.fnetCmt,
    'hinetAquaCmt': QuakeSourceType.hinetAquaCmt,
  };

  static final Set<QuakeSourceType> _legacySourcesHandledByUnified =
      Set<QuakeSourceType>.unmodifiable(_unifiedToQst.values.toSet());

  bool _isHandledByUnifiedPipeline(QuakeMessage event) {
    return _legacySourcesHandledByUnified.contains(event.source) ||
        event.source == QuakeSourceType.unadapted;
  }

  String _unifiedEventKey(UnifiedQuakeData event) {
    final source = event.isEew ? event.source : _unifiedInfoSlotSource(event);
    return '$source|${_unifiedCanonicalEventId(event)}';
  }

  @visibleForTesting
  String unifiedEventKeyForTest(UnifiedQuakeData event) {
    return _unifiedEventKey(event);
  }

  @visibleForTesting
  QuakeSourceType unifiedSourceTypeForTest(UnifiedQuakeData event) {
    return _unifiedSourceType(event) ?? QuakeSourceType.cenc;
  }

  @visibleForTesting
  QuakeMessage unifiedToQuakeMessageForTest(UnifiedQuakeData event) {
    return _unifiedToQuakeMessage(event);
  }

  String _unifiedInfoSlotSource(UnifiedQuakeData event) {
    if (event.isEew) return event.source;
    final noUpdateSourceKey = _noUpdateTimeFanInfoSourceKey(event.source);
    if (noUpdateSourceKey != null) return noUpdateSourceKey;
    return switch (event.source) {
      'p2pJmaEqlist' => 'jmaEqlist',
      _ => event.source,
    };
  }

  String _unifiedCanonicalEventId(UnifiedQuakeData event) {
    if (!event.isEew && _unifiedInfoSlotSource(event) == 'jmaEqlist') {
      final originTime = event.originTime;
      if (originTime != null) return _jmaInfoTimeToken(originTime);
      final digits = event.eventId.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 12) return digits;
    }
    return event.eventId;
  }

  String _jmaInfoTimeToken(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}'
        '${two(time.month)}${two(time.day)}${two(time.hour)}'
        '${two(time.minute)}${two(time.second)}';
  }

  Future<void> _loadBackgroundSeenState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final now = DateTime.now().toUtc();

    _backgroundSeenUnifiedInfoEvents.clear();
    final seenRows =
        prefs.getStringList(
          BackgroundEventProcessor.seenUnifiedInfoEventsPreferenceKey,
        ) ??
        const <String>[];
    for (final row in seenRows) {
      final separator = row.lastIndexOf('|');
      if (separator <= 0 || separator >= row.length - 1) continue;
      final seenMilliseconds = int.tryParse(row.substring(separator + 1));
      if (seenMilliseconds == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(
        seenMilliseconds,
        isUtc: true,
      );
      if (now.difference(seenAt) <= _backgroundSeenUnifiedInfoTtl) {
        _backgroundSeenUnifiedInfoEvents[row.substring(0, separator)] = seenAt;
      }
    }

    _backgroundAcceptedEewReportNums.clear();
    _backgroundAcceptedEewSeenAt.clear();
    final eewRows =
        prefs.getStringList(
          BackgroundEventProcessor.acceptedEewReportNumsPreferenceKey,
        ) ??
        const <String>[];
    for (final row in eewRows) {
      final timeSeparator = row.lastIndexOf('|');
      if (timeSeparator <= 0 || timeSeparator >= row.length - 1) continue;
      final reportSeparator = row.lastIndexOf('|', timeSeparator - 1);
      if (reportSeparator <= 0) continue;
      final reportNum = int.tryParse(
        row.substring(reportSeparator + 1, timeSeparator),
      );
      final seenMilliseconds = int.tryParse(row.substring(timeSeparator + 1));
      if (reportNum == null || seenMilliseconds == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(
        seenMilliseconds,
        isUtc: true,
      );
      if (now.difference(seenAt) > _backgroundAcceptedEewTtl) continue;
      final key = row.substring(0, reportSeparator);
      final previousReportNum = _backgroundAcceptedEewReportNums[key];
      final previousSeenAt = _backgroundAcceptedEewSeenAt[key];
      if (previousReportNum == null ||
          reportNum > previousReportNum ||
          (reportNum == previousReportNum &&
              (previousSeenAt == null || seenAt.isAfter(previousSeenAt)))) {
        _backgroundAcceptedEewReportNums[key] = reportNum;
        _backgroundAcceptedEewSeenAt[key] = seenAt;
      }
    }

    _pruneBackgroundSeenState();
  }

  void _rememberBackgroundAcceptedUnifiedEvent(UnifiedQuakeData event) {
    final now = DateTime.now().toUtc();
    final key = _unifiedEventKey(event);
    if (event.isEew) {
      final reportNum = _extractReportNum(event.reportNumText);
      final previous = _backgroundAcceptedEewReportNums[key];
      if (previous == null || reportNum > previous) {
        _backgroundAcceptedEewReportNums[key] = reportNum;
      }
      _backgroundAcceptedEewSeenAt[key] = now;
    } else {
      _backgroundSeenUnifiedInfoEvents[key] = now;
    }
    _pruneBackgroundSeenState();
    _backgroundSeenStateDirty = true;
    _scheduleBackgroundSeenStatePersist();
  }

  void _pruneBackgroundSeenState() {
    final now = DateTime.now().toUtc();
    _backgroundSeenUnifiedInfoEvents.removeWhere(
      (_, seenAt) => now.difference(seenAt) > _backgroundSeenUnifiedInfoTtl,
    );
    if (_backgroundSeenUnifiedInfoEvents.length >
        _maxBackgroundSeenUnifiedInfoEvents) {
      final entries = _backgroundSeenUnifiedInfoEvents.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final removeCount = entries.length - _maxBackgroundSeenUnifiedInfoEvents;
      for (var i = 0; i < removeCount; i++) {
        _backgroundSeenUnifiedInfoEvents.remove(entries[i].key);
      }
    }

    final expiredEewKeys = _backgroundAcceptedEewSeenAt.entries
        .where(
          (entry) => now.difference(entry.value) > _backgroundAcceptedEewTtl,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expiredEewKeys) {
      _backgroundAcceptedEewSeenAt.remove(key);
      _backgroundAcceptedEewReportNums.remove(key);
    }
    if (_backgroundAcceptedEewSeenAt.length > _maxBackgroundAcceptedEewEvents) {
      final entries = _backgroundAcceptedEewSeenAt.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final removeCount = entries.length - _maxBackgroundAcceptedEewEvents;
      for (var i = 0; i < removeCount; i++) {
        final key = entries[i].key;
        _backgroundAcceptedEewSeenAt.remove(key);
        _backgroundAcceptedEewReportNums.remove(key);
      }
    }
  }

  void _scheduleBackgroundSeenStatePersist() {
    _backgroundSeenStatePersistTimer?.cancel();
    _backgroundSeenStatePersistTimer = Timer(
      const Duration(milliseconds: 250),
      () {
        _backgroundSeenStatePersistTimer = null;
        unawaited(_persistBackgroundSeenState());
      },
    );
  }

  Future<void> _persistBackgroundSeenState() async {
    if (!_backgroundSeenStateDirty) return;
    _backgroundSeenStateDirty = false;
    _pruneBackgroundSeenState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final now = DateTime.now().toUtc();

    final mergedSeen = <String, DateTime>{};
    final storedSeenRows =
        prefs.getStringList(
          BackgroundEventProcessor.seenUnifiedInfoEventsPreferenceKey,
        ) ??
        const <String>[];
    for (final row in storedSeenRows) {
      final separator = row.lastIndexOf('|');
      if (separator <= 0 || separator >= row.length - 1) continue;
      final seenMilliseconds = int.tryParse(row.substring(separator + 1));
      if (seenMilliseconds == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(
        seenMilliseconds,
        isUtc: true,
      );
      if (now.difference(seenAt) <= _backgroundSeenUnifiedInfoTtl) {
        mergedSeen[row.substring(0, separator)] = seenAt;
      }
    }
    for (final entry in _backgroundSeenUnifiedInfoEvents.entries) {
      final previous = mergedSeen[entry.key];
      if (previous == null || entry.value.isAfter(previous)) {
        mergedSeen[entry.key] = entry.value;
      }
    }
    var seenEntries = mergedSeen.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (seenEntries.length > _maxBackgroundSeenUnifiedInfoEvents) {
      seenEntries = seenEntries.sublist(
        seenEntries.length - _maxBackgroundSeenUnifiedInfoEvents,
      );
    }
    await prefs.setStringList(
      BackgroundEventProcessor.seenUnifiedInfoEventsPreferenceKey,
      seenEntries
          .map((entry) => '${entry.key}|${entry.value.millisecondsSinceEpoch}')
          .toList(growable: false),
    );

    final mergedReports = <String, int>{};
    final mergedReportTimes = <String, DateTime>{};
    final storedEewRows =
        prefs.getStringList(
          BackgroundEventProcessor.acceptedEewReportNumsPreferenceKey,
        ) ??
        const <String>[];
    for (final row in storedEewRows) {
      final timeSeparator = row.lastIndexOf('|');
      if (timeSeparator <= 0 || timeSeparator >= row.length - 1) continue;
      final reportSeparator = row.lastIndexOf('|', timeSeparator - 1);
      if (reportSeparator <= 0) continue;
      final reportNum = int.tryParse(
        row.substring(reportSeparator + 1, timeSeparator),
      );
      final seenMilliseconds = int.tryParse(row.substring(timeSeparator + 1));
      if (reportNum == null || seenMilliseconds == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(
        seenMilliseconds,
        isUtc: true,
      );
      if (now.difference(seenAt) > _backgroundAcceptedEewTtl) continue;
      final key = row.substring(0, reportSeparator);
      mergedReports[key] = reportNum;
      mergedReportTimes[key] = seenAt;
    }
    for (final entry in _backgroundAcceptedEewReportNums.entries) {
      final seenAt = _backgroundAcceptedEewSeenAt[entry.key];
      if (seenAt == null) continue;
      final previousReport = mergedReports[entry.key];
      final previousSeenAt = mergedReportTimes[entry.key];
      if (previousReport == null ||
          entry.value > previousReport ||
          (entry.value == previousReport &&
              (previousSeenAt == null || seenAt.isAfter(previousSeenAt)))) {
        mergedReports[entry.key] = entry.value;
        mergedReportTimes[entry.key] = seenAt;
      }
    }
    var eewKeys = mergedReports.keys.toList()
      ..sort((a, b) => mergedReportTimes[a]!.compareTo(mergedReportTimes[b]!));
    if (eewKeys.length > _maxBackgroundAcceptedEewEvents) {
      eewKeys = eewKeys.sublist(
        eewKeys.length - _maxBackgroundAcceptedEewEvents,
      );
    }
    await prefs.setStringList(
      BackgroundEventProcessor.acceptedEewReportNumsPreferenceKey,
      eewKeys
          .map(
            (key) =>
                '$key|${mergedReports[key]}|${mergedReportTimes[key]!.millisecondsSinceEpoch}',
          )
          .toList(growable: false),
    );
  }

  QuakeSourceType? _unifiedSourceType(UnifiedQuakeData event) {
    if (event.source == 'jmaEqlist' && event.origin == 2) {
      return QuakeSourceType.p2p;
    }
    final mapped = _unifiedToQst[event.source];
    if (mapped != null) return mapped;
    if (_isUnadaptedUnifiedSource(event.source)) {
      return QuakeSourceType.unadapted;
    }
    return null;
  }

  static bool _isUnadaptedUnifiedSource(String source) {
    return source.startsWith('unadapted_') ||
        (source.startsWith('whews_') && !_unifiedToQst.containsKey(source));
  }

  bool _isReviewedUnifiedInfoEvent(UnifiedQuakeData event) {
    if (event.isEew) return false;
    final text = '${event.titleText} ${event.reportNumText}'.toLowerCase();
    return text.contains('正式') ||
        text.contains('已核实') ||
        text.contains('reviewed');
  }

  String? _unifiedListBucket(UnifiedQuakeData event) {
    if (event.isEew) return null;
    return switch (event.source) {
      'jmaEqlist' => 'jmaEqlist',
      'p2pJmaEqlist' => 'jmaEqlist',
      'cencEqlist' => 'cencEqlist',
      'usgsEqlist' => 'usgsEqlist',
      'fssnEqlist' => 'fssnEqlist',
      'kmaEqlist' => 'kmaEqlist',
      'cwaEqlist' => 'cwaEqlist',
      'emsc' => 'emscEqlist',
      'cencCmt' => 'cencCmt',
      'usgsCmt' => 'usgsCmt',
      'jmaCmt' => 'jmaCmt',
      'fnetCmt' => 'fnetCmt',
      'hinetAquaCmt' => 'hinetAquaCmt',
      _ => null,
    };
  }

  QuakeMessage _unifiedToListMessage(UnifiedQuakeData event) {
    final fallbackIntensity = IntensityCalculator.calcCsisLevel(
      event.magnitude,
      event.depth,
      0,
    );
    return _unifiedToQuakeMessage(
      event,
      isHistory: true,
      fallbackMaxIntensity: fallbackIntensity,
    );
  }

  QuakeMessage _unifiedToMapMessage(UnifiedQuakeData event) {
    return _unifiedToQuakeMessage(event);
  }

  QuakeMessage _unifiedToQuakeMessage(
    UnifiedQuakeData event, {
    bool isHistory = false,
    int? fallbackMaxIntensity,
  }) {
    final source = _unifiedSourceType(event) ?? QuakeSourceType.cenc;
    final intensity = double.tryParse(event.maxIntensity);
    final maxIntensity = intensity != null && intensity > 0
        ? intensity.round()
        : fallbackMaxIntensity;
    final isCenc = source == QuakeSourceType.cenc;
    final reviewLabel = isCenc ? _cencReviewLabel(event) : null;
    final reviewType = _unifiedReviewType(event);
    return QuakeMessage(
      source: source,
      eventId: event.eventId,
      location: event.hypocenter,
      magnitude: event.magnitude,
      latitude: event.lat ?? double.nan,
      longitude: event.lng ?? double.nan,
      depth: event.depth,
      originTime: event.originTime ?? DateTime.now(),
      reportTime: event.reportTime,
      timeZone: event.timeZone,
      maxIntensity: maxIntensity,
      jmaShindo: event.useShindo ? event.maxIntensity : null,
      isHistory: isHistory,
      isInfoEvent: !event.isEew,
      infoTypeName: isCenc ? reviewLabel : event.titleText,
      reviewType: isCenc ? _cencReviewType(reviewLabel) : reviewType,
      isWarn: event.isWarn,
      isFinal: event.isFinal,
      isCanceled: event.isCanceled,
      isAssumption: event.isAssumption,
      reportNumText: event.reportNumText,
      nodalPlane1: event.nodalPlane1,
      nodalPlane2: event.nodalPlane2,
      centroidDepth: event.centroidDepth,
      momentTensor: event.momentTensor,
      cmtMetadata: event.cmtMetadata,
      apiTypeLabel: event.apiTypeLabel,
    );
  }

  String _cencReviewLabel(UnifiedQuakeData event) {
    final text = '${event.reportNumText} ${event.titleText}'.toLowerCase();
    if (text.contains('正式') || text.contains('reviewed')) return '正式测定';
    return '自动测定';
  }

  String _cencReviewType(String? reviewLabel) {
    return reviewLabel == '正式测定' ? 'reviewed' : 'automatic';
  }

  bool _isCencRecentInfoUpdate(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.source != 'cencEqlist') return false;
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime == null || newReportTime == null) return false;

    // kanameishi 的 CENC 源适配使用真实 ReportTime/createTime 做 30 秒保护。
    // 当本项目因为字段缺失 fallback 到 originTime 时，不套这个窗口，避免误挡相近地震。
    if (oldEvent.originTime != null &&
        oldReportTime.isAtSameMomentAs(oldEvent.originTime!)) {
      return false;
    }
    if (event.originTime != null &&
        newReportTime.isAtSameMomentAs(event.originTime!)) {
      return false;
    }

    final diffMs = newReportTime.difference(oldReportTime).inMilliseconds;
    return diffMs >= 0 && diffMs < 30000;
  }

  bool _isSameUsgsInfoBody(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    if (event.source != 'usgsEqlist') return false;
    if (oldEvent.source != event.source) return false;

    // kanameishi 的 USGS 去重比较不包含 reportTime/updateTime：
    // 只有更新时间变化、主体内容未变时跳过，避免重复声音和重复刷新。
    return _isSameInfoBody(oldEvent, event);
  }

  /// 用于无可靠 reportTime 的信息源（EMSC 等）按主体内容去重。
  bool _isSameNoUpdateInfoBody(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.origin == WhewsService.adapterOrigin) return false;
    if (!_isNoUpdateTimeFanInfoSource(event.source)) return false;
    if (_noUpdateTimeFanInfoSourceKey(oldEvent.source) !=
        _noUpdateTimeFanInfoSourceKey(event.source)) {
      return false;
    }
    return _isSameInfoBody(oldEvent, event);
  }

  bool _isSameInfoBody(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    return _unifiedCanonicalEventId(oldEvent) ==
            _unifiedCanonicalEventId(event) &&
        oldEvent.titleText == event.titleText &&
        oldEvent.reportNumText == event.reportNumText &&
        oldEvent.hypocenter == event.hypocenter &&
        _sameDouble(oldEvent.lat, event.lat) &&
        _sameDouble(oldEvent.lng, event.lng) &&
        _sameDouble(oldEvent.depth, event.depth) &&
        _sameDouble(oldEvent.magnitude, event.magnitude) &&
        oldEvent.maxIntensity == event.maxIntensity &&
        oldEvent.className == event.className &&
        oldEvent.warnArea == event.warnArea &&
        oldEvent.isCanceled == event.isCanceled &&
        oldEvent.nodalPlane1 == event.nodalPlane1 &&
        oldEvent.nodalPlane2 == event.nodalPlane2 &&
        _sameDouble(oldEvent.centroidDepth, event.centroidDepth) &&
        _sameCmtMomentTensor(oldEvent, event) &&
        _sameCmtMetadata(oldEvent, event) &&
        _sameVolcanoEvent(oldEvent, event) &&
        QuakeTime.unifiedInstantUtc(oldEvent) ==
            QuakeTime.unifiedInstantUtc(event);
  }

  bool _sameVolcanoEvent(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    final oldVolcano = oldEvent.volcanoEvent;
    final newVolcano = event.volcanoEvent;
    if (oldVolcano == null || newVolcano == null) {
      return oldVolcano == null && newVolcano == null;
    }
    return oldVolcano.sameAs(newVolcano);
  }

  String? _usgsInfoBodyKey(UnifiedQuakeData event) {
    if (event.source != 'usgsEqlist') return null;
    return [
      event.eventId,
      event.titleText,
      event.hypocenter,
      event.lat?.toStringAsFixed(6) ?? '',
      event.lng?.toStringAsFixed(6) ?? '',
      event.depth.toStringAsFixed(3),
      event.magnitude.toStringAsFixed(3),
      event.maxIntensity,
      QuakeTime.unifiedInstantUtc(event).toIso8601String(),
    ].join('|');
  }

  bool _shouldSuppressCachedUsgsInfoBody(UnifiedQuakeData event) {
    final key = _usgsInfoBodyKey(event);
    if (key == null) return false;

    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    _seenUsgsInfoBodyKeys.removeWhere(
      (_, time) => now.difference(time.toUtc()) > ttl,
    );

    final contained = _seenUsgsInfoBodyKeys.containsKey(key);
    _seenUsgsInfoBodyKeys[key] = now;
    if (!contained) {
      unawaited(_persistSeenUsgsInfoBodyKeys());
    }
    return contained;
  }

  String? _emscInfoBodyKey(UnifiedQuakeData event) {
    if (event.source != 'emsc') return null;
    return [
      event.eventId,
      event.titleText,
      event.hypocenter,
      event.lat?.toStringAsFixed(6) ?? '',
      event.lng?.toStringAsFixed(6) ?? '',
      event.depth.toStringAsFixed(3),
      event.magnitude.toStringAsFixed(3),
      event.maxIntensity,
      QuakeTime.unifiedInstantUtc(event).toIso8601String(),
    ].join('|');
  }

  bool _shouldSuppressCachedEmscInfoBody(UnifiedQuakeData event) {
    final key = _emscInfoBodyKey(event);
    if (key == null) return false;

    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    _seenEmscInfoBodyKeys.removeWhere(
      (_, time) => now.difference(time.toUtc()) > ttl,
    );

    final contained = _seenEmscInfoBodyKeys.containsKey(key);
    _seenEmscInfoBodyKeys[key] = now;
    if (!contained) {
      unawaited(_persistSeenEmscInfoBodyKeys());
    }
    return contained;
  }

  String? _cwaInfoBodyKey(UnifiedQuakeData event) {
    if (event.source != 'cwaEqlist') return null;
    return [
      event.eventId,
      event.titleText,
      event.hypocenter,
      event.lat?.toStringAsFixed(6) ?? '',
      event.lng?.toStringAsFixed(6) ?? '',
      event.depth.toStringAsFixed(3),
      event.magnitude.toStringAsFixed(3),
      event.maxIntensity,
      QuakeTime.unifiedInstantUtc(event).toIso8601String(),
    ].join('|');
  }

  bool _shouldSuppressCachedCwaInfoBody(UnifiedQuakeData event) {
    final key = _cwaInfoBodyKey(event);
    if (key == null) return false;

    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    _seenCwaInfoBodyKeys.removeWhere(
      (_, time) => now.difference(time.toUtc()) > ttl,
    );

    final contained = _seenCwaInfoBodyKeys.containsKey(key);
    _seenCwaInfoBodyKeys[key] = now;
    if (!contained) {
      unawaited(_persistSeenCwaInfoBodyKeys());
    }
    return contained;
  }

  List<String> get _infoActionWhitelistItems => _infoActionWhitelist
      .split('|')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  bool _matchesInfoActionWhitelist(UnifiedQuakeData event) {
    return _infoActionWhitelistItems.any(event.hypocenter.contains);
  }

  bool _passesInfoMagnitudeFilter(UnifiedQuakeData event, double? threshold) {
    if (threshold == null || threshold == 0) return true;
    // “不接收”优先级高于地点白名单，关闭的源始终不进入 UI。
    if (threshold < 0) return false;
    return event.magnitude >= threshold || _matchesInfoActionWhitelist(event);
  }

  @visibleForTesting
  bool passesInfoMagnitudeFilterForTest(
    UnifiedQuakeData event,
    double? threshold,
  ) {
    return _passesInfoMagnitudeFilter(event, threshold);
  }

  @visibleForTesting
  bool shouldSuppressCachedUsgsInfoBodyForTest(UnifiedQuakeData event) {
    return _shouldSuppressCachedUsgsInfoBody(event);
  }

  bool _isUsgsSameReportBodyCorrection(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.source != 'usgsEqlist') return false;
    if (oldEvent.source != event.source) return false;
    if (oldEvent.eventId != event.eventId) return false;
    if (_isSameUsgsInfoBody(oldEvent, event)) return false;

    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime == null || newReportTime == null) return false;

    return newReportTime.isAtSameMomentAs(oldReportTime);
  }

  bool _isWhewsSameReportBodyCorrection(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (oldEvent.origin != WhewsService.adapterOrigin &&
        event.origin != WhewsService.adapterOrigin) {
      return false;
    }
    if (_unifiedInfoSlotSource(oldEvent) != _unifiedInfoSlotSource(event) ||
        _unifiedCanonicalEventId(oldEvent) != _unifiedCanonicalEventId(event) ||
        _isSameInfoBody(oldEvent, event)) {
      return false;
    }
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    return oldReportTime != null &&
        newReportTime != null &&
        newReportTime.isAtSameMomentAs(oldReportTime);
  }

  @visibleForTesting
  bool isUsgsSameReportBodyCorrectionForTest(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    return _isUsgsSameReportBodyCorrection(oldEvent, event);
  }

  String? _noUpdateTimeFanInfoSourceKey(String source) {
    switch (source) {
      case 'hko':
      case 'hkoEqlist':
        return 'hko';
      case 'emsc':
      case 'emscEqlist':
        return 'emsc';
      case 'bcsf':
      case 'bcsfEqlist':
        return 'bcsf';
      case 'gfz':
      case 'gfzEqlist':
        return 'gfz';
      case 'usp':
      case 'uspEqlist':
        return 'usp';
      case 'fssnCmt':
        return 'fssnCmt';
      case 'cencCmt':
        return 'cencCmt';
      case 'usgsCmt':
        return 'usgsCmt';
      case 'jmaCmt':
        return 'jmaCmt';
      case 'fnetCmt':
        return 'fnetCmt';
      case 'hinetAquaCmt':
        return 'hinetAquaCmt';
    }
    return null;
  }

  bool _isNoUpdateTimeFanInfoSource(String source) {
    return _noUpdateTimeFanInfoSourceKey(source) != null;
  }

  bool _isLocalFanInfoWithoutReportTime(String source) {
    switch (source) {
      case 'ningxia':
      case 'guangxi':
      case 'shanxi':
      case 'beijing':
      case 'yunnan':
        return true;
    }
    return false;
  }

  bool _shouldUseArrivalTimeForUnifiedInfo(UnifiedQuakeData event) {
    return !event.isEew &&
        event.origin != WhewsService.adapterOrigin &&
        (_showStaleInfoEvent ||
            _isNoUpdateTimeFanInfoSource(event.source) ||
            _isLocalFanInfoWithoutReportTime(event.source));
  }

  String? _seenNoUpdateInfoEventKey(UnifiedQuakeData event) {
    if (event.isEew) return null;
    if (event.origin == WhewsService.adapterOrigin) return null;
    final sourceKey = _noUpdateTimeFanInfoSourceKey(event.source);
    if (sourceKey == null) return null;
    final eventId = _unifiedCanonicalEventId(event).trim();
    if (eventId.isEmpty) return null;
    return '$sourceKey|$eventId';
  }

  Future<void> _loadSeenNoUpdateInfoEvents() async {
    final prefs = await SharedPreferences.getInstance();
    _seenNoUpdateInfoEvents.clear();
    final now = DateTime.now().toUtc();
    final rows = prefs.getStringList(_seenNoUpdateInfoEventsKey) ?? const [];
    for (final row in rows) {
      final sep = row.lastIndexOf('|');
      if (sep <= 0 || sep >= row.length - 1) continue;
      final key = row.substring(0, sep);
      final seenMs = int.tryParse(row.substring(sep + 1));
      if (seenMs == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(seenMs, isUtc: true);
      if (now.difference(seenAt) <= _seenNoUpdateInfoTtl) {
        _seenNoUpdateInfoEvents[key] = seenAt;
      }
    }
    await _persistSeenNoUpdateInfoEvents();
  }

  Future<void> _persistSeenNoUpdateInfoEvents() async {
    _pruneSeenNoUpdateInfoEvents();
    final prefs = await SharedPreferences.getInstance();
    final rows = _seenNoUpdateInfoEvents.entries
        .map((entry) => '${entry.key}|${entry.value.millisecondsSinceEpoch}')
        .toList(growable: false);
    await prefs.setStringList(_seenNoUpdateInfoEventsKey, rows);
  }

  Future<void> _loadSeenUsgsInfoBodyKeys() async {
    final prefs = await SharedPreferences.getInstance();
    _seenUsgsInfoBodyKeys.clear();
    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    final rows = prefs.getStringList(_seenUsgsInfoBodyKeysKey) ?? const [];
    for (final row in rows) {
      final sep = row.lastIndexOf('|');
      if (sep <= 0 || sep >= row.length - 1) continue;
      final key = row.substring(0, sep);
      final seenMs = int.tryParse(row.substring(sep + 1));
      if (seenMs == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(seenMs, isUtc: true);
      if (now.difference(seenAt) <= ttl) {
        _seenUsgsInfoBodyKeys[key] = seenAt;
      }
    }
    await _persistSeenUsgsInfoBodyKeys();
  }

  Future<void> _persistSeenUsgsInfoBodyKeys() async {
    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    _seenUsgsInfoBodyKeys.removeWhere(
      (_, seenAt) => now.difference(seenAt) > ttl,
    );
    final prefs = await SharedPreferences.getInstance();
    final rows = _seenUsgsInfoBodyKeys.entries
        .map((entry) => '${entry.key}|${entry.value.millisecondsSinceEpoch}')
        .toList(growable: false);
    await prefs.setStringList(_seenUsgsInfoBodyKeysKey, rows);
  }

  Future<void> _loadSeenEmscInfoBodyKeys() async {
    final prefs = await SharedPreferences.getInstance();
    _seenEmscInfoBodyKeys.clear();
    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    final rows = prefs.getStringList(_seenEmscInfoBodyKeysKey) ?? const [];
    for (final row in rows) {
      final sep = row.lastIndexOf('|');
      if (sep <= 0 || sep >= row.length - 1) continue;
      final key = row.substring(0, sep);
      final seenMs = int.tryParse(row.substring(sep + 1));
      if (seenMs == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(seenMs, isUtc: true);
      if (now.difference(seenAt) <= ttl) {
        _seenEmscInfoBodyKeys[key] = seenAt;
      }
    }
    await _persistSeenEmscInfoBodyKeys();
  }

  Future<void> _persistSeenEmscInfoBodyKeys() async {
    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    _seenEmscInfoBodyKeys.removeWhere(
      (_, seenAt) => now.difference(seenAt) > ttl,
    );
    final prefs = await SharedPreferences.getInstance();
    final rows = _seenEmscInfoBodyKeys.entries
        .map((entry) => '${entry.key}|${entry.value.millisecondsSinceEpoch}')
        .toList(growable: false);
    await prefs.setStringList(_seenEmscInfoBodyKeysKey, rows);
  }

  Future<void> _loadSeenCwaInfoBodyKeys() async {
    final prefs = await SharedPreferences.getInstance();
    _seenCwaInfoBodyKeys.clear();
    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    final rows = prefs.getStringList(_seenCwaInfoBodyKeysKey) ?? const [];
    for (final row in rows) {
      final sep = row.lastIndexOf('|');
      if (sep <= 0 || sep >= row.length - 1) continue;
      final key = row.substring(0, sep);
      final seenMs = int.tryParse(row.substring(sep + 1));
      if (seenMs == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(seenMs, isUtc: true);
      if (now.difference(seenAt) <= ttl) {
        _seenCwaInfoBodyKeys[key] = seenAt;
      }
    }
    await _persistSeenCwaInfoBodyKeys();
  }

  Future<void> _persistSeenCwaInfoBodyKeys() async {
    final now = DateTime.now().toUtc();
    const ttl = Duration(hours: 24);
    _seenCwaInfoBodyKeys.removeWhere(
      (_, seenAt) => now.difference(seenAt) > ttl,
    );
    final prefs = await SharedPreferences.getInstance();
    final rows = _seenCwaInfoBodyKeys.entries
        .map((entry) => '${entry.key}|${entry.value.millisecondsSinceEpoch}')
        .toList(growable: false);
    await prefs.setStringList(_seenCwaInfoBodyKeysKey, rows);
  }

  void _pruneSeenNoUpdateInfoEvents() {
    final now = DateTime.now().toUtc();
    _seenNoUpdateInfoEvents.removeWhere(
      (_, seenAt) => now.difference(seenAt) > _seenNoUpdateInfoTtl,
    );
    if (_seenNoUpdateInfoEvents.length <= _maxSeenNoUpdateInfoEvents) return;
    final sorted = _seenNoUpdateInfoEvents.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final removeCount =
        _seenNoUpdateInfoEvents.length - _maxSeenNoUpdateInfoEvents;
    for (var i = 0; i < removeCount; i++) {
      _seenNoUpdateInfoEvents.remove(sorted[i].key);
    }
  }

  void _rememberNoUpdateInfoEvent(
    UnifiedQuakeData event, {
    bool persist = true,
  }) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null) return;
    _seenNoUpdateInfoEvents[key] = DateTime.now().toUtc();
    _pruneSeenNoUpdateInfoEvents();
    if (persist) {
      unawaited(_persistSeenNoUpdateInfoEvents());
    }
  }

  bool _isCurrentNoUpdateInfoEvent(UnifiedQuakeData event) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null) return false;
    return _unifiedEvents.any((item) => _seenNoUpdateInfoEventKey(item) == key);
  }

  bool _shouldSuppressSeenNoUpdateInfoEvent(UnifiedQuakeData event) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null) return false;
    _pruneSeenNoUpdateInfoEvents();
    return _seenNoUpdateInfoEvents.containsKey(key) &&
        !_isCurrentNoUpdateInfoEvent(event);
  }

  @visibleForTesting
  void rememberNoUpdateInfoEventForTest(UnifiedQuakeData event) {
    _rememberNoUpdateInfoEvent(event, persist: false);
  }

  @visibleForTesting
  bool shouldSuppressSeenNoUpdateInfoEventForTest(UnifiedQuakeData event) {
    return _shouldSuppressSeenNoUpdateInfoEvent(event);
  }

  bool _isSameEventBodyChangedWithoutReportTime(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.origin == WhewsService.adapterOrigin) return false;
    if (!_isNoUpdateTimeFanInfoSource(event.source)) return false;
    if (_noUpdateTimeFanInfoSourceKey(oldEvent.source) !=
        _noUpdateTimeFanInfoSourceKey(event.source)) {
      return false;
    }
    if (oldEvent.eventId != event.eventId) return false;
    if (event.eventId.trim().isEmpty) return false;

    return oldEvent.titleText != event.titleText ||
        oldEvent.hypocenter != event.hypocenter ||
        !_sameDouble(oldEvent.lat, event.lat) ||
        !_sameDouble(oldEvent.lng, event.lng) ||
        !_sameDouble(oldEvent.depth, event.depth) ||
        !_sameDouble(oldEvent.magnitude, event.magnitude) ||
        oldEvent.maxIntensity != event.maxIntensity ||
        oldEvent.className != event.className ||
        !_sameCmtMomentTensor(oldEvent, event) ||
        !_sameCmtMetadata(oldEvent, event) ||
        QuakeTime.unifiedInstantUtc(oldEvent) !=
            QuakeTime.unifiedInstantUtc(event);
  }

  bool _sameCmtMomentTensor(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) => mapEquals(oldEvent.momentTensor?.toMap(), event.momentTensor?.toMap());

  bool _sameCmtMetadata(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    final oldMetadata = oldEvent.cmtMetadata;
    final newMetadata = event.cmtMetadata;
    if (oldMetadata == null || newMetadata == null) {
      return oldMetadata == newMetadata;
    }
    final oldValues = Map<String, dynamic>.from(oldMetadata.toMap())
      ..remove('rawMomentTensor');
    final newValues = Map<String, dynamic>.from(newMetadata.toMap())
      ..remove('rawMomentTensor');
    return mapEquals(oldValues, newValues) &&
        mapEquals(oldMetadata.rawMomentTensor, newMetadata.rawMomentTensor);
  }

  bool _sameDouble(double? a, double? b) {
    if (a == null || b == null) return a == b;
    return (a - b).abs() < 0.000001;
  }

  String? _unifiedReviewType(UnifiedQuakeData event) {
    final text = '${event.reportNumText} ${event.titleText}'.toLowerCase();
    if (text.contains('正式') ||
        text.contains('已核实') ||
        text.contains('reviewed') ||
        text.contains('confirmed')) {
      return 'reviewed';
    }
    if (text.contains('自动') ||
        text.contains('待核实') ||
        text.contains('automatic') ||
        text.contains('unverified')) {
      return 'automatic';
    }
    return null;
  }

  void _syncUnifiedToListBucket(UnifiedQuakeData event) {
    // 与参考项目一致：CENC 当前卡由 Wolfx/FAN setEqMessage 更新，
    // 历史列表只接受独立的 cenclist_response/HTTP 列表数据。
    if (event.source == 'cencEqlist') return;
    final bucket = _unifiedListBucket(event);
    if (bucket == null) return;
    _eqlist.upsertBucketItem(bucket, _unifiedToListMessage(event));
  }

  bool _isSameUnifiedEewEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!oldEvent.isEew || !event.isEew || oldEvent.source != event.source) {
      return false;
    }
    final oldId = oldEvent.eventId.trim();
    final newId = event.eventId.trim();
    if (oldId.isNotEmpty && newId.isNotEmpty && oldId == newId) {
      return true;
    }
    final oldIdTime = _eewEventIdTimeToken(oldId);
    final newIdTime = _eewEventIdTimeToken(newId);
    if (oldIdTime != null && newIdTime != null && oldIdTime != newIdTime) {
      return false;
    }

    final oldOrigin = oldEvent.originTime;
    final newOrigin = event.originTime;
    final sameOriginTime =
        oldOrigin != null &&
        newOrigin != null &&
        (oldOrigin.difference(newOrigin).inSeconds).abs() <= 2;
    if (!sameOriginTime) return false;

    final oldLat = oldEvent.lat;
    final oldLng = oldEvent.lng;
    final newLat = event.lat;
    final newLng = event.lng;
    if (oldLat == null || oldLng == null || newLat == null || newLng == null) {
      return true;
    }
    if ((oldLat == 0 && oldLng == 0) || (newLat == 0 && newLng == 0)) {
      return true;
    }
    return (oldLat - newLat).abs() <= 0.05 && (oldLng - newLng).abs() <= 0.05;
  }

  String? _eewEventIdTimeToken(String eventId) {
    return RegExp(r'(?:19|20)\d{12}').firstMatch(eventId)?.group(0);
  }

  bool _isWhewsSameReportEewRevision(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.origin != WhewsService.adapterOrigin ||
        !_isSameUnifiedEewEvent(oldEvent, event) ||
        _extractReportNum(oldEvent.reportNumText) !=
            _extractReportNum(event.reportNumText) ||
        _isSameInfoBody(oldEvent, event)) {
      return false;
    }
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime == null || newReportTime == null) return false;
    return !newReportTime.isBefore(oldReportTime);
  }

  int _findUnifiedEewIndex(UnifiedQuakeData event) {
    return _unifiedEvents.indexWhere(
      (e) => e.isEew && _isSameUnifiedEewEvent(e, event),
    );
  }

  int? _storedEewReportNumber(
    UnifiedQuakeData event, {
    UnifiedQuakeData? existingEvent,
  }) {
    final keys = <String>{_unifiedEventKey(event)};
    if (existingEvent != null) keys.add(_unifiedEventKey(existingEvent));
    final stored = <int>[];
    for (final key in keys) {
      final value = _ignoredEewIds[key];
      if (value != null) stored.add(value);
    }
    if (existingEvent != null) {
      stored.add(_extractReportNum(existingEvent.reportNumText));
    }
    if (stored.isEmpty) return null;
    return stored.reduce(math.max);
  }

  void _handleUnifiedEvent(
    UnifiedQuakeData event, {
    bool alreadyAccepted = false,
  }) {
    // kanameishi: EEW 过期检查（安全网）
    // 初始加载恢复的 EEW 如果已经过期，不应该显示
    if (event.isEew) {
      final elapsedSec = QuakeTime.calcPassedSecondsUnified(event);
      final timeoutSec = QuakeTime.eewTimeoutSecondsUnified(event);
      if (elapsedSec >= timeoutSec) {
        return;
      }
    }

    if (!event.isEew && !alreadyAccepted) {
      final qst = _unifiedSourceType(event);
      if (qst != null) {
        final filterSource = qst == QuakeSourceType.cencIr
            ? QuakeSourceType.cenc
            : qst;
        final threshold = _sourceInfoMagFilters[filterSource];
        if (threshold != null && threshold < 0) {
          debugPrint('QuakeProvider: 信息事件源已设为不接收，丢弃 ${event.source}');
          return;
        }
        if (!_passesInfoMagnitudeFilter(event, threshold)) {
          return;
        }
      }
      if (_shouldSuppressCachedUsgsInfoBody(event)) {
        return;
      }
      if (_shouldSuppressCachedEmscInfoBody(event)) {
        return;
      }
      if (_shouldSuppressCachedCwaInfoBody(event)) {
        return;
      }
      if (_usesReportTimeDisplayWindow(event) &&
          _remainingUnifiedDisplaySeconds(event) <= 0) {
        if (event.source != 'cencEqlist') {
          _syncUnifiedToListBucket(event);
        }
        notifyListeners();
        return;
      }
    }

    final eventKey = _unifiedEventKey(event);
    final existingIndex = event.isEew
        ? _findUnifiedEewIndex(event)
        : _unifiedEvents.indexWhere(
            (e) =>
                !e.isEew &&
                _unifiedInfoSlotSource(e) == _unifiedInfoSlotSource(event),
          );
    final existingEvent = existingIndex >= 0
        ? _unifiedEvents[existingIndex]
        : null;
    if (_shouldBlockDismissedUnifiedEvent(event) &&
        _dismissedUnifiedIds.contains(eventKey)) {
      // 旧事件拦截必须在同 source slot 替换前执行，防止已关闭事件重新顶回 UI。
      // 正式/已核实测定只允许覆盖此前关闭的自动测定一次。
      // 已关闭事件本身已经是正式测定时，同一轮询报文必须继续拦截。
      if (_isReviewedUnifiedInfoEvent(event) &&
          !_dismissedReviewedUnifiedIds.contains(eventKey)) {
        debugPrint('QuakeProvider: 正式测定覆盖已关闭事件: eventId=${event.eventId}');
        _dismissedUnifiedIds.remove(eventKey);
        _dismissedReviewedUnifiedIds.remove(eventKey);
      } else {
        debugPrint('QuakeProvider: 事件已关闭，跳过: eventId=${event.eventId}');
        return;
      }
    }

    if (!alreadyAccepted && _shouldSuppressSeenNoUpdateInfoEvent(event)) {
      debugPrint(
        'QuakeProvider: no-update info event already seen, list only: source=${event.source} eventId=${event.eventId}',
      );
      _syncUnifiedToListBucket(event);
      notifyListeners();
      return;
    }

    if (event.isEew) {
      final eewKey = eventKey;
      final reportNum = _extractReportNum(event.reportNumText);
      final storedReportNum = _storedEewReportNumber(
        event,
        existingEvent: existingEvent,
      );
      if (storedReportNum != null && reportNum <= storedReportNum) {
        final canApplyWhewsRevision =
            existingEvent != null &&
            _isWhewsSameReportEewRevision(existingEvent, event);
        if (canApplyWhewsRevision) {
          debugPrint('QuakeProvider: WHEWS EEW 同报正文修订: $eewKey #$reportNum');
        } else {
          return;
        }
      }
      _addToEewHistory(event);
    }

    // 信息事件按 source slot 匹配（参照 kanameishi 的 eqlistList 按 source 匹配逻辑）
    // P2PQ 的 JMA 地震信息和其它 JMA 地震信息共享一个当前 slot。
    if (existingIndex >= 0) {
      final oldEvent = _unifiedEvents[existingIndex];
      final oldKey = _unifiedEventKey(oldEvent);
      var suppressInfoActions = false;
      if (event.isEew) {
        final eewKey = eventKey;
        final reportNum = _extractReportNum(event.reportNumText);
        final storedReportNum = _storedEewReportNumber(
          event,
          existingEvent: oldEvent,
        );
        if (storedReportNum != null && reportNum <= storedReportNum) {
          final canApplyWhewsRevision = _isWhewsSameReportEewRevision(
            oldEvent,
            event,
          );
          if (canApplyWhewsRevision) {
            debugPrint('QuakeProvider: WHEWS EEW 更新同报正文: $eewKey #$reportNum');
          } else {
            return;
          }
        }
        if (oldKey != eventKey) {
          _unifiedDismissTimers[oldKey]?.cancel();
          _unifiedDismissTimers.remove(oldKey);
          _cancelPendingUnifiedUpdateEffects(oldKey);
          _dismissedUnifiedIds.remove(oldKey);
          _dismissedReviewedUnifiedIds.remove(oldKey);
          _ignoredEewIds.remove(oldKey);
        }
        _ignoredEewIds[eewKey] = reportNum;
      } else {
        // 信息事件按 source 匹配：参照 kanameishi 的 EqlistEvent.update()
        // 只有 reportTime 比旧的更新时才更新（防止重复推送触发声音/重置定时器）
        if (_isSameUsgsInfoBody(oldEvent, event)) {
          debugPrint(
            'QuakeProvider: USGS 主体内容未变化，仅更新时间变化，按本地去重规则跳过: eventId=${event.eventId}',
          );
          return;
        }
        if (_isSameNoUpdateInfoBody(oldEvent, event)) {
          debugPrint(
            'QuakeProvider: 无更新时间信息源主体内容未变化，跳过: source=${event.source} eventId=${event.eventId}',
          );
          return;
        }
        if (_isSameUnifiedInfoEvent(oldEvent, event) &&
            _isSameInfoBody(oldEvent, event)) {
          return;
        }
        final oldReportTime = oldEvent.reportTime;
        final newReportTime = event.reportTime;
        if (oldReportTime != null && newReportTime != null) {
          if (_isCencRecentInfoUpdate(oldEvent, event)) {
            debugPrint(
              'QuakeProvider: CENC 信息事件 30秒内更新，按本地源规则跳过: eventId=${event.eventId}',
            );
            return;
          }
          final oldOriginTime = oldEvent.originTime;
          final newOriginTime = event.originTime;
          final isNewerReport = newReportTime.isAfter(oldReportTime);
          final isNewerJmaLpgmReport = _isNewerJmaLpgmReport(oldEvent, event);
          final isNewerOrigin =
              newReportTime.isAtSameMomentAs(oldReportTime) &&
              oldOriginTime != null &&
              newOriginTime != null &&
              newOriginTime.isAfter(oldOriginTime);
          final isSameEventBodyCorrection =
              _isSameEventBodyChangedWithoutReportTime(oldEvent, event);
          final isUsgsSameReportBodyCorrection =
              _isUsgsSameReportBodyCorrection(oldEvent, event);
          final isWhewsSameReportBodyCorrection =
              _isWhewsSameReportBodyCorrection(oldEvent, event);
          suppressInfoActions =
              isUsgsSameReportBodyCorrection || isWhewsSameReportBodyCorrection;
          if (!isNewerReport &&
              !isNewerJmaLpgmReport &&
              !isNewerOrigin &&
              !isSameEventBodyCorrection &&
              !isUsgsSameReportBodyCorrection &&
              !isWhewsSameReportBodyCorrection) {
            debugPrint(
              'QuakeProvider: 信息事件不新于当前 source slot，跳过: source=${event.source} eventId=${event.eventId}',
            );
            return;
          }
        } else if (!_isSameUnifiedInfoEvent(oldEvent, event) &&
            !_isLaterUnifiedInfoEvent(oldEvent, event)) {
          // 首连聚合可能缺少 reportTime。不同事件仍必须有明确的
          // 发震时间顺序，不能让旧缓存覆盖当前卡。
          return;
        }
        // 清除旧 eventId 的 dismissed 标记
        if (oldKey != eventKey) {
          _dismissedUnifiedIds.remove(oldKey);
          _dismissedReviewedUnifiedIds.remove(oldKey);
          _unifiedDismissTimers[oldKey]?.cancel();
          _unifiedDismissTimers.remove(oldKey);
        }
      }
      _dismissedUnifiedIds.remove(eventKey);
      _dismissedReviewedUnifiedIds.remove(eventKey);
      final isNewInfoEvent =
          !event.isEew &&
          _unifiedCanonicalEventId(oldEvent) != _unifiedCanonicalEventId(event);
      if (!event.isEew &&
          !isNewInfoEvent &&
          event.origin != WhewsService.adapterOrigin &&
          _isNoUpdateTimeFanInfoSource(event.source)) {
        suppressInfoActions = true;
      }
      final arrivedAt = isNewInfoEvent
          ? (event.arrivedAt ?? DateTime.now())
          : oldEvent.arrivedAt;
      final nextEvent = !event.isEew
          ? _mergeUnifiedInfoEvent(oldEvent, event)
          : event;
      final acceptedEvent = nextEvent.copyWith(arrivedAt: arrivedAt);
      _unifiedEvents[existingIndex] = acceptedEvent;
      _unifiedMapRevision++;
      _rememberBackgroundAcceptedUnifiedEvent(acceptedEvent);
      if (isNewInfoEvent) {
        ObsAutomationInputService().emitUnifiedEvent(
          oldEvent,
          ObsUnifiedEventPhase.removed,
        );
        ObsAutomationInputService().emitUnifiedEvent(
          acceptedEvent,
          ObsUnifiedEventPhase.added,
        );
      } else {
        final automationPhase = acceptedEvent.isCanceled && !oldEvent.isCanceled
            ? ObsUnifiedEventPhase.canceled
            : ObsUnifiedEventPhase.updated;
        ObsAutomationInputService().emitUnifiedEvent(
          acceptedEvent,
          automationPhase,
        );
      }
      _sortUnifiedEvents();
      _startUnifiedCarousel();
      // EEW 每次更新重置定时器；信息事件更新不重置，防止连续推送导致事件挂住
      if (event.isEew) {
        _setupUnifiedDismissTimer(event);
      } else if (event.source == 'jmaEqlist' ||
          event.source == 'p2pJmaEqlist' ||
          event.source == 'usgsEqlist') {
        _setupUnifiedDismissTimer(event);
      } else if (isNewInfoEvent) {
        _unifiedDismissTimers[oldKey]?.cancel();
        _unifiedDismissTimers.remove(oldKey);
        _setupUnifiedDismissTimer(event);
      } else if (!_unifiedDismissTimers.containsKey(eventKey)) {
        _setupUnifiedDismissTimer(event);
      }
      _syncUnifiedToListBucket(nextEvent);
      _rememberNoUpdateInfoEvent(nextEvent);
      if (event.isEew) {
        final requiresImmediatePublish =
            nextEvent.isFinal ||
            nextEvent.isCanceled ||
            (!oldEvent.isWarn && nextEvent.isWarn);
        if (requiresImmediatePublish) {
          _cancelPendingUnifiedUpdateEffects(eventKey);
          _dispatchUnifiedEventEffects(nextEvent, isUpdate: true);
        } else {
          _scheduleUnifiedUpdateEffects(nextEvent);
        }
        _ensureUnifiedCountdownVoiceTimer();
        _publishUnifiedUi(immediate: requiresImmediatePublish);
      } else {
        if (!suppressInfoActions) {
          _announceUnifiedEvent(nextEvent, isFirst: false);
          onUnifiedEventNotified?.call(nextEvent, true);
          _triggerBackgroundNotification(nextEvent, true);
        }
        notifyListeners();
      }
      return;
    }

    final acceptedEvent = event.copyWith(
      arrivedAt: event.arrivedAt ?? DateTime.now(),
    );
    _unifiedEvents.insert(0, acceptedEvent);
    _unifiedMapRevision++;
    _rememberBackgroundAcceptedUnifiedEvent(acceptedEvent);
    ObsAutomationInputService().emitUnifiedEvent(
      acceptedEvent,
      acceptedEvent.isCanceled
          ? ObsUnifiedEventPhase.canceled
          : ObsUnifiedEventPhase.added,
    );
    if (event.isEew) {
      _ignoredEewIds[eventKey] = _extractReportNum(event.reportNumText);
    }
    _sortUnifiedEvents();
    _currentUnifiedIndex = 0;
    _startUnifiedCarousel();
    _setupUnifiedDismissTimer(event);
    _syncUnifiedToListBucket(event);
    _rememberNoUpdateInfoEvent(event);
    _dispatchUnifiedEventEffects(event, isUpdate: false);
    if (event.isEew) {
      _ensureUnifiedCountdownVoiceTimer();
      _publishUnifiedUi(immediate: true);
    } else {
      notifyListeners();
    }
  }

  void _publishUnifiedUi({required bool immediate}) {
    if (_disposed) return;
    _ensureTravelTimesLoaded();
    final now = DateTime.now();
    final lastPublishedAt = _lastUnifiedUiPublishedAt;
    final canPublishNow =
        immediate ||
        lastPublishedAt == null ||
        now.difference(lastPublishedAt) >= _unifiedUiPublishInterval;
    if (canPublishNow) {
      _unifiedUiPublishTimer?.cancel();
      _unifiedUiPublishTimer = null;
      _lastUnifiedUiPublishedAt = now;
      notifyListeners();
      return;
    }

    if (_unifiedUiPublishTimer != null) return;
    final remaining =
        _unifiedUiPublishInterval - now.difference(lastPublishedAt);
    _unifiedUiPublishTimer = Timer(remaining, () {
      _unifiedUiPublishTimer = null;
      if (_disposed) return;
      _lastUnifiedUiPublishedAt = DateTime.now();
      notifyListeners();
    });
  }

  void _ensureTravelTimesLoaded() {
    final travelTimes = TravelTimeService();
    if (travelTimes.isLoaded) return;
    unawaited(
      travelTimes.ensureLoaded().then((_) {
        if (_disposed) return;
        notifyListeners();
      }),
    );
  }

  void _scheduleUnifiedUpdateEffects(UnifiedQuakeData event) {
    final key = _unifiedEventKey(event);
    _pendingUnifiedUpdateEffects[key] = event;
    _unifiedUpdateEffectTimers[key]?.cancel();
    _unifiedUpdateEffectTimers[key] = Timer(_unifiedUpdateEffectDelay, () {
      _unifiedUpdateEffectTimers.remove(key);
      final latest = _pendingUnifiedUpdateEffects.remove(key);
      if (_disposed || latest == null) return;
      _dispatchUnifiedEventEffects(latest, isUpdate: true);
    });
  }

  void _cancelPendingUnifiedUpdateEffects(String key) {
    _unifiedUpdateEffectTimers.remove(key)?.cancel();
    _pendingUnifiedUpdateEffects.remove(key);
  }

  void _dispatchUnifiedEventEffects(
    UnifiedQuakeData event, {
    required bool isUpdate,
  }) {
    _announceUnifiedEvent(event, isFirst: !isUpdate);
    onUnifiedEventNotified?.call(event, isUpdate);
    _triggerBackgroundNotification(event, isUpdate);
  }

  /// 在应用处于后台时触发系统通知
  ///
  /// - EEW：首报立即通知；短时间连续更新只通知窗口内最后一报。
  ///   警报升级、最终报和取消报不等待合并窗口。
  /// - 信息事件：仅在首次收到时通知，避免重复推送。
  ///
  /// 通知数据直接使用经过 [QuakeProvider] 统一处理后的 [UnifiedQuakeData]，
  /// 本地烈度也基于该事件实时计算，不依赖前台 UI 状态。
  /// Android 前台服务只负责保活，主 isolate 继续负责统一事件通知。
  void _triggerBackgroundNotification(UnifiedQuakeData event, bool isUpdate) {
    if (!BackgroundService().isBackgroundHandlingEnabled) return;
    if (!BackgroundService().isInBackground) return;
    if (event.isEew) {
      BackgroundService().showEewNotification(
        event,
        localIntensity: _computeLocalIntensityForEvent(event),
      );
    } else if (!isUpdate) {
      BackgroundService().showReportNotification(event);
    }
  }

  /// 基于单个事件计算本地预估烈度，用于后台通知等不依赖当前 UI 状态的场景。
  ///
  /// 优先根据用户位置与震源距离计算；当缺少用户位置或事件经纬度时，
  /// 再 fallback 到事件自身 maxIntensity。
  double _computeLocalIntensityForEvent(UnifiedQuakeData event) {
    final userPos = LocationService().currentPosition;
    final lat = event.lat;
    final lng = event.lng;
    if (userPos != null && lat != null && lng != null) {
      try {
        final distance = QuakeCalculator.haversineDistance(
          userPos.latitude,
          userPos.longitude,
          lat,
          lng,
        );
        return IntensityCalculator.calculate(
          mag: event.magnitude,
          distance: distance,
        );
      } catch (e) {
        debugPrint('Local intensity calculation error: $e');
      }
    }
    final maxIntensity = double.tryParse(event.maxIntensity);
    if (maxIntensity != null && maxIntensity > 0) {
      return maxIntensity;
    }
    return 0.0;
  }

  @visibleForTesting
  void handleUnifiedEventForTest(UnifiedQuakeData event) {
    _handleUnifiedEvent(event);
  }

  @visibleForTesting
  void dismissUnifiedEventForTest(UnifiedQuakeData event) {
    final index = _unifiedEvents.indexWhere(
      (item) => _unifiedEventKey(item) == _unifiedEventKey(event),
    );
    if (index >= 0) _removeUnifiedEvent(index);
  }

  UnifiedQuakeData _mergeUnifiedInfoEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!_isSameUnifiedInfoEvent(oldEvent, event)) return event;

    var merged = event.copyWith(eventId: oldEvent.eventId);

    if (_jmaInfoTitleRank(event.titleText) <
        _jmaInfoTitleRank(oldEvent.titleText)) {
      merged = merged.copyWith(titleText: oldEvent.titleText);
    }

    if (!_hasKnownUnifiedShindo(event) && _hasKnownUnifiedShindo(oldEvent)) {
      merged = merged.copyWith(
        maxIntensity: oldEvent.maxIntensity,
        className: oldEvent.className,
      );
    }

    if (event.titleText.trim().isEmpty &&
        oldEvent.titleText.trim().isNotEmpty) {
      merged = merged.copyWith(titleText: oldEvent.titleText);
    }
    if (event.reportNumText.trim().isEmpty &&
        oldEvent.reportNumText.trim().isNotEmpty &&
        event.origin != 2) {
      merged = merged.copyWith(reportNumText: oldEvent.reportNumText);
    }
    if (event.hypocenter.trim().isEmpty &&
        oldEvent.hypocenter.trim().isNotEmpty) {
      merged = merged.copyWith(hypocenter: oldEvent.hypocenter);
    }
    if (event.lat == null && oldEvent.lat != null) {
      merged = merged.copyWith(lat: oldEvent.lat);
    }
    if (event.lng == null && oldEvent.lng != null) {
      merged = merged.copyWith(lng: oldEvent.lng);
    }
    if (event.depthText.trim().isEmpty &&
        oldEvent.depthText.trim().isNotEmpty) {
      merged = merged.copyWith(depthText: oldEvent.depthText);
    }
    if (!event.isCanceled &&
        event.warnArea.trim().isEmpty &&
        oldEvent.warnArea.trim().isNotEmpty) {
      merged = merged.copyWith(warnArea: oldEvent.warnArea);
    }
    if (event.apiTypeLabel.trim().isEmpty &&
        oldEvent.apiTypeLabel.trim().isNotEmpty) {
      merged = merged.copyWith(apiTypeLabel: oldEvent.apiTypeLabel);
    }
    if (event.centroidDepth == null && oldEvent.centroidDepth != null) {
      merged = merged.copyWith(centroidDepth: oldEvent.centroidDepth);
    }
    if (event.momentTensor == null && oldEvent.momentTensor != null) {
      merged = merged.copyWith(momentTensor: oldEvent.momentTensor);
    }
    if (event.cmtMetadata == null && oldEvent.cmtMetadata != null) {
      merged = merged.copyWith(cmtMetadata: oldEvent.cmtMetadata);
    }
    if (event.volcanoEvent == null && oldEvent.volcanoEvent != null) {
      merged = merged.copyWith(volcanoEvent: oldEvent.volcanoEvent);
    }

    if (!_hasUnifiedHypocenter(event) && _hasUnifiedHypocenter(oldEvent)) {
      merged = merged.copyWith(
        hypocenter: oldEvent.hypocenter,
        lat: oldEvent.lat,
        lng: oldEvent.lng,
      );
    }

    if (event.magnitude < 0 && oldEvent.magnitude >= 0) {
      merged = merged.copyWith(magnitude: oldEvent.magnitude);
    }

    if (event.depth < 0 && oldEvent.depth >= 0) {
      merged = merged.copyWith(
        depth: oldEvent.depth,
        depthText: oldEvent.depthText,
      );
    }

    return merged;
  }

  bool _isSameUnifiedInfoEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (oldEvent.isEew || event.isEew) return false;
    if (_unifiedInfoSlotSource(oldEvent) != _unifiedInfoSlotSource(event)) {
      return false;
    }
    final oldId = _unifiedCanonicalEventId(oldEvent).trim();
    final newId = _unifiedCanonicalEventId(event).trim();
    return oldId.isNotEmpty && oldId == newId;
  }

  bool _isNewerJmaLpgmReport(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!oldEvent.isJmaLpgm || !event.isJmaLpgm) return false;
    final oldBulletin = oldEvent.jmaLpgmBulletin;
    final newBulletin = event.jmaLpgmBulletin;
    if (oldBulletin == null || newBulletin == null) return false;
    return oldBulletin.eventId == newBulletin.eventId &&
        newBulletin.serial > oldBulletin.serial;
  }

  bool _isLaterUnifiedInfoEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    final oldOrigin = oldEvent.originTime;
    final newOrigin = event.originTime;
    if (oldOrigin != null && newOrigin != null) {
      return newOrigin.isAfter(oldOrigin);
    }
    final oldArrived = oldEvent.arrivedAt;
    final newArrived = event.arrivedAt;
    return oldArrived != null &&
        newArrived != null &&
        newArrived.isAfter(oldArrived);
  }

  @visibleForTesting
  UnifiedQuakeData mergeUnifiedInfoEventForTest(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    return _mergeUnifiedInfoEvent(oldEvent, event);
  }

  int _jmaInfoTitleRank(String title) {
    if (title.contains('各地の震度')) return 4;
    if (title.contains('震度・震源') || title.contains('震源・震度')) return 3;
    if (title.contains('震源')) return 2;
    if (title.contains('震度速報')) return 1;
    return 0;
  }

  bool _hasKnownUnifiedShindo(UnifiedQuakeData event) {
    final value = event.maxIntensity.trim();
    return value.isNotEmpty && value != '-' && value != '?' && value != '不明';
  }

  bool _hasUnifiedHypocenter(UnifiedQuakeData event) {
    final name = event.hypocenter.trim();
    if (name.isEmpty || name.contains('調査中') || name.contains('调查中')) {
      return false;
    }
    return event.lat != null && event.lng != null;
  }

  /// 统一事件的语音播报入口。
  ///
  /// SREV 提示音由 [NotificationService] 按用户开关统一播放，避免同一报
  /// 在 Provider 与通知服务中各创建一个播放器。
  void _announceUnifiedEvent(UnifiedQuakeData event, {required bool isFirst}) {
    if (event.isEew) {
      if (event.isCanceled) {
        _speakUnifiedEvent(event, phase: 'cancel', isUpdate: false);
        return;
      }

      final eewKey = '${event.source}|${event.eventId}';
      var phase = isFirst ? 'first' : (event.isFinal ? 'final' : 'update');
      if (event.isWarn && _eewWarnAnnouncementIds.add(eewKey)) {
        _eewCautionAnnouncementIds.add(eewKey);
        phase = isFirst ? 'first' : 'warn';
      } else if (_isCautionClass(event.className) &&
          _eewCautionAnnouncementIds.add(eewKey)) {
        phase = isFirst ? 'first' : 'caution';
      }
      _speakUnifiedEvent(event, phase: phase, isUpdate: !isFirst);
      return;
    }

    _speakUnifiedEvent(
      event,
      phase: isFirst ? 'first' : 'update',
      isUpdate: !isFirst,
    );
  }

  void _speakUnifiedEvent(
    UnifiedQuakeData event, {
    required String phase,
    required bool isUpdate,
  }) {
    final text = AlertVoiceHelper.generateUnifiedEventText(event, phase: phase);
    final reportKey = event.reportNumText.trim().isEmpty
        ? phase
        : '${phase}_${event.reportNumText.trim()}';
    TtsService().speakEvent(
      text,
      dedupeKey: '${_unifiedEventKey(event)}:$reportKey',
      isUpdate: isUpdate && phase != 'cancel' && phase != 'final',
      delay: const Duration(milliseconds: 1250),
    );
  }

  /// 计算统一 EEW 的 S 波剩余时间。
  ///
  /// 与统一 UI 使用同一事件时间语义：originTime 视为来源本地时间，
  /// 通过 timeZone 转成 UTC 后与 NTP 校时比较。没有可用的走时表、定位或
  /// 震源坐标时不猜测传播速度，直接不播报。
  int? _unifiedSCountdownForVoice(UnifiedQuakeData event) {
    final position = LocationService().currentPosition;
    if (position == null || event.originTime == null) return null;
    return _calculateUnifiedSCountdown(
      event,
      userLat: position.latitude,
      userLng: position.longitude,
      elapsedSeconds: QuakeTime.calcPassedSecondsUnified(event),
    );
  }

  bool _hasStrongLocalIntensityForUnifiedCountdown(
    UnifiedQuakeData event, {
    required double userLat,
    required double userLng,
  }) {
    if (!event.isEew ||
        event.isCanceled ||
        !userLat.isFinite ||
        !userLng.isFinite ||
        event.magnitude < 0 ||
        !event.depth.isFinite) {
      return false;
    }

    final eventLat = event.lat;
    final eventLng = event.lng;
    if (eventLat == null ||
        eventLng == null ||
        !eventLat.isFinite ||
        !eventLng.isFinite) {
      return false;
    }

    if (event.useShindo) {
      final shindo = IntensityCalculator.calcJmaShindo(
        event.magnitude,
        event.depth,
        eventLat,
        eventLng,
        userLat,
        userLng,
      );
      return shindo >= _unifiedCountdownStrongShindoThreshold;
    }

    final distance = QuakeCalculator.haversineDistance(
      eventLat,
      eventLng,
      userLat,
      userLng,
    );
    if (!distance.isFinite) return false;
    final csis = IntensityCalculator.calcCsisLevel(
      event.magnitude,
      event.depth,
      distance,
    );
    return csis >= _unifiedCountdownStrongCsisThreshold;
  }

  bool _hasStrongLocalIntensityForUnifiedCountdownAtCurrentLocation(
    UnifiedQuakeData event,
  ) {
    final position = LocationService().currentPosition;
    if (position == null) return false;
    return _hasStrongLocalIntensityForUnifiedCountdown(
      event,
      userLat: position.latitude,
      userLng: position.longitude,
    );
  }

  @visibleForTesting
  bool unifiedCountdownIsStrongForTest(
    UnifiedQuakeData event, {
    required double userLat,
    required double userLng,
  }) {
    return _hasStrongLocalIntensityForUnifiedCountdown(
      event,
      userLat: userLat,
      userLng: userLng,
    );
  }

  int? _calculateUnifiedSCountdown(
    UnifiedQuakeData event, {
    required double userLat,
    required double userLng,
    required int elapsedSeconds,
  }) {
    if (!event.isEew || event.isCanceled || event.originTime == null) {
      return null;
    }
    final eventLat = event.lat;
    final eventLng = event.lng;
    if (eventLat == null ||
        eventLng == null ||
        !eventLat.isFinite ||
        !eventLng.isFinite ||
        !userLat.isFinite ||
        !userLng.isFinite ||
        !event.depth.isFinite) {
      return null;
    }

    final travelTimes = TravelTimeService();
    if (!travelTimes.isLoaded) return null;

    final distance = QuakeCalculator.haversineDistance(
      eventLat,
      eventLng,
      userLat,
      userLng,
    );
    if (!distance.isFinite) return null;

    final tableName = distance <= 2000 ? 'jma2001' : 'jb';
    final reachTime = travelTimes.calcReachTime(
      tableName,
      false,
      event.depth,
      distance,
    );
    if (!reachTime.isFinite || reachTime <= 0) return null;
    return math.max((reachTime - elapsedSeconds).floor(), 0).toInt();
  }

  @visibleForTesting
  int? unifiedSCountdownForTest(
    UnifiedQuakeData event, {
    required double userLat,
    required double userLng,
    required int elapsedSeconds,
  }) {
    return _calculateUnifiedSCountdown(
      event,
      userLat: userLat,
      userLng: userLng,
      elapsedSeconds: elapsedSeconds,
    );
  }

  void _ensureUnifiedCountdownVoiceTimer() {
    if (_disposed) return;

    final activeKeys = _unifiedEvents
        .where((event) => event.isEew)
        .map(_unifiedEventKey)
        .toSet();
    _unifiedCountdownLastSpokenSeconds.removeWhere(
      (key, _) => !activeKeys.contains(key),
    );

    if (activeKeys.isEmpty) {
      _unifiedCountdownVoiceTimer?.cancel();
      _unifiedCountdownVoiceTimer = null;
      return;
    }

    _updateUnifiedCountdownVoice();
    _unifiedCountdownVoiceTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateUnifiedCountdownVoice(),
    );
  }

  void _updateUnifiedCountdownVoice() {
    if (_disposed) return;
    _removeExpiredUnifiedEewEvents();
    if (_disposed) return;
    final event = currentUnifiedEvent;
    if (event == null || !event.isEew || event.isCanceled) return;

    final countdown = _unifiedSCountdownForVoice(event);
    if (countdown == null) return;

    if (!_hasStrongLocalIntensityForUnifiedCountdownAtCurrentLocation(event)) {
      return;
    }

    final eventKey = _unifiedEventKey(event);
    if (_unifiedCountdownLastSpokenSeconds[eventKey] == countdown) return;

    if (countdown > 0 && countdown <= 10) {
      TtsService().speakCountdown(eventKey, countdown);
    } else if (countdown == 0) {
      TtsService().speakArrival(eventKey);
    }
    _unifiedCountdownLastSpokenSeconds[eventKey] = countdown;
  }

  void _speakTsunamiEvent(TsunamiMessage tsunami, {int? previousStatus}) {
    final isUpdate = previousStatus != null && previousStatus == tsunami.status;
    final text = AlertVoiceHelper.generateTsunamiText(
      tsunami,
      isUpdate: isUpdate,
    );
    TtsService().speakEvent(
      text,
      dedupeKey:
          'tsunami:${tsunami.source.name}:${tsunami.id}:${tsunami.status}',
      isUpdate: isUpdate,
      delay: const Duration(milliseconds: 1250),
    );
  }

  bool _isCautionClass(String className) {
    return className == 'green' ||
        className == 'yellow' ||
        className == 'orange' ||
        className == 'dark-orange' ||
        className == 'red' ||
        className == 'dark-red' ||
        className == 'purple';
  }

  int _extractReportNum(String text) {
    if (text.isEmpty) return 1;
    final match = RegExp(r'\d+').firstMatch(text);
    if (match == null) return 1;
    return int.tryParse(match.group(0) ?? '1') ?? 1;
  }

  void _addToEewHistory(UnifiedQuakeData event) {
    final groupIndex = _eewHistory.indexWhere(
      (g) =>
          g.eventId == event.eventId ||
          (g.reports.isNotEmpty && _isSameUnifiedEewEvent(g.latest, event)),
    );
    if (groupIndex >= 0) {
      _eewHistory[groupIndex] = _eewHistory[groupIndex].addReport(event);
    } else {
      _eewHistory.insert(
        0,
        EewEventGroup(
          eventId: event.eventId,
          reports: [event],
          firstArrivedAt: event.arrivedAt ?? DateTime.now(),
        ),
      );
    }
    if (_eewHistory.length > _maxPersistedEewHistoryGroups) {
      _eewHistory.removeRange(
        _maxPersistedEewHistoryGroups,
        _eewHistory.length,
      );
    }
    _schedulePersistEewHistory();
    _eewHistoryRevision++;
    _notifyHistorySlice();
  }

  void _sortUnifiedEvents() {
    _unifiedEvents.sort((a, b) {
      if (a.isEew && !b.isEew) return -1;
      if (!a.isEew && b.isEew) return 1;
      final aTime = a.arrivedAt ?? DateTime.now();
      final bTime = b.arrivedAt ?? DateTime.now();
      return bTime.compareTo(aTime);
    });
  }

  int _getUnifiedDismissSeconds(UnifiedQuakeData event) {
    if (event.isJmaLpgm) return const Duration(minutes: 1).inSeconds;
    final mag = event.magnitude;
    if (event.isEew) {
      if (event.isCanceled) return 20;
      if (event.isWarn) return (mag > 6 ? mag : 6).ceil() * 60;
      return (mag > 3 ? mag : 3).ceil() * 60;
    } else {
      int seconds = 300;
      if (event.className.contains('orange') || mag >= 6.0) seconds = 600;
      if (event.className.contains('red') || mag >= 7.0) seconds = 900;
      if (event.className == 'purple' || mag >= 7.5) seconds = 1200;
      if (event.isCanceled) seconds = 60;
      return seconds;
    }
  }

  int _getUnifiedElapsedSeconds(UnifiedQuakeData event) {
    if (event.isEew) return QuakeTime.calcPassedSecondsUnified(event);
    if (_shouldUseArrivalTimeForUnifiedInfo(event) &&
        event.origin != WhewsService.adapterOrigin) {
      return 0;
    }

    final referenceTime = QuakeTime.informationDisplayReference(event);
    if (referenceTime == null) {
      return QuakeTime.calcPassedSecondsUnified(event);
    }
    return QuakeTime.calcPassedSecondsFromDateTime(
      referenceTime,
      Duration(hours: event.timeZone),
    );
  }

  bool _usesReportTimeDisplayWindow(UnifiedQuakeData event) {
    return event.origin == WhewsService.adapterOrigin ||
        event.source == 'usgsEqlist' ||
        event.source == 'cwaEqlist' ||
        event.source == 'cencEqlist';
  }

  int _remainingUnifiedDisplaySeconds(UnifiedQuakeData event) {
    return _getUnifiedDismissSeconds(event) - _getUnifiedElapsedSeconds(event);
  }

  @visibleForTesting
  int unifiedDismissSecondsForTest(UnifiedQuakeData event) {
    return _getUnifiedDismissSeconds(event);
  }

  /// 旧管道信息事件过期秒数（仅按震级判断，与统一管道逻辑一致）
  int _getDismissSecondsForInfo(double magnitude) {
    int seconds = 300;
    if (magnitude >= 6.0) seconds = 600;
    if (magnitude >= 7.0) seconds = 900;
    if (magnitude >= 7.5) seconds = 1200;
    return seconds;
  }

  void _setupUnifiedDismissTimer(UnifiedQuakeData event) {
    final key = _unifiedEventKey(event);
    _unifiedDismissTimers[key]?.cancel();
    final totalSeconds = _getUnifiedDismissSeconds(event);

    // 参照 kanameishi 的 time -= passedTime 逻辑。
    final remainingSeconds = _remainingUnifiedDisplaySeconds(
      event,
    ).clamp(1, totalSeconds);
    _unifiedDismissTimers[key] = Timer(Duration(seconds: remainingSeconds), () {
      final index = _unifiedEvents.indexWhere(
        (e) => _unifiedEventKey(e) == key,
      );
      if (index >= 0) _removeUnifiedEvent(index);
    });
  }

  void _removeUnifiedEvent(int index) {
    final event = _unifiedEvents[index];
    final key = _unifiedEventKey(event);
    ObsAutomationInputService().emitUnifiedEvent(
      event,
      ObsUnifiedEventPhase.removed,
    );
    _clearRealtimeCencIrForUnifiedEvent(event);
    _rememberNoUpdateInfoEvent(event);
    if (_shouldBlockDismissedUnifiedEvent(event)) {
      _dismissedUnifiedIds.add(key);
      if (_isReviewedUnifiedInfoEvent(event)) {
        _dismissedReviewedUnifiedIds.add(key);
      } else {
        _dismissedReviewedUnifiedIds.remove(key);
      }
    }
    _unifiedDismissTimers[key]?.cancel();
    _unifiedDismissTimers.remove(key);
    _cancelPendingUnifiedUpdateEffects(key);
    _unifiedCountdownLastSpokenSeconds.remove(key);
    _unifiedEvents.removeAt(index);
    _unifiedMapRevision++;

    if (event.isEew) {
      final reportNum = _extractReportNum(event.reportNumText);
      _ignoredEewIds[key] = reportNum;
      if (_ignoredEewIds.length > _maxIgnoredEewIds) {
        final firstKey = _ignoredEewIds.keys.first;
        _ignoredEewIds.remove(firstKey);
      }
    }

    if (_dismissedUnifiedIds.length > 200) {
      final firstKey = _dismissedUnifiedIds.first;
      _dismissedUnifiedIds.remove(firstKey);
      _dismissedReviewedUnifiedIds.remove(firstKey);
    }

    if (_unifiedEvents.isEmpty) {
      _currentUnifiedIndex = 0;
      _unifiedCarouselTimer?.cancel();
      onAllEventsExpired?.call();
    } else {
      _currentUnifiedIndex = _currentUnifiedIndex.clamp(
        0,
        _unifiedEvents.length - 1,
      );
      _startUnifiedCarousel();
    }

    _ensureUnifiedCountdownVoiceTimer();
    notifyListeners();
  }

  /// 独立定时器失效或被重置时的 EEW 过期安全网。
  ///
  /// 每秒倒计时计时器本来就只在有统一 EEW 时运行，因此复用它检查事件
  /// 的绝对过期时间不会新增常驻计时器，也不会重复请求数据。
  void _removeExpiredUnifiedEewEvents() {
    for (var index = _unifiedEvents.length - 1; index >= 0; index--) {
      final event = _unifiedEvents[index];
      if (!event.isEew) continue;
      if (QuakeTime.calcPassedSecondsUnified(event) <
          QuakeTime.eewTimeoutSecondsUnified(event)) {
        continue;
      }
      _removeUnifiedEvent(index);
    }
  }

  void _clearRealtimeCencIrForUnifiedEvent(UnifiedQuakeData event) {
    if (event.source != 'nowQuakeCencIr') return;
    final realtime = _realtimeCencIrData;
    if (realtime == null) return;
    final realtimeId = _cencIrDataId(realtime);
    if (realtimeId == event.eventId || realtime.uniEventId == event.eventId) {
      _realtimeCencIrData = null;
    }
  }

  bool _shouldBlockDismissedUnifiedEvent(UnifiedQuakeData event) {
    if (!event.isEew && event.source == 'cwaEqlist') return false;
    return true;
  }

  void _clearLegacyActiveQuakePipeline() {
    for (final warning in _activeWarnings) {
      warning.dismissTimer?.cancel();
    }
    _activeWarnings.clear();
    _activeInfoEvents.clear();
    _currentWarningIndex = 0;
    _isShowingInfoEvent = false;
    _isShowingTempInfo = false;
    _currentDistance = 0.0;
    _estimatedIntensity = 0.0;
    _pCountdown = -1;
    _sCountdown = -1;
    _countdownTimer?.cancel();
    _carouselTimer?.cancel();
    _infoDismissTimer?.cancel();
    _tempInfoDisplayTimer?.cancel();
    if (_unifiedEvents.isEmpty) {
      _currentEvent = null;
    }
  }

  void setCurrentUnifiedIndex(int index) {
    if (_unifiedEvents.isEmpty) return;
    final newIndex = index.clamp(0, _unifiedEvents.length - 1);
    if (_currentUnifiedIndex == newIndex) return;
    _currentUnifiedIndex = newIndex;
    _updateUnifiedCountdownVoice();
    notifyListeners();
  }

  void nextUnified() {
    if (_unifiedEvents.length <= 1) return;
    _currentUnifiedIndex = (_currentUnifiedIndex + 1) % _unifiedEvents.length;
    _updateUnifiedCountdownVoice();
    notifyListeners();
  }

  void prevUnified() {
    if (_unifiedEvents.length <= 1) return;
    _currentUnifiedIndex =
        (_currentUnifiedIndex - 1 + _unifiedEvents.length) %
        _unifiedEvents.length;
    _updateUnifiedCountdownVoice();
    notifyListeners();
  }

  void _startUnifiedCarousel() {
    _unifiedCarouselTimer?.cancel();
    if (_unifiedEvents.length <= 1) return;
    _unifiedCarouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      nextUnified();
    });
  }

  /// 重建扁平化历史列表
  ///
  /// 根据过滤条件从各数据源桶中合并历史记录。
  void _rebuildFlat() {
    try {
      final merged = <QuakeMessage>[];
      final buckets = historyBySource;
      for (final entry in buckets.entries) {
        if (!_sourceFilter.contains(entry.key)) continue;
        final sourceType = _unifiedToQst[entry.key];
        final sourceThreshold = sourceType == null
            ? null
            : _sourceInfoMagFilters[sourceType];
        if (sourceThreshold != null && sourceThreshold < 0) continue;
        for (final e in entry.value) {
          if (sourceThreshold != null &&
              sourceThreshold > 0 &&
              e.magnitude < sourceThreshold) {
            continue;
          }
          if (_magFilter > 0 && e.magnitude < _magFilter) continue;
          merged.add(e);
        }
      }
      _dedupeJmaHistoryEvents(merged);
      merged.sort((a, b) {
        final utcA = _toUtc(a);
        final utcB = _toUtc(b);
        return utcB.compareTo(utcA);
      });
      if (merged.length > 100) merged.removeRange(100, merged.length);
      final signature = Object.hash(
        merged.length,
        Object.hashAll(
          merged.map(
            (item) => Object.hash(
              item.eventId,
              item.magnitude,
              item.originTime.millisecondsSinceEpoch,
              item.location,
            ),
          ),
        ),
      );
      if (signature == _flatHistorySignature) return;
      _flatHistorySignature = signature;
      _flatHistory = merged;
      _notifyHistorySlice();
    } catch (e) {
      print('_rebuildFlat error: $e');
    }
  }

  void _dedupeJmaHistoryEvents(List<QuakeMessage> items) {
    final seen = <String, int>{};
    var i = 0;
    while (i < items.length) {
      final key = _jmaHistoryDedupeKey(items[i]);
      if (key == null) {
        i++;
        continue;
      }
      final existingIndex = seen[key];
      if (existingIndex == null) {
        seen[key] = i;
        i++;
        continue;
      }
      final preferred = _preferJmaHistoryEvent(items[existingIndex], items[i]);
      items[existingIndex] = preferred;
      items.removeAt(i);
    }
  }

  String? _jmaHistoryDedupeKey(QuakeMessage event) {
    if (!_isJmaHistorySource(event.source)) return null;
    final location = event.location.trim().replaceAll(RegExp(r'\s+'), '');
    if (location.isEmpty) return null;
    final originMinute =
        _toUtc(event).millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final magnitude = (event.magnitude * 10).round();
    final depth = event.depth.round();
    return '$originMinute|$location|$magnitude|$depth';
  }

  bool _isJmaHistorySource(QuakeSourceType source) {
    return source == QuakeSourceType.wolfx ||
        source == QuakeSourceType.jma_fan ||
        source == QuakeSourceType.p2p;
  }

  QuakeMessage _preferJmaHistoryEvent(QuakeMessage a, QuakeMessage b) {
    final aReviewed = _isReviewedJmaHistoryEvent(a);
    final bReviewed = _isReviewedJmaHistoryEvent(b);
    if (aReviewed != bReviewed) return bReviewed ? b : a;
    final aReport = a.reportTime;
    final bReport = b.reportTime;
    if (aReport != null && bReport != null && bReport.isAfter(aReport)) {
      return b;
    }
    return a;
  }

  bool _isReviewedJmaHistoryEvent(QuakeMessage event) {
    final text =
        '${event.infoTypeName ?? ''} ${event.reviewType ?? ''} '
                '${event.reportNumText ?? ''} ${event.tsunamiWarning ?? ''}'
            .toLowerCase();
    return text.contains('reviewed') ||
        text.contains('confirmed') ||
        text.contains('正式') ||
        text.contains('確定') ||
        text.contains('已核实');
  }

  /// 将保存的来源墙上时间转换为 UTC，统一比较不同来源的事件。
  DateTime _toUtc(QuakeMessage event) {
    return QuakeTime.eventInstantUtc(event);
  }

  /// 判断是否为预警数据源
  ///
  /// 预警数据源提供紧急地震速报，需要优先显示和语音提醒。
  bool _isWarningSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
      case QuakeSourceType.cenc:
      case QuakeSourceType.sc_eew:
      case QuakeSourceType.fj_eew:
      case QuakeSourceType.cq_eew:
      case QuakeSourceType.cwa_eew:
      case QuakeSourceType.cea:
      case QuakeSourceType.cea_pr:
      case QuakeSourceType.jma_fan:
      case QuakeSourceType.sa:
      case QuakeSourceType.kma_eew_fan:
        return true;
      default:
        return false;
    }
  }

  /// 判断是否为信息事件数据源
  ///
  /// 信息事件数据源提供正式测定的地震信息。
  bool _isInfoEventSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.cenc:
      case QuakeSourceType.cencIr:
      case QuakeSourceType.usgs:
      case QuakeSourceType.cwa:
      case QuakeSourceType.fssn:
      case QuakeSourceType.fssnCmt:
      case QuakeSourceType.cencCmt:
      case QuakeSourceType.usgsCmt:
      case QuakeSourceType.p2p:
      case QuakeSourceType.hko:
      case QuakeSourceType.emsc:
      case QuakeSourceType.bcsf:
      case QuakeSourceType.gfz:
      case QuakeSourceType.usp:
      case QuakeSourceType.kma_eq:
      case QuakeSourceType.ningxia:
      case QuakeSourceType.guangxi:
      case QuakeSourceType.shanxi:
      case QuakeSourceType.beijing:
      case QuakeSourceType.yunnan:
      case QuakeSourceType.bmkg:
      case QuakeSourceType.geonet:
      case QuakeSourceType.tmd:
      case QuakeSourceType.ingv:
      case QuakeSourceType.nrcan:
      case QuakeSourceType.mmd:
      case QuakeSourceType.phivolcs:
      case QuakeSourceType.sgc:
      case QuakeSourceType.ga:
      case QuakeSourceType.cenais:
      case QuakeSourceType.unadapted:
        return true;
      default:
        return false;
    }
  }

  /// 处理新地震事件
  ///
  /// 从 EventBus 接收地震消息并进行处理。
  void _handleNewQuake(QuakeMessage event) async {
    try {
      await _handleNewQuakeInternal(event);
    } catch (e, stack) {
      final lines = stack.toString().split('\n');
      final short = lines.take(5).join('\n');
      print('_handleNewQuake error: $e\n$short');
    }
  }

  /// 处理新地震事件的内部实现
  ///
  /// 完整的事件处理流程：
  /// 1. 存入数据库
  /// 2. 计算距离和烈度
  /// 3. 更新预警/信息列表
  /// 4. 触发通知和语音
  Future<void> _handleNewQuakeInternal(QuakeMessage event) async {
    if (_isHandledByUnifiedPipeline(event)) {
      return;
    }

    try {
      await DatabaseHelper().insertQuake(event);
    } catch (e) {
      print('Database insert error: $e');
    }

    if (event.source == QuakeSourceType.cwa ||
        event.source == QuakeSourceType.cwa_eew) {
      debugPrint(
        'QuakeProvider: 收到CWA事件 source=${event.source} eventId=${event.eventId} isHistory=${event.isHistory} isInfoEvent=${event.isInfoEvent} mag=${event.magnitude}',
      );
    }

    if (_legacyActiveQuakePipelineDisabled) {
      _clearLegacyActiveQuakePipeline();
      if (event.isHistory ||
          event.isInfoEvent ||
          _isInfoEventSource(event.source)) {
        _routeToBucket(event);
        _rebuildFlat();
      }
      if (_unifiedEvents.isEmpty) {
        _currentEvent = null;
        onAllEventsExpired?.call();
      }
      notifyListeners();
      return;
    }

    if (event.isHistory) {
      _routeToBucket(event);
      _rebuildFlat();
      return;
    }

    // kanameishi: EEW 过期检查（旧管道安全网）
    // 对预警事件，检查是否已经过期，过期则直接入桶不显示预警卡片
    final bool isWarningForExpiry =
        _isWarningSource(event.source) && !event.isInfoEvent;
    if (isWarningForExpiry) {
      final elapsedSec = QuakeTime.calcPassedSeconds(event);
      final timeoutSec = QuakeTime.eewTimeoutSeconds(event);
      if (elapsedSec >= timeoutSec) {
        debugPrint(
          'QuakeProvider: EEW 已过期(旧管道)，入桶: eventId=${event.eventId} elapsed=${elapsedSec}s timeout=${timeoutSec}s',
        );
        _routeToBucket(event);
        _rebuildFlat();
        return;
      }
    }

    // 信息事件过期检查（旧管道安全网，与统一管道逻辑一致）
    final bool treatAsInfo = _isInfoEventSource(event.source);
    if (treatAsInfo && !_showStaleInfoEvent) {
      final reportTime = event.reportTime;
      if (reportTime != null) {
        final elapsedSec = QuakeTime.calcPassedSeconds(event);
        final dismissSec = _getDismissSecondsForInfo(event.magnitude);
        if (elapsedSec >= dismissSec) {
          debugPrint(
            'QuakeProvider: 信息事件已过期(旧管道)，入桶: eventId=${event.eventId} elapsed=${elapsedSec}s dismiss=${dismissSec}s',
          );
          _routeToBucket(event);
          _rebuildFlat();
          return;
        }
      }
    }

    // 信息事件源震级过滤：该源设了阈值且震级低于阈值则丢弃
    // 必须在 _routeToBucket 之前检查，防止低震级事件进入列表
    if (treatAsInfo) {
      final threshold = _sourceInfoMagFilters[event.source];
      if (threshold != null && threshold < 0) {
        debugPrint('QuakeProvider: 信息事件源已设为不接收，丢弃 ${event.source}');
        return;
      }
      if (threshold != null && threshold > 0 && event.magnitude < threshold) {
        debugPrint(
          'QuakeProvider: 信息事件震级过滤 [$threshold] 丢弃 ${event.source} M${event.magnitude}',
        );
        return;
      }
    }

    _routeToBucket(event);

    final userPos = LocationService().currentPosition;
    double distance = 0.0;
    if (userPos != null) {
      try {
        distance = QuakeCalculator.haversineDistance(
          userPos.latitude,
          userPos.longitude,
          event.latitude,
          event.longitude,
        );
      } catch (e) {
        print('Distance calculation error: $e');
        distance = 0.0;
      }
    }

    double intensity = 0.0;
    if (event.maxIntensity != null && event.maxIntensity! > 0) {
      intensity = event.maxIntensity!.toDouble();
    } else if (userPos != null) {
      try {
        intensity = IntensityCalculator.calculate(
          mag: event.magnitude,
          distance: distance,
        );
      } catch (e) {
        print('Intensity calculation error: $e');
        intensity = 0.0;
      }
    }

    QuakeMessage runtimeEvent = event;
    bool updatedExistingWarning = false;

    // 分发逻辑：isInfoEvent 覆盖优先
    // 某些源（如 cenc）可同时为预警源和情报源，靠 isInfoEvent 区分
    final bool treatAsWarning =
        _isWarningSource(event.source) && !event.isInfoEvent;

    if (_dismissedLegacyIds.contains(event.eventId)) {
      final changed = _purgeLegacyEventEntries(event.eventId);
      debugPrint('QuakeProvider: [旧管道] 事件已关闭，跳过: eventId=${event.eventId}');
      if (changed) {
        _reconcileLegacyDisplayAfterRemoval();
      }
      return;
    }

    if (treatAsWarning) {
      if (event.isCanceled) {
        // 取消报：标记并缩短过期时间
        final existingIndex = _activeWarnings.indexWhere(
          (w) => w.event.eventId == event.eventId,
        );
        if (existingIndex >= 0) {
          runtimeEvent = event.copyWith(
            originTime: _activeWarnings[existingIndex].event.originTime,
          );
          _activeWarnings[existingIndex].event = runtimeEvent;
          _activeWarnings[existingIndex].dismissTimer?.cancel();
          _activeWarnings[existingIndex].dismissTimer = Timer(
            Duration(seconds: 20),
            () {
              _removeWarning(existingIndex);
            },
          );
          updatedExistingWarning = true;
        }
      } else {
        final existingIndex = _activeWarnings.indexWhere(
          (w) => w.event.eventId == event.eventId,
        );
        if (existingIndex >= 0) {
          updatedExistingWarning = true;
          final preservedOrigin =
              _activeWarnings[existingIndex].event.originTime;
          runtimeEvent = event.copyWith(originTime: preservedOrigin);
          _activeWarnings[existingIndex].update(
            runtimeEvent,
            distance,
            intensity,
          );
          _resetWarningDismiss(existingIndex);
        } else {
          // kanameishi: 计算剩余显示时间
          // 用 QuakeTime.calcPassedSeconds 正确处理时区
          final elapsedSec = QuakeTime.calcPassedSeconds(event);
          final totalTimeout = QuakeTime.eewTimeoutSeconds(event);
          final remaining = (totalTimeout - elapsedSec).clamp(1, totalTimeout);
          final warning = ActiveWarning(
            event: event,
            distance: distance,
            estimatedIntensity: intensity,
            remainingSeconds: elapsedSec > 0 ? remaining : null,
          );
          _activeWarnings.insert(0, warning);
          _currentWarningIndex = 0;
          _isShowingInfoEvent = false;
          _setupWarningDismiss(warning, 0);
          _startCarousel();
        }
      }
    } else if (treatAsInfo) {
      final existingIndex = _activeInfoEvents.indexWhere(
        (i) => i.event.eventId == event.eventId,
      );
      if (existingIndex >= 0) {
        final old = _activeInfoEvents[existingIndex];
        final preservedOrigin = old.event.originTime;
        runtimeEvent = event.copyWith(
          originTime: preservedOrigin,
          // 保留旧事件中的 reportNumText（FAN cenc 不设它，但 jma_fan 会设）
          reportNumText: old.event.reportNumText,
        );
      }
      final infoEvent = ActiveInfoEvent(
        event: runtimeEvent,
        distance: distance,
        estimatedIntensity: intensity,
        receivedAt: DateTime.now(),
      );
      if (existingIndex >= 0) {
        _activeInfoEvents[existingIndex] = infoEvent;
      } else {
        _activeInfoEvents.insert(0, infoEvent);
      }
      _sortInfoEvents();

      if (_activeWarnings.isNotEmpty) {
        _showTempInfoEvent(infoEvent);
      } else {
        _isShowingInfoEvent = true;
        _startCarousel();
        _startInfoDismissTimer();
      }
    }

    final bool isSameCurrentEvent =
        _currentEvent?.eventId == runtimeEvent.eventId;
    _currentEvent = runtimeEvent;
    _currentDistance = distance;
    _estimatedIntensity = intensity;
    if (!isSameCurrentEvent) {
      _lastSpokenSeconds = -1;
    }

    try {
      await DatabaseHelper().insertQuake(event);
    } catch (e) {
      print('Database insert error (2nd): $e');
    }

    if (!kIsWeb && Platform.isWindows) _handleWindowsAlert(event);

    if (!isSameCurrentEvent || !updatedExistingWarning) {
      _countdownTimer?.cancel();
      _updateCountdownLogic();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _updateCountdownLogic();
      });
    }

    notifyListeners();
  }

  /// 启动轮播定时器
  ///
  /// 当有多个活动事件时，自动轮播显示。
  void _startCarousel() {
    _carouselTimer?.cancel();
    final total =
        _activeWarnings.length +
        (_isShowingInfoEvent ? _activeInfoEvents.length : 0);
    if (total <= 1) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      try {
        if (_activeWarnings.isNotEmpty) {
          _currentWarningIndex =
              (_currentWarningIndex + 1) % _activeWarnings.length;
          final warning = _activeWarnings[_currentWarningIndex];
          _currentEvent = warning.event;
          _currentDistance = warning.distance;
          _estimatedIntensity = warning.estimatedIntensity;
          _lastSpokenSeconds = warning.lastSpokenSeconds;
        } else if (_activeInfoEvents.isNotEmpty) {
          _currentWarningIndex =
              (_currentWarningIndex + 1) % _activeInfoEvents.length;
          final info = _activeInfoEvents[_currentWarningIndex];
          _currentEvent = info.event;
          _currentDistance = info.distance;
          _estimatedIntensity = info.estimatedIntensity;
          _lastSpokenSeconds = -1;
        }
        notifyListeners();
      } catch (e) {
        print('Carousel timer error: $e');
      }
    });
  }

  /// 临时显示信息事件
  ///
  /// 当有预警事件时收到信息事件，临时显示5秒后切回预警。
  void _showTempInfoEvent(ActiveInfoEvent infoEvent) {
    _tempInfoDisplayTimer?.cancel();
    _isShowingTempInfo = true;
    _currentEvent = infoEvent.event;
    _currentDistance = infoEvent.distance;
    _estimatedIntensity = infoEvent.estimatedIntensity;
    notifyListeners();

    _tempInfoDisplayTimer = Timer(
      Duration(seconds: _tempInfoDisplayDuration),
      () {
        _isShowingTempInfo = false;
        if (_activeWarnings.isNotEmpty) {
          _currentWarningIndex = _currentWarningIndex.clamp(
            0,
            _activeWarnings.length - 1,
          );
          _switchToWarning(_currentWarningIndex);
        } else if (_activeInfoEvents.isNotEmpty) {
          _isShowingInfoEvent = true;
          _switchToInfoEvent(0);
        } else {
          _currentEvent = null;
          onAllEventsExpired?.call();
        }
        notifyListeners();
      },
    );
  }

  /// 启动信息事件自动关闭定时器
  ///
  /// 信息事件在指定时间后自动关闭。
  void _startInfoDismissTimer() {
    _infoDismissTimer?.cancel();
    _infoDismissTimer = Timer(Duration(seconds: _infoDismissDuration), () {
      if (_activeInfoEvents.isNotEmpty) {
        final dismissed = _activeInfoEvents.removeAt(0);
        _dismissedLegacyIds.add(dismissed.event.eventId);
        if (_dismissedLegacyIds.length > 200) {
          _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
        }
        if (_activeInfoEvents.isEmpty) {
          _isShowingInfoEvent = false;
          _currentEvent = null;
          onAllEventsExpired?.call();
        } else {
          _currentEvent = _activeInfoEvents[0].event;
          _currentDistance = _activeInfoEvents[0].distance;
          _estimatedIntensity = _activeInfoEvents[0].estimatedIntensity;
        }
        notifyListeners();
      }
    });
  }

  /// 对信息事件进行排序
  ///
  /// 优先显示本地区域的事件，并优先使用官方数据源。
  void _sortInfoEvents() {
    _activeInfoEvents.sort((a, b) {
      final aLat = a.event.latitude;
      final aLon = a.event.longitude;
      final bLat = b.event.latitude;
      final bLon = b.event.longitude;

      final aInChina = _isInChina(aLat, aLon);
      final bInChina = _isInChina(bLat, bLon);
      final aInJapan = _isInJapan(aLat, aLon);
      final bInJapan = _isInJapan(bLat, bLon);
      final aInTaiwan = _isInTaiwan(aLat, aLon);
      final bInTaiwan = _isInTaiwan(bLat, bLon);

      final aIsPreferred =
          (aInChina && a.event.source == QuakeSourceType.cenc) ||
          (aInJapan && a.event.source == QuakeSourceType.wolfx) ||
          (aInTaiwan && a.event.source == QuakeSourceType.cwa);
      final bIsPreferred =
          (bInChina && b.event.source == QuakeSourceType.cenc) ||
          (bInJapan && b.event.source == QuakeSourceType.wolfx) ||
          (bInTaiwan && b.event.source == QuakeSourceType.cwa);

      if (aIsPreferred && !bIsPreferred) return -1;
      if (!aIsPreferred && bIsPreferred) return 1;

      if (aInChina && !bInChina) return -1;
      if (!aInChina && bInChina) return 1;
      if (aInJapan && !bInJapan) return -1;
      if (!aInJapan && bInJapan) return 1;
      if (aInTaiwan && !bInTaiwan) return -1;
      if (!aInTaiwan && bInTaiwan) return 1;

      return b.receivedAt.compareTo(a.receivedAt);
    });
  }

  /// 判断坐标是否在中国境内
  bool _isInChina(double lat, double lon) {
    return lat >= 18.0 && lat <= 54.0 && lon >= 73.0 && lon <= 135.0;
  }

  /// 判断坐标是否在日本境内
  bool _isInJapan(double lat, double lon) {
    return lat >= 24.0 && lat <= 46.0 && lon >= 122.0 && lon <= 146.0;
  }

  /// 判断坐标是否在台湾境内
  bool _isInTaiwan(double lat, double lon) {
    return lat >= 21.0 && lat <= 26.0 && lon >= 119.0 && lon <= 122.0;
  }

  /// 切换到下一个预警/信息事件
  void nextWarning() {
    if (_legacyActiveQuakePipelineDisabled) return;
    if (_activeWarnings.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex + 1) % _activeWarnings.length;
      _switchToWarning(_currentWarningIndex);
    } else if (_activeInfoEvents.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex + 1) % _activeInfoEvents.length;
      _switchToInfoEvent(_currentWarningIndex);
    }
  }

  /// 切换到上一个预警/信息事件
  void prevWarning() {
    if (_legacyActiveQuakePipelineDisabled) return;
    if (_activeWarnings.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex - 1 + _activeWarnings.length) %
          _activeWarnings.length;
      _switchToWarning(_currentWarningIndex);
    } else if (_activeInfoEvents.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex - 1 + _activeInfoEvents.length) %
          _activeInfoEvents.length;
      _switchToInfoEvent(_currentWarningIndex);
    }
  }

  /// 切换到指定索引的预警事件
  void _switchToWarning(int index) {
    if (_legacyActiveQuakePipelineDisabled) return;
    final warning = _activeWarnings[index];
    _currentEvent = warning.event;
    _currentDistance = warning.distance;
    _estimatedIntensity = warning.estimatedIntensity;
    _lastSpokenSeconds = warning.lastSpokenSeconds;
    final (p, s) = _computeCountdown();
    _pCountdown = p;
    _sCountdown = s;
    _isShowingInfoEvent = false;
    _startCarousel();
    notifyListeners();
  }

  /// 切换到指定索引的信息事件
  void _switchToInfoEvent(int index) {
    if (_legacyActiveQuakePipelineDisabled) return;
    final info = _activeInfoEvents[index];
    _currentEvent = info.event;
    _currentDistance = info.distance;
    _estimatedIntensity = info.estimatedIntensity;
    _lastSpokenSeconds = -1;
    _pCountdown = -1;
    _sCountdown = -1;
    _isShowingInfoEvent = true;
    _startCarousel();
    notifyListeners();
  }

  /// 关闭指定的预警事件
  bool _purgeLegacyEventEntries(String eventId) {
    if (_legacyActiveQuakePipelineDisabled) return false;
    var changed = false;
    _activeWarnings.removeWhere((w) {
      if (w.event.eventId != eventId) return false;
      w.dismissTimer?.cancel();
      changed = true;
      return true;
    });
    _activeInfoEvents.removeWhere((i) {
      if (i.event.eventId != eventId) return false;
      changed = true;
      return true;
    });
    if (_currentEvent?.eventId == eventId) {
      changed = true;
    }
    return changed;
  }

  void _reconcileLegacyDisplayAfterRemoval() {
    if (_legacyActiveQuakePipelineDisabled) {
      _clearLegacyActiveQuakePipeline();
      notifyListeners();
      return;
    }
    if (_activeWarnings.isEmpty && _activeInfoEvents.isEmpty) {
      _currentEvent = null;
      _currentDistance = 0;
      _estimatedIntensity = 0;
      _lastSpokenSeconds = -1;
      _carouselTimer?.cancel();
      _countdownTimer?.cancel();
      _tempInfoDisplayTimer?.cancel();
      _isShowingTempInfo = false;
      _isShowingInfoEvent = false;
      onAllEventsExpired?.call();
      notifyListeners();
      return;
    }

    if (_activeWarnings.isNotEmpty) {
      _currentWarningIndex = _currentWarningIndex.clamp(
        0,
        _activeWarnings.length - 1,
      );
      _switchToWarning(_currentWarningIndex);
      return;
    }

    _currentWarningIndex = _currentWarningIndex.clamp(
      0,
      _activeInfoEvents.length - 1,
    );
    _switchToInfoEvent(_currentWarningIndex);
  }

  void dismissWarning(String eventId) {
    if (_legacyActiveQuakePipelineDisabled) return;
    _activeWarnings.removeWhere((w) => w.event.eventId == eventId);
    _dismissedLegacyIds.add(eventId);
    if (_dismissedLegacyIds.length > 200) {
      _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
    }
    if (_activeWarnings.isEmpty) {
      _carouselTimer?.cancel();
      if (_activeInfoEvents.isNotEmpty) {
        _isShowingInfoEvent = true;
        _currentWarningIndex = 0;
        _switchToInfoEvent(0);
      } else {
        _currentEvent = null;
        _countdownTimer?.cancel();
        onAllEventsExpired?.call();
      }
    } else {
      _currentWarningIndex = _currentWarningIndex.clamp(
        0,
        _activeWarnings.length - 1,
      );
      _switchToWarning(_currentWarningIndex);
    }
    notifyListeners();
  }

  /// 关闭指定的信息事件
  void dismissInfoEvent(String eventId) {
    if (_legacyActiveQuakePipelineDisabled) return;
    _activeInfoEvents.removeWhere((i) => i.event.eventId == eventId);
    _dismissedLegacyIds.add(eventId);
    if (_dismissedLegacyIds.length > 200) {
      _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
    }
    if (_activeInfoEvents.isEmpty && _activeWarnings.isEmpty) {
      _currentEvent = null;
      _carouselTimer?.cancel();
      _countdownTimer?.cancel();
      onAllEventsExpired?.call();
    } else if (_isShowingInfoEvent && _activeInfoEvents.isNotEmpty) {
      _currentWarningIndex = _currentWarningIndex.clamp(
        0,
        _activeInfoEvents.length - 1,
      );
      _switchToInfoEvent(_currentWarningIndex);
    }
    notifyListeners();
  }

  String _cencIrDataId(CencIrData data) {
    return data.reportId.isNotEmpty ? data.reportId : data.uniEventId;
  }

  void _updateRealtimeCencIrData(
    CencIrData data, {
    bool requireUnifiedEvent = false,
  }) {
    _realtimeCencIrData = _mergeCencIrData(_realtimeCencIrData, data);
    notifyListeners();
    if (!requireUnifiedEvent) return;

    Timer.run(() {
      if (_disposed) return;
      final current = _realtimeCencIrData;
      if (current == null || !_isSameCencIrEvent(current, data)) return;
      if (_hasUnifiedCencIrEvent(data)) return;
      _realtimeCencIrData = null;
      notifyListeners();
    });
  }

  bool _hasUnifiedCencIrEvent(CencIrData data) {
    final reportId = data.reportId.trim();
    final uniEventId = data.uniEventId.trim();
    return _unifiedEvents.any((event) {
      if (event.source != 'nowQuakeCencIr') return false;
      final eventId = event.eventId.trim();
      return eventId.isNotEmpty &&
          (eventId == reportId || eventId == uniEventId);
    });
  }

  void _updateManualCencIrData(CencIrData data) {
    _manualCencIrData = _mergeCencIrData(_manualCencIrData, data);
    _isManualCencIrActive = true;
    notifyListeners();
  }

  @visibleForTesting
  void updateRealtimeCencIrDataForTest(
    CencIrData data, {
    bool requireUnifiedEvent = false,
  }) {
    _updateRealtimeCencIrData(data, requireUnifiedEvent: requireUnifiedEvent);
  }

  @visibleForTesting
  void updateManualCencIrDataForTest(CencIrData data) {
    _updateManualCencIrData(data);
  }

  /// 合并新旧 CENC 烈度速报数据，保留较新的字段
  CencIrData _mergeCencIrData(CencIrData? current, CencIrData data) {
    if (current == null || !_isSameCencIrEvent(current, data)) {
      return data;
    }
    final latest = data.gmtCreate.isBefore(current.gmtCreate) ? current : data;
    return CencIrData(
      reportId: latest.reportId.isNotEmpty ? latest.reportId : current.reportId,
      uniEventId: latest.uniEventId.isNotEmpty
          ? latest.uniEventId
          : current.uniEventId,
      oriTime: latest.oriTime,
      gmtCreate: latest.gmtCreate,
      locName: latest.locName.isNotEmpty ? latest.locName : current.locName,
      epiLon: latest.epiLon != 0 ? latest.epiLon : current.epiLon,
      epiLat: latest.epiLat != 0 ? latest.epiLat : current.epiLat,
      focDepth: latest.focDepth != 0 ? latest.focDepth : current.focDepth,
      subjectCodes: latest.subjectCodes.isNotEmpty
          ? latest.subjectCodes
          : current.subjectCodes,
      intensityInfoText: latest.intensityInfoText.isNotEmpty
          ? latest.intensityInfoText
          : current.intensityInfoText,
      contourGeojson: latest.contourGeojson ?? current.contourGeojson,
      instrumentIntensities: latest.instrumentIntensities.isNotEmpty
          ? latest.instrumentIntensities
          : current.instrumentIntensities,
      source: latest.source,
    );
  }

  bool _isSameCencIrEvent(CencIrData a, CencIrData b) {
    if (a.reportId.isNotEmpty && a.reportId == b.reportId) return true;
    if (a.uniEventId.isNotEmpty && a.uniEventId == b.uniEventId) return true;
    return a.oriTime.difference(b.oriTime).abs() <= const Duration(seconds: 1);
  }

  List<Map<String, dynamic>> _tagCencIrList(
    List<Map<String, dynamic>> list,
    String source,
  ) {
    return [
      for (final item in list) <String, dynamic>{...item, '_source': source},
    ];
  }

  void _rebuildCencIrList() {
    final selected = _shouldUseNowQuakeList
        ? _nowQuakeCencIrList
        : _fanCencIrList;
    _cencIrList = selected.map(Map<String, dynamic>.from).toList()
      ..sort((a, b) => _cencIrListTime(b).compareTo(_cencIrListTime(a)));
    notifyListeners();
  }

  bool get _shouldUseNowQuakeRealtime {
    return SourceManager().isSourceEnabled('NowQuake') &&
        _sourceStatuses['NowQuake'] == SourceStatus.connected;
  }

  bool get _shouldUseNowQuakeList {
    return _shouldUseNowQuakeRealtime && _nowQuakeCencIrList.isNotEmpty;
  }

  void _syncFanCencIrFallbackRequests() {
    final fanService = SourceManager().getSource<FanService>();
    if (fanService == null) return;

    final manager = SourceManager();
    final nowQuakeEnabled = manager.isSourceEnabled('NowQuake');
    final nowQuakeStatus = _sourceStatuses['NowQuake'];
    final nowQuake = manager.getSource<NowQuakeCencIntensityService>();
    final nowQuakeListUnavailable =
        nowQuakeStatus == SourceStatus.connected &&
        (nowQuake?.hasCompletedListRequest ?? false) &&
        !(nowQuake?.hasUsableList ?? false);
    final useFanFallback =
        !nowQuakeEnabled ||
        nowQuakeStatus == SourceStatus.disconnected ||
        nowQuakeStatus == SourceStatus.error ||
        nowQuakeListUnavailable;
    fanService.setCencIrRequestsEnabled(useFanFallback);
  }

  String _cencIrListTime(Map<String, dynamic> item) {
    return item['oriTime']?.toString() ?? item['shockTime']?.toString() ?? '';
  }

  /// 手动请求 CENC 烈度速报详情
  ///
  /// 根据事件 [id] 发送 cencirdetail 请求，
  /// 获取完整烈度数据并在地图上显示。
  void requestCencIrDetail(String id, {String? source}) {
    unawaited(_requestCencIrDetail(id, source: source));
  }

  Future<void> _requestCencIrDetail(String id, {String? source}) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return;
    final requestSerial = ++_manualCencIrRequestSerial;
    _pendingManualCencIrId = normalizedId;
    final fanService = SourceManager().getSource<FanService>();
    final nowQuake = SourceManager().getSource<NowQuakeCencIntensityService>();

    final shouldTryNowQuake =
        source == 'nowquake' || (source != 'fan' && _shouldUseNowQuakeRealtime);
    if (shouldTryNowQuake && nowQuake != null) {
      final detail = await nowQuake.requestDetail(normalizedId);
      if (requestSerial != _manualCencIrRequestSerial ||
          _pendingManualCencIrId != normalizedId) {
        return;
      }
      if (detail != null) {
        _pendingManualCencIrId = null;
        _updateManualCencIrData(detail);
        return;
      }
    }

    if (fanService == null || !SourceManager().isSourceEnabled('FAN')) {
      if (_pendingManualCencIrId == normalizedId) {
        _pendingManualCencIrId = null;
      }
      return;
    }
    _fanCencIrDetailFallbackIds.add(normalizedId);
    fanService.requestCencIrDetail(normalizedId);
  }

  /// 清除当前地图上的 CENC 烈度速报数据
  ///
  /// 如果当前显示的是手动选择的数据，则切回实时数据；否则清除实时数据。
  void clearCencIrData() {
    _manualCencIrRequestSerial++;
    _pendingManualCencIrId = null;
    _fanCencIrDetailFallbackIds.clear();
    if (_isManualCencIrActive) {
      _manualCencIrData = null;
      _isManualCencIrActive = false;
    } else {
      _realtimeCencIrData = null;
    }
    notifyListeners();
  }

  /// 处理 Windows 平台的预警窗口
  void _handleWindowsAlert(QuakeMessage event) async {
    try {
      if (_estimatedIntensity >= 2.0 || event.magnitude >= 4.5) {
        await WindowsManager().forceShowAlert();
      }
    } catch (e) {
      print('_handleWindowsAlert error: $e');
    }
  }

  /// 将事件路由到对应的数据桶
  void _routeToBucket(QuakeMessage event) {
    try {
      switch (event.source) {
        case QuakeSourceType.fssn:
          _eqlist.addFssnItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.kma_eq:
          _eqlist.addKmaItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.kma_eew_fan:
          // KMA EEW 不上列表，仅作为预警卡片显示
          break;
        case QuakeSourceType.cwa:
          _eqlist.addCwaItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.cwa_eew:
          // CWA EEW 不上列表，仅作为预警卡片显示
          break;
        case QuakeSourceType.cenc:
          _eqlist.addCencItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.cea:
        case QuakeSourceType.cea_pr:
        case QuakeSourceType.hko:
        case QuakeSourceType.emsc:
        case QuakeSourceType.bcsf:
        case QuakeSourceType.gfz:
        case QuakeSourceType.usp:
        case QuakeSourceType.ningxia:
        case QuakeSourceType.guangxi:
        case QuakeSourceType.shanxi:
        case QuakeSourceType.beijing:
        case QuakeSourceType.yunnan:
          // 不上列表，仅作为信息事件卡片显示
          break;
        default:
          break;
      }
    } catch (e) {
      print('_routeToBucket error: $e');
    }
  }

  /// 计算当前事件的 P/S 波到达倒计时
  ///
  /// 参考 kanameishi：距离 <= 2000 km 使用 jma2001 走时表，
  /// 更远距离使用 jb 走时表；分别计算 P 波和 S 波到达时间。
  (int pCountdown, int sCountdown) _computeCountdown() {
    if (_currentEvent == null || _currentDistance <= 0) return (-1, -1);

    final tts = TravelTimeService();
    if (!tts.isLoaded) return (-1, -1);

    final tableName = _currentDistance <= 2000 ? 'jma2001' : 'jb';
    final normalizedOrigin = QuakeTime.normalizedOriginLocal(_currentEvent!);
    final elapsed = QuakeCalculator.getElapsedSeconds(
      normalizedOrigin,
      NtpService().now,
    );

    final pReachTime = tts.calcReachTime(
      tableName,
      true,
      _currentEvent!.depth,
      _currentDistance,
    );
    final sReachTime = tts.calcReachTime(
      tableName,
      false,
      _currentEvent!.depth,
      _currentDistance,
    );

    final pCountdown = pReachTime > 0
        ? math.max((pReachTime - elapsed).floor(), 0)
        : -1;
    final sCountdown = sReachTime > 0
        ? math.max((sReachTime - elapsed).floor(), 0)
        : -1;

    return (pCountdown, sCountdown);
  }

  /// 更新倒计时逻辑
  ///
  /// 每秒执行一次，计算地震波到达倒计时并触发语音提醒。
  void _updateCountdownLogic() {
    try {
      if (_currentEvent == null) return;

      _cleanExpiredWarnings();

      if (_isShowingInfoEvent && _activeWarnings.isEmpty) {
        notifyListeners();
        return;
      }

      final (pCountdown, sCountdown) = _computeCountdown();
      _pCountdown = pCountdown;
      _sCountdown = sCountdown;

      // 语音倒计时仍基于原简化逻辑，避免与现有 TTS 播报策略耦合。
      final double sArrival = _currentDistance / 3.5;
      final normalizedOrigin = QuakeTime.normalizedOriginLocal(_currentEvent!);
      final double elapsed = QuakeCalculator.getElapsedSeconds(
        normalizedOrigin,
        NtpService().now,
      );
      final int voiceCountdown = (sArrival - elapsed).floor();
      _triggerVoiceAlert(voiceCountdown);

      if (_sCountdown < -60) {
        _countdownTimer?.cancel();
        if (!kIsWeb && Platform.isWindows) {
          try {
            WindowsManager().resetWindowState();
          } catch (_) {}
        }
      }
      notifyListeners();
    } catch (e) {
      print('_updateCountdownLogic error: $e');
    }
  }

  /// 清理过期的预警和信息事件
  void _cleanExpiredWarnings() {
    try {
      final now = NtpService().now;
      _activeWarnings.removeWhere((w) {
        if (w.dismissTimer?.isActive == true) return false;
        final elapsed = now
            .toUtc()
            .difference(QuakeTime.eventInstantUtc(w.event))
            .inSeconds
            .abs();
        final expired = elapsed > w.timeoutSeconds + 60;
        if (expired) {
          _dismissedLegacyIds.add(w.event.eventId);
        }
        return expired;
      });
      _activeInfoEvents.removeWhere((i) {
        final elapsed = now.difference(i.receivedAt).inSeconds;
        final expired = elapsed > 300;
        if (expired) {
          _dismissedLegacyIds.add(i.event.eventId);
        }
        return expired;
      });
      if (_dismissedLegacyIds.length > 200) {
        _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
      }
      if (_activeWarnings.isEmpty && _activeInfoEvents.isEmpty) {
        _currentEvent = null;
        _pCountdown = -1;
        _sCountdown = -1;
        _carouselTimer?.cancel();
        _countdownTimer?.cancel();
        _tempInfoDisplayTimer?.cancel();
        _isShowingTempInfo = false;
        _isShowingInfoEvent = false;
        onAllEventsExpired?.call();
      } else if (_activeWarnings.isNotEmpty) {
        if (_currentWarningIndex >= _activeWarnings.length) {
          _currentWarningIndex = 0;
          _switchToWarning(0);
        }
      } else if (_activeInfoEvents.isNotEmpty) {
        if (_currentWarningIndex >= _activeInfoEvents.length) {
          _currentWarningIndex = 0;
          _switchToInfoEvent(0);
        }
      }
    } catch (e) {
      print('_cleanExpiredWarnings error: $e');
    }
  }

  /// 设置预警自动移除定时器
  ///
  /// 参考 kanameishi 的 terminate 策略。
  void _setupWarningDismiss(ActiveWarning warning, int index) {
    warning.dismissTimer?.cancel();
    final int dismissSec = warning.remainingSeconds ?? warning.timeoutSeconds;
    warning.dismissTimer = Timer(Duration(seconds: dismissSec), () {
      _removeWarning(index);
    });
  }

  /// 重置预警自动移除定时器
  ///
  /// 事件更新时重置定时器，延长显示时间。
  void _resetWarningDismiss(int index) {
    if (index >= 0 && index < _activeWarnings.length) {
      _setupWarningDismiss(_activeWarnings[index], index);
    }
  }

  /// 移除预警
  ///
  /// 从活动预警列表中移除并清理资源。
  void _removeWarning(int index) {
    if (index >= 0 && index < _activeWarnings.length) {
      final removed = _activeWarnings[index];
      _dismissedLegacyIds.add(removed.event.eventId);
      if (_dismissedLegacyIds.length > 200) {
        _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
      }
      _activeWarnings[index].dismissTimer?.cancel();
      _activeWarnings.removeAt(index);
      if (_activeWarnings.isEmpty) {
        _carouselTimer?.cancel();
        _currentWarningIndex = 0;
        _isShowingTempInfo = false;
        if (_activeInfoEvents.isNotEmpty) {
          _isShowingInfoEvent = true;
          _switchToInfoEvent(0);
        } else {
          _currentEvent = null;
          _pCountdown = -1;
          _sCountdown = -1;
          onAllEventsExpired?.call();
        }
      } else {
        if (_currentWarningIndex >= _activeWarnings.length) {
          _currentWarningIndex = 0;
        }
        final warning = _activeWarnings[_currentWarningIndex];
        _currentEvent = warning.event;
        _currentDistance = warning.distance;
        _estimatedIntensity = warning.estimatedIntensity;
      }
      notifyListeners();
    }
  }

  /// 触发语音警报
  ///
  /// 根据倒计时播报相应的语音提醒。
  void _triggerVoiceAlert(int countdown) {
    try {
      if (_currentEvent == null) return;
      if (_lastSpokenSeconds == -1 && countdown > 0) {
        final text = AlertVoiceHelper.generateLegacyAlertText(
          _currentEvent!,
          countdown,
          _estimatedIntensity,
        );
        TtsService().speakEvent(
          text,
          dedupeKey: 'legacy:${_currentEvent!.eventId}:initial',
          isUpdate: false,
          delay: const Duration(milliseconds: 900),
        );
        _lastSpokenSeconds = countdown;
        return;
      }
      if (countdown <= 10 && countdown > 0 && countdown != _lastSpokenSeconds) {
        TtsService().speakCountdown(_currentEvent!.eventId, countdown);
        _lastSpokenSeconds = countdown;
      } else if (countdown == 0 && _lastSpokenSeconds != 0) {
        TtsService().speakArrival(_currentEvent!.eventId);
        _lastSpokenSeconds = 0;
      }
    } catch (e) {
      print('_triggerVoiceAlert error: $e');
    }
  }

  /// 释放资源
  @override
  void dispose() {
    _disposed = true;
    _eewHistoryPersistTimer?.cancel();
    _eewHistoryPersistTimer = null;
    _queuePersistEewHistory();
    _backgroundSeenStatePersistTimer?.cancel();
    _backgroundSeenStatePersistTimer = null;
    _unifiedUiPublishTimer?.cancel();
    _unifiedUiPublishTimer = null;
    for (final timer in _unifiedUpdateEffectTimers.values) {
      timer.cancel();
    }
    _unifiedUpdateEffectTimers.clear();
    _pendingUnifiedUpdateEffects.clear();
    _eqlistStartTimer?.cancel();
    _eqlistStartTimer = null;
    _eqlist.onAnyUpdated = null;
    _eqlist.onUsgsCurrentUpdated = null;
    _eqlist.onEmscCurrentUpdated = null;
    _eqlist.onCwaCurrentUpdated = null;
    _eqlist.onHttpStatusChanged = null;
    _eqlist.onCmtStatusChanged = null;
    _eqlist.cencCmt.onListUpdated = null;
    _eqlist.usgsCmt.onListUpdated = null;
    _eqlist.jmaCmt.onListUpdated = null;
    _eqlist.fnetCmt.onListUpdated = null;
    _eqlist.hinetAquaCmt.onListUpdated = null;
    _eqlist.stop();
    _countdownTimer?.cancel();
    _carouselTimer?.cancel();
    _tempInfoDisplayTimer?.cancel();
    _infoDismissTimer?.cancel();
    for (final timer in _unifiedDismissTimers.values) {
      timer.cancel();
    }
    _unifiedDismissTimers.clear();
    _unifiedCarouselTimer?.cancel();
    _unifiedCountdownVoiceTimer?.cancel();
    _unifiedCountdownVoiceTimer = null;
    _unifiedCountdownLastSpokenSeconds.clear();
    _weatherAlarmExpiryTimer?.cancel();
    _weatherAlarmExpiryTimer = null;
    for (final sub in _unifiedSubscriptions) {
      sub.cancel();
    }
    _eventBusSubscription?.cancel();
    _sourceStatusSubscription?.cancel();
    BackgroundService().connectionHostingNotifier.removeListener(
      _syncChinaWeatherMode,
    );
    _chinaWeatherService.stop();
    _typhoonService.stop();
    sourceStatusListenable.dispose();
    weatherListenable.dispose();
    typhoonListenable.dispose();
    historyListenable.dispose();
    super.dispose();
  }
}
