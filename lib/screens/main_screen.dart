import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show compute;
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/map_state_provider.dart';
import '../providers/quake_provider.dart';
import '../widgets/map/quake_map_view.dart';
import '../widgets/map/source_dashboard.dart';
import '../widgets/ui/alert_module.dart';
import '../widgets/ui/eqlist_panel.dart';
import '../widgets/ui/history_panel.dart';
import '../widgets/ui/top_status_bar.dart';
import '../widgets/ui/weather_marquee.dart';
import '../widgets/ui/settings_page.dart';
import '../widgets/ui/station_dashboard.dart';
import '../widgets/ui/ui_runtime_flags.dart';
import '../widgets/ui/ui_scale.dart';
import '../widgets/ui/app_page_background.dart';
import '../core/source_estimation/source_estimation_models.dart';
import '../core/source_estimation/station_event_tracker.dart';
import '../services/sources/shake_detection_service.dart';
import '../services/sources/global_quake_service.dart';
import '../models/tsunami_message.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late final MapController _mapController;

  StationSummaryData _stationData = StationSummaryData();
  final ValueNotifier<StationSummaryData> _stationDataNotifier =
      ValueNotifier<StationSummaryData>(StationSummaryData());
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showInfoDrawer = false;
  bool _phoneActionsExpanded = false;
  bool _sideInfoAutoShowBeta = true;
  bool _infoOpenedByAuto = false;
  Timer? _infoAutoHideTimer;
  String? _lastAutoTriggerSignature;
  String _lastNiedInfoSignature = '-';
  String _lastSnetInfoSignature = '-';
  String _lastJmaTsunamiInfoSignature = '-';
  String _lastNmefcTsunamiInfoSignature = '-';
  String? _pendingInfoPageKey;
  int _infoPageIndex = 0;
  Timer? _infoPageCarousel;
  List<String> _lastInfoPageKeys = const [];
  String _lastInfoPageKeysSignature = '';
  String _lastStationDataUiSignature = '';

  static const double _refWidth = 1700.0;
  static const double _stationPanelVisualHeight = 104.0;
  static const double _infoPanelHeight = 186.0;
  static const double _stationPanelWidth = 234.0;
  static const String _sideInfoAutoShowBetaKey = 'side_info_auto_show_beta';
  static const String _infoPageNied = 'nied';
  static const String _infoPageSnet = 'snet';
  static const String _infoPageJmaTsunami = 'jmaTsunami';
  static const String _infoPageNmefcTsunami = 'nmefcTsunami';

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
    // 延迟关联控制器，确保 Provider 已准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapStateProvider>().setController(_mapController, this);
      AppPageBackground.cachedBytes();
    });
  }

  @override
  void dispose() {
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.removeListener(
      _onSideInfoAutoShowSettingChanged,
    );
    _infoAutoHideTimer?.cancel();
    _infoPageCarousel?.cancel();
    _stationDataNotifier.dispose();
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

          // 3. 右侧数据源状态面板
          if (!isPhone && !_showInfoDrawer) const SourceDashboard(),

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
                  selector: (context, provider) => provider.cencIrData != null,
                  builder: (context, hasData, _) {
                    return _buildCircularButton(
                      context: context,
                      icon: hasData ? Icons.waves : Icons.waves_outlined,
                      tooltip: hasData ? '关闭 CENC 烈度速报' : 'CENC 烈度速报',
                      color: hasData
                          ? const Color(0xFF2ECC71)
                          : Colors.blueAccent,
                      onPressed: () {
                        final provider = context.read<QuakeProvider>();
                        if (hasData) {
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
                    context.read<MapStateProvider>().recenterToDefaultView();
                  },
                ),
              ],
            ),
          ),
          if (isPhone) ..._buildPhoneOverlays(context),
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
                                .recenterToDefaultView();
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
                              provider.cencIrData != null,
                          builder: (context, hasData, _) {
                            return _buildPhoneActionButton(
                              context,
                              icon: hasData
                                  ? Icons.waves
                                  : Icons.waves_outlined,
                              tooltip: hasData ? '关闭 CENC 烈度速报' : 'CENC 烈度速报',
                              color: hasData
                                  ? const Color(0xFF2ECC71)
                                  : Colors.blueAccent,
                              onPressed: () {
                                final provider = context.read<QuakeProvider>();
                                if (hasData) {
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
        final hasSnet = _stationData.snetTopStations.isNotEmpty;
        final jmaTsunami = provider.jmaTsunami;
        final hasJmaTsunami =
            jmaTsunami != null &&
            (jmaTsunami.isActive || jmaTsunami.areas.isNotEmpty);
        final nmefc = provider.nmefcTsunami;
        final hasNmefc = nmefc != null && nmefc.isActive;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleAutoInfoPopup(_stationData, provider);
        });

        final mainPages = <_InfoDrawerPage>[];
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

        if (!showCarousel) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_infoOpenedByAuto || !_showInfoDrawer) return;
            _infoAutoHideTimer?.cancel();
            setState(() {
              _showInfoDrawer = false;
              _infoOpenedByAuto = false;
            });
          });
          return const SizedBox.shrink();
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
                  color: const Color(0xC21A2435),
                  borderRadius: BorderRadius.circular(_s(10, context)),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: _s(0.7, context),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: _s(14, context),
                      offset: Offset(0, _s(5, context)),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 380),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0.08, 0),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: showCarousel
                          ? KeyedSubtree(
                              key: ValueKey(mainPages[_infoPageIndex].key),
                              child: _buildInfoSurface(
                                context,
                                mainPages[_infoPageIndex].child,
                              ),
                            )
                          : const SizedBox.shrink(),
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
      padding: EdgeInsets.symmetric(
        horizontal: _s(8, context),
        vertical: _s(7, context),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: _s(0.6, context),
        ),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: _s(0.6, context),
        ),
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

    final rows = <Widget>[];
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

    if (strong.isNotEmpty) {
      final prefs = groupByPref(strong);
      rows.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                '強い揺れを検出',
                style: titleStyle.copyWith(color: colorStrong),
              ),
            ),
            SizedBox(height: _s(2, context)),
            Text(prefs.values.join('  '), style: textStyle),
          ],
        ),
      );
    }
    if (detected.isNotEmpty) {
      final prefs = groupByPref(detected);
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: strong.isNotEmpty ? _s(6, context) : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  '揺れを検出',
                  style: titleStyle.copyWith(color: colorDetected),
                ),
              ),
              SizedBox(height: _s(2, context)),
              Text(prefs.values.join('  '), style: textStyle),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: _s(2, context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
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
    setState(() => _sideInfoAutoShowBeta = enabled);
    UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value = enabled;
  }

  void _onSideInfoAutoShowSettingChanged() {
    if (!mounted) return;
    final enabled = UiRuntimeFlags.sideInfoAutoShowBetaNotifier.value;
    if (_sideInfoAutoShowBeta == enabled) return;
    setState(() => _sideInfoAutoShowBeta = enabled);
    if (!enabled && _infoOpenedByAuto) {
      _infoAutoHideTimer?.cancel();
      setState(() {
        _showInfoDrawer = false;
        _infoOpenedByAuto = false;
      });
    }
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
    _checkNiedAutoHide(data, provider);
  }

  String _stationDataUiSignature(StationSummaryData data) {
    final seis = data.seisJsStation;
    final nied = data.niedMaxStation;
    final trea = data.treaMaxStation;
    final kma = data.kmaMaxStation;
    return [
      seis?.shindo ?? -1,
      seis?.maxIntensity.toStringAsFixed(2) ?? '-',
      seis?.pga.toStringAsFixed(1) ?? '-',
      nied?.level ?? -1,
      trea?.currentIntensity.toStringAsFixed(1) ?? '-',
      kma?.intensity ?? -3,
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

  void _checkNiedAutoHide(StationSummaryData data, QuakeProvider provider) {
    if (!_infoOpenedByAuto) return;
    if (_hasActiveTsunami(provider) || data.snetTopStations.isNotEmpty) {
      _infoAutoHideTimer?.cancel();
      return;
    }
    final isDetecting = _hasFormalNiedDetect(data);
    if (isDetecting) {
      _infoAutoHideTimer?.cancel();
    } else if (_infoAutoHideTimer == null || !_infoAutoHideTimer!.isActive) {
      _scheduleAutoInfoHide();
    }
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
    final tsunamiHold = _hasActiveTsunami(provider);
    final shouldShow = _hasAutoInfoContent(data, provider);

    if (!shouldShow) {
      _lastAutoTriggerSignature = null;
      _lastNiedInfoSignature = '-';
      _lastSnetInfoSignature = '-';
      _lastJmaTsunamiInfoSignature = '-';
      _lastNmefcTsunamiInfoSignature = '-';
      _pendingInfoPageKey = null;
      if (_infoOpenedByAuto &&
          (_infoAutoHideTimer == null || !_infoAutoHideTimer!.isActive)) {
        _scheduleAutoInfoHide();
      }
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
        '$niedSignature|$snetSignature|$jmaTsunamiSignature|$nmefcTsunamiSignature';
    if (signature == _lastAutoTriggerSignature) {
      if (!_showInfoDrawer) {
        setState(() {
          _showInfoDrawer = true;
          _infoOpenedByAuto = true;
          if (detectTriggered) {
            _pendingInfoPageKey = _infoPageNied;
          }
        });
      }
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
    _lastNiedInfoSignature = niedSignature;
    _lastSnetInfoSignature = snetSignature;
    _lastJmaTsunamiInfoSignature = jmaTsunamiSignature;
    _lastNmefcTsunamiInfoSignature = nmefcTsunamiSignature;

    setState(() {
      _showInfoDrawer = true;
      _infoOpenedByAuto = true;
      if (focusPageKey != null) {
        _pendingInfoPageKey = focusPageKey;
      }
    });
    if (tsunamiHold) {
      _infoAutoHideTimer?.cancel();
      return;
    }
    if (detectTriggered) {
      final stage = data.niedDetect?.stage ?? '';
      if (stage == 'strong' || stage == 'detected') {
        _infoAutoHideTimer?.cancel();
      } else {
        _scheduleAutoInfoHide();
      }
    } else {
      _scheduleAutoInfoHide();
    }
  }

  bool _hasActiveTsunami(QuakeProvider provider) {
    return provider.jmaTsunami?.isActive == true ||
        provider.nmefcTsunami?.isActive == true;
  }

  void _scheduleAutoInfoHide() {
    _infoAutoHideTimer?.cancel();
    _infoAutoHideTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || !_infoOpenedByAuto) return;
      setState(() {
        _showInfoDrawer = false;
        _infoOpenedByAuto = false;
      });
    });
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
                    '可从 FAN 数据源获取最近的烈度速报',
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
                  final isActive =
                      provider.cencIrData != null &&
                      provider.cencIrData!.uniEventId ==
                          item['uniEventId']?.toString();

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
                      provider.requestCencIrDetail(id);
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

class _NiedHypCurveOverlay extends StatefulWidget {
  const _NiedHypCurveOverlay();

  @override
  State<_NiedHypCurveOverlay> createState() => _NiedHypCurveOverlayState();
}

class _NiedHypCurveOverlayState extends State<_NiedHypCurveOverlay> {
  List<_NiedHypCurvePanelData> _panels = const [];
  String _signature = '';
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    StationEventTracker.instance.currentNiedEvent.addListener(_scheduleUpdate);
    _scheduleUpdate();
  }

  @override
  void dispose() {
    StationEventTracker.instance.currentNiedEvent.removeListener(
      _scheduleUpdate,
    );
    super.dispose();
  }

  void _scheduleUpdate() {
    final estimate =
        StationEventTracker.instance.currentNiedEvent.value?.estimate;
    final rawPanels = estimate?.diagnostics['travel_time_curve_panels'];
    final signature = _curveSignature(estimate);
    if (signature == _signature) return;
    _signature = signature;
    final serial = ++_requestSerial;
    if (rawPanels is! Iterable || signature.isEmpty) {
      if (_panels.isNotEmpty && mounted) {
        setState(() => _panels = const []);
      }
      return;
    }
    compute<List<Object?>, List<Map<String, Object?>>>(
      _prepareNiedHypCurvePayload,
      rawPanels.cast<Object?>().toList(growable: false),
    ).then((payload) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _panels = _NiedHypCurvePanelData.fromPrepared(payload);
      });
    });
  }

  static String _curveSignature(SourceEstimate? estimate) {
    if (estimate == null) return '';
    final d = estimate.diagnostics;
    return [
      estimate.method,
      estimate.latitude.toStringAsFixed(3),
      estimate.longitude.toStringAsFixed(3),
      estimate.depthKm?.toStringAsFixed(1) ?? '-',
      d['score'],
      d['effective_station_count'],
      d['worker_candidate_held_by_score_gate'],
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    final scale = UiScale.compact(context);
    final isPhone = UiScale.isPhone(context);
    final width = isPhone
        ? math.min(360.0, MediaQuery.sizeOf(context).width - 24)
        : 560.0 * scale.clamp(0.75, 1.0);
    final height = isPhone ? 176.0 : 268.0 * scale.clamp(0.78, 1.0);
    final right = isPhone ? 12.0 : 92.0 * scale.clamp(0.75, 1.0);
    final bottom = isPhone ? 96.0 : 24.0;

    return Positioned(
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: _panels.isEmpty
            ? const SizedBox.shrink()
            : RepaintBoundary(
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _NiedHypCurvePainter(panels: _panels),
                ),
              ),
      ),
    );
  }
}

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
        if (distance == null || observed == null || predicted == null) {
          continue;
        }
        samples.add({
          'distance_km': distance,
          'observed_s': observed,
          'predicted_s': predicted,
          'weight': _niedCurveDiagDouble(item['weight']) ?? 0.0,
          'level': _niedCurveDiagInt(item['level']),
        });
      }
    }

    final curve = <Map<String, Object?>>[];
    final rawCurve = raw['curve'];
    if (rawCurve is Iterable) {
      for (final item in rawCurve) {
        if (item is! Map) continue;
        final distance = _niedCurveDiagDouble(item['distance_km']);
        final arrival = _niedCurveDiagDouble(item['arrival_s']);
        if (distance == null || arrival == null) continue;
        curve.add({'distance_km': distance, 'arrival_s': arrival});
      }
    }

    if (samples.isEmpty || curve.length < 2) continue;
    final latitude = _niedCurveDiagDouble(raw['latitude']);
    final longitude = _niedCurveDiagDouble(raw['longitude']);
    final depthKm = _niedCurveDiagDouble(raw['depth_km']);
    final score = _niedCurveDiagDouble(raw['score']);
    final rmse = _niedCurveDiagDouble(raw['rmse']);
    final observedMinS = _niedCurveDiagDouble(raw['observed_min_s']);
    final observedMaxS = _niedCurveDiagDouble(raw['observed_max_s']);
    final distanceMaxKm = _niedCurveDiagDouble(raw['distance_max_km']);
    if (latitude == null ||
        longitude == null ||
        depthKm == null ||
        score == null ||
        rmse == null ||
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
      'score': score,
      'rmse': rmse,
      'observed_min_s': observedMinS,
      'observed_max_s': observedMaxS,
      'distance_max_km': distanceMaxKm,
      'weighted_sample_count': samples
          .where((sample) => (_niedCurveDiagDouble(sample['weight']) ?? 0) > 0)
          .length,
      'samples': _niedCurveDisplaySamplesPayload(samples),
      'curve': curve,
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
      .take(48)
      .toList(growable: false);
  final background = samples
      .where((sample) => (_niedCurveDiagDouble(sample['weight']) ?? 0) <= 0)
      .take(math.max(0, 56 - weighted.length))
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
    required this.score,
    required this.rmse,
    required this.observedMinSeconds,
    required this.observedMaxSeconds,
    required this.distanceMaxKm,
    required this.weightedSampleCount,
    required this.samples,
    required this.curve,
  });

  final String label;
  final bool selected;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double score;
  final double rmse;
  final double observedMinSeconds;
  final double observedMaxSeconds;
  final double distanceMaxKm;
  final int weightedSampleCount;
  final List<_NiedHypCurveSample> samples;
  final List<_NiedHypCurvePoint> curve;

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
          if (distance == null || observed == null || predicted == null) {
            continue;
          }
          samples.add(
            _NiedHypCurveSample(
              distanceKm: distance,
              observedSeconds: observed,
              predictedSeconds: predicted,
              weight: _diagDouble(item['weight']) ?? 0.0,
              level: _diagInt(item['level']),
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
      if (samples.isEmpty || curve.length < 2) continue;
      final latitude = _diagDouble(raw['latitude']);
      final longitude = _diagDouble(raw['longitude']);
      final depthKm = _diagDouble(raw['depth_km']);
      final score = _diagDouble(raw['score']);
      final rmse = _diagDouble(raw['rmse']);
      final observedMinS = _diagDouble(raw['observed_min_s']);
      final observedMaxS = _diagDouble(raw['observed_max_s']);
      final distanceMaxKm = _diagDouble(raw['distance_max_km']);
      final weightedSampleCount = _diagInt(raw['weighted_sample_count']);
      if (latitude == null ||
          longitude == null ||
          depthKm == null ||
          score == null ||
          rmse == null ||
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
          score: score,
          rmse: rmse,
          observedMinSeconds: observedMinS,
          observedMaxSeconds: observedMaxS,
          distanceMaxKm: distanceMaxKm,
          weightedSampleCount: weightedSampleCount,
          samples: samples,
          curve: curve,
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
    required this.distanceKm,
    required this.observedSeconds,
    required this.predictedSeconds,
    required this.weight,
    required this.level,
  });

  final double distanceKm;
  final double observedSeconds;
  final double predictedSeconds;
  final double weight;
  final int? level;
}

