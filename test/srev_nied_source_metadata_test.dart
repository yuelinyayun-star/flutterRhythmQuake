import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_realtime_pipeline.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'JIAN same coordinates with revised identity refresh the detection directory',
    () async {
      final pipeline = NiedRealtimePipeline(
        testMode: true,
        testPrefecturesJson: File(
          'assets/maps/japan_prefectures.geojson',
        ).readAsStringSync(),
      );
      NiedPipelineFrame? result;
      final errors = <Object>[];
      pipeline.onFrame = (f) => result = f;
      pipeline.onError = errors.add;
      final t = DateTime.utc(2026, 11, 25, 9);
      WhewsStationFrame frame(
        String code,
        String name,
        String region,
        String network,
        int second,
      ) => WhewsStationFrame(
        source: 'jian',
        kind: WhewsStationKind.nied,
        dataTime: t.add(Duration(seconds: second)),
        coordinates: const [LatLng(35.2974, 136.7505)],
        values: const [1.2],
        codes: [code],
        names: [name],
        regions: [region],
        stationTypes: [network],
      );
      try {
        await pipeline.start(
          source: 'jian',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: false,
        );
        await pipeline.injectArray(frame('OLD', '尾西', '愛知県', 'K-NET', 0), t);
        expect(errors, isEmpty);
        expect(result!.stations.single.code, 'OLD');
        await pipeline.injectArray(
          frame('NEW', '修正局', '岐阜県', 'KiK-net', 1),
          t.add(const Duration(seconds: 1)),
        );
        expect(errors, isEmpty);
        final s = result!.stations.single;
        expect(
          [s.code, s.name, s.prefecture, s.network],
          ['NEW', '修正局', '岐阜県', 'KiK-net'],
        );
        expect(s.continuousShindo, 1.2);
      } finally {
        pipeline.dispose();
      }
    },
    skip: !NativeNiedDetectionOwner.supported,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
