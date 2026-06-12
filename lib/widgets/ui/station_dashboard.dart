import 'package:flutter/material.dart';
import 'dart:ui';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/shake_detection_service.dart';
import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/kma_monitor.dart';

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
  final List<DetectedStationEntry> detectedStations;
  const NiedDetectSummary({
    required this.stage,
    required this.weakCount,
    required this.detectedCount,
    required this.strongCount,
    required this.maxShindo,
    this.detectedStations = const [],
  });
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
  const StationDashboard({super.key, required this.data});

  static const double _refWidth = 1280.0;

  double _scale(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    return (w / _refWidth).clamp(0.7, 1.0);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  double get _combinedWidth => 3.0 * 75.0 + 2.0 * 1.0 + 6.0 + 1.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50 + _s(12, context),
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: _combinedWidth,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSeisJsSection(),
                _buildDivider(),
                _buildMaxSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35)),
    );
  }

  Widget _buildSeisJsSection() {
    final s = data.seisJsStation;
    final shindo = s?.shindo ?? 0;
    final maxInt = s?.maxIntensity ?? 0;
    final pga = s?.pga ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '计测震度',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 7,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  shindo >= 0 ? shindo.toString() : '--',
                  style: TextStyle(
                    color: _shindoColor(shindo),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 2.5,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9142),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Flexible(
                      child: Text(
                        '新艾利都六分街',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _barText(
                      '最大烈度',
                      maxInt.toStringAsFixed(2),
                      const Color(0xFFFF9142),
                    ),
                    const SizedBox(height: 2),
                    _barText(
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

  Widget _buildMaxSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Row(
        children: [
          _maxCard(
            'NIED',
            '最大震度',
            _niedMaxLabel(data.niedMaxStation),
            const Color(0xFF00DC8C),
          ),
          Container(
            width: 1,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          _maxCard(
            'TREM',
            '最大震度',
            data.treaMaxStation?.alertIntensity != null &&
                    data.treaMaxStation!.alertIntensity >= 0
                ? data.treaMaxStation!.alertIntensity.toString()
                : '--',
            const Color(0xFF1ABC9C),
          ),
          Container(
            width: 1,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          _maxCard(
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

  Widget _maxCard(String source, String label, String value, Color accent) {
    return Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            source,
            style: TextStyle(
              color: accent,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 6),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _barText(String label, String value, Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2.5,
          height: 9,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 8,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: accent,
            fontSize: 9,
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
