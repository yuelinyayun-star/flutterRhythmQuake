import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/snet_station.dart';
import '../../models/source_status.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/station_event_tracker.dart';
import '../../providers/map_state_provider.dart';
import '../../providers/quake_provider.dart';
import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/lmoni_image_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/lpgm_monitor_service.dart';
import '../../services/sources/snet_service.dart';
import '../../services/sources/global_quake_service.dart';
import '../../core/nied_replay_logger.dart';
import '../map/map_config.dart';
import '../map/quake_map_view.dart';
import 'app_page_background.dart';
import 'ui_runtime_flags.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  static const double _legendRefHeight = 230.0;
  final LpgmMonitorService _lpgm = LpgmMonitorService();
  StreamSubscription<LpgmSnapshot>? _lpgmSub;
  StreamSubscription<LpgmInputFrame>? _lpgmFrameSub;
  LpgmSnapshot? _latestLpgm;
  Uint8List? _latestLpgmFrameBytes;
  _LegendBarGeometry _legendGeometry = const _LegendBarGeometry.fallback();
  Color _legendMarkerColor = const Color(0xFFFFE08A);
  ui.Image? _legendImage;
  Uint8List? _legendRgba;
  int _legendRgbaW = 0;
  int _legendRgbaH = 0;
  StreamSubscription<List<NiedStation>?>? _niedStationSub;
  StreamSubscription<NiedGifFrame>? _niedGifFrameSub;
  Timer? _snetUiTimer;
  final SnetService _snetService = SnetService();
  final LmoniImageService _lmoniImageService = LmoniImageService();
  List<NiedStation> _latestNiedStations = const [];
  String _niedDataSource = 'lmoni';
  DateTime? _niedGifStamp;
  double _niedGifMaxShindo = -3.0;
  double _niedGifMaxPga = 0.0;
  double _niedGifMaxPgv = 0.0;
  double _niedGifMaxPgd = 0.0;
  Uint8List? _niedSurfaceGifBytes;
  ui.Image? _niedLegendImage;
  _LegendBarGeometry? _niedLegendGeometry;
  final TextEditingController _mapboxUsernameController =
      TextEditingController();
  final TextEditingController _mapboxStyleIdController =
      TextEditingController();
  final TextEditingController _mapboxTokenController = TextEditingController();
  bool _mapboxDebugLoaded = false;
  final GlobalQuakeService _globalQuakeService = GlobalQuakeService();
  StreamSubscription<void>? _globalQuakeSub;
  final TextEditingController _globalQuakePrimaryHostController =
      TextEditingController();
  final TextEditingController _globalQuakePrimaryPortController =
      TextEditingController();
  final TextEditingController _globalQuakeSecondaryHostController =
      TextEditingController();
  final TextEditingController _globalQuakeSecondaryPortController =
      TextEditingController();
  bool _globalQuakeEnabled = false;
  bool _globalQuakeLoaded = false;

  @override
  void initState() {
    super.initState();
    _latestLpgm = _lpgm.latestSnapshot;
    _latestLpgmFrameBytes = _lpgm.latestInputFrame?.imageBytes;
    NiedReplayLogger.instance.revision.addListener(_onReplayLoggerChanged);
    _initNiedDebugState();
    _initGlobalQuakeDebugState();
    _loadMapboxDebugState();
    _loadNiedLegendAssets();
    _loadLegendGeometry();
    _snetUiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _lpgmSub = _lpgm.snapshotStream.listen((snapshot) {
      if (!mounted) return;
      setState(() => _latestLpgm = snapshot);
    });
    _lpgmFrameSub = _lpgm.inputFrameStream.listen((frame) {
      if (!mounted) return;
      setState(() {
        _latestLpgmFrameBytes = frame.imageBytes;
      });
    });
    if (_lpgm.isRunning) {
      unawaited(_lpgm.refreshDebugFrame());
    } else {
      unawaited(_lpgm.start());
    }
  }

  @override
  void dispose() {
    _lpgmSub?.cancel();
    _lpgmFrameSub?.cancel();
    _niedStationSub?.cancel();
    _niedGifFrameSub?.cancel();
    _globalQuakeSub?.cancel();
    _globalQuakePrimaryHostController.dispose();
    _globalQuakePrimaryPortController.dispose();
    _globalQuakeSecondaryHostController.dispose();
    _globalQuakeSecondaryPortController.dispose();
    _mapboxUsernameController.dispose();
    _mapboxStyleIdController.dispose();
    _mapboxTokenController.dispose();
    _snetUiTimer?.cancel();
    NiedReplayLogger.instance.revision.removeListener(_onReplayLoggerChanged);
    QuakeMapView.niedSourceNotifier.removeListener(_onNiedSourceChanged);
    _legendImage?.dispose();
    _niedLegendImage?.dispose();
    _legendImage = null;
    _niedLegendImage = null;
    _legendRgba = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020208),
      appBar: AppBar(
        backgroundColor: const Color(0xCC101A33),
        elevation: 0,
        title: const Text('Debug'),
      ),
      body: Stack(
        children: [
          const AppPageBackground(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Consumer2<QuakeProvider, MapStateProvider>(
              builder: (context, quake, mapState, _) {
                final connected = quake.sourceStatuses.values
                    .where((s) => s == SourceStatus.connected)
                    .length;
                final total = quake.sourceStatuses.length;

                return ListView(
                  children: [
                    _buildMapboxPanel(mapState),
                    const SizedBox(height: 10),
                    _buildLpgmPanel(),
                    const SizedBox(height: 10),
                    _buildNiedGifPanelV2(),
                    const SizedBox(height: 10),
                    _buildNiedSourceEstimatePanel(),
                    const SizedBox(height: 10),
                    _buildReplayLoggerToggle(),
                    const SizedBox(height: 10),
                    _buildGlobalQuakeToggle(),
                    const SizedBox(height: 10),
                    _buildSnetPanel(),
                    const SizedBox(height: 10),
                    _debugCard(
                      title: 'Runtime',
                      lines: [
                        'Camera AutoFollow: ${mapState.canAutoFollow}',
                        'Unified Events: ${quake.unifiedEvents.length}',
                        'Warnings: ${quake.activeWarnings.length}',
                        'Info Events: ${quake.activeInfoEvents.length}',
                        'Sources: $connected / $total online',
                      ],
                    ),
                    const SizedBox(height: 10),
                    _debugCard(
                      title: 'Source Status',
                      lines: quake.sourceStatuses.entries
                          .map((e) => '${e.key}: ${e.value.name}')
                          .toList(growable: false),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initNiedDebugState() async {
    final prefs = await SharedPreferences.getInstance();
    NiedReplayLogger.instance.loadPreferencesFrom(prefs);
    _niedDataSource = prefs.getString('nied_data_source') ?? 'lmoni';
    QuakeMapView.niedSourceNotifier.addListener(_onNiedSourceChanged);
    _ensureNiedGifMonitorRunning(_niedDataSource);
    final lastFrame = _lmoniImageService.lastGifFrame;
    if (lastFrame != null) {
      _niedGifStamp = lastFrame.dataTime;
      _niedSurfaceGifBytes = lastFrame.surfaceGifBytes;
    }
    _niedStationSub = _lmoniImageService.stationStream.listen((stations) {
      if (!mounted || !_isNiedGifSource(_niedDataSource) || stations == null) {
        return;
      }
      final frameTime = _lmoniImageService.lastFrameTime;
      if (frameTime == null) return;
      var maxShindo = -3.0;
      var maxPga = 0.0;
      var maxPgv = 0.0;
      var maxPgd = 0.0;
      for (final s in stations) {
        final obs = s.gifObservation;
        final shindo = obs?.shindo;
        if (shindo != null && shindo > maxShindo) maxShindo = shindo;
        final pga = obs?.pga;
        if (pga != null && pga > maxPga) maxPga = pga;
        final pgv = obs?.pgv;
        if (pgv != null && pgv > maxPgv) maxPgv = pgv;
        final pgd = obs?.pgd;
        if (pgd != null && pgd > maxPgd) maxPgd = pgd;
      }
      setState(() {
        _latestNiedStations = List.unmodifiable(stations);
        _niedGifStamp = frameTime;
        _niedGifMaxShindo = maxShindo;
        _niedGifMaxPga = maxPga;
        _niedGifMaxPgv = maxPgv;
        _niedGifMaxPgd = maxPgd;
      });
    });
    _niedGifFrameSub = _lmoniImageService.gifFrameStream.listen((frame) {
      if (!mounted || !_isNiedGifSource(_niedDataSource)) return;
      setState(() {
        _niedGifStamp = frame.dataTime;
        _niedSurfaceGifBytes = frame.surfaceGifBytes;
      });
    });
    if (mounted) setState(() {});
  }

  void _onReplayLoggerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initGlobalQuakeDebugState() async {
    final prefs = await SharedPreferences.getInstance();
    final primaryHost =
        prefs.getString(GlobalQuakeService.primaryHostPreferenceKey) ??
        GlobalQuakeService.defaultPrimaryHost;
    final primaryPort =
        prefs.getInt(GlobalQuakeService.primaryPortPreferenceKey) ??
        GlobalQuakeService.defaultPort;
    final secondaryHost =
        prefs.getString(GlobalQuakeService.secondaryHostPreferenceKey) ??
        GlobalQuakeService.defaultSecondaryHost;
    final secondaryPort =
        prefs.getInt(GlobalQuakeService.secondaryPortPreferenceKey) ??
        GlobalQuakeService.defaultPort;
    _globalQuakeService.configureServers(
      primaryHost: primaryHost,
      primaryPort: primaryPort,
      secondaryHost: secondaryHost,
      secondaryPort: secondaryPort,
    );
    _globalQuakeEnabled =
        prefs.getBool(GlobalQuakeService.enabledPreferenceKey) ??
        _globalQuakeService.isEnabled;
    _globalQuakeSub = _globalQuakeService.onDebugStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    if (mounted) {
      setState(() {
        _globalQuakePrimaryHostController.text = primaryHost;
        _globalQuakePrimaryPortController.text = primaryPort.toString();
        _globalQuakeSecondaryHostController.text = secondaryHost;
        _globalQuakeSecondaryPortController.text = secondaryPort.toString();
        _globalQuakeLoaded = true;
      });
    }
  }

  Future<void> _setGlobalQuakeEnabled(bool enabled) async {
    setState(() => _globalQuakeEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(GlobalQuakeService.enabledPreferenceKey, enabled);
    if (enabled) {
      _globalQuakeService.connect();
    } else {
      _globalQuakeService.disconnect();
    }
  }

  Future<void> _saveGlobalQuakeServers() async {
    final primaryHost = _globalQuakePrimaryHostController.text.trim().isEmpty
        ? GlobalQuakeService.defaultPrimaryHost
        : _globalQuakePrimaryHostController.text.trim();
    final primaryPort =
        int.tryParse(_globalQuakePrimaryPortController.text.trim()) ??
        GlobalQuakeService.defaultPort;
    final secondaryHost =
        _globalQuakeSecondaryHostController.text.trim().isEmpty
        ? GlobalQuakeService.defaultSecondaryHost
        : _globalQuakeSecondaryHostController.text.trim();
    final secondaryPort =
        int.tryParse(_globalQuakeSecondaryPortController.text.trim()) ??
        GlobalQuakeService.defaultPort;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      GlobalQuakeService.primaryHostPreferenceKey,
      primaryHost,
    );
    await prefs.setInt(
      GlobalQuakeService.primaryPortPreferenceKey,
      primaryPort,
    );
    await prefs.setString(
      GlobalQuakeService.secondaryHostPreferenceKey,
      secondaryHost,
    );
    await prefs.setInt(
      GlobalQuakeService.secondaryPortPreferenceKey,
      secondaryPort,
    );
    _globalQuakeService.configureServers(
      primaryHost: primaryHost,
      primaryPort: primaryPort,
      secondaryHost: secondaryHost,
      secondaryPort: secondaryPort,
    );
    if (!mounted) return;
    setState(() {
      _globalQuakePrimaryHostController.text = primaryHost;
      _globalQuakePrimaryPortController.text = primaryPort.toString();
      _globalQuakeSecondaryHostController.text = secondaryHost;
      _globalQuakeSecondaryPortController.text = secondaryPort.toString();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('GlobalQuake servers saved')));
  }

  void _onNiedSourceChanged() {
    if (!mounted) return;
    final next = QuakeMapView.niedSourceNotifier.value;
    setState(() {
      _niedDataSource = next;
      if (!_isNiedGifSource(next)) {
        _niedSurfaceGifBytes = null;
      }
    });
    if (_isNiedGifSource(next)) {
      _ensureNiedGifMonitorRunning(next);
      final frame = _lmoniImageService.lastGifFrame;
      if (frame != null) {
        setState(() {
          _niedGifStamp = frame.dataTime;
          _niedSurfaceGifBytes = frame.surfaceGifBytes;
        });
      }
    }
  }

  void _ensureNiedGifMonitorRunning(String source) {
    if (!_isNiedGifSource(source)) return;
    _lmoniImageService.start();
    NiedMonitorService().configureEndpoint(source);
    NiedMonitorService().start();
  }

  bool _isNiedGifSource(String source) =>
      source == 'lmoni' || source == 'kmoni';

  String _niedSourceLabel(String source) {
    switch (source) {
      case 'kmoni':
        return 'KMONI';
      case 'yahoo':
        return 'Yahoo';
      default:
        return 'Lmoni';
    }
  }

  String _formatShindoValue(double v) {
    final fixed = v.toStringAsFixed(2);
    return fixed.endsWith('00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  Future<void> _loadMapboxDebugState() async {
    final prefs = await SharedPreferences.getInstance();
    final username =
        prefs.getString(MapConfig.mapboxUsernameKey) ??
        MapConfig.mapboxUsername;
    final styleId =
        prefs.getString(MapConfig.mapboxStyleIdKey) ?? MapConfig.mapboxStyleId;
    final token =
        prefs.getString(MapConfig.mapboxAccessTokenKey) ??
        MapConfig.mapboxAccessToken;
    MapConfig.configureMapbox(
      username: username,
      styleId: styleId,
      accessToken: token,
    );
    if (!mounted) return;
    setState(() {
      _mapboxUsernameController.text = MapConfig.mapboxUsername;
      _mapboxStyleIdController.text = MapConfig.mapboxStyleId;
      _mapboxTokenController.text = MapConfig.mapboxAccessToken;
      _mapboxDebugLoaded = true;
    });
  }

  Future<void> _saveMapboxDebugState(MapStateProvider mapState) async {
    final username = _mapboxUsernameController.text.trim();
    final styleId = _mapboxStyleIdController.text.trim();
    final token = _mapboxTokenController.text.trim();
    MapConfig.configureMapbox(
      username: username,
      styleId: styleId,
      accessToken: token,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      MapConfig.mapboxUsernameKey,
      MapConfig.mapboxUsername,
    );
    await prefs.setString(MapConfig.mapboxStyleIdKey, MapConfig.mapboxStyleId);
    if (MapConfig.mapboxAccessToken.isEmpty) {
      await prefs.remove(MapConfig.mapboxAccessTokenKey);
    } else {
      await prefs.setString(
        MapConfig.mapboxAccessTokenKey,
        MapConfig.mapboxAccessToken,
      );
    }
    if (!mounted) return;
    mapState.refreshTileConfig();
    setState(() {
      _mapboxUsernameController.text = MapConfig.mapboxUsername;
      _mapboxStyleIdController.text = MapConfig.mapboxStyleId;
      _mapboxTokenController.text = MapConfig.mapboxAccessToken;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mapbox config saved')));
  }

  Future<void> _resetMapboxDebugState(MapStateProvider mapState) async {
    _mapboxUsernameController.text = 'mapbox';
    _mapboxStyleIdController.text = 'dark-v11';
    _mapboxTokenController.clear();
    await _saveMapboxDebugState(mapState);
  }

  Widget _buildMapboxPanel(MapStateProvider mapState) {
    final active = mapState.tileKey == MapConfig.mapboxEewceDarkKey;
    final configured = MapConfig.hasMapboxAccessToken;
    final fallback = active && !configured;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Mapbox Base Map',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  configured ? 'configured' : 'token empty',
                  style: TextStyle(
                    color: configured ? const Color(0xFF3AFF6F) : Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              fallback
                  ? 'Mapbox is selected, but token is empty. Current map falls back to Petal Dark.'
                  : 'Default EEWCE-like style: mapbox/dark-v11. Replace account, style id, or token here when quota changes.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            if (!_mapboxDebugLoaded)
              const LinearProgressIndicator(minHeight: 2)
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _mapboxField(
                    label: 'Account',
                    width: 180,
                    controller: _mapboxUsernameController,
                  ),
                  _mapboxField(
                    label: 'Style ID',
                    width: 220,
                    controller: _mapboxStyleIdController,
                  ),
                  _mapboxField(
                    label: 'Access Token',
                    width: 360,
                    controller: _mapboxTokenController,
                    obscureText: true,
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _mapboxDebugLoaded
                      ? () => _resetMapboxDebugState(mapState)
                      : null,
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _mapboxDebugLoaded
                      ? () => _saveMapboxDebugState(mapState)
                      : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapboxField({
    required String label,
    required double width,
    required TextEditingController controller,
    bool obscureText = false,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0xFF82B1FF)),
          ),
        ),
      ),
    );
  }

  Future<void> _loadNiedLegendAssets() async {
    const url =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg/nied_jma_s_w_scale.png';
    try {
      final bytes = await _fetchLegendBytes(url);
      if (bytes == null) return;
      final image = await _decodeLegendImage(bytes);
      final detected = await _detectLegendBarGeometry(bytes);
      if (!mounted || image == null || detected == null) return;
      setState(() {
        _niedLegendImage?.dispose();
        _niedLegendImage = image;
        _niedLegendGeometry = detected.geometry;
      });
    } catch (_) {
      // keep fallback (network contain image)
    }
  }

  double _niedLegendIndicatorTop(double boxHeight) {
    final shindo = _niedGifMaxShindo.clamp(-3.0, 7.0);
    final t = ((shindo + 3.0) / 10.0).clamp(0.0, 1.0);
    final g = _niedLegendGeometry;
    if (g == null) {
      final top = 0.08 * boxHeight;
      final bottom = 0.96 * boxHeight;
      return bottom - t * (bottom - top);
    }
    final contentH = (g.contentBottom - g.contentTop).clamp(1.0, g.srcHeight);
    final barTopN = ((g.barTop - g.contentTop) / contentH).clamp(0.0, 1.0);
    final barBottomN = ((g.barBottom - g.contentTop) / contentH).clamp(
      0.0,
      1.0,
    );
    final top = barTopN * boxHeight;
    final bottom = barBottomN * boxHeight;
    return bottom - t * (bottom - top);
  }

  Widget _buildLpgmPanel() {
    final snapshot = _latestLpgm;
    final hasData = snapshot != null;
    final maxSva = hasData ? snapshot.maxSva : 0.0;
    final maxClass = hasData ? snapshot.maxClass : -1;
    final timeText = hasData ? _fmtTime(snapshot.dataTime) : '--';
    final mapBytes = _latestLpgmFrameBytes;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '長周期地震動モニタ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '最大Sva: ${hasData ? maxSva.toStringAsFixed(3) : '--'}    最大階級: ${maxClass >= 0 ? maxClass : '--'}    時刻: $timeText',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 250,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.28),
                        child: mapBytes == null
                            ? _emptyCenter('等待长周期图层数据...')
                            : Image.memory(
                                mapBytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildLegendWithMarker(
                    maxSva: maxSva,
                    hasData: hasData,
                    maxRawRgb: snapshot?.maxRawRgb,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNiedGifPanelV2() {
    const legendUrl =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg/nied_jma_s_w_scale.png';
    final isGif = _isNiedGifSource(_niedDataSource);
    final maxText = _formatShindoValue(_niedGifMaxShindo);
    final stampText = _niedGifStamp == null ? '--' : _fmtTime(_niedGifStamp!);
    final topStations =
        _latestNiedStations
            .where((s) => (s.gifObservation?.shindo ?? -99) > -3.0)
            .toList(growable: false)
          ..sort((a, b) {
            final bShindo = b.gifObservation?.shindo ?? -99;
            final aShindo = a.gifObservation?.shindo ?? -99;
            final valueCmp = bShindo.compareTo(aShindo);
            if (valueCmp != 0) return valueCmp;
            return a.code.compareTo(b.code);
          });

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '強震モニタ（数据源：${_niedSourceLabel(_niedDataSource)}）',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '最大震度: $maxText    时刻: $stampText',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Max PGA: ${_niedGifMaxPga.toStringAsFixed(3)}   Max PGV: ${_niedGifMaxPgv.toStringAsFixed(3)}   Max PGD: ${_niedGifMaxPgd.toStringAsFixed(4)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildNiedGifMapCardV2(
                      title: '地表',
                      gifBytes: isGif ? _niedSurfaceGifBytes : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildNiedLegendWithMarkerV2(
                    isGif: isGif,
                    legendUrl: legendUrl,
                    maxText: maxText,
                  ),
                ],
              ),
            ),
            if (topStations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: topStations
                    .take(5)
                    .map(_buildNiedGifStationChip)
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildNiedGifMapCardV2({
    required String title,
    required Uint8List? gifBytes,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: Colors.black.withValues(alpha: 0.28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: gifBytes == null
                  ? _emptyCenter('空')
                  : Image.memory(
                      gifBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNiedLegendWithMarkerV2({
    required bool isGif,
    required String legendUrl,
    required String maxText,
  }) {
    const legendWidth = 92.0;
    const legendHeight = 220.0;
    final markerTop = _niedLegendIndicatorTop(
      legendHeight,
    ).clamp(0.0, legendHeight - 1);
    return SizedBox(
      width: legendWidth + 60,
      child: Stack(
        children: [
          Positioned(
            left: 54,
            top: 0,
            width: legendWidth,
            height: legendHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: Colors.black.withValues(alpha: 0.28),
                child: isGif
                    ? _buildNiedLegendInnerV2(legendUrl: legendUrl)
                    : _emptyCenter('空'),
              ),
            ),
          ),
          if (isGif)
            Positioned(
              left: 0,
              top: (markerTop - 9).clamp(0, legendHeight - 18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0x88FFE08A)),
                    ),
                    child: Text(
                      maxText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  CustomPaint(
                    size: const Size(10, 10),
                    painter: _TrianglePainter(color: const Color(0xFFFFE08A)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNiedLegendInnerV2({required String legendUrl}) {
    if (_niedLegendImage != null && _niedLegendGeometry != null) {
      return CustomPaint(
        painter: _LegendImageCropPainter(
          image: _niedLegendImage!,
          geometry: _niedLegendGeometry!,
          preserveAspect: true,
        ),
        child: const SizedBox.expand(),
      );
    }
    return Image.network(legendUrl, fit: BoxFit.contain, gaplessPlayback: true);
  }

  Widget _buildSnetPanel() {
    final stations = _snetService.stations;
    final active = stations.where((s) => s.isActive).toList();
    final above1 = active.where((s) => s.shindo >= 1.0).toList()
      ..sort((a, b) => b.shindo.compareTo(a.shindo));
    final maxShindo = active.isEmpty
        ? 0.0
        : active.map((s) => s.shindo).reduce((a, b) => a > b ? a : b);
    final top5 =
        (List<SnetStation>.of(active)
              ..sort((a, b) => b.shindo.compareTo(a.shindo)))
            .take(5)
            .toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'S-Net モニタ（状态：${_snetService.isMonitoring ? "ON" : "OFF"}）',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            _buildSnetTopStations(top5),
            const SizedBox(height: 8),
            Text(
              '最大震度: ${_formatShindoValue(maxShindo)}    活跃: ${active.length}/${stations.length}    震度>=1: ${above1.length}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNiedSourceEstimatePanel() {
    return ValueListenableBuilder<SeismicActiveEvent?>(
      valueListenable: StationEventTracker.instance.currentNiedEvent,
      builder: (context, currentEvent, _) {
        return ValueListenableBuilder<List<SeismicActiveEvent>>(
          valueListenable: StationEventTracker.instance.niedEventHistory,
          builder: (context, history, _) {
            final estimate = currentEvent?.estimate;
            final topStations = currentEvent == null
                ? const <SeismicStationEventRecord>[]
                : (List<SeismicStationEventRecord>.from(currentEvent.records)
                        ..sort((a, b) {
                          final bValue = b.lastValue ?? b.peakValue ?? -99;
                          final aValue = a.lastValue ?? a.peakValue ?? -99;
                          final valueCmp = bValue.compareTo(aValue);
                          if (valueCmp != 0) return valueCmp;
                          return a.descriptor.code.compareTo(b.descriptor.code);
                        }))
                      .take(5)
                      .toList(growable: false);
            final timingPicks =
                (estimate?.diagnostics['top_timing_picks'] as List<dynamic>?)
                    ?.whereType<Map<String, Object?>>()
                    .toList(growable: false) ??
                const <Map<String, Object?>>[];

            final lines = <String>[
              'Current Event: ${currentEvent?.eventId ?? "--"}',
              'Stage: ${currentEvent?.stageName ?? "idle"}',
              'Max Shindo: ${currentEvent?.maxShindo ?? "--"}',
              'Started: ${currentEvent == null ? "--" : _fmtTime(currentEvent.startedAt)}',
              'Updated: ${currentEvent == null ? "--" : _fmtTime(currentEvent.updatedAt)}',
              'Tracked Stations: ${currentEvent?.records.length ?? 0}',
              'History: ${history.length}',
              'Estimate: ${estimate == null ? "--" : "${estimate.latitude.toStringAsFixed(3)}, ${estimate.longitude.toStringAsFixed(3)}"}',
              'Depth: ${estimate?.depthKm == null ? "--" : estimate!.depthKm!.toStringAsFixed(1)} km',
              'Confidence: ${estimate == null ? "--" : estimate.confidence.toStringAsFixed(2)}',
              'Method: ${estimate?.method ?? "--"}',
              'Support: ${estimate?.supportingStationCount ?? 0}',
              if (estimate?.originTime != null)
                'Origin: ${_fmtTime(estimate!.originTime!)}',
              if (estimate?.diagnostics['time_score'] != null)
                'Time Score: ${estimate!.diagnostics['time_score']}',
              if (estimate?.diagnostics['rank_score'] != null)
                'Rank Score: ${estimate!.diagnostics['rank_score']}',
              ..._sourceCandidateRegionDebugLines(currentEvent?.metadata),
            ];

            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        const Text(
                          'NIED Source Estimation',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              UiRuntimeFlags.niedHypCurvePanelVisibleNotifier,
                          builder: (context, visible, _) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '主界面曲线面板',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Switch(
                                  key: const ValueKey(
                                    'nied-hyp-curve-panel-toggle',
                                  ),
                                  value: visible,
                                  activeThumbColor: Colors.lightBlueAccent,
                                  activeTrackColor: Colors.lightBlueAccent
                                      .withValues(alpha: 0.35),
                                  onChanged: _setNiedHypCurvePanelVisible,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...lines.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          line,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (topStations.isEmpty)
                      _emptyCenter('No tracked stations')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: topStations
                            .map(_buildEstimateStationChip)
                            .toList(),
                      ),
                    if (timingPicks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Timing Picks',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: timingPicks
                            .map(_buildTimingPickChip)
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _setNiedHypCurvePanelVisible(bool visible) {
    UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value = visible;
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        UiRuntimeFlags.niedHypCurvePanelVisiblePreferenceKey,
        visible,
      );
    }());
  }

  Widget _buildEstimateStationChip(SeismicStationEventRecord record) {
    final shindo = record.lastValue ?? record.peakValue ?? -3.0;
    final jmaIndex = JpShindoScale.jmaIndexFromShindo(shindo);
    final color = _debugJmaColor(jmaIndex);
    final stateText = record.state.name;
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.52)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.descriptor.code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Shindo ${_formatShindoValue(shindo)}  $stateText',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'PGA ${_fmtMotion(record.lastPga)}  PGV ${_fmtMotion(record.lastPgv)}  PGD ${_fmtMotion(record.lastPgd, digits: 4)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'Rise ${record.firstRiseAt == null ? "--" : _fmtTime(record.firstRiseAt!)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _sourceCandidateRegionDebugLines(
    Map<String, Object?>? metadata,
  ) {
    if (metadata == null) return const [];
    final candidateRegion = _debugMap(metadata['candidate_region']);
    if (candidateRegion == null) return const [];
    final residualGate = _debugMap(metadata['candidate_region_residual_gate']);
    final localSupportGate = _debugMap(
      metadata['candidate_region_local_support_gate'],
    );
    final lines = <String>[
      'Candidate Region: ${candidateRegion['status'] ?? "--"}'
          ' / reason ${candidateRegion['reason'] ?? "--"}',
      'Candidate Region Point: '
          '${_fmtDebugNumber(candidateRegion['latitude'], digits: 3)}, '
          '${_fmtDebugNumber(candidateRegion['longitude'], digits: 3)}',
      'Candidate Coordinate Switch: '
          '${candidateRegion['production_coordinate_switch_allowed'] == true}',
    ];
    if (residualGate != null) {
      lines.add(
        'Residual Gate: supported '
        '${residualGate['residual_supported'] == true}'
        ' / rank ${_fmtDebugNumber(residualGate['rank_delta'], digits: 3)}'
        ' / atten ${_fmtDebugNumber(residualGate['attenuation_delta'], digits: 3)}',
      );
    }
    if (localSupportGate != null) {
      lines.add(
        'Local Support Gate: confirmed '
        '${localSupportGate['local_support_confirmed'] == true}'
        ' / members ${localSupportGate['member_count'] ?? "--"}'
        ' (${_fmtSignedDebugInt(localSupportGate['member_count_growth'])})',
      );
      lines.add(
        'Local Support Geometry: ${localSupportGate['station_geometry'] ?? "--"}'
        ' / est-member '
        '${_fmtDebugNumber(localSupportGate['estimate_member_centroid_distance_km'])} km'
        ' / convergence '
        '${_fmtDebugNumber(localSupportGate['convergence_km'])} km',
      );
    }
    return lines;
  }

  Map<String, Object?>? _debugMap(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    return null;
  }

  String _fmtDebugNumber(Object? value, {int digits = 1}) {
    final number = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value)
        : null;
    if (number == null || !number.isFinite) return '--';
    return number.toStringAsFixed(digits);
  }

  String _fmtSignedDebugInt(Object? value) {
    final number = value is num
        ? value.round()
        : value is String
        ? int.tryParse(value)
        : null;
    if (number == null) return '--';
    return number > 0 ? '+$number' : '$number';
  }

  Widget _buildTimingPickChip(Map<String, Object?> pick) {
    final code = (pick['code'] ?? '--').toString();
    final delay = (pick['delay_s'] as num?)?.toDouble();
    final value = (pick['value'] as num?)?.toDouble();
    final pga = (pick['pga'] as num?)?.toDouble();
    final pgv = (pick['pgv'] as num?)?.toDouble();
    final pgd = (pick['pgd'] as num?)?.toDouble();
    final activity = (pick['activity'] as num?)?.toDouble();
    final ascend = pick['ascend'];
    return Container(
      width: 172,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'delay ${delay == null ? "--" : delay.toStringAsFixed(2)}s',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'value ${value == null ? "--" : _formatShindoValue(value)}  act ${activity == null ? "--" : activity.toStringAsFixed(1)}  up $ascend',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'pga ${_fmtMotion(pga)}  pgv ${_fmtMotion(pgv)}  pgd ${_fmtMotion(pgd, digits: 4)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnetTopStations(List<SnetStation> topStations) {
    if (topStations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          '当前无活跃测站',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < topStations.length; i++)
          _buildSnetTopStationChip(i + 1, topStations[i]),
      ],
    );
  }

  Widget _buildSnetTopStationChip(int rank, SnetStation station) {
    final shindo = station.shindo;
    final jmaIndex = JpShindoScale.jmaIndexFromShindo(shindo);
    final color = _debugJmaColor(jmaIndex);
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.52)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                color: jmaIndex >= 4 ? Colors.black : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  station.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '震度 ${_formatShindoValue(shindo)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _debugJmaColor(int index) {
    const colors = [
      Color(0xFF888888),
      Color(0xFF8282FF),
      Color(0xFF46B4FF),
      Color(0xFF00DC8C),
      Color(0xFFFFFF00),
      Color(0xFFFFB400),
      Color(0xFFFF6400),
      Color(0xFFFF0000),
      Color(0xFFB40000),
      Color(0xFF640096),
    ];
    return colors[index.clamp(0, colors.length - 1)];
  }

  // ignore: unused_element
  Widget _buildNiedGifPanel() {
    const legendUrl =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg/nied_jma_s_w_scale.png';
    final isGif = _isNiedGifSource(_niedDataSource);
    final maxText = _formatShindoValue(_niedGifMaxShindo);
    final stampText = _niedGifStamp == null ? '--' : _fmtTime(_niedGifStamp!);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '強震モニタ（数据源：${_niedSourceLabel(_niedDataSource)}）',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '最大震度: $maxText    时刻: $stampText',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildNiedGifMapCard(
                      title: '地表',
                      gifBytes: isGif ? _niedSurfaceGifBytes : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 92,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.28),
                        child: isGif
                            ? _buildNiedLegendInner(legendUrl: legendUrl)
                            : _emptyCenter('空'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNiedGifMapCard({
    required String title,
    required Uint8List? gifBytes,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: Colors.black.withValues(alpha: 0.28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: gifBytes == null
                  ? _emptyCenter('空')
                  : Image.memory(
                      gifBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => _emptyCenter('加载失败'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNiedLegendInner({required String legendUrl}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight <= 0 ? 220.0 : constraints.maxHeight;
        final markerTop = _niedLegendIndicatorTop(h).clamp(0.0, h - 1);
        return Stack(
          children: [
            Positioned.fill(
              child: (_niedLegendImage != null && _niedLegendGeometry != null)
                  ? CustomPaint(
                      painter: _LegendImageCropPainter(
                        image: _niedLegendImage!,
                        geometry: _niedLegendGeometry!,
                      ),
                      child: const SizedBox.expand(),
                    )
                  : Image.network(
                      legendUrl,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: (markerTop - 0.5).clamp(0.0, h - 1),
              child: Container(height: 1, color: const Color(0xB2FFE08A)),
            ),
            Positioned(
              left: 0,
              top: (markerTop - 5).clamp(0.0, h - 10),
              child: CustomPaint(
                size: const Size(8, 10),
                painter: _TrianglePainter(color: const Color(0xFFFFE08A)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLegendWithMarker({
    required double maxSva,
    required bool hasData,
    int? maxRawRgb,
  }) {
    const legendWidth = 92.0;
    const legendHeight = 230.0;

    final clampedSva = maxSva.clamp(0.001, 1000.0);
    final markerTop = hasData
        ? _markerTopFromSva(
            clampedSva.toDouble(),
            boxWidth: legendWidth,
            boxHeight: legendHeight,
            geometry: _legendGeometry,
            fitMode: _LegendFitMode.cropContentFill,
          )
        : legendHeight;
    final markerColor = hasData
        ? _colorForSva(clampedSva.toDouble(), boxHeight: legendHeight)
        : _legendMarkerColor;

    // 原始 GIF 图上最大值位置的像素颜色
    final rawColor = maxRawRgb != null
        ? Color.fromARGB(
            0xFF,
            (maxRawRgb >> 16) & 0xFF,
            (maxRawRgb >> 8) & 0xFF,
            maxRawRgb & 0xFF,
          )
        : null;

    return SizedBox(
      width: legendWidth + 64,
      child: Stack(
        children: [
          Positioned(
            left: 54,
            top: 0,
            width: legendWidth,
            height: legendHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: Colors.black.withValues(alpha: 0.28),
                child: _legendImage == null
                    ? Image.network(
                        LpgmMonitorService.legendImageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.bottomRight,
                      )
                    : CustomPaint(
                        painter: _LegendImageCropPainter(
                          image: _legendImage!,
                          geometry: _legendGeometry,
                        ),
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
          ),
          if (hasData)
            Positioned(
              left: 0,
              top: (markerTop - 9).clamp(0, legendHeight - 18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: markerColor.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: markerColor.withValues(alpha: 0.95),
                      ),
                    ),
                    child: Text(
                      maxSva.toStringAsFixed(3),
                      style: TextStyle(
                        color: markerColor.computeLuminance() > 0.62
                            ? const Color(0xFF101626)
                            : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  CustomPaint(
                    size: const Size(10, 10),
                    painter: _TrianglePainter(color: markerColor),
                  ),
                ],
              ),
            ),
          // 原图颜色对比色块
          if (hasData && rawColor != null)
            Positioned(
              left: legendWidth + 58,
              top: (markerTop - 10).clamp(0, legendHeight - 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: rawColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '原',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  double _markerTopFromSva(
    double sva, {
    required double boxWidth,
    required double boxHeight,
    required _LegendBarGeometry geometry,
    _LegendFitMode fitMode = _LegendFitMode.containCenter,
  }) {
    final srcW = geometry.srcWidth;
    final srcH = geometry.srcHeight;
    final barYMin = geometry.barTop;
    final barYMax = geometry.barBottom;
    if (fitMode == _LegendFitMode.cropContentFill) {
      return _calibratedLegendYFromSva(sva, boxHeight);
    }

    final scale = fitMode == _LegendFitMode.coverBottomRight
        ? math.max(boxWidth / srcW, boxHeight / srcH)
        : math.min(boxWidth / srcW, boxHeight / srcH);
    final drawnW = srcW * scale;
    final drawnH = srcH * scale;
    final offsetY = fitMode == _LegendFitMode.coverBottomRight
        ? (boxHeight - drawnH)
        : (boxHeight - drawnH) / 2.0;
    // keep x transform for completeness; y is what marker needs.
    final _ = fitMode == _LegendFitMode.coverBottomRight
        ? (boxWidth - drawnW)
        : (boxWidth - drawnW) / 2.0;
    final barTop = offsetY + drawnH * (barYMin / srcH);
    final barBottom = offsetY + drawnH * (barYMax / srcH);
    final barHeight = (barBottom - barTop).clamp(1.0, boxHeight);

    final logSva = math.log(sva) / math.ln10;
    final t = ((logSva + 3.0) / 6.0).clamp(0.0, 1.0);
    return barTop + (1.0 - t) * barHeight;
  }

  double _calibratedLegendYFromSva(double sva, double boxHeight) {
    final scale = boxHeight / _legendRefHeight;
    final logV = math.log(sva.clamp(0.001, 1000.0)) / math.ln10;
    final points = _svaLegendCalib;
    if (points.length < 2) return boxHeight * 0.5;

    if (logV <= points.first.log10Sva) {
      final p0 = points[0];
      final p1 = points[1];
      final t = (logV - p0.log10Sva) / (p1.log10Sva - p0.log10Sva);
      return (p0.y + (p1.y - p0.y) * t) * scale;
    }
    if (logV >= points.last.log10Sva) {
      final p0 = points[points.length - 2];
      final p1 = points.last;
      final t = (logV - p0.log10Sva) / (p1.log10Sva - p0.log10Sva);
      return (p0.y + (p1.y - p0.y) * t) * scale;
    }

    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (logV >= a.log10Sva && logV <= b.log10Sva) {
        final t = (logV - a.log10Sva) / (b.log10Sva - a.log10Sva);
        return (a.y + (b.y - a.y) * t) * scale;
      }
    }
    return points.last.y * scale;
  }

  Future<void> _loadLegendGeometry() async {
    try {
      final bytes = await _fetchLegendBytes(LpgmMonitorService.legendImageUrl);
      if (bytes == null) return;
      final image = await _decodeLegendImage(bytes);
      final detected = await _detectLegendBarGeometry(bytes);
      if (detected == null || image == null || !mounted) return;
      setState(() {
        _legendGeometry = detected.geometry;
        _legendMarkerColor = detected.midColor;
        _legendImage?.dispose();
        _legendImage = image;
        _legendRgba = detected.rgba;
        _legendRgbaW = detected.width;
        _legendRgbaH = detected.height;
      });
    } catch (_) {
      // keep fallback geometry
    }
  }

  Future<Uint8List?> _fetchLegendBytes(String url) async {
    final client = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Referer', 'https://www.lmoni.bosai.go.jp/monitor/');
      req.headers.set('User-Agent', _ua);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      return await consolidateHttpClientResponseBytes(res);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<_LegendDetectResult?> _detectLegendBarGeometry(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) {
      img.dispose();
      codec.dispose();
      return null;
    }
    final width = img.width;
    final height = img.height;
    final scanFromX = (width * 0.60).floor();
    int contentMinX = width;
    int contentMinY = height;
    int contentMaxX = -1;
    int contentMaxY = -1;

    final colCount = List<int>.filled(width, 0);
    final colMinY = List<int>.filled(width, height);
    final colMaxY = List<int>.filled(width, -1);

    for (int y = 0; y < height; y++) {
      for (int x = scanFromX; x < width; x++) {
        final off = (y * width + x) * 4;
        final r = raw.getUint8(off);
        final g = raw.getUint8(off + 1);
        final b = raw.getUint8(off + 2);
        final a = raw.getUint8(off + 3);
        // Keep all visible pixels (including black text/ticks) when trimming transparent area.
        if (a > 8) {
          if (x < contentMinX) contentMinX = x;
          if (y < contentMinY) contentMinY = y;
          if (x > contentMaxX) contentMaxX = x;
          if (y > contentMaxY) contentMaxY = y;
        }
        if (!_isLegendScaleColor(r, g, b)) continue;
        colCount[x]++;
        if (y < colMinY[x]) colMinY[x] = y;
        if (y > colMaxY[x]) colMaxY[x] = y;
      }
    }

    int bestX = -1;
    int bestScore = -1;
    int bestSpan = 0;
    for (int x = scanFromX; x < width; x++) {
      final c = colCount[x];
      if (c <= 0) continue;
      final span = colMaxY[x] - colMinY[x] + 1;
      if (span < 80 || c < 40) continue;
      final score = c * 3 + span;
      if (score > bestScore) {
        bestScore = score;
        bestX = x;
        bestSpan = span;
      }
    }

    if (bestX < 0) {
      img.dispose();
      codec.dispose();
      return null;
    }

    final minCount = (colCount[bestX] * 0.35).floor().clamp(20, 9999);
    final minSpan = (bestSpan * 0.55).floor().clamp(60, 9999);

    int xMin = bestX;
    int xMax = bestX;
    for (int x = bestX - 1; x >= scanFromX; x--) {
      final span = colMaxY[x] - colMinY[x] + 1;
      if (colCount[x] >= minCount && span >= minSpan) {
        xMin = x;
      } else {
        break;
      }
    }
    for (int x = bestX + 1; x < width; x++) {
      final span = colMaxY[x] - colMinY[x] + 1;
      if (colCount[x] >= minCount && span >= minSpan) {
        xMax = x;
      } else {
        break;
      }
    }

    int barTop = height;
    int barBottom = -1;
    for (int x = xMin; x <= xMax; x++) {
      if (colCount[x] == 0) continue;
      if (colMinY[x] < barTop) barTop = colMinY[x];
      if (colMaxY[x] > barBottom) barBottom = colMaxY[x];
    }
    if (barBottom > barTop) {
      final refined = _refineBarByDarkGuides(
        raw: raw,
        width: width,
        height: height,
        xMin: xMin,
        xMax: xMax,
        colorTop: barTop,
        colorBottom: barBottom,
      );
      barTop = refined.$1;
      barBottom = refined.$2;
    }

    img.dispose();
    codec.dispose();

    if (barBottom <= barTop) return null;
    final midY = ((barTop + barBottom) / 2.0).round().clamp(0, height - 1);
    final midX = ((xMin + xMax) / 2.0).round().clamp(0, width - 1);
    final off = (midY * width + midX) * 4;
    final midColor = Color.fromARGB(
      0xFF,
      raw.getUint8(off),
      raw.getUint8(off + 1),
      raw.getUint8(off + 2),
    );
    final hasContent =
        contentMaxX > contentMinX + 4 && contentMaxY > contentMinY + 4;
    final pad = 2;
    final left = hasContent
        ? (contentMinX - pad).clamp(0, width - 1).toDouble()
        : 0.0;
    final top = hasContent
        ? (contentMinY - pad).clamp(0, height - 1).toDouble()
        : 0.0;
    final right = hasContent
        ? (contentMaxX + 1 + pad).clamp(1, width).toDouble()
        : width.toDouble();
    final bottom = hasContent
        ? (contentMaxY + 1 + pad).clamp(1, height).toDouble()
        : height.toDouble();
    return _LegendDetectResult(
      geometry: _LegendBarGeometry(
        srcWidth: width.toDouble(),
        srcHeight: height.toDouble(),
        barLeft: xMin.toDouble(),
        barRight: xMax.toDouble(),
        barTop: barTop.toDouble(),
        barBottom: barBottom.toDouble(),
        contentLeft: left,
        contentTop: top,
        contentRight: right,
        contentBottom: bottom,
      ),
      midColor: midColor,
      rgba: Uint8List.fromList(
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      ),
      width: width,
      height: height,
    );
  }

  Future<ui.Image?> _decodeLegendImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  bool _isLegendScaleColor(int r, int g, int b) {
    final rn = r / 255.0;
    final gn = g / 255.0;
    final bn = b / 255.0;
    final cMax = math.max(rn, math.max(gn, bn));
    final cMin = math.min(rn, math.min(gn, bn));
    final delta = cMax - cMin;
    if (cMax < 0.15 || delta < 0.12) return false;
    final s = cMax == 0 ? 0.0 : delta / cMax;
    return s >= 0.45;
  }

  (int, int) _refineBarByDarkGuides({
    required ByteData raw,
    required int width,
    required int height,
    required int xMin,
    required int xMax,
    required int colorTop,
    required int colorBottom,
  }) {
    final left = (xMin - 1).clamp(0, width - 1);
    final right = (xMax + 1).clamp(0, width - 1);
    int top = colorTop;
    int bottom = colorBottom;

    // Search a short window around the color-band edge for faint dark guide rows.
    final topFrom = (colorTop - 18).clamp(0, height - 1);
    final topTo = (colorTop + 6).clamp(0, height - 1);
    double bestTopScore = -1;
    int bestTop = top;
    for (int y = topFrom; y <= topTo; y++) {
      final dark = _rowDarkRatio(raw, width, y, left, right);
      final nearColor = _rowColorRatio(
        raw,
        width,
        (y + 1).clamp(0, height - 1),
        left,
        right,
      );
      final score = dark * 0.75 + nearColor * 0.25;
      if (dark >= 0.40 && nearColor >= 0.22 && score > bestTopScore) {
        bestTopScore = score;
        bestTop = y;
      }
    }
    top = bestTop;

    final bottomFrom = (colorBottom - 6).clamp(0, height - 1);
    final bottomTo = (colorBottom + 18).clamp(0, height - 1);
    double bestBottomScore = -1;
    int bestBottom = bottom;
    for (int y = bottomFrom; y <= bottomTo; y++) {
      final dark = _rowDarkRatio(raw, width, y, left, right);
      final nearColor = _rowColorRatio(
        raw,
        width,
        (y - 1).clamp(0, height - 1),
        left,
        right,
      );
      final score = dark * 0.75 + nearColor * 0.25;
      if (dark >= 0.40 && nearColor >= 0.22 && score > bestBottomScore) {
        bestBottomScore = score;
        bestBottom = y;
      }
    }
    bottom = bestBottom;

    if (bottom <= top + 10) {
      return (colorTop, colorBottom);
    }
    return (top, bottom);
  }

  double _rowDarkRatio(ByteData raw, int width, int y, int left, int right) {
    int total = 0;
    int hit = 0;
    for (int x = left; x <= right; x++) {
      final off = (y * width + x) * 4;
      final r = raw.getUint8(off);
      final g = raw.getUint8(off + 1);
      final b = raw.getUint8(off + 2);
      final a = raw.getUint8(off + 3);
      if (a < 12) continue;
      total++;
      if (_isDarkGuidePixel(r, g, b)) hit++;
    }
    if (total == 0) return 0.0;
    return hit / total;
  }

  double _rowColorRatio(ByteData raw, int width, int y, int left, int right) {
    int total = 0;
    int hit = 0;
    for (int x = left; x <= right; x++) {
      final off = (y * width + x) * 4;
      final r = raw.getUint8(off);
      final g = raw.getUint8(off + 1);
      final b = raw.getUint8(off + 2);
      final a = raw.getUint8(off + 3);
      if (a < 12) continue;
      total++;
      if (_isLegendScaleColor(r, g, b)) hit++;
    }
    if (total == 0) return 0.0;
    return hit / total;
  }

  bool _isDarkGuidePixel(int r, int g, int b) {
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    return maxC <= 125 && (maxC - minC) <= 32;
  }

  Color _colorForSva(double sva, {required double boxHeight}) {
    final rgba = _legendRgba;
    if (rgba != null && _legendRgbaW > 0 && _legendRgbaH > 0) {
      final yDisplay = _calibratedLegendYFromSva(
        sva,
        boxHeight,
      ).clamp(0.0, boxHeight - 1);
      final contentH =
          (_legendGeometry.contentBottom - _legendGeometry.contentTop).clamp(
            1.0,
            _legendGeometry.srcHeight,
          );
      final y = (_legendGeometry.contentTop + (yDisplay / boxHeight) * contentH)
          .round()
          .clamp(0, _legendRgbaH - 1);
      final x = ((_legendGeometry.barLeft + _legendGeometry.barRight) * 0.5)
          .round()
          .clamp(0, _legendRgbaW - 1);
      final off = (y * _legendRgbaW + x) * 4;
      if (off >= 0 && off + 3 < rgba.length) {
        return Color.fromARGB(0xFF, rgba[off], rgba[off + 1], rgba[off + 2]);
      }
    }
    return _legendMarkerColor;
  }

  Widget _buildNiedGifStationChip(NiedStation station) {
    final obs = station.gifObservation;
    final shindo = obs?.shindo ?? -3.0;
    final jmaIndex = JpShindoScale.jmaIndexFromShindo(shindo);
    final color = _debugJmaColor(jmaIndex);
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.52)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            station.code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Shindo ${_formatShindoValue(shindo)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'PGA ${_fmtMotion(obs?.pga)}  PGV ${_fmtMotion(obs?.pgv)}  PGD ${_fmtMotion(obs?.pgd, digits: 4)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtMotion(double? v, {int digits = 3}) {
    if (v == null || !v.isFinite) return '--';
    return v.toStringAsFixed(digits);
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Widget _emptyCenter(String text) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildReplayLoggerToggle() {
    final logger = NiedReplayLogger.instance;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: logger.isEnabled
            ? Colors.amber.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: logger.isEnabled ? Colors.amber : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NIED Replay Logger',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      logger.isEnabled
                          ? 'Recording frames to disk...'
                          : 'Enable to record GIF→Detect→Epicenter logs',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    if (logger.lastLogPath != null)
                      Text(
                        'Last: ${logger.lastLogPath!.split(Platform.pathSeparator).last}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: logger.isEnabled,
                activeThumbColor: Colors.amber,
                activeTrackColor: Colors.amber.withValues(alpha: 0.35),
                onChanged: (v) => setState(() => logger.setEnabled(v)),
              ),
            ],
          ),
          const Divider(height: 18, color: Colors.white12),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '推算触发自动保存',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '源推算 confirmed/strong 时自动开启并立即保存 replay log',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: logger.autoSaveOnSourceTrigger,
                activeThumbColor: Colors.lightGreenAccent,
                activeTrackColor: Colors.lightGreenAccent.withValues(
                  alpha: 0.35,
                ),
                onChanged: (v) {
                  unawaited(
                    logger.setAutoSaveOnSourceTrigger(v).then((_) {
                      if (mounted) setState(() {});
                    }),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalQuakeToggle() {
    final status = _globalQuakeService.status;
    final statusColor = switch (status) {
      SourceStatus.connected => const Color(0xFF3AFF6F),
      SourceStatus.connecting || SourceStatus.synchronizing => Colors.amber,
      SourceStatus.error => const Color(0xFFFF6673),
      SourceStatus.disconnected => Colors.white54,
    };
    final lastEvent = _globalQuakeService.lastEvent;
    final subtitle = _globalQuakeEnabled
        ? 'Status: ${status.name}  Active: ${_globalQuakeService.localWsUrl}'
        : 'Connect directly to the GlobalQuake 地震预警 TCP stream.';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _globalQuakeEnabled
            ? const Color(0xFF203A2B).withValues(alpha: 0.35)
            : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _globalQuakeEnabled ? statusColor : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'GlobalQuake 地震预警',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status.name,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    if (lastEvent != null)
                      Text(
                        'Last: ${lastEvent.hypocenter} M${lastEvent.magnitude.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    if (_globalQuakeService.lastError != null)
                      Text(
                        'Error: ${_globalQuakeService.lastError}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFA0A8),
                          fontSize: 10,
                        ),
                      )
                    else if (_globalQuakeService.lastLog != null)
                      Text(
                        'Log: ${_globalQuakeService.lastLog}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: _globalQuakeEnabled,
                activeThumbColor: statusColor,
                activeTrackColor: statusColor.withValues(alpha: 0.35),
                onChanged: _globalQuakeLoaded ? _setGlobalQuakeEnabled : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _globalQuakeField(
                label: 'Primary host',
                width: 260,
                controller: _globalQuakePrimaryHostController,
              ),
              _globalQuakeField(
                label: 'Primary port',
                width: 120,
                controller: _globalQuakePrimaryPortController,
                keyboardType: TextInputType.number,
              ),
              _globalQuakeField(
                label: 'Secondary host',
                width: 260,
                controller: _globalQuakeSecondaryHostController,
              ),
              _globalQuakeField(
                label: 'Secondary port',
                width: 120,
                controller: _globalQuakeSecondaryPortController,
                keyboardType: TextInputType.number,
              ),
              ElevatedButton(
                onPressed: _globalQuakeLoaded ? _saveGlobalQuakeServers : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _globalQuakeField({
    required String label,
    required double width,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0xFF82B1FF)),
          ),
        ),
      ),
    );
  }

  Widget _debugCard({required String title, required List<String> lines}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LegendFitMode { containCenter, coverBottomRight, cropContentFill }

class _SvaLegendCalibPoint {
  final double sva;
  final double y;
  const _SvaLegendCalibPoint(this.sva, this.y);
  double get log10Sva => math.log(sva) / math.ln10;
}

final List<_SvaLegendCalibPoint> _svaLegendCalib = [
  _SvaLegendCalibPoint(0.001, 226.6),
  _SvaLegendCalibPoint(0.01, 213.0),
  _SvaLegendCalibPoint(0.1, 193.8),
  _SvaLegendCalibPoint(1.0, 174.6),
  _SvaLegendCalibPoint(2.0, 158.6),
  _SvaLegendCalibPoint(5.0, 141.0),
  _SvaLegendCalibPoint(10.0, 122.6),
  _SvaLegendCalibPoint(20.0, 105.0),
  _SvaLegendCalibPoint(50.0, 87.4),
  _SvaLegendCalibPoint(100.0, 69.8),
  _SvaLegendCalibPoint(200.0, 51.4),
  _SvaLegendCalibPoint(500.0, 33.8),
  _SvaLegendCalibPoint(1000.0, 18.6),
];

class _LegendDetectResult {
  final _LegendBarGeometry geometry;
  final Color midColor;
  final Uint8List rgba;
  final int width;
  final int height;

  const _LegendDetectResult({
    required this.geometry,
    required this.midColor,
    required this.rgba,
    required this.width,
    required this.height,
  });
}

class _LegendBarGeometry {
  final double srcWidth;
  final double srcHeight;
  final double barLeft;
  final double barRight;
  final double barTop;
  final double barBottom;
  final double contentLeft;
  final double contentTop;
  final double contentRight;
  final double contentBottom;

  const _LegendBarGeometry({
    required this.srcWidth,
    required this.srcHeight,
    required this.barLeft,
    required this.barRight,
    required this.barTop,
    required this.barBottom,
    required this.contentLeft,
    required this.contentTop,
    required this.contentRight,
    required this.contentBottom,
  });

  const _LegendBarGeometry.fallback()
    : srcWidth = 352.0,
      srcHeight = 400.0,
      barLeft = 330.0,
      barRight = 337.0,
      barTop = 206.0,
      barBottom = 396.0,
      contentLeft = 292.0,
      contentTop = 180.0,
      contentRight = 352.0,
      contentBottom = 400.0;
}

const String _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LegendImageCropPainter extends CustomPainter {
  final ui.Image image;
  final _LegendBarGeometry geometry;
  final bool preserveAspect;

  const _LegendImageCropPainter({
    required this.image,
    required this.geometry,
    this.preserveAspect = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTRB(
      geometry.contentLeft.clamp(0.0, image.width.toDouble() - 1),
      geometry.contentTop.clamp(0.0, image.height.toDouble() - 1),
      geometry.contentRight.clamp(1.0, image.width.toDouble()),
      geometry.contentBottom.clamp(1.0, image.height.toDouble()),
    );
    Rect dst = Offset.zero & size;
    if (preserveAspect) {
      final sw = src.width;
      final sh = src.height;
      if (sw > 0 && sh > 0 && size.width > 0 && size.height > 0) {
        final scale = math.min(size.width / sw, size.height / sh);
        final dw = sw * scale;
        final dh = sh * scale;
        final dx = (size.width - dw) / 2.0;
        final dy = (size.height - dh) / 2.0;
        dst = Rect.fromLTWH(dx, dy, dw, dh);
      }
    }
    final paint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _LegendImageCropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.geometry != geometry ||
        oldDelegate.preserveAspect != preserveAspect;
  }
}
