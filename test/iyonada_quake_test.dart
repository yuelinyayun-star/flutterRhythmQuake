/// 模拟 2026/06/03 23:22:36 M2.7 伊予灘 地震的 NIED 检测 + 震源推算
/// 运行: flutter test tools/test_iyonada_quake.dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:flutterrhythmquake/core/hypocenter_estimator.dart';

void main() {
  test('Iyonada M2.7 quake detection + epicenter estimation', () {
    final rng = Random(42);

    const eqLat = 33.531;
    const eqLng = 132.332;
    const eqDepth = 43.9;
    const eqMag = 2.7;

    // 使用 JMA 2001 公式计算真实震度分布
    // IntensityCalculator.calcJmaShindo(mj, dep, dist)
    final stations = <NiedStation>[];
    for (int i = 0; i < 80; i++) {
      final dLat = (rng.nextDouble() - 0.5) * 1.0;  // ±0.5° 范围
      final dLng = (rng.nextDouble() - 0.5) * 1.0;
      final stationLat = eqLat + dLat;
      final stationLng = eqLng + dLng;
      final distKm = haversine(eqLat, eqLng, stationLat, stationLng);
      final dist3d = sqrt(distKm * distKm + eqDepth * eqDepth);

      // JMA 2001 计测震度
      final mw = eqMag - 0.171;
      final faultLength = pow(10, 0.5 * mw - 1.85) / 2;
      final hypoDist = max(dist3d - faultLength, 3.0);
      final pgv600 = pow(10,
        0.58 * mw + 0.0038 * eqDepth - 1.29 -
        log(hypoDist + 0.0028 * pow(10, 0.5 * mw)) / ln10 -
        0.002 * hypoDist
      );
      final pgv = pgv600 * 1.307;
      final instShindo = pgv > 0 ? (2.68 + 1.72 * log(pgv) / ln10) : -3.0;
      final shindo = instShindo.clamp(-3.0, 7.0);
      final level = shindoToLevel(shindo);
      // 远距离噪声站: 随机 0 或 -1
      final actualLevel = distKm > 80 ? (rng.nextBool() ? 0 : -1) : level;

      final station = NiedStation(
        id: i,
        code: 'N${i.toString().padLeft(3, '0')}',
        name: 'Station $i',
        coordinate: LatLng(stationLat, stationLng),
        network: 'K-NET',
        prefecture: prefectureAt(stationLat, stationLng),
        expireSeconds: 10,
      );
      station.level = actualLevel;
      station.recentLevel = List.filled(10, actualLevel);
      station.lastUpdate = DateTime.now();
      stations.add(station);
    }

    print('\n=== Iyonada M2.7 Quake Simulation ===');
    print('Generated ${stations.length} stations');
    print('Active: ${stations.where((s) => s.level >= 0).length}');
    print('Max level: ${stations.map((s) => s.level).reduce(max)}');
    print('');

    final detection = ShakeDetectionService();
    List<String> logs = [];

    detection.onDetectionSnapshotChanged = (snapshot) {
      if (snapshot.stage == ShakeDetectStage.idle) return;
      final msg = 'Stage: ${snapshot.stage.name} | '
          'Weak:${snapshot.weakCount} Detected:${snapshot.detectedCount} '
          'Strong:${snapshot.strongCount} | MaxShindo:${snapshot.maxShindo}';
      print(msg);
      logs.add(msg);
      if (snapshot.detectedStations.isNotEmpty) {
        for (final s in snapshot.detectedStations.take(3)) {
          print('  ${s.prefecture}(${s.code}) L${s.level} S${s.jmaShindo} [${s.detectReason}]');
        }
      }
    };

    detection.setSensitivity(2);
    detection.setStations(stations);

    // Frame 0: 搭建邻接关系 (所有站 level=0，背景噪声)
    for (final s in stations) {
      s.level = 0;
      s.recentLevel = List.filled(s.expireSeconds, 0);
      s.lastUpdate = DateTime.now();
    }
    detection.processUpdate();

    // Frame 1: 地震信号初现 (level 按 JMA2001 分布)
    for (final s in stations) {
      final dist = haversine(eqLat, eqLng, s.coordinate.latitude, s.coordinate.longitude);
      final dist3d = sqrt(dist * dist + eqDepth * eqDepth);
      final mw = eqMag - 0.171;
      final fl = pow(10, 0.5 * mw - 1.85) / 2;
      final hd = max(dist3d - fl, 3.0);
      final pgv600 = pow(10, 0.58*mw + 0.0038*eqDepth - 1.29 - log(hd + 0.0028*pow(10,0.5*mw))/ln10 - 0.002*hd);
      final ipgv = pgv600 * 1.307;
      final ish = ipgv > 0 ? (2.68 + 1.72 * log(ipgv) / ln10) : -3.0;
      s.level = shindoToLevel(ish.clamp(-3.0, 7.0));
      s.lastUpdate = DateTime.now();
    }
    detection.processUpdate();

    // Frames 2-4: 持续信号
    for (int frame = 2; frame < 6; frame++) {
      for (final s in stations) {
        s.lastUpdate = DateTime.now();
      }
      detection.processUpdate();
    }

    // Epicenter
    print('\n--- Epicenter Estimation ---');
    final estimate = HypocenterEstimator.estimate(stations);
    expect(estimate, isNotNull);
    if (estimate != null) {
      final err = haversine(eqLat, eqLng, estimate.latitude, estimate.longitude);
      print('True:   ${eqLat}N, ${eqLng}E');
      print('Est:    ${estimate.latitude.toStringAsFixed(3)}N, ${estimate.longitude.toStringAsFixed(3)}E');
      print('Error:  ${err.toStringAsFixed(1)} km');
      print('Conf:   ${(estimate.confidence * 100).toStringAsFixed(0)}%');
      // 模拟测站随机分布，误差在 150km 内可接受
      expect(err, lessThan(150.0));
    }

    expect(logs.isNotEmpty, true);
    expect(logs.any((l) => l.contains('detected') || l.contains('strong')), true);
  });
}

double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}

int shindoToLevel(double shindo) {
  const scratchValues = [
    -3.0, -2.5, -2.0, -1.5, -1.17, -0.84, -0.5, -0.17,
    0.16, 0.5, 0.83, 1.16, 1.5, 1.83, 2.16, 2.5,
    2.83, 3.16, 3.5, 3.83, 4.16, 4.5, 4.75, 5.0,
    5.25, 5.5, 5.75, 6.0, 6.25, 6.5,
  ];
  if (shindo < scratchValues.first) return -1;
  if (shindo >= scratchValues.last) return scratchValues.length - 1;
  for (int i = scratchValues.length - 1; i >= 0; i--) {
    if (shindo >= scratchValues[i]) return i;
  }
  return -1;
}

String prefectureAt(double lat, double lng) {
  if (lat > 34.0) return '広島県';
  if (lat > 33.5) return '愛媛県';
  if (lat > 33.0) return '大分県';
  return '高知県';
}
