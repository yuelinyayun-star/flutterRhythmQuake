import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_channel_sensitivity.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_realtime_pipeline_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_display_frame.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';
import 'package:flutterrhythmquake/services/sources/native_seedlink_signal_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original 206-record archive retains calibrated values through prepared map views',
    () async {
      final input = File(
        'tmp/fdsn_connection_review/costa_rica_QUEP_mmi_input.json',
      );
      if (!input.existsSync()) {
        markTestSkipped(
          'Original Costa Rica waveform and ObsPy audit are required.',
        );
        return;
      }
      final spec = jsonDecode(input.readAsStringSync(encoding: utf8)) as Map;
      final original = File(spec['waveform'] as String).readAsBytesSync();
      final hash = sha256.convert(original).toString();
      expect(hash, spec['sha256']);
      final records = (spec['records'] as List).cast<Map>();
      final worker = FdsnRealtimePipeline(testMode: true);
      FdsnDisplayFrame? frame;
      List<FdsnStation> stations = const [];
      final errors = <Object>[];
      worker.onError = errors.add;
      worker.onFrame = (value) {
        frame = value;
        if (value.stations != null) stations = value.stations!;
      };
      final row = (records.first['metadataRow'] as List).cast<String>();
      final metadata = FdsnStation(
        network: row[0],
        station: row[1],
        location: row[2],
        source: 'EarthScope',
        coordinate: LatLng(double.parse(row[4]), double.parse(row[5])),
      );
      try {
        await worker.connect(stationLimit: 300, sources: {'EarthScope'});
        await worker.injectOriginal(
          metadata: [metadata],
          displayClock: DateTime.parse(records.first['end']),
        );
        expect(stations, isEmpty);
        FdsnMotionSample? last;
        DateTime? latestTime;
        for (final record in records) {
          final r = (record['metadataRow'] as List).cast<String>();
          final time = DateTime.parse(record['end']);
          final offset = record['offset'] as int;
          final decoded = decodeFdsnRecordForTest(
            Uint8List.sublistView(original, offset, offset + 512),
          )!;
          expect(decoded, record['samples']);
          final response = FdsnChannelSensitivity.parse(
            r.join('|'),
            network: r[0],
            station: r[1],
            location: r[2],
            channel: r[3],
            time: time,
          )!;
          final metrics = fdsnMetricsForTest(
            decoded,
            (record['sampleRate'] as num).toDouble(),
            response.sensitivity,
            response.unit,
          );
          last = FdsnMotionSample(
            source: 'EarthScope',
            network: r[0],
            station: r[1],
            channel: r[3],
            timestamp: time,
            pga: metrics['pga'],
            pgv: metrics['pgv'],
            intensity: metrics['mmi'],
          );
          final older = latestTime != null && time.isBefore(latestTime);
          if (!older) latestTime = time;
          await worker.injectOriginal(sample: last, displayClock: latestTime);
          expect(frame!.processingIsolate, 'fdsn-realtime-data-owner');
          if (older) {
            expect(frame!.automation, isEmpty);
            continue;
          }
          expect(frame!.automation.single.observedAt, time);
          expect(frame!.automation.single.intensity, metrics['mmi']);
          expect(stations.single.pga, metrics['pga']);
          expect(stations.single.pgv, metrics['pgv']);
          expect(stations.single.intensity, metrics['mmi']);
        }
        expect(metadata.lastMotionUpdate, isNull);
        expect(metadata.intensity, isNull);
        final lastView = stations.single;
        await worker.injectOriginal(
          sample: FdsnMotionSample(
            source: 'EarthScope',
            network: row[0],
            station: row[1],
            channel: row[3],
            timestamp: DateTime.parse(records.first['end']),
            intensity: last!.intensity,
          ),
          displayClock: last.timestamp,
        );
        expect(frame!.automation, isEmpty);
        expect(stations.single.lastMotionUpdate, lastView.lastMotionUpdate);
        await worker.injectOriginal(
          displayClock: last.timestamp.add(const Duration(minutes: 4)),
        );
        expect(stations, isEmpty);
        await worker.connect(stationLimit: 300, sources: {});
        await worker.injectOriginal(sample: last, displayClock: last.timestamp);
        expect(stations, isEmpty);
        expect(frame!.automation, isEmpty);
        expect(errors, isEmpty);
        expect(
          sha256.convert(File(spec['waveform']).readAsBytesSync()).toString(),
          hash,
        );
      } finally {
        worker.dispose();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(NativeSeedLinkSignal.diagnostics['sessions'], 0);
    },
  );

  test('stop during startup cannot reopen a stale FDSN owner', () async {
    final worker = FdsnRealtimePipeline(testMode: true);
    final pending = worker.connect(stationLimit: 300, sources: {'EarthScope'});
    worker.stop();
    await pending;
    expect(FdsnRealtimePipeline.active, isNot(same(worker)));
    await worker.connect(stationLimit: 100, sources: {'GEOFON'});
    await worker.injectOriginal();
    expect(worker.lastFrame!.limit, 100);
    worker.dispose();
  });
}
