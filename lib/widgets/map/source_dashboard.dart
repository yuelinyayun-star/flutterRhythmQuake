import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../models/source_status.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/fdsn_motion_service.dart';
import '../../services/sources/fan_service.dart';
import '../../services/sources/global_quake_service.dart';
import '../../services/sources/kma_monitor.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/nied_yahoo_service.dart';
import '../../services/sources/palert_service.dart';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/source_manager.dart';
import 'quake_map_view.dart';
import '../ui/ui_scale.dart';

class DataProgressFreshnessTracker {
  DataProgressFreshnessTracker({this.staleAfter = const Duration(seconds: 3)});

  final Duration staleAfter;
  String? _source;
  DateTime? _frameTime;
  DateTime? _lastProgressAt;

  bool update({
    required String source,
    required DateTime? frameTime,
    required DateTime now,
  }) {
    if (_source != source) {
      _source = source;
      _frameTime = frameTime;
      _lastProgressAt = frameTime == null ? null : now;
    } else if (frameTime == null) {
      _frameTime = null;
      _lastProgressAt = null;
    } else if (_frameTime != frameTime) {
      _frameTime = frameTime;
      _lastProgressAt = now;
    }

    final lastProgressAt = _lastProgressAt;
    if (frameTime == null || lastProgressAt == null) return false;
    final elapsed = now.difference(lastProgressAt);
    return !elapsed.isNegative && elapsed < staleAfter;
  }
}

class SourceDashboard extends StatefulWidget {
  const SourceDashboard({super.key});

  @override
  State<SourceDashboard> createState() => _SourceDashboardState();
}

