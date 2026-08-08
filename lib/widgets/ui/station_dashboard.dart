import 'package:flutter/material.dart';
import 'dart:ui';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/shake_detection_service.dart';
import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/kma_monitor.dart';
import '../../services/sources/palert_service.dart';
import '../../models/snet_station.dart';
import '../../core/intensity_calculator.dart';
import 'ui_scale.dart';

@visibleForTesting
String tremDashboardShindoLabel(num instShindo) {
  final level = CwaStationService.gridLevelFromInstShindo(instShindo);
  if (level < 0) return '--';
  const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
  final index = JpShindoScale.jmaIndexFromKanameishiLevel(level);
  return labels[index.clamp(0, labels.length - 1)];
}

SeisJsStation? selectSeisJsCurrentMaxStation(Iterable<SeisJsStation> stations) {
  SeisJsStation? selected;
  var maxIntensity = double.negativeInfinity;
  for (final station in stations) {
    final intensity = station.intensity;
    if (!intensity.isFinite || intensity <= maxIntensity) continue;
    maxIntensity = intensity;
    selected = station;
  }
  return selected;
}

List<SnetTopStation> selectSnetSidebarTopStations(
  Iterable<SnetStation> stations,
) {
  final active =
      stations
          .where(
            (station) =>
                station.isActive &&
                station.level >= 0 &&
                station.shindo.isFinite,
          )
          .toList(growable: false)
        ..sort((a, b) {
          final shindoCompare = b.shindo.compareTo(a.shindo);
          if (shindoCompare != 0) return shindoCompare;
          return a.code.compareTo(b.code);
        });
  if (active.isEmpty ||
      JpShindoScale.jmaIndexFromShindo(active.first.shindo) <= 0) {
    return const <SnetTopStation>[];
  }

  return active
      .take(5)
      .map(
        (station) => SnetTopStation(
          code: station.code,
          shindo: station.shindo,
          jmaIndex: JpShindoScale.jmaIndexFromShindo(station.shindo),
        ),
      )
      .toList(growable: false);
}

class SnetTopStation {
  final String code;
  final double shindo;
  final int jmaIndex;
  const SnetTopStation({
    required this.code,
    required this.shindo,
    required this.jmaIndex,
  });
}

class LpgmTopStation {
  final String code;
  final double sva;
  final int lpgmClass;
  const LpgmTopStation({
    required this.code,
    required this.sva,
    required this.lpgmClass,
  });
}

class NiedDetectSummary {
  final String stage;
  final int weakCount;
  final int detectedCount;
  final int strongCount;
  final int maxShindo;
  final int visualGridCount;
  final List<DetectedStationEntry> detectedStations;
  final List<NiedDetectVisualArea> visualAreas;
  const NiedDetectSummary({
    required this.stage,
    required this.weakCount,
    required this.detectedCount,
    required this.strongCount,
    required this.maxShindo,
    this.visualGridCount = 0,
    this.detectedStations = const [],
    this.visualAreas = const [],
  });
}

class NiedDetectVisualArea {
  final String name;
  final int jmaShindo;

  const NiedDetectVisualArea({required this.name, required this.jmaShindo});
}

class StationSummaryData {
  SeisJsStation? seisJsStation;
  SeisJsStation? seisJsMaxStation;
  NiedStation? niedMaxStation;
  CwaStation? treaMaxStation;
  KmaStation? kmaMaxStation;
  PAlertStation? pAlertMaxStation;
  DateTime? snetWindowStart;
  DateTime? snetWindowEnd;
  List<SnetTopStation> snetTopStations = const [];
  NiedDetectSummary? niedDetect;
  DateTime? lpgmTime;
  double? lpgmMaxSva;
  int? lpgmMaxClass;
  List<LpgmTopStation> lpgmTopStations = const [];
}

class StationDashboard extends StatelessWidget {
  final StationSummaryData data;
  final bool phoneMode;

  const StationDashboard({
    super.key,
    required this.data,
    this.phoneMode = false,
  });

