import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lpgm_monitor_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LpgmStationReading reading(String code, double sva) {
    return LpgmStationReading(
      code: code,
      name: code,
      coordinate: const LatLng(0, 0),
      sva: sva,
      lpgmClass: LpgmMonitorService.lpgmClassFromSva(sva),
    );
  }

  test('samples only the station center pixel', () {
    const width = 352;
    const height = 400;
    const x = 166;
    const y = 233;
    final packedRgb = List<int>.filled(width * height, 0x002BE8);
    packedRgb[y * width + x] = 0xFFAF00;

    final sva = LpgmMonitorService().sampleCenterSvaForTesting(packedRgb, x, y);

    expect(sva, isNotNull);
    expect(sva!, closeTo(20.320240281, 0.000001));
  });

  test('blocks the persistent ISKH08 LPGM outlier only', () {
    expect(LpgmMonitorService.blockedStationCodes, const {'ISKH08'});
    expect(LpgmMonitorService.isBlockedStationForTesting('ISKH08'), isTrue);
    expect(LpgmMonitorService.isBlockedStationForTesting('ISK009'), isFalse);
  });

  test('suppresses a lone high LPGM station', () {
    final high = reading('ISKH08', 20.32);
    final quiet = reading('ISK009', 0.02);

    expect(
      LpgmMonitorService.shouldSuppressIsolatedHighForTesting(
        candidate: high,
        readings: [high, quiet],
        previousSvaByCode: const {'ISKH08': 20.0, 'ISK009': 0.02},
      ),
      isTrue,
    );
  });

  test('keeps high LPGM when another station is also high', () {
    final high = reading('ISKH08', 20.32);
    final supporting = reading('ISK009', 5.1);

    expect(
      LpgmMonitorService.shouldSuppressIsolatedHighForTesting(
        candidate: high,
        readings: [high, supporting],
        previousSvaByCode: const {'ISKH08': 0.02, 'ISK009': 0.02},
      ),
      isFalse,
    );
  });

  test('keeps high LPGM when another station rises meaningfully', () {
    final high = reading('ISKH08', 20.32);
    final supporting = reading('ISK009', 0.2);

    expect(
      LpgmMonitorService.shouldSuppressIsolatedHighForTesting(
        candidate: high,
        readings: [high, supporting],
        previousSvaByCode: const {'ISKH08': 0.02, 'ISK009': 0.05},
      ),
      isFalse,
    );
  });

  test('does not infer supporting rise without a previous frame', () {
    final high = reading('ISKH08', 20.32);
    final elevated = reading('ISK009', 0.2);

    expect(
      LpgmMonitorService.shouldSuppressIsolatedHighForTesting(
        candidate: high,
        readings: [high, elevated],
        previousSvaByCode: const {},
      ),
      isTrue,
    );
  });

  test('keeps confirmed supporting station while it remains elevated', () {
    final high = reading('ISKH08', 20.32);
    final stableSupport = reading('ISK009', 0.2);

    expect(
      LpgmMonitorService.shouldSuppressIsolatedHighForTesting(
        candidate: high,
        readings: [high, stableSupport],
        previousSvaByCode: const {'ISKH08': 20.0, 'ISK009': 0.2},
        confirmedSupportingRiseCodes: const {'ISK009'},
      ),
      isFalse,
    );
  });

  test('does not treat a small fluctuation as supporting rise', () {
    final high = reading('ISKH08', 20.32);
    final fluctuation = reading('ISK009', 0.12);

    expect(
      LpgmMonitorService.shouldSuppressIsolatedHighForTesting(
        candidate: high,
        readings: [high, fluctuation],
        previousSvaByCode: const {'ISKH08': 20.0, 'ISK009': 0.08},
      ),
      isTrue,
    );
  });
}
