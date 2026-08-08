import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/map_state_provider.dart';
import '../providers/quake_provider.dart';
import '../providers/notification_settings_provider.dart';
import '../services/notification_service.dart';
import '../widgets/map/quake_map_view.dart';
import '../widgets/ui/in_app_notification_overlay.dart';
import '../widgets/map/source_dashboard.dart';
import '../widgets/ui/alert_module.dart';
import '../widgets/ui/eqlist_panel.dart';
import '../widgets/ui/history_panel.dart';
import '../widgets/ui/top_status_bar.dart';
import '../widgets/ui/weather_marquee.dart';
import '../widgets/ui/settings_page.dart';
import '../widgets/ui/station_dashboard.dart';
import '../widgets/ui/cmt_sidebar_panel.dart';
import '../widgets/ui/volcano_sidebar_panel.dart';
import '../widgets/ui/ui_runtime_flags.dart';
import '../widgets/ui/ui_scale.dart';
import '../widgets/ui/app_page_background.dart';
import '../core/source_estimation/source_estimation_models.dart';
import '../core/source_estimation/station_event_tracker.dart';
import '../services/sources/shake_detection_service.dart';
import '../services/sources/global_quake_service.dart';
import '../services/sources/cma_local_weather_service.dart';
import '../services/location_service.dart';
import '../widgets/map/ka_shindo_marker_style.dart';
import '../models/tsunami_message.dart';
import '../models/quake_message.dart';
import '../models/unified_quake_data.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  NotificationService? _notificationService;

  StationSummaryData _stationData = StationSummaryData();
  final ValueNotifier<StationSummaryData> _stationDataNotifier =
      ValueNotifier<StationSummaryData>(StationSummaryData());
  final CmaLocalWeatherService _cmaWeatherService = CmaLocalWeatherService();
  CmaLocalWeatherState _cmaWeatherState = const CmaLocalWeatherState();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showInfoDrawer = true;
  bool _cmaWeatherLayoutEnabled = false;
  bool _sideInfoSettingLoaded = false;
  bool _phoneActionsExpanded = false;
  bool _sideInfoAutoShowBeta = true;
  String? _lastAutoTriggerSignature;
  String _lastNiedInfoSignature = '-';
  String _lastSnetInfoSignature = '-';
  String _lastJmaTsunamiInfoSignature = '-';
  String _lastNmefcTsunamiInfoSignature = '-';
  String _lastCmtInfoSignature = '-';
  String _lastVolcanoInfoSignature = '-';
  String? _pendingInfoPageKey;
  int _infoPageIndex = 0;
  Timer? _infoPageCarousel;
  List<String> _lastInfoPageKeys = const [];
  String _lastInfoPageKeysSignature = '';
  int _niedDetectPageIndex = 0;
  int _niedDetectPageCount = 0;
  String _niedDetectPageSignature = '';
  Timer? _niedDetectPageCarousel;
  String _lastStationDataUiSignature = '';

  static const double _refWidth = 1700.0;
  static const double _stationPanelVisualHeight = 104.0;
  static const double _infoPanelHeight = 186.0;
  static const double _stationPanelWidth = 234.0;
  static const double _rightActionButtonSize = 52.0;
  static const double _rightActionButtonGap = 12.0;
  static const double _rightActionButtonBottom = 30.0;
  static const double _rightInfoPanelButtonGap = 10.0;
  static const int _rightActionButtonCount = 4;
  static const String _sideInfoAutoShowBetaKey = 'side_info_auto_show_beta';
  static const String _infoPageNied = 'nied';
  static const String _infoPageSnet = 'snet';
  static const String _infoPageJmaTsunami = 'jmaTsunami';
  static const String _infoPageNmefcTsunami = 'nmefcTsunami';
  static const String _infoPageCmt = 'cmt';
  static const String _infoPageVolcano = 'volcano';

  double _scale(BuildContext c) {
    return UiScale.factor(c, refWidth: _refWidth, min: 0.55);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  double _sideS(double v, BuildContext c) => UiScale.sc(c, v);

  double _infoPanelWidth(BuildContext context) {
    return _sideS(_stationPanelWidth, context);
  }

  double _infoPanelHeightForLayout(BuildContext context) {
    return _sideS(_infoPanelHeight, context);
  }

  double _rightInfoPanelTop(BuildContext context) {
    return UiScale.topBarHeight(context) + _sideS(12 + 140, context);
  }

  double _rightInfoPanelBottom(BuildContext context) {
    final buttonStackHeight =
        _rightActionButtonSize * _rightActionButtonCount +
        _rightActionButtonGap * (_rightActionButtonCount - 1);
    return _s(
      _rightActionButtonBottom + buttonStackHeight + _rightInfoPanelButtonGap,
      context,
    );
  }

  bool _hasFormalNiedDetect(StationSummaryData data) {
    final detect = data.niedDetect;
    if (detect == null) return false;
    return detect.stage != 'idle' &&
        (detect.visualGridCount > 0 ||
            detect.visualAreas.isNotEmpty ||
            detect.detectedStations.isNotEmpty);
  }

  bool _hasAutoInfoContent(StationSummaryData data, QuakeProvider provider) {
    return _hasFormalNiedDetect(data) ||
        data.snetTopStations.isNotEmpty ||
        _activeCmtMapEvent(provider) != null ||
        _activeVolcanoEvent(provider) != null ||
        (provider.jmaTsunami?.isActive == true) ||
        (provider.jmaTsunami?.areas.isNotEmpty ?? false) ||
        (provider.nmefcTsunami?.isActive == true);
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadSideInfoAutoShowBeta();
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.addListener(
      _onSideInfoAutoShowSettingChanged,
    );
    _cmaWeatherService.stateNotifier.addListener(_onCmaWeatherStateChanged);
    LocationService().positionListenable.addListener(
      _onLocalWeatherPositionChanged,
    );
    // 延迟关联控制器，确保 Provider 已准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapStateProvider>().setController(_mapController, this);
      AppPageBackground.cachedBytes();
      _notificationService ??= NotificationService(
        context.read<QuakeProvider>(),
        context.read<NotificationSettingsProvider>(),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = !UiScale.isPhone(context);
    if (_cmaWeatherLayoutEnabled == enabled) return;
    _cmaWeatherLayoutEnabled = enabled;
    _syncCmaWeatherActivity();
  }

  @override
  void dispose() {
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.removeListener(
      _onSideInfoAutoShowSettingChanged,
    );
    LocationService().positionListenable.removeListener(
      _onLocalWeatherPositionChanged,
    );
    _cmaWeatherService.stateNotifier.removeListener(_onCmaWeatherStateChanged);
    _cmaWeatherService.dispose();
    _infoPageCarousel?.cancel();
    _niedDetectPageCarousel?.cancel();
    _stationDataNotifier.dispose();
    _notificationService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = UiScale.isPhone(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: 350,
        backgroundColor: const Color(0xFF0A0A0A),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.1),
                border: const Border(
                  bottom: BorderSide(color: Colors.blueAccent, width: 0.5),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.history, color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text(
                    '历史记录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: HistoryPanel()),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 1. 地图视图
          QuakeMapView(
            mapController: _mapController,
            onStationDataChanged: _onStationDataChanged,
          ),

          // 2. 顶部状态栏
          const Positioned(top: 0, left: 0, right: 0, child: TopStatusBar()),

          // 3. 数据源状态面板
          if (!isPhone) const SourceDashboard(),

          // Station summary panel
          ValueListenableBuilder<StationSummaryData>(
            valueListenable: _stationDataNotifier,
            builder: (context, data, child) =>
                StationDashboard(data: data, phoneMode: isPhone),
          ),

          if (!isPhone)
            Positioned(
              top: _rightInfoPanelTop(context),
              right: _sideS(20, context),
              bottom: _rightInfoPanelBottom(context),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                offset: _showInfoDrawer ? Offset.zero : const Offset(1.05, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 260),
                  opacity: _showInfoDrawer ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_showInfoDrawer,
                    child: ValueListenableBuilder<StationSummaryData>(
                      valueListenable: _stationDataNotifier,
                      builder: (context, data, child) =>
                          _buildRightInfoDrawer(),
                    ),
                  ),
                ),
              ),
            ),

          // 3.5 天气预警跑马灯
          if (!isPhone)
            Positioned(
              top: UiScale.belowTopBar(context, 12),
              left: _s(450, context),
              right: _s(350, context),
              child: const WeatherMarquee(),
            ),

          // 4. 左侧预警模块和地震列表
          if (!isPhone)
            Positioned(
              top: UiScale.belowTopBar(context, 12),
              left: _s(20, context),
              bottom: _s(20, context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AlertModule(),
                  SizedBox(height: _s(12, context)),
                  const Expanded(child: EqlistPanel()),
                ],
              ),
            ),

          const _NiedHypCurveOverlay(),

          // 6. 功能按钮
          Positioned(
            bottom: _s(30, context),
            right: _s(20, context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCircularButton(
                  context: context,
                  icon: Icons.settings,
                  tooltip: '设置',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
                SizedBox(height: _s(12, context)),
                Selector<QuakeProvider, bool>(
                  selector: (context, provider) =>
                      provider.isManualCencIrActive,
                  builder: (context, isManualActive, _) {
                    return _buildCircularButton(
                      context: context,
                      icon: isManualActive ? Icons.waves : Icons.waves_outlined,
                      tooltip: isManualActive
                          ? '关闭手动 CENC 烈度速报'
                          : '手动查看 CENC 烈度速报',
                      color: isManualActive
                          ? const Color(0xFF2ECC71)
                          : Colors.blueAccent,
                      onPressed: () {
                        final provider = context.read<QuakeProvider>();
                        if (isManualActive) {
                          provider.clearCencIrData();
                        } else {
                          _showCencIrSheet(context);
                        }
                      },
                    );
                  },
                ),
                SizedBox(height: _s(12, context)),
                _buildCircularButton(
                  context: context,
                  icon: Icons.history,
                  tooltip: '查看历史',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                SizedBox(height: _s(12, context)),
                _buildCircularButton(
                  context: context,
                  icon: Icons.my_location,
                  tooltip: '回到中心',
                  onPressed: () {
                    context.read<MapStateProvider>().moveToSystemDefaultView();
                  },
                ),
              ],
            ),
          ),
          if (isPhone) ..._buildPhoneOverlays(context),

          // 应用内轻通知覆盖层
          const InAppNotificationOverlay(),
        ],
      ),
    );
  }

  List<Widget> _buildPhoneOverlays(BuildContext context) {
    final scale = UiScale.phone(context);
    double s(double value) => value * scale;
    final stationScale = UiScale.compact(context);
    final stationTop = UiScale.topBarHeight(context) + 8 * stationScale;
    final stationHeight = _stationPanelVisualHeight * stationScale;
    final actionGap = s(8);
    final actionSize = ((stationHeight - actionGap) / 2).clamp(s(30), s(42));
    final actionIconSize = (actionSize * 0.52).clamp(s(16), s(22));

    return [
      Positioned(
        right: s(10),
        top: stationTop,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPhoneActionButton(
              context,
              icon: Icons.settings,
              tooltip: '设置',
              buttonSize: actionSize,
              iconSize: actionIconSize,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            SizedBox(height: actionGap),
            _buildPhoneActionButton(
              context,
              icon: _phoneActionsExpanded ? Icons.close : Icons.add,
              tooltip: _phoneActionsExpanded ? '收起' : '更多',
              buttonSize: actionSize,
              iconSize: actionIconSize,
              onPressed: () {
                setState(() => _phoneActionsExpanded = !_phoneActionsExpanded);
              },
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _phoneActionsExpanded
                  ? Column(
                      key: const ValueKey('phone-actions-expanded'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: s(8)),
                        _buildPhoneActionButton(
                          context,
                          icon: Icons.my_location,
                          tooltip: '回到中心',
                          onPressed: () {
                            context
                                .read<MapStateProvider>()
                                .moveToSystemDefaultView();
                          },
                        ),
                        SizedBox(height: s(8)),
                        _buildPhoneActionButton(
                          context,
                          icon: Icons.history,
                          tooltip: '查看历史',
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                        ),
                        SizedBox(height: s(8)),
                        Selector<QuakeProvider, bool>(
                          selector: (context, provider) =>
                              provider.isManualCencIrActive,
                          builder: (context, isManualActive, _) {
                            return _buildPhoneActionButton(
                              context,
                              icon: isManualActive
                                  ? Icons.waves
                                  : Icons.waves_outlined,
                              tooltip: isManualActive
                                  ? '关闭手动 CENC 烈度速报'
                                  : '手动查看 CENC 烈度速报',
                              color: isManualActive
                                  ? const Color(0xFF2ECC71)
                                  : Colors.blueAccent,
                              onPressed: () {
                                final provider = context.read<QuakeProvider>();
                                if (isManualActive) {
                                  provider.clearCencIrData();
                                } else {
                                  _showCencIrSheet(context);
                                }
                              },
                            );
                          },
                        ),
                      ],
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('phone-actions-collapsed'),
                    ),
            ),
          ],
        ),
      ),
      _buildPhoneBottomSheet(context),
    ];
  }

  Widget _buildPhoneActionButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color color = Colors.blueAccent,
    double? buttonSize,
    double? iconSize,
  }) {
    final scale = UiScale.phone(context);
    double s(double value) => value * scale;
    final resolvedButtonSize = buttonSize ?? s(42);
    final resolvedIconSize = iconSize ?? s(22);
    return Tooltip(
      message: tooltip ?? '',
      child: RepaintBoundary(
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: const Color(0xD01A1A1A),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: SizedBox.square(
                  dimension: resolvedButtonSize,
                  child: Icon(icon, color: color, size: resolvedIconSize),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneBottomSheet(BuildContext context) {
    final scale = UiScale.phone(context);
    double s(double value) => value * scale;
    final height = MediaQuery.sizeOf(context).height;

    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.24,
      maxChildSize: 0.86,
      snap: true,
      snapSizes: const [0.32, 0.58, 0.86],
      builder: (context, scrollController) {
        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(s(16))),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xE6141820),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(s(16)),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: s(0.7),
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    height: height * 0.86,
                    child: DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          SizedBox(height: s(8)),
                          Container(
                            width: s(42),
                            height: s(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(s(999)),
                            ),
                          ),
                          SizedBox(height: s(8)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: s(14)),
                            child: TabBar(
                              indicatorColor: Colors.blueAccent,
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.white54,
                              labelStyle: TextStyle(
                                fontSize: s(13),
                                fontWeight: FontWeight.w700,
                              ),
                              unselectedLabelStyle: TextStyle(
                                fontSize: s(13),
                                fontWeight: FontWeight.w600,
                              ),
                              tabs: const [
                                Tab(text: '预警'),
                                Tab(text: '地震列表'),
                                Tab(text: '状态'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _buildPhoneAlertTab(context, s),
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    s(10),
                                    s(8),
                                    s(10),
                                    s(10),
                                  ),
                                  child: const EqlistPanel(embedded: true),
                                ),
                                _buildPhoneStatusTab(context, s),
                              ],
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
        );
      },
    );
  }

  Widget _buildPhoneAlertTab(BuildContext context, double Function(double) s) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(s(10), s(8), s(10), s(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WeatherMarquee(),
          SizedBox(height: s(8)),
          const AlertModule(),
        ],
      ),
    );
  }

  Widget _buildPhoneStatusTab(BuildContext context, double Function(double) s) {
    return Consumer<QuakeProvider>(
      builder: (context, provider, child) {
        final globalQuakeEnabled = GlobalQuakeService().isEnabled;
        final rows =
            provider.sourceStatuses.entries
                .where(
                  (entry) =>
                      entry.key != 'CENC' &&
                      entry.key != 'S-net' &&
                      (entry.key != 'GlobalQuake' || globalQuakeEnabled),
                )
                .toList()
              ..sort((a, b) => a.key.compareTo(b.key));
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(s(14), s(10), s(14), s(24)),
          itemCount: rows.length,
          separatorBuilder: (_, _) => Divider(
            height: s(1),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          itemBuilder: (context, index) {
            final entry = rows[index];
            final online = entry.value.name == 'connected';
            return Padding(
              padding: EdgeInsets.symmetric(vertical: s(9)),
              child: Row(
                children: [
                  Container(
                    width: s(8),
                    height: s(8),
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFF00DC8C) : Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: s(10)),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: s(13),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    entry.value.name.toUpperCase(),
                    style: TextStyle(
                      color: online
                          ? const Color(0xFF00DC8C)
                          : Colors.white.withValues(alpha: 0.45),
                      fontSize: s(10),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCircularButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color color = Colors.blueAccent,
  }) {
    return Tooltip(
      message: tooltip ?? "",
      child: RepaintBoundary(
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: const Color(0xCC1A1A1A),
              shape: const CircleBorder(),
              elevation: 0,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: EdgeInsets.all(_s(14, context)),
                  child: Icon(icon, color: color, size: _s(24, context)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightInfoDrawer() {
    return Consumer2<MapStateProvider, QuakeProvider>(
      builder: (context, mapState, provider, _) {
        final detect = _stationData.niedDetect;
        final hasNied = _hasFormalNiedDetect(_stationData);
        if (!hasNied) _stopNiedDetectPagination();
        final hasSnet = _stationData.snetTopStations.isNotEmpty;
        final jmaTsunami = provider.jmaTsunami;
        final hasJmaTsunami =
            jmaTsunami != null &&
            (jmaTsunami.isActive || jmaTsunami.areas.isNotEmpty);
        final nmefc = provider.nmefcTsunami;
        final hasNmefc = nmefc != null && nmefc.isActive;
        final cmt = _activeCmtMapEvent(provider);
        final volcano = _activeVolcanoEvent(provider);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleAutoInfoPopup(_stationData, provider);
        });

        final mainPages = <_InfoDrawerPage>[];
        if (cmt != null) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageCmt,
              child: CmtSidebarPanel(
                event: cmt,
                scale: (value) => _s(value, context),
              ),
            ),
          );
        }
        if (volcano != null) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageVolcano,
              child: VolcanoSidebarPanel(
                event: volcano,
                scale: (value) => _s(value, context),
              ),
            ),
          );
        }
        if (hasNied) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageNied,
              child: _buildDetectStationsArea(context, detect!),
            ),
          );
        }
        if (hasSnet) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageSnet,
              child: _buildSnetSection(context),
            ),
          );
        }
        if (hasJmaTsunami) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageJmaTsunami,
              child: _buildTsunamiSection(context, jmaTsunami, 'P2P/JMA'),
            ),
          );
        }
        if (hasNmefc) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageNmefcTsunami,
              child: _buildTsunamiSection(context, nmefc, 'NMEFC'),
            ),
          );
        }
        _syncInfoCarouselPages(mainPages);

        final showCarousel = mainPages.isNotEmpty;
        if (showCarousel && _infoPageIndex >= mainPages.length) {
          _infoPageIndex = 0;
        }

        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_s(10, context)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                width: _infoPanelWidth(context),
                constraints: BoxConstraints(
                  minHeight: _infoPanelHeightForLayout(context),
                ),
                padding: EdgeInsets.fromLTRB(
                  _s(12, context),
                  _s(10, context),
                  _s(12, context),
                  _s(10, context),
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(_s(10, context)),
                  border: Border.all(
                    color: Colors.white12,
                    width: _s(0.5, context),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [...previousChildren, ?currentChild],
                          );
                        },
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0.08, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: SizedBox.expand(
                          key: ValueKey(
                            showCarousel
                                ? mainPages[_infoPageIndex].key
                                : 'weatherPlaceholder',
                          ),
                          child: _buildInfoSurface(
                            context,
                            showCarousel
                                ? mainPages[_infoPageIndex].child
                                : _buildWeatherPlaceholder(context),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: _s(8, context)),
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    SizedBox(height: _s(6, context)),
                    _buildLpgmFooter(context),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoSurface(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _s(8, context),
        vertical: _s(7, context),
      ),
      child: child,
    );
  }

  Widget _buildSnetSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            '[S-Net 海底观测] ${_snetWindowText()}',
            style: TextStyle(
              color: Colors.white70,
              fontSize: _s(12, context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: _s(4, context)),
        ..._stationData.snetTopStations.map((s) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: _s(1, context)),
            child: Text(
              '${s.code} 震度 ${_jmaLabelFromIndex(s.jmaIndex)} (${s.shindo.toStringAsFixed(3)})',
              style: TextStyle(
                color: Colors.white,
                fontSize: _s(11, context),
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTsunamiSection(
    BuildContext context,
    TsunamiMessage tsunami,
    String sourceLabel,
  ) {
    final areas = tsunami.areas.take(4).toList();
    final title = _tsunamiSideTitle(tsunami, sourceLabel);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: _s(6, context),
              height: _s(6, context),
              decoration: BoxDecoration(
                color: _tsunamiClassColor(tsunami.className),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: _s(6, context)),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _s(12, context),
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            Text(
              '${tsunami.areas.length} 区域',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: _s(10, context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (tsunami.reportTime.isNotEmpty) ...[
          SizedBox(height: _s(3, context)),
          Text(
            tsunami.reportTime,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: _s(10, context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        SizedBox(height: _s(6, context)),
        if (areas.isEmpty)
          Text(
            tsunami.titleText.isEmpty ? '暂无海啸信息' : tsunami.titleText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: _s(11, context),
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          )
        else
          ...areas.map((area) => _buildTsunamiAreaRow(context, area)),
      ],
    );
  }

  Widget _buildTsunamiAreaRow(BuildContext context, TsunamiAreaInfo area) {
    final color = _tsunamiClassColor(area.className);
    final timeText = area.arrivalTime?.trim();
    final heightText = area.description?.trim();
    final meta = [
      if (area.condition?.trim().isNotEmpty == true) area.condition!.trim(),
      if (timeText?.isNotEmpty == true) timeText!,
      if (heightText?.isNotEmpty == true) heightText!,
    ].join('  ');

    return Padding(
      padding: EdgeInsets.only(top: _s(3, context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _s(3, context),
            height: _s(23, context),
            margin: EdgeInsets.only(top: _s(1, context)),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(_s(2, context)),
            ),
          ),
          SizedBox(width: _s(6, context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  area.name.isEmpty ? '未知区域' : area.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _s(11, context),
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: _s(9.5, context),
                      fontWeight: FontWeight.w600,
                      height: 1.12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tsunamiSideTitle(TsunamiMessage tsunami, String sourceLabel) {
    final title = tsunami.title.trim().isNotEmpty
        ? tsunami.title.trim()
        : tsunami.titleText.trim();
    return title.isEmpty ? sourceLabel : '$sourceLabel $title';
  }

  Color _tsunamiClassColor(String className) {
    switch (className) {
      case 'blue':
        return const Color(0xFF4AA3FF);
      case 'yellow':
        return const Color(0xFFF4D44D);
      case 'red':
        return const Color(0xFFFF4F4F);
      case 'purple':
        return const Color(0xFFB56AFF);
      default:
        return const Color(0xFF9EA9B7);
    }
  }

  Widget _buildLpgmFooter(BuildContext context) {
    final maxSva = _stationData.lpgmMaxSva;
    final maxClass = _stationData.lpgmMaxClass;
    final svaText = (maxSva != null && maxSva > 0)
        ? maxSva.toStringAsFixed(3)
        : '--';
    final classText = (maxClass != null && maxClass >= 0)
        ? maxClass.toString()
        : '--';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        _s(8, context),
        _s(7, context),
        _s(8, context),
        _s(6, context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '长周期地震动观测 (beta)',
            style: TextStyle(
              color: Colors.white70,
              fontSize: _s(12, context),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: _s(4, context)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '最大 SVA: $svaText    最大阶级: $classText',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: _s(10.5, context),
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherPlaceholder(BuildContext context) {
    final observation = _cmaWeatherState.observation;
    if (observation == null) {
      final message = switch (_cmaWeatherState.status) {
        CmaLocalWeatherStatus.noLocation => '等待定位信息',
        CmaLocalWeatherStatus.resolvingStation => '正在查找附近气象站...',
        CmaLocalWeatherStatus.loading => '正在获取气象实况...',
        CmaLocalWeatherStatus.failed => '气象实况暂不可用',
        CmaLocalWeatherStatus.idle || CmaLocalWeatherStatus.ready => '等待气象实况',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '气象实况',
            style: TextStyle(
              color: Colors.white70,
              fontSize: _s(12, context),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: _s(4, context)),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: _s(10.5, context),
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      );
    }

    final stationText = _cmaWeatherStationText(observation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '站点：$stationText（${observation.station.id}）',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.96),
            fontSize: _s(10.8, context),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: _s(3, context)),
        Text(
          '实况：',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: _s(10.5, context),
            fontWeight: FontWeight.w700,
            height: 1.18,
          ),
        ),
        if (_cmaHasNumber(observation.temperature))
          _buildCmaWeatherRow(
            context,
            '瞬时温度',
            _cmaWeatherTimedNumber(
              observation.temperature,
              '℃',
              observation.observedAt,
            ),
          ),
        if (_cmaHasNumber(observation.pressure))
          _buildCmaWeatherRow(
            context,
            '地面气压',
            _cmaWeatherTimedNumber(
              observation.pressure,
              'hPa',
              observation.observedAt,
            ),
          ),
        if (_cmaHasNumber(observation.humidity))
          _buildCmaWeatherRow(
            context,
            '相对湿度',
            _cmaWeatherTimedNumber(
              observation.humidity,
              '%',
              observation.observedAt,
              digits: 0,
            ),
          ),
        if (_cmaHasWindDirection(observation))
          _buildCmaWeatherRow(
            context,
            '2分钟平均风向',
            _cmaTimedText(
              _cmaWindDirectionText(observation),
              observation.observedAt,
            ),
          ),
        if (_cmaHasNumber(observation.windSpeed))
          _buildCmaWeatherRow(
            context,
            '2分钟平均风速',
            _cmaWeatherTimedNumber(
              observation.windSpeed,
              'm/s',
              observation.observedAt,
            ),
          ),
        if (_cmaHasNumber(observation.precipitation))
          _buildCmaWeatherRow(
            context,
            '1小时降水',
            _cmaWeatherTimedNumber(
              observation.precipitation,
              'mm',
              observation.observedAt,
            ),
          ),
      ],
    );
  }

  Widget _buildCmaWeatherRow(
    BuildContext context,
    String label,
    String value, {
    bool muted = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: _s(1.5, context)),
      child: Text(
        '$label：$value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted
              ? Colors.white.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.86),
          fontSize: _s(10.3, context),
          fontWeight: FontWeight.w600,
          height: 1.18,
        ),
      ),
    );
  }

  String _cmaWeatherStationText(CmaLocalWeatherObservation observation) {
    final parts = observation.locationPath
        .split(RegExp(r'[,，]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != '中国')
        .toList(growable: false);
    return parts.isEmpty ? observation.station.name : parts.join();
  }

  bool _cmaHasNumber(double? value) => value != null && value.isFinite;

  bool _cmaHasWindDirection(CmaLocalWeatherObservation observation) {
    return observation.windDirection.trim().isNotEmpty ||
        _cmaHasNumber(observation.windDirectionDegree);
  }

  String _cmaWeatherNumber(double? value, String unit, {int digits = 1}) {
    if (value == null || !value.isFinite) return '--';
    return '${value.toStringAsFixed(digits)} $unit';
  }

  String _cmaWeatherTimedNumber(
    double? value,
    String unit,
    DateTime? time, {
    int digits = 1,
  }) {
    if (value == null || !value.isFinite) return '--';
    return _cmaTimedText(_cmaWeatherNumber(value, unit, digits: digits), time);
  }

  String _cmaTimedText(String value, DateTime? time) {
    if (value == '--' || time == null) return value;
    return '$value（${_cmaWeatherTime(time)}）';
  }

  String _cmaWindDirectionText(CmaLocalWeatherObservation observation) {
    final direction = observation.windDirection.replaceFirst(RegExp(r'风$'), '');
    final label = direction.isEmpty ? '--' : direction;
    final abbreviation = _cmaWindDirectionAbbreviation(direction);
    if (abbreviation != null) return '$label($abbreviation)';
    final degree = observation.windDirectionDegree;
    if (degree == null || !degree.isFinite) return label;
    return '$label(${_cmaWindAbbreviationFromDegree(degree)})';
  }

  String? _cmaWindDirectionAbbreviation(String direction) {
    return const {
      '北': 'N',
      '东北': 'NE',
      '东': 'E',
      '东南': 'SE',
      '南': 'S',
      '西南': 'SW',
      '西': 'W',
      '西北': 'NW',
    }[direction];
  }

  String _cmaWindAbbreviationFromDegree(double degree) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final normalized = ((degree % 360) + 360) % 360;
    return labels[((normalized + 22.5) ~/ 45) % labels.length];
  }

  String _cmaWeatherTime(DateTime? time) {
    if (time == null) return '--';
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  String _snetWindowText() {
    final start = _stationData.snetWindowStart;
    final end = _stationData.snetWindowEnd;
    if (start == null || end == null) return '';
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${hm(start)}-${hm(end)}';
  }

  String _jmaLabelFromIndex(int idx) {
    const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    return labels[idx.clamp(0, labels.length - 1)];
  }

  Widget _buildDetectStationsArea(
    BuildContext context,
    NiedDetectSummary detect,
  ) {
    const jmaLabels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    final visualAreas = detect.visualAreas.isNotEmpty
        ? detect.visualAreas
        : _visualAreasFromDetectedStations(detect.detectedStations);
    // Keep strong-detect areas separate from lower-level detected areas.
    final strong = visualAreas.where((s) => s.jmaShindo >= 4).toList();
    final detected = visualAreas
        .where((s) => s.jmaShindo >= 0 && s.jmaShindo < 4)
        .toList();

    Map<String, String> groupByPref(List<NiedDetectVisualArea> entries) {
      final prefMaxShindo = <String, int>{};
      for (final e in entries) {
        final pref = e.name;
        final current = prefMaxShindo[pref] ?? -1;
        if (e.jmaShindo > current) prefMaxShindo[pref] = e.jmaShindo;
      }
      return prefMaxShindo.map((pref, shindo) {
        final label = shindo >= 0 && shindo < jmaLabels.length
            ? jmaLabels[shindo]
            : '?';
        return MapEntry(pref, '$pref($label)');
      });
    }

    const colorStrong = Color(0xFFE74C3C);
    const colorDetected = Color(0xFFE67E22);
    final titleStyle = TextStyle(
      fontSize: _s(12, context),
      fontWeight: FontWeight.w700,
    );
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: _s(11, context),
      height: 1.35,
    );
    final sections = <_DetectSectionData>[
      if (strong.isNotEmpty)
        _DetectSectionData(
          title: '強い揺れを検出',
          color: colorStrong,
          labels: groupByPref(strong).values.toList(growable: false),
        ),
      if (detected.isNotEmpty)
        _DetectSectionData(
          title: '揺れを検出',
          color: colorDetected,
          labels: groupByPref(detected).values.toList(growable: false),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _s(180, context);
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : _s(120, context);
        final pages = _paginateDetectSections(
          context: context,
          sections: sections,
          maxWidth: availableWidth,
          maxHeight: availableHeight,
          titleStyle: titleStyle,
          textStyle: textStyle,
        );
        final signature = [
          for (final section in sections)
            '${section.title}:${section.labels.join(',')}',
          availableWidth.round(),
          availableHeight.round(),
          pages.length,
        ].join('|');
        _syncNiedDetectPagination(signature, pages.length);

        if (pages.isEmpty) return const SizedBox.expand();
        final pageIndex = _niedDetectPageIndex.clamp(0, pages.length - 1);
        final page = pages[pageIndex];
        return Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: _s(2, context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < page.sections.length; i++) ...[
                      if (i > 0) SizedBox(height: _s(6, context)),
                      Center(
                        child: Text(
                          page.sections[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle.copyWith(
                            color: page.sections[i].color,
                          ),
                        ),
                      ),
                      SizedBox(height: _s(2, context)),
                      for (final line in page.sections[i].lines)
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (pages.length > 1)
              Positioned(
                right: 0,
                bottom: 0,
                child: Text(
                  '${pageIndex + 1}/${pages.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: _s(9, context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<_DetectPageData> _paginateDetectSections({
    required BuildContext context,
    required List<_DetectSectionData> sections,
    required double maxWidth,
    required double maxHeight,
    required TextStyle titleStyle,
    required TextStyle textStyle,
  }) {
    if (sections.isEmpty || maxWidth <= 0 || maxHeight <= 0) return const [];

    final textScaler = MediaQuery.textScalerOf(context);
    double measuredHeight(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout(maxWidth: maxWidth);
      return painter.height;
    }

    final titleHeight = measuredHeight('強い揺れを検出', titleStyle);
    final lineHeight = measuredHeight('東京都(4)', textStyle);
    final titleGap = _s(2, context);
    final sectionGap = _s(6, context);
    final pageIndicatorReserve = _s(13, context);
    final verticalPadding = _s(4, context);
    final pageHeight = math.max(
      titleHeight + titleGap + lineHeight,
      maxHeight - pageIndicatorReserve - verticalPadding,
    );

    final pages = <_DetectPageData>[];
    var currentSections = <_DetectPageSectionData>[];
    var remainingHeight = pageHeight;

    void commitPage() {
      if (currentSections.isEmpty) return;
      pages.add(_DetectPageData(sections: currentSections));
      currentSections = <_DetectPageSectionData>[];
      remainingHeight = pageHeight;
    }

    for (final section in sections) {
      final lines = _wrapDetectLabels(
        context: context,
        labels: section.labels,
        maxWidth: maxWidth,
        style: textStyle,
      );
      var lineIndex = 0;
      while (lineIndex < lines.length) {
        final leadingGap = currentSections.isEmpty ? 0.0 : sectionGap;
        final headerHeight = leadingGap + titleHeight + titleGap;
        if (currentSections.isNotEmpty &&
            remainingHeight < headerHeight + lineHeight) {
          commitPage();
          continue;
        }

        final lineCapacity = math.max(
          1,
          ((remainingHeight - headerHeight) / lineHeight).floor(),
        );
        final end = math.min(lines.length, lineIndex + lineCapacity);
        final pageLines = lines.sublist(lineIndex, end);
        currentSections.add(
          _DetectPageSectionData(
            title: section.title,
            color: section.color,
            lines: pageLines,
          ),
        );
        remainingHeight -= headerHeight + pageLines.length * lineHeight;
        lineIndex = end;
        if (lineIndex < lines.length) commitPage();
      }
    }
    commitPage();
    return pages;
  }

  List<String> _wrapDetectLabels({
    required BuildContext context,
    required List<String> labels,
    required double maxWidth,
    required TextStyle style,
  }) {
    if (labels.isEmpty) return const [];
    final textScaler = MediaQuery.textScalerOf(context);
    bool fits(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines && painter.width <= maxWidth;
    }

    final lines = <String>[];
    var current = '';
    for (final label in labels) {
      final candidate = current.isEmpty ? label : '$current  $label';
      if (current.isNotEmpty && !fits(candidate)) {
        lines.add(current);
        current = label;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  List<NiedDetectVisualArea> _visualAreasFromDetectedStations(
    List<DetectedStationEntry> stations,
  ) {
    final prefMax = <String, int>{};
    for (final station in stations) {
      final name = station.prefecture.isNotEmpty
          ? station.prefecture
          : station.code;
      final current = prefMax[name] ?? -1;
      if (station.jmaShindo > current) prefMax[name] = station.jmaShindo;
    }
    return prefMax.entries
        .map(
          (entry) =>
              NiedDetectVisualArea(name: entry.key, jmaShindo: entry.value),
        )
        .toList(growable: false);
  }

  Future<void> _loadSideInfoAutoShowBeta() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_sideInfoAutoShowBetaKey) ?? true;
    if (!mounted) return;
    setState(() {
      _sideInfoSettingLoaded = true;
      _sideInfoAutoShowBeta = enabled;
      _showInfoDrawer = enabled;
    });
    _syncCmaWeatherActivity();
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value = enabled;
  }

  void _onSideInfoAutoShowSettingChanged() {
    if (!mounted) return;
    final enabled = UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value;
    if (_sideInfoAutoShowBeta == enabled) return;
    setState(() {
      _sideInfoAutoShowBeta = enabled;
      _showInfoDrawer = enabled;
    });
    _syncCmaWeatherActivity();
  }

  void _onCmaWeatherStateChanged() {
    if (!mounted) return;
    setState(() {
      _cmaWeatherState = _cmaWeatherService.stateNotifier.value;
    });
  }

  void _onLocalWeatherPositionChanged() {
    if (!_cmaWeatherLayoutEnabled || !_showInfoDrawer) return;
    final position = LocationService().currentPosition;
    if (position == null) {
      _cmaWeatherService.clearLocation();
      return;
    }
    unawaited(
      _cmaWeatherService.startForLocation(
        position.latitude,
        position.longitude,
      ),
    );
  }

  void _syncCmaWeatherActivity() {
    if (!_sideInfoSettingLoaded ||
        !_cmaWeatherLayoutEnabled ||
        !_showInfoDrawer) {
      _cmaWeatherService.pause();
      return;
    }
    _onLocalWeatherPositionChanged();
  }

  void _onStationDataChanged(StationSummaryData data) {
    if (!mounted) return;
    final signature = _stationDataUiSignature(data);
    if (signature != _lastStationDataUiSignature) {
      _lastStationDataUiSignature = signature;
      _stationData = data;
      _stationDataNotifier.value = data;
    } else {
      _stationData = data;
    }
    final provider = context.read<QuakeProvider>();
    _handleAutoInfoPopup(data, provider);
  }

  String _stationDataUiSignature(StationSummaryData data) {
    final seis = data.seisJsStation;
    final seisMax = data.seisJsMaxStation;
    final nied = data.niedMaxStation;
    final trea = data.treaMaxStation;
    final kma = data.kmaMaxStation;
    final pAlert = data.pAlertMaxStation;
    final snetMax = data.snetTopStations.isEmpty
        ? -1
        : data.snetTopStations.first.jmaIndex;
    return [
      seis?.shindo ?? -1,
      seis?.maxIntensity.toStringAsFixed(2) ?? '-',
      seis?.pga.toStringAsFixed(1) ?? '-',
      seisMax?.intensity.toStringAsFixed(2) ?? '-',
      nied?.level ?? -1,
      trea?.currentIntensity.toStringAsFixed(1) ?? '-',
      kma?.intensity ?? -3,
      snetMax,
      pAlert?.shindoClass ?? -1,
      _niedDetectUiSignature(data.niedDetect),
      _snetUiSignature(data),
      data.lpgmMaxSva?.toStringAsFixed(3) ?? '-',
      data.lpgmMaxClass ?? -1,
    ].join('|');
  }

  String _niedDetectUiSignature(NiedDetectSummary? detect) {
    if (detect == null) return '-';
    final prefMax = <String, int>{};
    final visualAreas = detect.visualAreas.isNotEmpty
        ? detect.visualAreas
        : _visualAreasFromDetectedStations(detect.detectedStations);
    for (final entry in visualAreas) {
      final pref = entry.name;
      final current = prefMax[pref] ?? -1;
      if (entry.jmaShindo > current) prefMax[pref] = entry.jmaShindo;
    }
    final prefSignature =
        (prefMax.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((entry) => '${entry.key}:${entry.value}')
            .join(',');
    return [
      detect.stage,
      detect.weakCount,
      detect.detectedCount,
      detect.strongCount,
      detect.maxShindo,
      detect.visualGridCount,
      visualAreas.length,
      prefSignature,
    ].join(',');
  }

  String _snetUiSignature(StationSummaryData data) {
    final topStations = data.snetTopStations
        .map((s) => '${s.code}:${s.jmaIndex}:${s.shindo.toStringAsFixed(3)}')
        .join(',');
    return [
      _hmSignature(data.snetWindowStart),
      _hmSignature(data.snetWindowEnd),
      topStations,
    ].join(',');
  }

  String _hmSignature(DateTime? time) {
    if (time == null) return '-';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  QuakeMessage? _activeCmtMapEvent(QuakeProvider provider) {
    final unified = provider.unifiedEvents;
    final mapEvents = provider.unifiedMapEvents;
    if (unified.isEmpty || unified.length != mapEvents.length) return null;

    final currentIndex = provider.currentUnifiedIndex;
    if (currentIndex >= 0 &&
        currentIndex < unified.length &&
        _isCmtSource(mapEvents[currentIndex].source)) {
      return mapEvents[currentIndex];
    }

    var selectedIndex = -1;
    DateTime? latestArrival;
    for (var index = 0; index < unified.length; index++) {
      if (!_isCmtSource(mapEvents[index].source)) continue;
      final arrivedAt = unified[index].arrivedAt ?? unified[index].originTime;
      if (selectedIndex < 0 ||
          (arrivedAt != null &&
              (latestArrival == null || arrivedAt.isAfter(latestArrival)))) {
        selectedIndex = index;
        latestArrival = arrivedAt;
      }
    }
    return selectedIndex < 0 ? null : mapEvents[selectedIndex];
  }

  bool _isCmtSource(QuakeSourceType source) {
    return source == QuakeSourceType.fssnCmt ||
        source == QuakeSourceType.cencCmt ||
        source == QuakeSourceType.usgsCmt ||
        source == QuakeSourceType.jmaCmt ||
        source == QuakeSourceType.fnetCmt ||
        source == QuakeSourceType.hinetAquaCmt;
  }

  String _cmtInfoSignature(QuakeMessage? event) {
    if (event == null) return '-';
    final metadata = event.cmtMetadata;
    return [
      event.source.name,
      event.eventId,
      event.nodalPlane1,
      event.nodalPlane2,
      event.centroidDepth,
      event.momentTensor?.toMap(),
      metadata?.toMap(),
    ].join('|');
  }

  UnifiedQuakeData? _activeVolcanoEvent(QuakeProvider provider) {
    return selectVolcanoSidebarEvent(
      provider.unifiedEvents,
      provider.currentUnifiedIndex,
    );
  }

  String _volcanoInfoSignature(UnifiedQuakeData? event) {
    final volcano = event?.volcanoEvent;
    if (event == null || volcano == null) return '-';
    return [
      event.eventId,
      volcano.kindCode,
      volcano.updates,
      volcano.infoTypeName,
      event.reportTime,
    ].join('|');
  }

  void _syncInfoCarouselPages(List<_InfoDrawerPage> pages) {
    final pageKeys = pages.map((p) => p.key).toList();
    final keysSignature = pageKeys.join('|');
    final pendingKey = _pendingInfoPageKey;
    final pendingIndex = pendingKey == null ? -1 : pageKeys.indexOf(pendingKey);
    if (keysSignature == _lastInfoPageKeysSignature && pendingIndex < 0) {
      return;
    }

    final currentKey =
        _infoPageIndex >= 0 && _infoPageIndex < _lastInfoPageKeys.length
        ? _lastInfoPageKeys[_infoPageIndex]
        : null;

    _infoPageCarousel?.cancel();
    if (pages.isEmpty) {
      _infoPageIndex = 0;
    } else if (pendingIndex >= 0) {
      _infoPageIndex = pendingIndex;
      _pendingInfoPageKey = null;
    } else if (pendingKey != null) {
      _pendingInfoPageKey = null;
      if (currentKey != null && pageKeys.contains(currentKey)) {
        _infoPageIndex = pageKeys.indexOf(currentKey);
      } else if (_infoPageIndex >= pages.length) {
        _infoPageIndex = 0;
      }
    } else if (currentKey != null && pageKeys.contains(currentKey)) {
      _infoPageIndex = pageKeys.indexOf(currentKey);
    } else if (_infoPageIndex >= pages.length) {
      _infoPageIndex = 0;
    }

    _lastInfoPageKeys = pageKeys;
    _lastInfoPageKeysSignature = keysSignature;
    if (pages.length > 1) {
      _infoPageCarousel = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        setState(() {
          _infoPageIndex = (_infoPageIndex + 1) % pages.length;
        });
      });
    }
  }

  void _syncNiedDetectPagination(String signature, int pageCount) {
    if (!_showInfoDrawer) {
      _stopNiedDetectPagination();
      return;
    }
    if (_niedDetectPageSignature == signature &&
        _niedDetectPageCount == pageCount) {
      return;
    }

    _niedDetectPageCarousel?.cancel();
    _niedDetectPageCarousel = null;
    _niedDetectPageSignature = signature;
    _niedDetectPageCount = pageCount;
    _niedDetectPageIndex = 0;
    if (pageCount <= 1) return;

    _niedDetectPageCarousel = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_showInfoDrawer || _niedDetectPageCount <= 1) return;
      final currentInfoKey =
          _infoPageIndex >= 0 && _infoPageIndex < _lastInfoPageKeys.length
          ? _lastInfoPageKeys[_infoPageIndex]
          : null;
      if (currentInfoKey != _infoPageNied) return;
      setState(() {
        _niedDetectPageIndex =
            (_niedDetectPageIndex + 1) % _niedDetectPageCount;
      });
    });
  }

  void _stopNiedDetectPagination() {
    _niedDetectPageCarousel?.cancel();
    _niedDetectPageCarousel = null;
    _niedDetectPageSignature = '';
    _niedDetectPageCount = 0;
    _niedDetectPageIndex = 0;
  }

  void _handleAutoInfoPopup(StationSummaryData data, QuakeProvider provider) {
    if (!_sideInfoAutoShowBeta) return;

    final detectTriggered = _hasFormalNiedDetect(data);
    final snetTriggered = data.snetTopStations.isNotEmpty;
    final jmaTsunami = provider.jmaTsunami;
    final nmefcTsunami = provider.nmefcTsunami;
    final jmaTsunamiTriggered =
        jmaTsunami != null &&
        (jmaTsunami.isActive || jmaTsunami.areas.isNotEmpty);
    final nmefcTsunamiTriggered = nmefcTsunami?.isActive == true;
    final cmt = _activeCmtMapEvent(provider);
    final cmtSignature = _cmtInfoSignature(cmt);
    final cmtTriggered = cmt != null;
    final volcano = _activeVolcanoEvent(provider);
    final volcanoSignature = _volcanoInfoSignature(volcano);
    final volcanoTriggered = volcano != null;
    final shouldShow = _hasAutoInfoContent(data, provider);

    if (!shouldShow) {
      _lastAutoTriggerSignature = null;
      _lastNiedInfoSignature = '-';
      _lastSnetInfoSignature = '-';
      _lastJmaTsunamiInfoSignature = '-';
      _lastNmefcTsunamiInfoSignature = '-';
      _lastCmtInfoSignature = '-';
      _lastVolcanoInfoSignature = '-';
      _pendingInfoPageKey = null;
      return;
    }

    final snetTopCode = data.snetTopStations.isEmpty
        ? '-'
        : data.snetTopStations.first.code;
    final snetTopJma = data.snetTopStations.isEmpty
        ? -1
        : data.snetTopStations.first.jmaIndex;
    final niedSignature = detectTriggered
        ? _niedDetectUiSignature(data.niedDetect)
        : '-';
    final snetSignature = snetTriggered
        ? '$snetTopCode|$snetTopJma|${data.snetTopStations.length}'
        : '-';
    final jmaTsunamiSignature = jmaTsunamiTriggered
        ? '${jmaTsunami.id}|${jmaTsunami.status}|${jmaTsunami.areas.length}'
        : '-';
    final nmefcTsunamiSignature = nmefcTsunamiTriggered
        ? '${nmefcTsunami!.id}|${nmefcTsunami.status}|${nmefcTsunami.areas.length}'
        : '-';
    final signature =
        '$niedSignature|$snetSignature|$jmaTsunamiSignature|$nmefcTsunamiSignature|$cmtSignature|$volcanoSignature';
    if (signature == _lastAutoTriggerSignature) {
      return;
    }
    _lastAutoTriggerSignature = signature;

    String? focusPageKey;
    if (detectTriggered && niedSignature != _lastNiedInfoSignature) {
      focusPageKey = _infoPageNied;
    }
    if (snetTriggered && snetSignature != _lastSnetInfoSignature) {
      focusPageKey = _infoPageSnet;
    }
    if (jmaTsunamiTriggered &&
        jmaTsunamiSignature != _lastJmaTsunamiInfoSignature) {
      focusPageKey = _infoPageJmaTsunami;
    }
    if (nmefcTsunamiTriggered &&
        nmefcTsunamiSignature != _lastNmefcTsunamiInfoSignature) {
      focusPageKey = _infoPageNmefcTsunami;
    }
    if (cmtTriggered && cmtSignature != _lastCmtInfoSignature) {
      focusPageKey = _infoPageCmt;
    }
    if (volcanoTriggered && volcanoSignature != _lastVolcanoInfoSignature) {
      focusPageKey = _infoPageVolcano;
    }
    _lastNiedInfoSignature = niedSignature;
    _lastSnetInfoSignature = snetSignature;
    _lastJmaTsunamiInfoSignature = jmaTsunamiSignature;
    _lastNmefcTsunamiInfoSignature = nmefcTsunamiSignature;
    _lastCmtInfoSignature = cmtSignature;
    _lastVolcanoInfoSignature = volcanoSignature;

    if (focusPageKey != null && _pendingInfoPageKey != focusPageKey) {
      setState(() {
        _pendingInfoPageKey = focusPageKey;
      });
    }
  }

  void _showCencIrSheet(BuildContext context) {
    final provider = context.read<QuakeProvider>();
    final list = provider.cencIrList;
    final scale = UiScale.isPhone(context)
        ? UiScale.phone(context)
        : UiScale.main(context);
    double s(double value) => value * scale;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(s(16))),
      ),
      builder: (sheetContext) {
        if (list.isEmpty) {
          return Container(
            height: s(200),
            padding: EdgeInsets.all(s(24)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, color: Colors.white38, size: s(48)),
                  SizedBox(height: s(12)),
                  Text(
                    '暂无 CENC 烈度速报数据',
                    style: TextStyle(color: Colors.white54, fontSize: s(14)),
                  ),
                  SizedBox(height: s(4)),
                  Text(
                    '可从 FAN / NowQuake 获取最近的烈度速报',
                    style: TextStyle(color: Colors.white30, fontSize: s(12)),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(14)),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white12, width: s(0.5)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.waves_outlined,
                    color: const Color(0xFF2ECC71),
                    size: s(20),
                  ),
                  SizedBox(width: s(8)),
                  Text(
                    '选择 CENC 烈度速报',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: s(15),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${list.length} items',
                    style: TextStyle(color: Colors.white38, fontSize: s(12)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(vertical: s(8)),
                itemCount: list.length,
                separatorBuilder: (_, index) =>
                    Divider(height: s(1), color: Colors.white10),
                itemBuilder: (_, i) {
                  final item = list[i];
                  final name =
                      item['nameByInfo']?.toString() ??
                      item['locName']?.toString() ??
                      item['placeName']?.toString() ??
                      '未知地点';
                  final time =
                      item['shockTime']?.toString() ??
                      item['oriTime']?.toString() ??
                      '';
                  final mag = item['magnitude']?.toString() ?? '';
                  final id = item['id']?.toString() ?? '';
                  final manualData = provider.manualCencIrData;
                  final isActive =
                      manualData != null &&
                      (manualData.reportId == id ||
                          manualData.uniEventId ==
                              item['uniEventId']?.toString());

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: s(20),
                      vertical: s(2),
                    ),
                    leading: Container(
                      width: s(36),
                      height: s(36),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF2ECC71).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(s(8)),
                      ),
                      child: Icon(
                        Icons.waves,
                        color: isActive
                            ? const Color(0xFF2ECC71)
                            : Colors.white38,
                        size: s(18),
                      ),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: s(13),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Row(
                      children: [
                        if (time.isNotEmpty) ...[
                          Text(
                            time.length >= 16 ? time.substring(5, 16) : time,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: s(11),
                            ),
                          ),
                          if (mag.isNotEmpty) SizedBox(width: s(8)),
                        ],
                        if (mag.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: s(6),
                              vertical: s(1),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(s(4)),
                            ),
                            child: Text(
                              'M$mag',
                              style: TextStyle(
                                color: const Color(0xFFE67E22),
                                fontSize: s(11),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isActive) ...[
                          SizedBox(width: s(6)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: s(5),
                              vertical: s(1),
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF2ECC71,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(s(3)),
                            ),
                            child: Text(
                              'Active',
                              style: TextStyle(
                                color: const Color(0xFF2ECC71),
                                fontSize: s(10),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.white24,
                      size: s(18),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      provider.requestCencIrDetail(
                        id,
                        source: item['_source']?.toString(),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InfoDrawerPage {
  final String key;
  final Widget child;

  const _InfoDrawerPage({required this.key, required this.child});
}

class _DetectSectionData {
  const _DetectSectionData({
    required this.title,
    required this.color,
    required this.labels,
  });

  final String title;
  final Color color;
  final List<String> labels;
}

class _DetectPageSectionData {
  const _DetectPageSectionData({
    required this.title,
    required this.color,
    required this.lines,
  });

  final String title;
  final Color color;
  final List<String> lines;
}

class _DetectPageData {
  const _DetectPageData({required this.sections});

  final List<_DetectPageSectionData> sections;
}

class _NiedHypCurveOverlay extends StatefulWidget {
  const _NiedHypCurveOverlay({super.key, this.prepareInBackground = true});

  final bool prepareInBackground;

  @override
  State<_NiedHypCurveOverlay> createState() => _NiedHypCurveOverlayState();
}

class _NiedHypCurveOverlayState extends State<_NiedHypCurveOverlay> {
  List<_NiedHypCurvePanelData> _panels = const [];
  String _signature = '';
  int _requestSerial = 0;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    StationEventTracker.instance.currentNiedEvent.addListener(_scheduleUpdate);
    UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.addListener(
      _onVisibilityChanged,
    );
    _scheduleUpdate();
  }

  @override
  void deactivate() {
    _isActive = false;
    _requestSerial++;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _isActive = true;
    _signature = '';
    _scheduleUpdate();
  }

  @override
  void dispose() {
    _isActive = false;
    _requestSerial++;
    StationEventTracker.instance.currentNiedEvent.removeListener(
      _scheduleUpdate,
    );
    UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.removeListener(
      _onVisibilityChanged,
    );
    super.dispose();
  }

  void _onVisibilityChanged() {
    if (!mounted || !_isActive) return;
    _requestSerial++;
    if (UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value) {
      _signature = '';
      setState(() {});
      _scheduleUpdate();
      return;
    }
    setState(() {});
  }

  void _scheduleUpdate() {
    if (!mounted ||
        !_isActive ||
        !UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value) {
      return;
    }
    final event = StationEventTracker.instance.currentNiedEvent.value;
    final estimate = event?.estimate;
    final rawPanels = estimate?.diagnostics['travel_time_curve_panels'];
    final signature = _curveSignature(event);
    if (signature == _signature) return;
    _signature = signature;
    final serial = ++_requestSerial;
    if (rawPanels is! Iterable || signature.isEmpty) {
      if (_panels.isNotEmpty && mounted && _isActive) {
        setState(() => _panels = const []);
      }
      return;
    }
    final rawPayload = rawPanels.cast<Object?>().toList(growable: false);
    if (!widget.prepareInBackground) {
      final payload = _prepareNiedHypCurvePayload(rawPayload);
      if (!mounted || !_isActive || serial != _requestSerial) return;
      setState(() {
        _panels = _NiedHypCurvePanelData.fromPrepared(payload);
      });
      return;
    }
    compute<List<Object?>, List<Map<String, Object?>>>(
      _prepareNiedHypCurvePayload,
      rawPayload,
    ).then((payload) {
      if (!mounted || !_isActive || serial != _requestSerial) return;
      setState(() {
        _panels = _NiedHypCurvePanelData.fromPrepared(payload);
      });
    });
  }

  static String _curveSignature(SeismicActiveEvent? event) {
    final estimate = event?.estimate;
    if (estimate == null) return '';
    final rawPanels = estimate.diagnostics['travel_time_curve_panels'];
    if (rawPanels is! Iterable) return '';
    Map<Object?, Object?>? selectedPanel;
    for (final rawPanel in rawPanels) {
      if (rawPanel is Map && rawPanel['selected'] == true) {
        selectedPanel = rawPanel;
        break;
      }
    }
    selectedPanel ??= rawPanels.whereType<Map>().firstOrNull;
    final samples = selectedPanel?['samples'];
    final sampleCount = samples is Iterable ? samples.length : 0;
    return <Object?>[
      event!.eventId,
      estimate.method,
      estimate.diagnostics['travel_time_curve_revision'],
      estimate.latitude,
      estimate.longitude,
      estimate.depthKm,
      estimate.originTime?.microsecondsSinceEpoch,
      selectedPanel?['latitude'],
      selectedPanel?['longitude'],
      selectedPanel?['depth_km'],
      selectedPanel?['origin_time'],
      selectedPanel?['error_level'],
      sampleCount,
      identityHashCode(rawPanels),
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    if (!UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value ||
        _panels.isEmpty) {
      return const SizedBox.shrink();
    }
    final scale = UiScale.compact(context);
    final isPhone = UiScale.isPhone(context);
    final viewport = MediaQuery.sizeOf(context);
    final maxSide = math.max(
      1.0,
      math.min(
        viewport.width - 24.0,
        viewport.height - (isPhone ? 112.0 : 48.0),
      ),
    );
    final preferredSide = isPhone ? 240.0 : 300.0 * scale.clamp(0.85, 1.0);
    final side = math.min(preferredSide, maxSide);
    final right = isPhone ? 12.0 : 92.0 * scale.clamp(0.75, 1.0);
    final bottom = isPhone ? 96.0 : 24.0;

    return Positioned(
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('nied-hyp-curve-canvas'),
            size: Size.square(side),
            painter: _NiedHypCurvePainter(panels: _panels),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildNiedHypCurveOverlayForTesting({
  Key? key,
  bool prepareInBackground = false,
}) => _NiedHypCurveOverlay(key: key, prepareInBackground: prepareInBackground);

List<Map<String, Object?>> _prepareNiedHypCurvePayload(
  List<Object?> rawPanels,
) {
  final panels = <Map<String, Object?>>[];
  for (final raw in rawPanels) {
    if (raw is! Map) continue;
    final samples = <Map<String, Object?>>[];
    final rawSamples = raw['samples'];
    if (rawSamples is Iterable) {
      for (final item in rawSamples) {
        if (item is! Map) continue;
        final distance = _niedCurveDiagDouble(item['distance_km']);
        final observed = _niedCurveDiagDouble(item['observed_s']);
        final predicted = _niedCurveDiagDouble(item['predicted_s']);
        final residual = _niedCurveDiagDouble(item['residual_s']);
        if (distance == null ||
            observed == null ||
            predicted == null ||
            residual == null) {
          continue;
        }
        samples.add({
          'code': item['code']?.toString() ?? '',
          'distance_km': distance,
          'epicentral_distance_km':
              _niedCurveDiagDouble(item['epicentral_distance_km']) ?? distance,
          'hypocentral_distance_km': _niedCurveDiagDouble(
            item['hypocentral_distance_km'],
          ),
          'observed_s': observed,
          'predicted_s': predicted,
          'residual_s': residual,
          'weight': _niedCurveDiagDouble(item['weight']) ?? 0.0,
          'level': _niedCurveDiagInt(item['level']),
          'wave': item['wave']?.toString() == 'S' ? 'S' : 'P',
        });
      }
    }

    final curve = <Map<String, Object?>>[];
    final rawCurve = raw['p_curve'] ?? raw['curve'];
    if (rawCurve is Iterable) {
      for (final item in rawCurve) {
        if (item is! Map) continue;
        final distance = _niedCurveDiagDouble(item['distance_km']);
        final arrival = _niedCurveDiagDouble(item['arrival_s']);
        if (distance == null || arrival == null) continue;
        curve.add({'distance_km': distance, 'arrival_s': arrival});
      }
    }

    final sCurve = <Map<String, Object?>>[];
    final rawSCurve = raw['s_curve'];
    if (rawSCurve is Iterable) {
      for (final item in rawSCurve) {
        if (item is! Map) continue;
        final distance = _niedCurveDiagDouble(item['distance_km']);
        final arrival = _niedCurveDiagDouble(item['arrival_s']);
        if (distance == null || arrival == null) continue;
        sCurve.add({'distance_km': distance, 'arrival_s': arrival});
      }
    }

    if (samples.isEmpty || curve.length < 2) continue;
    final latitude = _niedCurveDiagDouble(raw['latitude']);
    final longitude = _niedCurveDiagDouble(raw['longitude']);
    final depthKm = _niedCurveDiagDouble(raw['depth_km']);
    final score = _niedCurveDiagDouble(raw['score']);
    final rmse = _niedCurveDiagDouble(raw['rmse']);
    final errorLevel = _niedCurveDiagDouble(raw['error_level']);
    final activeTimingRmse = _niedCurveDiagDouble(raw['active_timing_rmse']);
    final inactivePenalty = _niedCurveDiagDouble(raw['inactive_penalty']);
    final weightSum = _niedCurveDiagDouble(raw['weight_sum']);
    final stationScale = _niedCurveDiagDouble(raw['station_scale']);
    final waveCountPenaltyMultiplier = _niedCurveDiagDouble(
      raw['wave_count_penalty_multiplier'],
    );
    final pWaveCount = _niedCurveDiagInt(raw['p_wave_count']);
    final sWaveCount = _niedCurveDiagInt(raw['s_wave_count']);
    final effectiveStationCount = _niedCurveDiagInt(
      raw['effective_station_count'],
    );
    final observedMinS = _niedCurveDiagDouble(raw['observed_min_s']);
    final observedMaxS = _niedCurveDiagDouble(raw['observed_max_s']);
    final distanceMaxKm = _niedCurveDiagDouble(raw['distance_max_km']);
    if (latitude == null ||
        longitude == null ||
        depthKm == null ||
        score == null ||
        rmse == null ||
        errorLevel == null ||
        activeTimingRmse == null ||
        inactivePenalty == null ||
        weightSum == null ||
        stationScale == null ||
        waveCountPenaltyMultiplier == null ||
        pWaveCount == null ||
        sWaveCount == null ||
        effectiveStationCount == null ||
        observedMinS == null ||
        observedMaxS == null ||
        distanceMaxKm == null) {
      continue;
    }

    panels.add({
      'label': raw['label']?.toString() ?? '-',
      'selected': raw['selected'] == true,
      'latitude': latitude,
      'longitude': longitude,
      'depth_km': depthKm,
      'origin_time': raw['origin_time']?.toString(),
      'time_reference': raw['time_reference']?.toString(),
      'time_reference_model': raw['time_reference_model']?.toString(),
      'distance_axis_model': raw['distance_axis_model']?.toString(),
      'travel_time_model': raw['travel_time_model']?.toString(),
      'score': score,
      'rmse': rmse,
      'error_level': errorLevel,
      'active_timing_rmse': activeTimingRmse,
      'inactive_penalty': inactivePenalty,
      'weight_sum': weightSum,
      'station_scale': stationScale,
      'wave_count_penalty_multiplier': waveCountPenaltyMultiplier,
      'p_wave_count': pWaveCount,
      's_wave_count': sWaveCount,
      'effective_station_count': effectiveStationCount,
      'observed_min_s': observedMinS,
      'observed_max_s': observedMaxS,
      'distance_max_km': distanceMaxKm,
      'samples': _niedCurveDisplaySamplesPayload(samples),
      'curve': curve,
      's_curve': sCurve,
    });
  }

  panels.sort((a, b) {
    final aSelected = a['selected'] == true;
    final bSelected = b['selected'] == true;
    if (aSelected != bSelected) return aSelected ? -1 : 1;
    final aScore = _niedCurveDiagDouble(a['score']) ?? double.infinity;
    final bScore = _niedCurveDiagDouble(b['score']) ?? double.infinity;
    return aScore.compareTo(bScore);
  });
  return panels.take(4).toList(growable: false);
}

double? _niedCurveDiagDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _niedCurveDiagInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<Map<String, Object?>> _niedCurveDisplaySamplesPayload(
  List<Map<String, Object?>> samples,
) {
  final weighted = samples
      .where((sample) => (_niedCurveDiagDouble(sample['weight']) ?? 0) > 0)
      .toList(growable: false);
  final background = samples
      .where((sample) => (_niedCurveDiagDouble(sample['weight']) ?? 0) <= 0)
      .toList(growable: false);
  return [...weighted, ...background];
}

class _NiedHypCurvePanelData {
  const _NiedHypCurvePanelData({
    required this.label,
    required this.selected,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.originTime,
    required this.timeReference,
    required this.score,
    required this.rmse,
    required this.errorLevel,
    required this.activeTimingRmse,
    required this.inactivePenalty,
    required this.weightSum,
    required this.stationScale,
    required this.waveCountPenaltyMultiplier,
    required this.pWaveCount,
    required this.sWaveCount,
    required this.observedMinSeconds,
    required this.observedMaxSeconds,
    required this.distanceMaxKm,
    required this.weightedSampleCount,
    required this.samples,
    required this.curve,
    required this.sCurve,
  });

  final String label;
  final bool selected;
  final double latitude;
  final double longitude;
  final double depthKm;
  final DateTime? originTime;
  final DateTime? timeReference;
  final double score;
  final double rmse;
  final double errorLevel;
  final double activeTimingRmse;
  final double inactivePenalty;
  final double weightSum;
  final double stationScale;
  final double waveCountPenaltyMultiplier;
  final int pWaveCount;
  final int sWaveCount;
  final double observedMinSeconds;
  final double observedMaxSeconds;
  final double distanceMaxKm;
  final int weightedSampleCount;
  final List<_NiedHypCurveSample> samples;
  final List<_NiedHypCurvePoint> curve;
  final List<_NiedHypCurvePoint> sCurve;

  static List<_NiedHypCurvePanelData> fromPrepared(
    List<Map<String, Object?>> rawPanels,
  ) {
    final panels = <_NiedHypCurvePanelData>[];
    for (final raw in rawPanels) {
      final samples = <_NiedHypCurveSample>[];
      final rawSamples = raw['samples'];
      if (rawSamples is Iterable) {
        for (final item in rawSamples) {
          if (item is! Map) continue;
          final distance = _diagDouble(item['distance_km']);
          final observed = _diagDouble(item['observed_s']);
          final predicted = _diagDouble(item['predicted_s']);
          final residual = _diagDouble(item['residual_s']);
          if (distance == null ||
              observed == null ||
              predicted == null ||
              residual == null) {
            continue;
          }
          samples.add(
            _NiedHypCurveSample(
              code: item['code']?.toString() ?? '',
              distanceKm: distance,
              observedSeconds: observed,
              predictedSeconds: predicted,
              residualSeconds: residual,
              weight: _diagDouble(item['weight']) ?? 0.0,
              level: _diagInt(item['level']),
              wave: item['wave']?.toString() == 'S' ? 'S' : 'P',
            ),
          );
        }
      }
      final curve = <_NiedHypCurvePoint>[];
      final rawCurve = raw['curve'];
      if (rawCurve is Iterable) {
        for (final item in rawCurve) {
          if (item is! Map) continue;
          final distance = _diagDouble(item['distance_km']);
          final arrival = _diagDouble(item['arrival_s']);
          if (distance == null || arrival == null) continue;
          curve.add(_NiedHypCurvePoint(distanceKm: distance, seconds: arrival));
        }
      }
      final sCurve = <_NiedHypCurvePoint>[];
      final rawSCurve = raw['s_curve'];
      if (rawSCurve is Iterable) {
        for (final item in rawSCurve) {
          if (item is! Map) continue;
          final distance = _diagDouble(item['distance_km']);
          final arrival = _diagDouble(item['arrival_s']);
          if (distance == null || arrival == null) continue;
          sCurve.add(
            _NiedHypCurvePoint(distanceKm: distance, seconds: arrival),
          );
        }
      }
      if (samples.isEmpty || curve.length < 2) continue;
      final latitude = _diagDouble(raw['latitude']);
      final longitude = _diagDouble(raw['longitude']);
      final depthKm = _diagDouble(raw['depth_km']);
      final score = _diagDouble(raw['score']);
      final rmse = _diagDouble(raw['rmse']);
      final errorLevel = _diagDouble(raw['error_level']);
      final activeTimingRmse = _diagDouble(raw['active_timing_rmse']);
      final inactivePenalty = _diagDouble(raw['inactive_penalty']);
      final weightSum = _diagDouble(raw['weight_sum']);
      final stationScale = _diagDouble(raw['station_scale']);
      final waveCountPenaltyMultiplier = _diagDouble(
        raw['wave_count_penalty_multiplier'],
      );
      final pWaveCount = _diagInt(raw['p_wave_count']);
      final sWaveCount = _diagInt(raw['s_wave_count']);
      final observedMinS = _diagDouble(raw['observed_min_s']);
      final observedMaxS = _diagDouble(raw['observed_max_s']);
      final distanceMaxKm = _diagDouble(raw['distance_max_km']);
      final weightedSampleCount = _diagInt(raw['effective_station_count']);
      if (latitude == null ||
          longitude == null ||
          depthKm == null ||
          score == null ||
          rmse == null ||
          errorLevel == null ||
          activeTimingRmse == null ||
          inactivePenalty == null ||
          weightSum == null ||
          stationScale == null ||
          waveCountPenaltyMultiplier == null ||
          pWaveCount == null ||
          sWaveCount == null ||
          observedMinS == null ||
          observedMaxS == null ||
          distanceMaxKm == null ||
          weightedSampleCount == null) {
        continue;
      }
      panels.add(
        _NiedHypCurvePanelData(
          label: raw['label']?.toString() ?? '-',
          selected: raw['selected'] == true,
          latitude: latitude,
          longitude: longitude,
          depthKm: depthKm,
          originTime: DateTime.tryParse(raw['origin_time']?.toString() ?? ''),
          timeReference: DateTime.tryParse(
            raw['time_reference']?.toString() ?? '',
          ),
          score: score,
          rmse: rmse,
          errorLevel: errorLevel,
          activeTimingRmse: activeTimingRmse,
          inactivePenalty: inactivePenalty,
          weightSum: weightSum,
          stationScale: stationScale,
          waveCountPenaltyMultiplier: waveCountPenaltyMultiplier,
          pWaveCount: pWaveCount,
          sWaveCount: sWaveCount,
          observedMinSeconds: observedMinS,
          observedMaxSeconds: observedMaxS,
          distanceMaxKm: distanceMaxKm,
          weightedSampleCount: weightedSampleCount,
          samples: samples,
          curve: curve,
          sCurve: sCurve,
        ),
      );
    }
    return panels;
  }

  static double? _diagDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _diagInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _NiedHypCurveSample {
  const _NiedHypCurveSample({
    required this.code,
    required this.distanceKm,
    required this.observedSeconds,
    required this.predictedSeconds,
    required this.residualSeconds,
    required this.weight,
    required this.level,
    required this.wave,
  });

  final String code;
  final double distanceKm;
  final double observedSeconds;
  final double predictedSeconds;
  final double residualSeconds;
  final double weight;
  final int? level;
  final String wave;
}

class _NiedHypCurvePoint {
  const _NiedHypCurvePoint({required this.distanceKm, required this.seconds});

  final double distanceKm;
  final double seconds;
}

({double minX, double maxX, double minY, double maxY})
niedHypCurveDisplayExtent({
  required double distanceMaxKm,
  required double observedMinSeconds,
  required double observedMaxSeconds,
}) {
  final maxX = distanceMaxKm.isFinite && distanceMaxKm > 0
      ? distanceMaxKm
      : 1.0;
  final minY = observedMinSeconds.isFinite ? observedMinSeconds : 0.0;
  final rawMaxY = observedMaxSeconds.isFinite ? observedMaxSeconds : minY;
  final maxY = rawMaxY > minY ? rawMaxY : minY + 1.0;
  return (minX: 0.0, maxX: maxX, minY: minY, maxY: maxY);
}

class _NiedHypCurvePainter extends CustomPainter {
  const _NiedHypCurvePainter({required this.panels});

  final List<_NiedHypCurvePanelData> panels;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xEAF8F8F8);
    canvas.drawRect(Offset.zero & size, bg);
    if (panels.length == 1) {
      _drawPanel(
        canvas,
        Rect.fromLTWH(10, 12, size.width - 20, size.height - 24),
        panels.first,
        large: true,
      );
      return;
    }
    final mainW = size.width * 0.42;
    final gap = 10.0;
    final mainRect = Rect.fromLTWH(10, 12, mainW - 16, size.height - 24);
    _drawPanel(canvas, mainRect, panels.first, large: true);

    final smallPanels = panels.skip(1).take(2).toList(growable: false);
    final rightX = mainW + gap;
    final smallW = (size.width - rightX - 12 - gap) / 2;
    final smallH = (size.height - 30) / 2;
    for (var i = 0; i < smallPanels.length; i++) {
      final row = i ~/ 2;
      final col = i % 2;
      final rect = Rect.fromLTWH(
        rightX + col * (smallW + gap),
        14 + row * (smallH + 8),
        smallW,
        smallH,
      );
      _drawPanel(canvas, rect, smallPanels[i], large: false);
    }
  }

  void _drawPanel(
    Canvas canvas,
    Rect rect,
    _NiedHypCurvePanelData panel, {
    required bool large,
  }) {
    final compactSquare = large && rect.width < 400;
    final border = Paint()
      ..color = panel.selected
          ? const Color(0xFF5B3BE8)
          : const Color(0xFF989898)
      ..style = PaintingStyle.stroke
      ..strokeWidth = large ? 1.6 : 1.1;
    final axis = Paint()
      ..color = const Color(0xFF8A8A8A)
      ..strokeWidth = 1.0;
    final grid = Paint()
      ..color = const Color(0xFFD8D8D8)
      ..strokeWidth = 0.6;
    canvas.drawRect(rect, border);

    final plot = Rect.fromLTRB(
      rect.left + (large ? 38 : 26),
      rect.top + (large ? (compactSquare ? 86 : 72) : 34),
      rect.right - 10,
      rect.bottom - (large ? 24 : 16),
    );
    final ext = _extent(panel);
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      axis,
    );
    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.left, plot.bottom),
      axis,
    );
    canvas.drawLine(
      Offset(plot.left, (plot.top + plot.bottom) / 2),
      Offset(plot.right, (plot.top + plot.bottom) / 2),
      grid,
    );

    canvas.save();
    canvas.clipRect(plot);
    _drawTravelTimeCurve(
      canvas,
      plot,
      ext,
      panel.curve,
      color: panel.selected ? const Color(0xFF2457D6) : const Color(0xFF00A5B8),
      strokeWidth: large ? 3.2 : 2.4,
    );
    if (panel.samples.any((sample) => sample.wave == 'S')) {
      _drawTravelTimeCurve(
        canvas,
        plot,
        ext,
        panel.sCurve,
        color: panel.selected
            ? const Color(0xFFD93636)
            : const Color(0xFFD96B36),
        strokeWidth: large ? 3.2 : 2.4,
      );
    }
    _drawStationResiduals(canvas, plot, ext, panel.samples, large: large);
    canvas.restore();

    for (final sample in panel.samples) {
      final point = _toPlot(
        plot,
        ext,
        sample.distanceKm,
        sample.observedSeconds,
      );
      final activeWeight = sample.weight > 0;
      final radius = activeWeight ? (large ? 4.0 : 3.0) : (large ? 2.5 : 2.0);
      _drawSampleMarker(
        canvas,
        point,
        radius: radius,
        color: _sampleColor(
          sample.level,
        ).withValues(alpha: activeWeight ? 0.88 : 0.22),
        shadowColor: Colors.black.withValues(alpha: activeWeight ? 0.18 : 0.06),
        sWave: sample.wave == 'S',
      );
      if (activeWeight && large && sample.weight >= 1.0) {
        canvas.drawCircle(
          point,
          radius + 1.4,
          Paint()
            ..color = const Color(0xFF202020).withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }

    _drawText(
      canvas,
      large
          ? compactSquare
                ? '当前震源 ${panel.latitude.toStringAsFixed(3)}, ${panel.longitude.toStringAsFixed(3)}'
                : '当前震源 ${panel.latitude.toStringAsFixed(3)}, ${panel.longitude.toStringAsFixed(3)}  深${panel.depthKm.toStringAsFixed(0)}km'
          : '${panel.label} ${panel.score.toStringAsFixed(2)}',
      Offset(rect.left + 8, rect.top + 6),
      color: panel.selected ? const Color(0xFFD92323) : Colors.black87,
      size: large ? (compactSquare ? 12.5 : 17) : 12,
      weight: FontWeight.w800,
      maxWidth: rect.width - 16,
    );
    _drawText(
      canvas,
      large
          ? compactSquare
                ? '深${panel.depthKm.toStringAsFixed(0)}km  误差 ${panel.errorLevel.toStringAsFixed(2)}  点RMSE ${panel.activeTimingRmse.toStringAsFixed(2)}s'
                : '发生 ${_formatOriginTime(panel.originTime)}  搜索分值 ${panel.score.toStringAsFixed(3)}'
          : '点RMSE ${panel.activeTimingRmse.toStringAsFixed(2)}s',
      Offset(rect.left + 8, rect.top + (large ? 28 : 18)),
      color: Colors.black87,
      size: large ? (compactSquare ? 9 : 10) : 8,
      weight: FontWeight.w600,
      maxWidth: rect.width - 16,
    );
    if (large) {
      _drawText(
        canvas,
        compactSquare
            ? '发生 ${_formatOriginTime(panel.originTime)}  t0 ${_formatOriginTime(panel.timeReference)}'
            : '误差水平 ${panel.errorLevel.toStringAsFixed(2)}  点RMSE ${panel.activeTimingRmse.toStringAsFixed(2)}s  含未着RMSE ${panel.rmse.toStringAsFixed(2)}s',
        Offset(rect.left + 8, rect.top + 42),
        color: Colors.black87,
        size: compactSquare ? 8.5 : 9,
        weight: FontWeight.w600,
        maxWidth: rect.width - 16,
      );
      _drawText(
        canvas,
        compactSquare
            ? '分值${panel.score.toStringAsFixed(3)}  总RMSE${panel.rmse.toStringAsFixed(2)}s  未着${panel.inactivePenalty.toStringAsFixed(0)}  使用${panel.weightedSampleCount}站'
            : '未着 ${panel.inactivePenalty.toStringAsFixed(2)}  使用 ${panel.weightedSampleCount}站',
        Offset(rect.left + 8, rect.top + 56),
        color: Colors.black87,
        size: compactSquare ? 7.5 : 9,
        weight: FontWeight.w600,
        maxWidth: rect.width - 16,
      );
      if (compactSquare) {
        _drawText(
          canvas,
          'P${panel.pWaveCount} S${panel.sWaveCount}  S系数${panel.waveCountPenaltyMultiplier.toStringAsFixed(2)}  权重${panel.weightSum.toStringAsFixed(1)}  尺度${panel.stationScale.toStringAsFixed(1)}',
          Offset(rect.left + 8, rect.top + 70),
          color: Colors.black87,
          size: 7.5,
          weight: FontWeight.w600,
          maxWidth: rect.width - 16,
        );
      }
    }
    _drawAxisValue(
      canvas,
      _axisValue(ext.minX),
      Offset(plot.left, plot.bottom + 2),
      align: TextAlign.left,
      large: large,
    );
    _drawAxisValue(
      canvas,
      '${_axisValue(ext.maxX)}km',
      Offset(plot.right, plot.bottom + 2),
      align: TextAlign.right,
      large: large,
    );
    _drawAxisValue(
      canvas,
      '${_axisValue(ext.minY)}s',
      Offset(plot.left - 3, plot.bottom - (large ? 10 : 8)),
      align: TextAlign.right,
      large: large,
    );
    _drawAxisValue(
      canvas,
      '${_axisValue(ext.maxY)}s',
      Offset(plot.left - 3, plot.top - 1),
      align: TextAlign.right,
      large: large,
    );
  }

  String _formatOriginTime(DateTime? value) {
    if (value == null) return '--:--:--.---';
    String two(int number) => number.toString().padLeft(2, '0');
    final millis = value.millisecond.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.$millis';
  }

  void _drawStationResiduals(
    Canvas canvas,
    Rect plot,
    ({double minX, double maxX, double minY, double maxY}) ext,
    List<_NiedHypCurveSample> samples, {
    required bool large,
  }) {
    final paint = Paint()
      ..color = const Color(0xFF333333).withValues(alpha: 0.42)
      ..strokeWidth = large ? 1.25 : 0.9
      ..strokeCap = StrokeCap.round;
    final predictedPaint = Paint()
      ..color = const Color(0xFF333333).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = large ? 0.9 : 0.7;
    for (final sample in samples) {
      if (sample.weight <= 0) continue;
      final residualAlpha = (0.28 + sample.residualSeconds.abs() / 6.0).clamp(
        0.28,
        0.72,
      );
      paint.color = const Color(0xFF333333).withValues(alpha: residualAlpha);
      final observed = _toPlot(
        plot,
        ext,
        sample.distanceKm,
        sample.observedSeconds,
        clamp: false,
      );
      final predicted = _toPlot(
        plot,
        ext,
        sample.distanceKm,
        sample.predictedSeconds,
        clamp: false,
      );
      canvas.drawLine(predicted, observed, paint);
      canvas.drawCircle(predicted, large ? 1.7 : 1.2, predictedPaint);
    }
  }

  void _drawSampleMarker(
    Canvas canvas,
    Offset point, {
    required double radius,
    required Color color,
    required Color shadowColor,
    required bool sWave,
  }) {
    if (!sWave) {
      canvas.drawCircle(
        point.translate(1.2, 1.2),
        radius,
        Paint()..color = shadowColor,
      );
      canvas.drawCircle(point, radius, Paint()..color = color);
      return;
    }
    Path diamond(Offset center) => Path()
      ..moveTo(center.dx, center.dy - radius - 1)
      ..lineTo(center.dx + radius + 1, center.dy)
      ..lineTo(center.dx, center.dy + radius + 1)
      ..lineTo(center.dx - radius - 1, center.dy)
      ..close();

    canvas.drawPath(
      diamond(point.translate(1.2, 1.2)),
      Paint()..color = shadowColor,
    );
    canvas.drawPath(diamond(point), Paint()..color = color);
    canvas.drawPath(
      diamond(point),
      Paint()
        ..color = const Color(0xFFD93636)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawTravelTimeCurve(
    Canvas canvas,
    Rect plot,
    ({double minX, double maxX, double minY, double maxY}) ext,
    List<_NiedHypCurvePoint> curve, {
    required Color color,
    required double strokeWidth,
  }) {
    if (curve.length < 2) return;
    final path = Path();
    for (var i = 0; i < curve.length; i++) {
      final point = _toPlot(
        plot,
        ext,
        curve[i].distanceKm,
        curve[i].seconds,
        clamp: false,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  ({double minX, double maxX, double minY, double maxY}) _extent(
    _NiedHypCurvePanelData panel,
  ) {
    return niedHypCurveDisplayExtent(
      distanceMaxKm: panel.distanceMaxKm,
      observedMinSeconds: panel.observedMinSeconds,
      observedMaxSeconds: panel.observedMaxSeconds,
    );
  }

  String _axisValue(double value) {
    if ((value - value.roundToDouble()).abs() < 1e-6) {
      return value.round().toString();
    }
    return value.toStringAsFixed(value.abs() >= 100 ? 1 : 2);
  }

  void _drawAxisValue(
    Canvas canvas,
    String text,
    Offset anchor, {
    required TextAlign align,
    required bool large,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black54,
          fontSize: large ? 8 : 6.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrainsMono',
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout();
    final dx = align == TextAlign.right ? anchor.dx - painter.width : anchor.dx;
    painter.paint(canvas, Offset(dx, anchor.dy));
  }

  Offset _toPlot(
    Rect plot,
    ({double minX, double maxX, double minY, double maxY}) ext,
    double x,
    double y, {
    bool clamp = true,
  }) {
    var tx = (x - ext.minX) / (ext.maxX - ext.minX);
    var ty = (y - ext.minY) / (ext.maxY - ext.minY);
    if (clamp) {
      tx = tx.clamp(0.0, 1.0);
      ty = ty.clamp(0.0, 1.0);
    }
    return Offset(plot.left + tx * plot.width, plot.bottom - ty * plot.height);
  }

  Color _sampleColor(int? level) {
    return KaShindoMarkerStyle.colorForLevel(level ?? -1);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double size,
    required FontWeight weight,
    double maxWidth = 360,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'JetBrainsMono',
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _NiedHypCurvePainter oldDelegate) =>
      oldDelegate.panels != panels;
}
