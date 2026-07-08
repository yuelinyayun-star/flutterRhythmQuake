import 'package:flutter/material.dart';
import 'dart:ui';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/shake_detection_service.dart';
import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/kma_monitor.dart';
import 'ui_scale.dart';

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
                  _buildSeisJsSection(context),
                  _buildDivider(context),
                  _buildMaxSection(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      height: _s(1, context),
      margin: EdgeInsets.symmetric(horizontal: _s(6, context)),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35)),
    );
  }

  Widget _buildSeisJsSection(BuildContext context) {
    final s = data.seisJsStation;
    final shindo = s?.shindo ?? 0;
    final maxInt = s?.maxIntensity ?? 0;
    final pga = s?.pga ?? 0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _s(8, context),
        vertical: _s(6, context),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _s(48, context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '计测震度',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: _s(7, context),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: _s(1, context)),
                Text(
                  shindo >= 0 ? shindo.toString() : '--',
                  style: TextStyle(
                    color: _shindoColor(shindo),
                    fontSize: _s(22, context),
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: _s(1, context),
            height: _s(34, context),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          SizedBox(width: _s(6, context)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: _s(2.5, context),
                      height: _s(10, context),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9142),
                        borderRadius: BorderRadius.circular(_s(2, context)),
                      ),
                    ),
                    SizedBox(width: _s(5, context)),
                    Flexible(
                      child: Text(
                        '新艾利都六分街',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _s(9, context),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: _s(4, context)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _barText(
                      context,
                      '最大烈度',
                      maxInt.toStringAsFixed(2),
                      const Color(0xFFFF9142),
                    ),
                    SizedBox(height: _s(2, context)),
                    _barText(
                      context,
                      'PGA',
                      '${pga.toStringAsFixed(1)} gal',
                      const Color(0xFF4FC3F7),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaxSection(BuildContext context) {
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
            '最大震度',
            _niedMaxLabel(data.niedMaxStation),
            const Color(0xFF00DC8C),
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
            '最大震度',
            data.treaMaxStation?.currentIntensity != null &&
                    data.treaMaxStation!.currentIntensity >= 0
                ? CwaStationService.shindoFromInstShindo(
                    data.treaMaxStation!.currentIntensity,
                  ).toString()
                : '--',
            const Color(0xFF1ABC9C),
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
            '最大烈度',
            data.kmaMaxStation?.intensity != null &&
                    data.kmaMaxStation!.intensity >= 0
                ? data.kmaMaxStation!.intensity.toString()
                : '--',
            const Color(0xFFE67E22),
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
    Color accent,
  ) {
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
          SizedBox(height: _s(1, context)),
          Text(
            label,
            style: TextStyle(color: Colors.white38, fontSize: _s(6, context)),
          ),
          SizedBox(height: _s(1, context)),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: _s(14, context),
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _barText(
    BuildContext context,
    String label,
    String value,
    Color accent,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _s(2.5, context),
          height: _s(9, context),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(_s(1.5, context)),
          ),
        ),
        SizedBox(width: _s(4, context)),
        Text(
          '$label ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: _s(8, context),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: accent,
            fontSize: _s(9, context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _niedMaxLabel(NiedStation? station) {
    if (station == null || station.level < 0) return '--';
    const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    final idx = JpShindoScale.jmaIndexFromLevel(station.level);
    return labels[idx.clamp(0, labels.length - 1).toInt()];
  }

  Color _shindoColor(int shindo) {
    if (shindo >= 7) return const Color(0xFFB40000);
    if (shindo >= 6) return const Color(0xFFFF0000);
    if (shindo >= 5) return const Color(0xFFFFB400);
    if (shindo >= 4) return const Color(0xFFFFFF00);
    if (shindo >= 3) return const Color(0xFF00DC8C);
    if (shindo >= 2) return const Color(0xFF46B4FF);
    if (shindo >= 1) return const Color(0xFF8282FF);
    return Colors.white38;
  }
}
