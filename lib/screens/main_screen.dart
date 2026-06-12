import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
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
import '../widgets/ui/app_page_background.dart';
import '../services/sources/shake_detection_service.dart';
import '../models/tsunami_message.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late final MapController _mapController;

  StationSummaryData _stationData = StationSummaryData();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showInfoDrawer = false;
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

  static const double _refWidth = 1700.0;
  static const double _rightButtonsVisualHeight = 244.0;
  static const double _stationPanelVisualHeight = 104.0;
  static const double _infoPanelHeight = 186.0;
  static const double _stationPanelWidth = 234.0;
  static const String _sideInfoAutoShowBetaKey = 'side_info_auto_show_beta';
  static const String _infoPageNied = 'nied';
  static const String _infoPageSnet = 'snet';
  static const String _infoPageJmaTsunami = 'jmaTsunami';
  static const String _infoPageNmefcTsunami = 'nmefcTsunami';

  double _scale(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    return (w / _refWidth).clamp(0.55, 1.0);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  double _infoPanelWidth(BuildContext context) {
    return _stationPanelWidth;
  }

  double _rightInfoPanelTop(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final stationTop = 50 + _s(12, context);
    final stationBottom = stationTop + _stationPanelVisualHeight;
    final rightButtonsTop =
        screenH - _s(30, context) - _rightButtonsVisualHeight;
    final middle = (stationBottom + rightButtonsTop) / 2;
    final panelTop = middle - _infoPanelHeight / 2;
    final lower = stationBottom + 8;
    final upper = rightButtonsTop - _infoPanelHeight - 8;
    if (lower > upper) return middle - _infoPanelHeight / 2;
    return panelTop.clamp(lower, upper);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    "历史预警记录",
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
          // 1. 地图背景
          QuakeMapView(
            mapController: _mapController,
            onStationDataChanged: _onStationDataChanged,
          ),

          // 2. 顶部状态栏
          const Positioned(top: 0, left: 0, right: 0, child: TopStatusBar()),

          // 3. 数据源状态面板 (内置 Positioned)
          if (!_showInfoDrawer) const SourceDashboard(),

          // 3.2 测站汇总面板
          StationDashboard(data: _stationData),

          Positioned(
            top: _rightInfoPanelTop(context),
            right: 20,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              offset: _showInfoDrawer ? Offset.zero : const Offset(1.05, 0),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 260),
                opacity: _showInfoDrawer ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_showInfoDrawer,
                  child: _buildRightInfoDrawer(),
                ),
              ),
            ),
          ),

          // 3.5 气象预警滚动字幕 (左侧卡片与右侧状态面板之间)
          Positioned(
            top: 50 + _s(12, context),
            left: _s(450, context),
            right: _s(350, context),
            child: const WeatherMarquee(),
          ),

          // 4. 左侧预警模块和地震列表
          Positioned(
            top: 50 + _s(12, context),
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

          // 6. 功能按钮（移动到右下角）
          Positioned(
            bottom: _s(30, context),
            right: _s(20, context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCircularButton(
                  icon: Icons.settings,
                  tooltip: "设置",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Consumer<QuakeProvider>(
                  builder: (context, provider, _) {
                    final hasData = provider.cencIrData != null;
                    return _buildCircularButton(
                      icon: hasData ? Icons.waves : Icons.waves_outlined,
                      tooltip: hasData ? "关闭 CENC 烈度速报" : "CENC 烈度速报",
                      color: hasData
                          ? const Color(0xFF2ECC71)
                          : Colors.blueAccent,
                      onPressed: () {
                        if (hasData) {
                          provider.clearCencIrData();
                        } else {
                          _showCencIrSheet(context);
                        }
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildCircularButton(
                  icon: Icons.history,
                  tooltip: "查看历史",
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(height: 12),
                _buildCircularButton(
                  icon: Icons.my_location,
                  tooltip: "回到中心",
                  onPressed: () {
                    context.read<MapStateProvider>().recenterToDefaultView();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color color = Colors.blueAccent,
  }) {
    return Tooltip(
      message: tooltip ?? "",
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
                padding: const EdgeInsets.all(14),
                child: Icon(icon, color: color, size: 24),
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
        final hasNied =
            detect != null &&
            (detect.stage == 'strong' ||
                detect.stage == 'detected' ||
                detect.stage == 'weak') &&
            detect.detectedStations.isNotEmpty;
        final hasSnet = _stationData.snetTopStations.isNotEmpty;
        final jmaTsunami = provider.jmaTsunami;
        final hasJmaTsunami =
            jmaTsunami != null &&
            (jmaTsunami.isActive || jmaTsunami.areas.isNotEmpty);
        final nmefc = provider.nmefcTsunami;
        final hasNmefc = nmefc != null && nmefc.areas.isNotEmpty;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleAutoInfoPopup(_stationData, provider);
        });

        final mainPages = <_InfoDrawerPage>[];
        if (hasNied) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageNied,
              child: _buildDetectStationsArea(detect.detectedStations),
            ),
          );
        }
        if (hasSnet) {
          mainPages.add(
            _InfoDrawerPage(key: _infoPageSnet, child: _buildSnetSection()),
          );
        }
        if (hasJmaTsunami) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageJmaTsunami,
              child: _buildTsunamiSection(jmaTsunami, 'P2P/JMA'),
            ),
          );
        }
        if (hasNmefc) {
          mainPages.add(
            _InfoDrawerPage(
              key: _infoPageNmefcTsunami,
              child: _buildTsunamiSection(nmefc, 'NMEFC'),
            ),
          );
        }
        _syncInfoCarouselPages(mainPages);

        final showCarousel = mainPages.isNotEmpty;
        if (showCarousel && _infoPageIndex >= mainPages.length) {
          _infoPageIndex = 0;
        }

        if (!showCarousel) return const SizedBox.shrink();

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: _infoPanelWidth(context),
              constraints: const BoxConstraints(minHeight: 166),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xC21A2435),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.7,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
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
                              mainPages[_infoPageIndex].child,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildLpgmFooter(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoSurface(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.6,
        ),
      ),
      child: child,
    );
  }

  Widget _buildSnetSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            '[S-Net震度分布] ${_snetWindowText()}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        ..._stationData.snetTopStations.map((s) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              '${s.code}  震度${_jmaLabelFromIndex(s.jmaIndex)}（${s.shindo.toStringAsFixed(3)}）',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
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

  Widget _buildTsunamiSection(TsunamiMessage tsunami, String sourceLabel) {
    final areas = tsunami.areas.take(4).toList();
    final title = _tsunamiSideTitle(tsunami, sourceLabel);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _tsunamiClassColor(tsunami.className),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            Text(
              '${tsunami.areas.length}区',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (tsunami.reportTime.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            tsunami.reportTime,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (areas.isEmpty)
          Text(
            tsunami.titleText.isEmpty ? '暂无区域明细' : tsunami.titleText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          )
        else
          ...areas.map(_buildTsunamiAreaRow),
      ],
    );
  }

  Widget _buildTsunamiAreaRow(TsunamiAreaInfo area) {
    final color = _tsunamiClassColor(area.className);
    final timeText = area.arrivalTime?.trim();
    final heightText = area.description?.trim();
    final meta = [
      if (area.condition?.trim().isNotEmpty == true) area.condition!.trim(),
      if (timeText?.isNotEmpty == true) timeText!,
      if (heightText?.isNotEmpty == true) heightText!,
    ].join('  ');

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 23,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  area.name.isEmpty ? '未命名预报区' : area.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
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
                      fontSize: 9.5,
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
    final level = switch (tsunami.grade) {
      TsunamiGrade.majorWarning => '大海啸警报',
      TsunamiGrade.warning => '海啸警报',
      TsunamiGrade.watch => tsunami.className == 'blue' ? '海啸蓝色警报' : '海啸注意报',
      TsunamiGrade.none => tsunami.title.contains('解除') ? '海啸解除' : '海啸信息',
    };
    return '$sourceLabel $level';
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

  Widget _buildLpgmFooter() {
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
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '長周期地震動階級 (beta)',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '最大Sva: $svaText    最大動階: $classText',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 10.5,
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
    return '${hm(start)}—${hm(end)}';
  }

  String _jmaLabelFromIndex(int idx) {
    const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    return labels[idx.clamp(0, labels.length - 1)];
  }

  Widget _buildDetectStationsArea(List<DetectedStationEntry> stations) {
    const jmaLabels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    // kanameishi-dev 逻辑：震度4+ 为強検出，其余为検出，与地图检出框对应
    final strong = stations.where((s) => s.jmaShindo >= 4).toList();
    final detected = stations
        .where((s) => s.jmaShindo >= 0 && s.jmaShindo < 4)
        .toList();

    Map<String, String> groupByPref(List<DetectedStationEntry> entries) {
      final prefMaxShindo = <String, int>{};
      for (final e in entries) {
        final pref = e.prefecture.isNotEmpty ? e.prefecture : e.code;
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
    const titleStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 11,
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
                '強検出',
                style: titleStyle.copyWith(color: colorStrong),
              ),
            ),
            const SizedBox(height: 2),
            Text(prefs.values.join('  '), style: textStyle),
          ],
        ),
      );
    }
    if (detected.isNotEmpty) {
      final prefs = groupByPref(detected);
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: strong.isNotEmpty ? 6 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  '検出',
                  style: titleStyle.copyWith(color: colorDetected),
                ),
              ),
              const SizedBox(height: 2),
              Text(prefs.values.join('  '), style: textStyle),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
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
    setState(() => _stationData = data);
    final provider = context.read<QuakeProvider>();
    _handleAutoInfoPopup(data, provider);
    _checkNiedAutoHide(data, provider);
  }

  void _checkNiedAutoHide(StationSummaryData data, QuakeProvider provider) {
    if (!_infoOpenedByAuto) return;
    if (_hasActiveTsunami(provider)) {
      _infoAutoHideTimer?.cancel();
      return;
    }
    final detect = data.niedDetect;
    final isDetecting =
        detect != null &&
        (detect.stage == 'strong' || detect.stage == 'detected');
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

    final detectStage = data.niedDetect?.stage ?? 'idle';
    final detectTriggered =
        detectStage == 'weak' ||
        detectStage == 'detected' ||
        detectStage == 'strong';
    final snetTriggered = data.snetTopStations.isNotEmpty;
    final jmaTsunami = provider.jmaTsunami;
    final nmefcTsunami = provider.nmefcTsunami;
    final jmaTsunamiTriggered =
        jmaTsunami != null &&
        (jmaTsunami.isActive || jmaTsunami.areas.isNotEmpty);
    final nmefcTsunamiTriggered =
        nmefcTsunami != null && nmefcTsunami.areas.isNotEmpty;
    final tsunamiHold = _hasActiveTsunami(provider);
    final shouldShow =
        detectTriggered ||
        snetTriggered ||
        jmaTsunamiTriggered ||
        nmefcTsunamiTriggered;

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

    final detectMax = data.niedDetect?.maxShindo ?? -1;
    final snetTopCode = data.snetTopStations.isEmpty
        ? '-'
        : data.snetTopStations.first.code;
    final snetTopJma = data.snetTopStations.isEmpty
        ? -1
        : data.snetTopStations.first.jmaIndex;
    final niedSignature = detectTriggered ? '$detectStage|$detectMax' : '-';
    final snetSignature = snetTriggered
        ? '$snetTopCode|$snetTopJma|${data.snetTopStations.length}'
        : '-';
    final jmaTsunamiSignature = jmaTsunamiTriggered
        ? '${jmaTsunami.id}|${jmaTsunami.status}|${jmaTsunami.areas.length}'
        : '-';
    final nmefcTsunamiSignature = nmefcTsunamiTriggered
        ? '${nmefcTsunami.id}|${nmefcTsunami.status}|${nmefcTsunami.areas.length}'
        : '-';
    final signature =
        '$niedSignature|$snetSignature|$jmaTsunamiSignature|$nmefcTsunamiSignature';
    if (signature == _lastAutoTriggerSignature) return;
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

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        if (list.isEmpty) {
          return Container(
            height: 200,
            padding: const EdgeInsets.all(24),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, color: Colors.white38, size: 48),
                  SizedBox(height: 12),
                  Text(
                    '暂无 CENC 烈度速报数据',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '等待 FAN 数据源连接后自动获取',
                    style: TextStyle(color: Colors.white30, fontSize: 12),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white12, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.waves_outlined,
                    color: Color(0xFF2ECC71),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '选择 CENC 烈度速报',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${list.length} 条',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, index) =>
                    const Divider(height: 1, color: Colors.white10),
                itemBuilder: (_, i) {
                  final item = list[i];
                  final name =
                      item['nameByInfo']?.toString() ??
                      item['locName']?.toString() ??
                      item['placeName']?.toString() ??
                      '未知';
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF2ECC71).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.waves,
                        color: isActive
                            ? const Color(0xFF2ECC71)
                            : Colors.white38,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
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
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          if (mag.isNotEmpty) const SizedBox(width: 8),
                        ],
                        if (mag.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'M$mag',
                              style: const TextStyle(
                                color: Color(0xFFE67E22),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF2ECC71,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              '显示中',
                              style: TextStyle(
                                color: Color(0xFF2ECC71),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white24,
                      size: 18,
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
