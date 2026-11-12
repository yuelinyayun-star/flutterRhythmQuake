// 候选算法（未被生产默认路径引用）：逐站反演 + 稳健合并的震级估计。
//
// 背景
//   生产 srev-kaizou 震级在"内陆浅震"情形实际退化为 M ≈ I_max + 1.311：
//   其距离项 D = 震央到最近 scratch 站的距离、且下限钳到 20km，多数事件被钳，
//   于是 1.73·log10(D) 成为常数 2.251，距离根本不参与。
//   本实现改为 JMA 式：**每站用自身震源距反演 M，再稳健合并**。
//
// 标定来源
//   tmp/knet_mag_lab/ —— 9 个事件的 K-NET/KiK-net 波形全保真观测
//   （官方計測震度 I = 2·log10(a0.3s)+0.94），拟合衰减律 I = a·M + b·log10(R) + c，
//   以留一交叉验证(LOO)选定系数。小震(M<5)子集：RMS 由生产 0.449 → 0.223。
//
// 边界
//   本文件为**候选/影子实现**，不修改生产默认行为；接入需产品决策（见配套提案文档）。
import 'dart:math' as math;

/// 一组多事件标定系数：I = a·M + b·log10(max(R, dmin)) + k·R + c
class MagnitudeCalibration {
  const MagnitudeCalibration({
    required this.id,
    required this.a,
    required this.b,
    required this.k,
    required this.c,
    required this.residualRms,
    required this.eventCount,
    required this.note,
  });

  final String id;
  final double a;
  final double b;
  final double k;
  final double c;
  final double residualRms;
  final int eventCount;
  final String note;
}

/// 小震目标域(M<5)标定：5 事件 / 184 站，拟合 RMS 0.557。
const MagnitudeCalibration kMagnitudeCalibSmallM1V1 = MagnitudeCalibration(
  id: 'knet_multievent_small_m1_v1',
  a: 1.4334,
  b: -3.3730,
  k: 0.0,
  c: 0.9120,
  residualRms: 0.557,
  eventCount: 5,
  note: '小震(M<5)操作域 I>=0.5, R<=300km；留一验证 RMS 0.223（vs 生产 0.449）',
);

/// 全量标定（含 M6.6-7.6 大震；大震近场强度饱和，斜率被压低）。
const MagnitudeCalibration kMagnitudeCalibAllM1V1 = MagnitudeCalibration(
  id: 'knet_multievent_all_m1_v1',
  a: 1.2640,
  b: -3.2350,
  k: 0.0,
  c: 1.4170,
  residualRms: 0.748,
  eventCount: 9,
  note: '全 9 事件操作域；作为小震模型的兜底',
);

class MagnitudeStationIntensity {
  const MagnitudeStationIntensity({
    required this.code,
    required this.intensity,
    required this.latitude,
    required this.longitude,
  });

  final String code;

  /// JMA 計測震度（或 App 从图像解码出的连续震度）。
  final double intensity;
  final double latitude;
  final double longitude;
}

class MagnitudePerStationEntry {
  const MagnitudePerStationEntry({
    required this.code,
    required this.intensity,
    required this.distanceKm,
    required this.magnitude,
    required this.used,
  });

  final String code;
  final double intensity;
  final double distanceKm;
  final double magnitude;
  final bool used;
}

class MagnitudePerStationResult {
  const MagnitudePerStationResult({
    required this.magnitude,
    required this.inputStationCount,
    required this.usedStationCount,
    required this.medianMagnitude,
    required this.scatterMad,
    required this.calibrationId,
    required this.entries,
  });

  final double magnitude;
  final int inputStationCount;
  final int usedStationCount;
  final double medianMagnitude;
  final double scatterMad;
  final String calibrationId;
  final List<MagnitudePerStationEntry> entries;

  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'mag_perstation_model': 'multievent_perstation_robust_v1',
    'mag_perstation_calibration': calibrationId,
    'mag_perstation_magnitude': magnitude,
    'mag_perstation_input_station_count': inputStationCount,
    'mag_perstation_used_station_count': usedStationCount,
    'mag_perstation_median': medianMagnitude,
    'mag_perstation_scatter_mad': scatterMad,
  };
}

class MagnitudePerStationCandidate {
  const MagnitudePerStationCandidate();

  static const double defaultMinimumDistanceKm = 20.0;
  static const double defaultOutlierMadK = 3.0;
  static const int defaultMinimumStationCount = 2;