  double _scale(BuildContext c) {
    return UiScale.compact(c);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  double _combinedWidth(BuildContext c) =>
      _s(3.0 * 75.0 + 2.0 * 1.0 + 6.0 + 1.0, c);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: UiScale.topBarHeight(context) + _s(phoneMode ? 8 : 12, context),
      left: phoneMode ? _s(10, context) : null,
      right: phoneMode ? null : _s(20, context),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_s(10, context)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: _combinedWidth(context),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(_s(10, context)),
                border: Border.all(
                  color: Colors.white12,
                  width: _s(0.5, context),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTopMaxSection(context),
                  _buildBottomMaxSection(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopMaxSection(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _s(3, context),
        vertical: _s(5, context),
      ),
      child: Row(
        children: [
          _maxCard(
            context,
            'NIED',
            '当前最大震度',
            _niedMaxLabel(data.niedMaxStation),
            const Color(0xFF00DC8C),
            valueColor: _niedMaxColor(),
          ),
          Container(
            width: _s(1, context),
            height: _s(30, context),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          _maxCard(
            context,
            'S-net',
            '当前最大震度',
            _snetMaxLabel(),
            const Color(0xFF00E5FF),
            valueColor: _snetMaxColor(),
          ),
          Container(
            width: _s(1, context),
            height: _s(30, context),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          _maxCard(
            context,
            'KMA',
            '当前最大烈度',
            data.kmaMaxStation?.heldIntensity != null &&
                    data.kmaMaxStation!.heldIntensity >= 0
                ? data.kmaMaxStation!.heldIntensity.toString()
                : '--',
            const Color(0xFFE67E22),
            valueColor: _csisValueColor(data.kmaMaxStation?.heldIntensity),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomMaxSection(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _s(3, context),
        vertical: _s(5, context),
      ),
      child: Row(
        children: [
          _maxCard(
            context,
            'SeisJS',
            '当前最大烈度',
            data.seisJsMaxStation != null
                ? data.seisJsMaxStation!.intensity.round().toString()
                : '--',
            const Color(0xFFFF9142),
            valueColor: _csisValueColor(
              data.seisJsMaxStation?.intensity.round(),
            ),
          ),
          Container(
            width: _s(1, context),
            height: _s(30, context),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          _maxCard(
            context,
            'TREM',
            '当前最大震度',
            data.treaMaxStation?.currentIntensity != null &&
                    data.treaMaxStation!.currentIntensity >= 0
                ? tremDashboardShindoLabel(
                    data.treaMaxStation!.currentIntensity,
                  )
                : '--',
            const Color(0xFF1ABC9C),
            valueColor: _tremMaxColor(),
          ),
          Container(
            width: _s(1, context),
            height: _s(30, context),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          _maxCard(
            context,
            'P-Alert',
            '当前最大震度',
            data.pAlertMaxStation?.shindoLabel ?? '--',
            const Color(0xFFE74C3C),
            valueColor: _pAlertMaxColor(),
          ),
        ],
      ),
    );
  }

  Widget _maxCard(
    BuildContext context,
    String source,
    String label,
    String value,
    Color accent, {
    Color? valueColor,
  }) {
    return Container(
      width: _s(75, context),
      padding: EdgeInsets.symmetric(
        vertical: _s(2, context),
        horizontal: _s(4, context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            source,
            style: TextStyle(
              color: accent,
              fontSize: _s(8, context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: _s(2, context)),
          Container(
            width: _s(12, context),
            height: _s(1, context),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(_s(1, context)),
            ),
          ),
          SizedBox(height: _s(2, context)),
          Text(
            label,
            style: TextStyle(color: Colors.white38, fontSize: _s(6, context)),
          ),
          SizedBox(height: _s(1, context)),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white.withValues(alpha: 0.9),
              fontSize: _s(14, context),
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  String _niedMaxLabel(NiedStation? station) {
    if (station == null || station.level < 0) return '--';
    const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    final idx = JpShindoScale.jmaIndexFromKanameishiLevel(station.level);
    return labels[idx.clamp(0, labels.length - 1).toInt()];
  }

  String _snetMaxLabel() {
    if (data.snetTopStations.isEmpty) return '--';
    const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    final idx = data.snetTopStations.first.jmaIndex;
    return labels[idx.clamp(0, labels.length - 1)];
  }

  Color? _niedMaxColor() {
    final station = data.niedMaxStation;
    if (station == null || station.level < 0) return null;
    final shindo = JpShindoScale.rawShindoFromKanameishiLevel(station.level);
    return Color(IntensityCalculator.getJmaShindoColor(shindo));
  }

  Color? _snetMaxColor() {
    if (data.snetTopStations.isEmpty) return null;
    final idx = data.snetTopStations.first.jmaIndex;
    return _jmaIndexValueColor(idx);
  }

  Color? _tremMaxColor() {
    final station = data.treaMaxStation;
    if (station == null || station.currentIntensity < 0) return null;
    final level = CwaStationService.gridLevelFromInstShindo(
      station.currentIntensity,
    );
    final shindo = JpShindoScale.rawShindoFromKanameishiLevel(level);
    return _jmaNumberValueColor(shindo);
  }

  Color? _pAlertMaxColor() {
    final station = data.pAlertMaxStation;
    if (station == null || station.gridLevel < 0) return null;
    final shindo = JpShindoScale.rawShindoFromKanameishiLevel(
      station.gridLevel,
    );
    return Color(IntensityCalculator.getJmaShindoColor(shindo));
  }

  Color? _jmaNumberValueColor(num? value) {
    if (value == null || value < 0) return null;
    final shindo = value.toDouble();
    return Color(IntensityCalculator.getJmaShindoColor(shindo));
  }

  Color? _jmaIndexValueColor(int idx) {
    if (idx < 0) return null;
    const shindoByIndex = [0.0, 1.0, 2.0, 3.0, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5];
    return Color(
      IntensityCalculator.getJmaShindoColor(
        shindoByIndex[idx.clamp(0, shindoByIndex.length - 1)],
      ),
    );
  }

  Color? _csisValueColor(num? value) {
    if (value == null || value < 0) return null;
    return Color(IntensityCalculator.getCsisColor(value.round()));
  }
}