class _SourceDashboardState extends State<SourceDashboard> {
  final ValueNotifier<int> _clockTick = ValueNotifier<int>(0);
  final Map<String, DataProgressFreshnessTracker> _stationFreshness = {};
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _clockTick.value++;
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clockTick.dispose();
    super.dispose();
  }

  double _scale(BuildContext c) => UiScale.compact(c);

  double _s(double v, BuildContext c) => v * _scale(c);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: _s(8, context),
      bottom: _s(6, context),
      child: RepaintBoundary(
        child: Transform.scale(
          scale: 0.92,
          alignment: Alignment.bottomLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _s(430, context)),
            child: Builder(
              builder: (context) {
                final provider = context.read<QuakeProvider>();
                return ValueListenableBuilder<int>(
                  valueListenable: provider.sourceStatusListenable,
                  builder: (context, _, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSocketStatusRow(context, provider),
                        AnimatedBuilder(
                          animation: Listenable.merge([
                            NiedMonitorService().dataFrameTime,
                            NiedYahooService().dataFrameTime,
                            QuakeMapView.niedSourceNotifier,
                            CwaStationService().dataTimeNotifier,
                            KmaMonitorService().dataTimeNotifier,
                            SeisJsService().dataTimeNotifier,
                            PAlertService().dataTimeNotifier,
                            FdsnMotionService().linkedStationCountNotifier,
                            FdsnMotionService().dataTimeNotifier,
                            QuakeMapView.niedReplayNotifier,
                            QuakeMapView.niedMonitorEnabledNotifier,
                            QuakeMapView.tremStationEnabledNotifier,
                            QuakeMapView.kmaPewsEnabledNotifier,
                            QuakeMapView.wolfxSeisJsEnabledNotifier,
                            QuakeMapView.pAlertEnabledNotifier,
                            QuakeMapView.fdsnSeedLinkEnabledNotifier,
                            _clockTick,
                          ]),
                          builder: (context, child) {
                            return _buildStationStatusLines(
                              context,
                              provider,
                              FdsnMotionService()
                                  .linkedStationCountNotifier
                                  .value,
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocketStatusRow(BuildContext context, QuakeProvider provider) {
    final fan = SourceManager().getSource<FanService>();
    if (fan != null && SourceManager().isSourceEnabled('FAN')) {
      return AnimatedBuilder(
        animation: Listenable.merge([
          fan.authStatusNotifier,
          fan.connectionStatusNotifier,
        ]),
        builder: (context, child) => _buildSocketStatusRowContent(
          context,
          provider,
          fan.authStatusNotifier.value,
          fan.connectionStatusNotifier.value,
        ),
      );
    }
    return _buildSocketStatusRowContent(context, provider, null, null);
  }

  Widget _buildSocketStatusRowContent(
    BuildContext context,
    QuakeProvider provider,
    FanAuthStatus? fanAuthStatus,
    FanConnectionStatus? fanConnectionStatus,
  ) {
    final names = <(String, String)>[
      if (SourceManager().isSourceEnabled('Wolfx')) ('Wolfx', 'Wolfx'),
      if (SourceManager().isSourceEnabled('FAN'))
        (_fanLabel(fanAuthStatus, fanConnectionStatus), 'FAN'),
      if (SourceManager().isSourceEnabled('WHEWS')) ('WHEWS', 'WHEWS'),
      if (SourceManager().isSourceEnabled('NowQuake')) ('NowQuake', 'NowQuake'),
      if (SourceManager().isSourceEnabled('P2P')) ('P2PQ', 'P2P'),
      if (GlobalQuakeService().isEnabled) ('GQ', 'GlobalQuake'),
    ];
    return _buildSourceRow(context, [
      for (final (label, key) in names)
        _buildStatusName(context, label, provider.sourceStatuses[key]),
    ]);
  }

  String _fanLabel(FanAuthStatus? authStatus, FanConnectionStatus? _) {
    return switch (authStatus) {
      FanAuthStatus.failed => 'FAN（认证失败）',
      FanAuthStatus.unauthenticated || null => 'FAN（未认证）',
      FanAuthStatus.authenticated || FanAuthStatus.authenticating => 'FAN',
    };
  }

  Widget _buildStationStatusLines(
    BuildContext context,
    QuakeProvider provider,
    int fdsnCount,
  ) {
    final now = DateTime.now();
    final niedFrameTime = _niedFrameTime;
    final niedFrameIsFresh = _isDataProgressFresh(
      key: 'nied',
      source: QuakeMapView.niedSourceNotifier.value,
      frameTime: niedFrameTime,
      now: now,
    );
    final tremTime = CwaStationService().dataTimeNotifier.value;
    final kmaTime = KmaMonitorService().dataTimeNotifier.value;
    final seisJsTime = SeisJsService().dataTimeNotifier.value;
    final pAlertTime = PAlertService().dataTimeNotifier.value;
    final fdsnTime = FdsnMotionService().dataTimeNotifier.value;
    final lines = <Widget>[
      if (QuakeMapView.niedMonitorEnabledNotifier.value)
        _buildStationLine(
          context,
          '強震モニタ:',
          provider.sourceStatuses['NIED'],
          time: niedFrameTime,
          utcOffsetHours: 9,
          verifyFresh: true,
          freshnessOverride: niedFrameIsFresh,
          replay: QuakeMapView.niedReplayNotifier.value.enabled,
        ),
      if (QuakeMapView.tremStationEnabledNotifier.value)
        _buildStationLine(
          context,
          'TREM-RTS :',
          provider.sourceStatuses['TREM'],
          time: tremTime,
          utcOffsetHours: 8,
          verifyFresh: true,
          freshnessOverride: _isDataProgressFresh(
            key: 'trem',
            frameTime: tremTime,
            now: now,
          ),
        ),
      if (QuakeMapView.kmaPewsEnabledNotifier.value)
        _buildStationLine(
          context,
          'KMA-PEWS:',
          provider.sourceStatuses['KMA'],
          time: kmaTime,
          utcOffsetHours: 9,
          verifyFresh: true,
          freshnessOverride: _isDataProgressFresh(
            key: 'kma',
            frameTime: kmaTime,
            now: now,
          ),
        ),
      if (QuakeMapView.wolfxSeisJsEnabledNotifier.value)
        _buildStationLine(
          context,
          'SeisJS:',
          provider.sourceStatuses['SeisJS'],
          time: seisJsTime,
          utcOffsetHours: 8,
          verifyFresh: true,
          freshnessOverride: _isDataProgressFresh(
            key: 'seisjs',
            frameTime: seisJsTime,
            now: now,
          ),
        ),
      if (QuakeMapView.pAlertEnabledNotifier.value)
        _buildStationLine(
          context,
          'P-Alert:',
          provider.sourceStatuses['P-Alert'],
          time: pAlertTime,
          utcOffsetHours: 8,
          verifyFresh: true,
          freshnessOverride: _isDataProgressFresh(
            key: 'palert',
            frameTime: pAlertTime,
            now: now,
          ),
        ),
      if (QuakeMapView.fdsnSeedLinkEnabledNotifier.value)
        _buildStationLine(
          context,
          'FDSN:',
          fdsnTime != null
              ? SourceStatus.connected
              : (fdsnCount > 0
                    ? SourceStatus.connecting
                    : SourceStatus.disconnected),
          time: fdsnTime,
          utcOffsetHours: 0,
          verifyFresh: true,
          freshnessOverride: _isDataProgressFresh(
            key: 'fdsn',
            frameTime: fdsnTime,
            now: now,
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }

  DateTime? get _niedFrameTime {
    return QuakeMapView.niedSourceNotifier.value == 'yahoo'
        ? NiedYahooService().dataFrameTime.value
        : NiedMonitorService().dataFrameTime.value;
  }

  bool _isDataProgressFresh({
    required String key,
    String? source,
    required DateTime? frameTime,
    required DateTime now,
  }) {
    final tracker = _stationFreshness.putIfAbsent(
      key,
      DataProgressFreshnessTracker.new,
    );
    return tracker.update(
      source: source ?? key,
      frameTime: frameTime,
      now: now,
    );
  }

  Widget _buildSourceRow(BuildContext context, List<Widget> children) {
    return Wrap(
      spacing: _s(7, context),
      runSpacing: _s(2, context),
      children: children,
    );
  }

  Widget _buildStatusName(
    BuildContext context,
    String name,
    SourceStatus? status,
  ) {
    return Text(
      name,
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        color: _getStatusColor(status ?? SourceStatus.disconnected),
        fontSize: _s(10, context),
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        shadows: _textStrokeShadows(context),
      ),
    );
  }

  Widget _buildStationLine(
    BuildContext context,
    String name,
    SourceStatus? status, {
    DateTime? time,
    int? utcOffsetHours,
    bool verifyFresh = false,
    bool? freshnessOverride,
    bool replay = false,
  }) {
    final displayTime = verifyFresh && utcOffsetHours != null
        ? time ?? DateTime(1970, 1, 1, utcOffsetHours, 0, 0)
        : time;
    final isFresh = freshnessOverride ?? false;
    final color = verifyFresh
        ? (replay
              ? const Color(0xFFFFFF00)
              : (isFresh ? Colors.white : const Color(0xFFFF0000)))
        : _getStatusColor(status ?? SourceStatus.disconnected);
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          color: color,
          fontSize: _s(10, context),
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          shadows: _textStrokeShadows(context),
        ),
        children: [
          TextSpan(text: name),
          if (displayTime != null && utcOffsetHours != null)
            TextSpan(
              text:
                  ' ${_formatTime(displayTime, utcOffsetHours)} '
                  '(UTC${utcOffsetHours >= 0 ? '+' : ''}$utcOffsetHours)',
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time, int utcOffsetHours) {
    final shifted = _displayWallTime(time, utcOffsetHours);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${shifted.year}-${two(shifted.month)}-${two(shifted.day)} '
        '${two(shifted.hour)}:${two(shifted.minute)}:${two(shifted.second)}';
  }

  DateTime _displayWallTime(DateTime time, int utcOffsetHours) {
    if (time.isUtc) {
      return time.toUtc().add(Duration(hours: utcOffsetHours));
    }
    return time;
  }

  Color _getStatusColor(SourceStatus status) {
    switch (status) {
      case SourceStatus.connected:
        return const Color(0xFF008000);
      case SourceStatus.connecting:
        return const Color(0xFFFFFF00);
      case SourceStatus.error:
        return const Color(0xFFFF0000);
      case SourceStatus.disconnected:
        return Colors.white;
      case SourceStatus.synchronizing:
        return const Color(0xFFFFFF00);
    }
  }

  List<Shadow> _textStrokeShadows(BuildContext context) {
    final offset = _s(0.65, context);
    const color = Color(0xE6000000);
    return [
      Shadow(offset: Offset(-offset, 0), color: color),
      Shadow(offset: Offset(offset, 0), color: color),
      Shadow(offset: Offset(0, -offset), color: color),
      Shadow(offset: Offset(0, offset), color: color),
    ];
  }
}