  /// 逐站反演 + MAD 稳健合并。样本不足时退化为"用最强站单站反演"。
  static MagnitudePerStationResult? estimate({
    required List<MagnitudeStationIntensity> stations,
    required double sourceLatitude,
    required double sourceLongitude,
    double sourceDepthKm = 0.0,
    MagnitudeCalibration calibration = kMagnitudeCalibSmallM1V1,
    bool useHypocentralDistance = true,
    double minimumDistanceKm = defaultMinimumDistanceKm,
    double intensityFloor = 0.0,
    int minimumStationCount = defaultMinimumStationCount,
    double outlierMadK = defaultOutlierMadK,
  }) {
    if (!sourceLatitude.isFinite || !sourceLongitude.isFinite) return null;

    final entries = <MagnitudePerStationEntry>[];
    for (final s in stations) {
      if (!s.intensity.isFinite || s.intensity < intensityFloor) continue;
      if (!s.latitude.isFinite || !s.longitude.isFinite) continue;
      final epicentral = _distanceKm(
        sourceLatitude,
        sourceLongitude,
        s.latitude,
        s.longitude,
      );
      final depth = sourceDepthKm.isFinite ? sourceDepthKm : 0.0;
      final rawDistance = useHypocentralDistance
          ? math.sqrt(epicentral * epicentral + depth * depth)
          : epicentral;
      if (!rawDistance.isFinite || rawDistance <= 0.0) continue;
      final clamped = math.max(rawDistance, minimumDistanceKm);
      final magnitude =
          (s.intensity -
              calibration.b * (math.log(clamped) / math.ln10) -
              calibration.k * rawDistance -
              calibration.c) /
          calibration.a;
      if (!magnitude.isFinite) continue;
      entries.add(
        MagnitudePerStationEntry(
          code: s.code,
          intensity: s.intensity,
          distanceKm: rawDistance,
          magnitude: magnitude,
          used: false,
        ),
      );
    }
    if (entries.isEmpty) return null;

    final sorted = List<MagnitudePerStationEntry>.of(entries)
      ..sort((p, q) => p.magnitude.compareTo(q.magnitude));
    final median = _median(sorted.map((e) => e.magnitude).toList());

    var used = entries;
    if (entries.length >= 3) {
      final mad = _median(
        entries.map((e) => (e.magnitude - median).abs()).toList(),
      );
      if (mad > 0) {
        final threshold = outlierMadK * 1.4826 * mad;
        final kept = entries
            .where((e) => (e.magnitude - median).abs() <= threshold)
            .toList();
        if (kept.length >= math.max(2, minimumStationCount)) {
          used = kept;
        }
      }
    }

    final scatterMad = entries.length >= 3
        ? _median(entries.map((e) => (e.magnitude - median).abs()).toList())
        : 0.0;

    final usedSet = used.map((e) => e.code).toSet();
    final flagged = entries
        .map(
          (e) => MagnitudePerStationEntry(
            code: e.code,
            intensity: e.intensity,
            distanceKm: e.distanceKm,
            magnitude: e.magnitude,
            used: usedSet.contains(e.code),
          ),
        )
        .toList();

    if (used.length < minimumStationCount) {
      // 站数不足：退化为"最强站单站反演"，但明确标注。
      final strongest = entries.reduce(
        (p, q) => p.intensity >= q.intensity ? p : q,
      );
      return MagnitudePerStationResult(
        magnitude: math.max(0.0, strongest.magnitude),
        inputStationCount: entries.length,
        usedStationCount: 1,
        medianMagnitude: median,
        scatterMad: scatterMad,
        calibrationId: calibration.id,
        entries: flagged,
      );
    }

    final mean = used.map((e) => e.magnitude).reduce((p, q) => p + q) / used.length;
    return MagnitudePerStationResult(
      magnitude: math.max(0.0, mean),
      inputStationCount: entries.length,
      usedStationCount: used.length,
      medianMagnitude: median,
      scatterMad: scatterMad,
      calibrationId: calibration.id,
      entries: flagged,
    );
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return double.nan;
    final sorted = List<double>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  /// 与生产 srevKaizouStationDistanceKm 同口径的近似平面距离（km）。
  static double _distanceKm(
    double sourceLatitude,
    double sourceLongitude,
    double stationLatitude,
    double stationLongitude,
  ) {
    final latitudePart = (sourceLatitude - stationLatitude) * 111.2;
    final longitudePart =
        6371.0 *
        (sourceLongitude - stationLongitude) *
        (3.1416 / 180.0) *
        math.cos(
          ((sourceLatitude + stationLatitude) / 2.0) * math.pi / 180.0,
        );
    return math.sqrt(
      latitudePart * latitudePart + longitudePart * longitudePart,
    );
  }
}