class _NiedHypCurvePoint {
  const _NiedHypCurvePoint({required this.distanceKm, required this.seconds});

  final double distanceKm;
  final double seconds;
}

class _NiedHypCurvePainter extends CustomPainter {
  const _NiedHypCurvePainter({required this.panels});

  final List<_NiedHypCurvePanelData> panels;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xEAF8F8F8);
    canvas.drawRect(Offset.zero & size, bg);
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
      rect.top + (large ? 42 : 30),
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

    final line = Path();
    for (var i = 0; i < panel.curve.length; i++) {
      final p = _toPlot(
        plot,
        ext,
        panel.curve[i].distanceKm,
        panel.curve[i].seconds,
        clamp: false,
      );
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
    }
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(
      line,
      Paint()
        ..color = panel.selected
            ? const Color(0xFF5B3BE8)
            : const Color(0xFF00B7C8)
        ..strokeWidth = large ? 4.0 : 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
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
      canvas.drawCircle(
        point.translate(1.2, 1.2),
        radius,
        Paint()
          ..color = Colors.black.withValues(alpha: activeWeight ? 0.18 : 0.06),
      );
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = _sampleColor(
            sample.level,
          ).withValues(alpha: activeWeight ? 0.88 : 0.22),
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
      large ? '误差 ${panel.score.toStringAsFixed(3)}' : panel.label,
      Offset(rect.left + 8, rect.top + 6),
      color: panel.selected ? const Color(0xFFD92323) : Colors.black87,
      size: large ? 17 : 12,
      weight: FontWeight.w800,
    );
    _drawText(
      canvas,
      'rmse ${panel.rmse.toStringAsFixed(2)}  W${panel.weightedSampleCount}/${panel.samples.length}  ${panel.latitude.toStringAsFixed(2)}, ${panel.longitude.toStringAsFixed(2)}  深${panel.depthKm.toStringAsFixed(0)}km',
      Offset(rect.left + 8, rect.top + (large ? 28 : 18)),
      color: Colors.black87,
      size: large ? 10 : 8,
      weight: FontWeight.w600,
    );
    if (large) {
      _drawText(
        canvas,
        '距离(km)',
        Offset(plot.right - 48, plot.bottom + 5),
        color: Colors.black54,
        size: 10,
        weight: FontWeight.w600,
      );
      _drawText(
        canvas,
        '时刻(s)',
        Offset(plot.left - 2, rect.top + 22),
        color: Colors.black54,
        size: 10,
        weight: FontWeight.w600,
      );
    }
  }

  ({double minX, double maxX, double minY, double maxY}) _extent(
    _NiedHypCurvePanelData panel,
  ) {
    var maxX = math.max(1.0, panel.distanceMaxKm);
    var minY = panel.observedMinSeconds;
    var maxY = panel.observedMaxSeconds;
    for (final sample in panel.samples) {
      maxX = math.max(maxX, sample.distanceKm);
      minY = math.min(minY, sample.observedSeconds);
      maxY = math.max(maxY, sample.observedSeconds);
    }
    if (!minY.isFinite || !maxY.isFinite || (maxY - minY).abs() < 1e-6) {
      minY = -1;
      maxY = 1;
    }
    final padY = math.max(0.8, (maxY - minY) * 0.12);
    return (minX: 0, maxX: maxX * 1.04, minY: minY - padY, maxY: maxY + padY);
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
    final v = level ?? -1;
    if (v >= 22) return const Color(0xFFE53935);
    if (v >= 16) return const Color(0xFFFF8F24);
    if (v >= 10) return const Color(0xFFF4D83A);
    if (v >= 6) return const Color(0xFF62F148);
    return const Color(0xFF111111);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double size,
    required FontWeight weight,
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
      ellipsis: '',
    )..layout(maxWidth: 360);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _NiedHypCurvePainter oldDelegate) =>
      oldDelegate.panels != panels;
}
