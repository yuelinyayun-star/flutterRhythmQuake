import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/station_image_decoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'prepared debug views cannot reenter detection or external imports',
    () async {
      final image = LmoniImageService()
        ..stop()
        ..start();
      final observations = <List<NiedStation>?>[];
      final displays = <List<NiedStation>?>[];
      final imports = <List<NiedStation>?>[];
      final subscriptions = [
        image.stationStream.listen(observations.add),
        image.displayStationStream.listen(displays.add),
        image.externalStationStream.listen(imports.add),
      ];
      try {
        final bytes = File(
          'test/fixtures/nied_recovery/20260610180120.lmoni.jma_s.gif',
        ).readAsBytesSync();
        image.processPixels(
          decodeStationImageCpu(bytes)!.packedRgb,
          dataTime: DateTime(2026, 6, 10, 18, 1, 20),
        );
        await Future<void>.delayed(Duration.zero);
        expect(observations, hasLength(1));
        expect(displays, hasLength(1));
        expect(imports, isEmpty);
        final views = [
          for (final station in observations.single!)
            NiedStation.detachedSnapshot(station),
        ];
        image.acceptPreparedStations(views);
        await Future<void>.delayed(Duration.zero);
        expect(displays, hasLength(2));
        expect(observations, hasLength(1));
        expect(imports, isEmpty);
        // User-requested K-NET imports retain their explicit ingress.
        image.broadcastStations(views);
        await Future<void>.delayed(Duration.zero);
        expect(imports, hasLength(1));
        expect(imports.single, views);
      } finally {
        for (final sub in subscriptions) {
          await sub.cancel();
        }
        image.stop();
      }
    },
  );
}
