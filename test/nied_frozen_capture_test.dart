import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'support/nied_replay_fixture.dart';
import 'support/foreground_station_payload_before_frozen.dart';
import 'support/nied_station_snapshot_reference.dart';

String _encode(Map<String, dynamic> value) => jsonEncode(value);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '51 original GIF frames keep every historical field, order and JSON value',
    () async {
      final dir = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!dir.existsSync()) {
        markTestSkipped('Original GIF capture required');
        return;
      }
      final service = LmoniImageService()..start();
      addTearDown(service.stop);
      Map<String, dynamic>? retained;
      String? retainedJson;
      for (var second = 20; second <= 70; second++) {
        final stamp = DateTime(2026, 6, 10, 18, 1, second);
        final raw = (await decodeNiedGifFile(
          File('${dir.path}/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif'),
        ))!;
        final next = service.stationStream.firstWhere((s) => s != null);
        service.processPixels(
          raw.packedRgb,
          dataTime: stamp,
          receivedAt: stamp,
        );
        final stations = (await next)!;
        final expected = OriginalForegroundStationPayload.nied(
          stations,
          source: 'kmoni',
          includeTrackingHistory: false,
        );
        final actual = snapshotSourcePayload(
          ForegroundStationPayload.nied(
            stations,
            source: 'kmoni',
            includeTrackingHistory: false,
          ),
        );
        expect(jsonEncode(actual), jsonEncode(expected));
        expect((actual['stations'] as List).first, isA<SourcePayloadFields>());
        retained ??= actual;
        retainedJson ??= jsonEncode(actual);
        if (second == 20) {
          expect(await compute(_encode, actual), jsonEncode(expected));
          // Controlled timezone/cache boundary; this copy is never fed into
          // the original-GIF replay or source estimation.
          final boundary = referenceStationSnapshot(stations.first)
            ..lastUpdate = stamp.toUtc()
            ..lastDataTime = stamp.toLocal()
            ..lastReceivedAt = null;
          expect(
            jsonEncode(
              ForegroundStationPayload.nied([
                boundary,
              ], includeTrackingHistory: false),
            ),
            jsonEncode(
              OriginalForegroundStationPayload.nied([
                boundary,
              ], includeTrackingHistory: false),
            ),
          );
        }
      }
      expect(jsonEncode(retained), retainedJson);
      final station = (retained!['stations'] as List).first as Map;
      expect(() => station['level'] = 20, throwsUnsupportedError);
      expect(
        () => (station['coordinate'] as Map)['lat'] = 0,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'frozen field layouts detach nested containers and distinguish missing/null',
    () {
      final keys = ['first', 'nullable'];
      final values = <dynamic>[
        {
          'nested': [1, 2.0, -0.0],
        },
        null,
      ];
      final fields = SourcePayloadFields(SourcePayloadLayout(keys), values);
      final before = jsonEncode(fields);
      keys[0] = 'changed';
      (values.first['nested'] as List).clear();
      expect(jsonEncode(fields), before);
      expect(fields.containsKey('nullable'), isTrue);
      expect(fields.containsKey('absent'), isFalse);
      expect(fields['nullable'], isNull);
      expect(identical(snapshotSourcePayload(fields), fields), isTrue);
    },
  );
}
