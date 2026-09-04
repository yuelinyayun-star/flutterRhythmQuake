/// 模拟 2026/06/03 23:22:36 M2.7 伊予灘 地震的 NIED 检测 + 震源推算
/// 用法: dart run tools/test_iyonada_quake.dart
library;

import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../lib/services/sources/nied_monitor.dart';
import '../lib/services/sources/shake_detection_service.dart';
import '../lib/core/hypocenter_estimator.dart';

void main() {
  final rng = Random(42);

  // ── 地震参数 ──
  const eqLat = 33.531;
  const eqLng = 132.332;
  const eqDepth = 43.9; // km
  const eqMag = 2.7;

  // ── 生成模拟测站 ──
  // 在震中周围 0.5° 范围内分布 30 个 NIED 测站
  final stations = <NiedStation>[];
  for (int i = 0; i < 30; i++) {
    // 随机分布
    final dLat = (rng.nextDouble() - 0.5) * 0.5;
    final dLng = (rng.nextDouble() - 0.5) * 0.5;
    final stationLat = eqLat + dLat;
    final stationLng = eqLng + dLng;
    final distKm = _haversine(eqLat, eqLng, stationLat, stationLng);
    final dist3d = sqrt(distKm * distKm + eqDepth * eqDepth);

    // M2.7 JMA 震度估算 (距离衰减)
    // log10(PGA) = 0.43M - log10(R+10) - 0.0014R + 0.17
    final hypoDist = max(dist3d, 5.0);
    final logPga =
        0.43 * eqMag - log(hypoDist + 10) / ln10 - 0.0014 * hypoDist + 0.17;
    final pga = pow(10, logPga).toDouble();
    // PGV ~ PGA / 5 (近似)
    final pgv = max(pga / 5.0, 0.01);
    // 计测震度 = 2.68 + 1.72 * log10(PGV)
    final instShindo = 2.68 + 1.72 * log(pgv.clamp(0.01, 999)) / ln10;
    final shindo = instShindo.clamp(-3.0, 7.0);

    // shindo → level (scratchValues lookup)
    final level = _shindoToLevel(shindo);

    // 微弱站 (远距离) 设 level = 0 或 -1
    final actualLevel = distKm > 100 ? (rng.nextBool() ? 0 : -1) : level;

    final station = NiedStation(
      code: 'NIED${i.toString().padLeft(3, '0')}',
      prefecture: _prefectureAt(stationLat, stationLng),
      network: 'K-NET',
      coordinate: LatLng(stationLat, stationLng),
    );
    station.level = actualLevel;
    station.recentLevel = List.filled(10, actualLevel);
    station.lastUpdate = DateTime.now();
    station.scanReliable = true;
    // 设置 expireSeconds
    station.defaultExpireSeconds = 10;
    station.expireSeconds = 8;

    stations.add(station);
  }

  print('Generated ${stations.length} simulated stations');
  print('Active (level >= 0): ${stations.where((s) => s.level >= 0).length}');
  print('Max level: ${stations.map((s) => s.level).reduce(max)}');
  print('');

  // ── 运行检测 ──
  final detection = ShakeDetectionService();
  onSnapshot(snapshot) {
    print('─── Detection Snapshot ───');
    print('Stage: ${snapshot.stage.name}');
    print(
      'Weak: ${snapshot.weakCount}, Detected: ${snapshot.detectedCount}, Strong: ${snapshot.strongCount}',
    );
    print('Max Shindo: ${snapshot.maxShindo}');
    if (snapshot.detectedStations.isNotEmpty) {
      print('Top stations:');
      for (final s in snapshot.detectedStations.take(5)) {
        print(
          '  ${s.prefecture} (${s.code}) level=${s.level} shindo=${s.jmaShindo} state=${s.detectState} reason=${s.detectReason}',
        );
      }
    }
    print('');
  }

  detection.onDetectionSnapshotChanged = onSnapshot;
  detection.setSensitivity(2);
  detection.setStations(stations);

  // 多次迭代以让 detectConsecutiveFrames 累计
  for (int frame = 0; frame < 4; frame++) {
    print('── Frame ${frame + 1} ──');
    // 每帧稍微增加 level 模拟震度增长
    if (frame == 0) {
      // 第一帧: 轻微前震
      for (final s in stations) {
        if (s.level >= 0 &&
            _haversine(
                  eqLat,
                  eqLng,
                  s.coordinate.latitude,
                  s.coordinate.longitude,
                ) <
                30) {
          s.level = max(s.level, _shindoToLevel(1.0));
        }
      }
    }
    if (frame >= 1) {
      // 后续帧: 主震
      for (final s in stations) {
        final dist = _haversine(
          eqLat,
          eqLng,
          s.coordinate.latitude,
          s.coordinate.longitude,
        );
        final actualLevel = _shindoToLevel(3.5 - dist * 0.02);
        if (actualLevel >= 0) s.level = actualLevel;
      }
    }
    detection.processUpdate();
  }

  // ── 震源推算 ──
  print('─── Hypocenter Estimation ───');
  final estimate = HypocenterEstimator.estimate(stations);
  if (estimate != null) {
    final distError = _haversine(
      eqLat,
      eqLng,
      estimate.latitude,
      estimate.longitude,
    );
    print(
      'Estimated: ${estimate.latitude.toStringAsFixed(3)}N, ${estimate.longitude.toStringAsFixed(3)}E',
    );
    print('True:     $eqLat N, $eqLng E');
    print('Error:    ${distError.toStringAsFixed(1)} km');
    print('Confidence: ${(estimate.confidence * 100).toStringAsFixed(0)}%');
  } else {
    print('No estimate (not enough active stations)');
  }
}

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}

int _shindoToLevel(double shindo) {
  const scratchValues = [
    -3.0,
    -2.5,
    -2.0,
    -1.5,
    -1.17,
    -0.84,
    -0.5,
    -0.17,
    0.16,
    0.5,
    0.83,
    1.16,
    1.5,
    1.83,
    2.16,
    2.5,
    2.83,
    3.16,
    3.5,
    3.83,
    4.16,
    4.5,
    4.75,
    5.0,
    5.25,
    5.5,
    5.75,
    6.0,
    6.25,
    6.5,
  ];
  if (shindo < scratchValues.first) return -1;
  if (shindo >= scratchValues.last) return scratchValues.length - 1;
  for (int i = scratchValues.length - 1; i >= 0; i--) {
    if (shindo >= scratchValues[i]) return i;
  }
  return -1;
}

String _prefectureAt(double lat, double lng) {
  if (lat > 34.0) return '広島県';
  if (lat > 33.5) return '愛媛県';
  if (lat > 33.0) return '大分県';
  return '高知県';
}
