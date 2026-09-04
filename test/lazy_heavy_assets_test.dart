import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/services/boundary_service.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TravelTimeService lazy load', () {
    tearDown(() {
      TravelTimeService().resetForTesting();
    });

    test('starts unloaded and returns empty results until ensureLoaded', () {
      final service = TravelTimeService();
      expect(service.isLoaded, isFalse);
      final before = service.calcWaveDistance('jma2001', true, 10, 30);
      expect(before.radius, 0);
    });

    test('ensureLoaded makes wave distance and reach time available', () async {
      final service = TravelTimeService();
      await service.ensureLoaded();
      expect(service.isLoaded, isTrue);

      final wave = service.calcWaveDistance('jma2001', true, 10, 30);
      expect(wave.radius, greaterThan(0));

      final reach = service.calcReachTime('jma2001', false, 10, 100);
      expect(reach, greaterThan(0));
    });

    test('concurrent ensureLoaded shares one load', () async {
      final service = TravelTimeService();
      await Future.wait([
        service.ensureLoaded(),
        service.ensureLoaded(),
        service.load(),
      ]);
      expect(service.isLoaded, isTrue);
      expect(service.loadedListenable.value, isTrue);
    });
  });

  group('EpicenterRegionService lazy load', () {
    tearDown(() {
      EpicenterRegionService.instance.setResolverForTesting(null);
    });

    test('lookup is null before load and resolves after load', () async {
      final service = EpicenterRegionService.instance;
      expect(service.isLoaded, isFalse);
      expect(service.lookup(39.9042, 116.4074), isNull);

      await service.load();
      expect(service.isLoaded, isTrue);
      expect(service.lookup(39.9042, 116.4074), '北京市东城区');
    });

    test(
      'getFEName falls back before load and uses detail after load',
      () async {
        EpicenterRegionService.instance.setResolverForTesting(null);
        expect(EpicenterRegionService.instance.isLoaded, isFalse);

        final before = getFEName(39.9042, 116.4074);
        expect(before, isNotEmpty);
        expect(before.endsWith('附近'), isTrue);

        await EpicenterRegionService.instance.load();
        final after = getFEName(39.9042, 116.4074);
        expect(after, '北京市东城区附近');
      },
    );
  });

  group('BoundaryService lazy load', () {
    tearDown(() {
      BoundaryService().resetForTesting();
    });

    test('load parses visible boundary layers for display', () async {
      final service = BoundaryService();
      expect(service.isLoaded, isFalse);

      await service.load();
      expect(service.isLoaded, isTrue);
      expect(service.layers.length, 3);
      expect(service.layers.any((layer) => layer.name.contains('断层')), isFalse);

      final polylineCount = service.layers.fold<int>(
        0,
        (sum, layer) => sum + layer.polylines.length,
      );
      expect(polylineCount, greaterThan(0));
      expect(service.cityLabels, isNotEmpty);
    });

    test('concurrent load shares one parse pass', () async {
      final service = BoundaryService();
      await Future.wait([service.load(), service.load()]);
      expect(service.isLoaded, isTrue);
      expect(service.layers.length, 3);
    });
  });
}
