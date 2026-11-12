import 'package:flutterrhythmquake/services/whews_authorization_policy.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_history.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_history_io.dart'
    as native_io;
import 'package:flutterrhythmquake/services/sources/native_station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/nied_array_observation_processor.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:flutterrhythmquake/widgets/map/station_summary_projection.dart';
import 'support/dart_ka_station_reference.dart';

NiedStation view(int i, LatLng coordinate) => NiedStation(
  id: i,
  code: '原站$i',
  name: '日本測站',
  coordinate: coordinate,
  network: 'K-NET',
  prefecture: '岩手県',
  expireSeconds: 10,
);
DartKaStationReference reference(NiedStation station) => DartKaStationReference(
  id: station.id,
  code: station.code,
  name: station.name,
  coordinate: station.coordinate,
  network: station.network,
  prefecture: station.prefecture,
  expireSeconds: station.expireSeconds,
);
List<Object?> values(dynamic s) => [
  s.level,
  s.ascend,
  s.triggerStamp,
  s.activity,
  s.abnormalUpdateCount,
  s.continuousShindo,
  s.isActive,
  s.lastDataTime,
  s.lastUpdate,
  List<int>.of(s.recentLevel as List<int>),
];

// Frozen map frame-gap order. Controlled timestamps below are ABI/lifecycle
// cases, not modified earthquake captures or performance evidence.
void oldApply(
  List<DartKaStationReference> stations,
  WhewsStationFrame frame,
  DateTime? previous,
) {
  if (previous != null) {
    final diff = frame.dataTime.difference(previous).inMilliseconds;
    if (diff > 1000) {
      final missing = ((diff / 1000).round() - 1).clamp(0, 60);
      if (missing > 0) {
        for (final s in stations) {
          s.recentLevel.insertAll(0, List.filled(missing, -1));
          if (s.recentLevel.length > 60) {
            s.recentLevel = s.recentLevel.sublist(0, 60);
          }
          if (diff > 10000) s.isActive = false;
        }
      }
    }
  }
  for (var i = 0; i < stations.length; i++) {
    final s = stations[i], raw = frame.values[i];
    s.lastDataTime = s.lastUpdate = frame.dataTime;
    s.updateFromContinuousShindo(
      raw.isFinite && raw > -3 && raw <= 7 ? raw : null,
    );
  }
}

void main() {
  setUp(() => WhewsAuthorizationPolicy.storeOverride = MemoryConnectionRetryStore());
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = NativeKaHistorySession.supported;
  test(
    'original WHEWS frame reaches native KA and sidebar without changing raw data',
    () async {
      final directory = File('test/fixtures/whews_nied/stations.json');
      final observations = File('test/fixtures/whews_nied/observations.json');
      final directoryBytes = directory.readAsBytesSync(),
          bodyBytes = observations.readAsBytesSync();
      final service = WhewsStationService(
        kind: WhewsStationKind.nied,
        apiToken: '',
      );
      addTearDown(service.dispose);
      final frameFuture = service.frameStream.first;
      service.handleMessageForTesting(jsonDecode(utf8.decode(directoryBytes)));
      service.handleMessageForTesting(jsonDecode(utf8.decode(bodyBytes)));
      final frame = await frameFuture;
      final stations = [
        for (var i = 0; i < frame.values.length; i++)
          view(i, frame.coordinates[i]),
      ];
      final old = stations.map(reference).toList();
      final processor = NiedArrayObservationProcessor()..configure(stations);
      addTearDown(processor.dispose);
      expect(stations.length, 1560);
      oldApply(old, frame, null);
      final before = NativeKaHistorySession.diagnostics['kaCalls']!;
      expect(processor.apply(frame, receivedAt: frame.dataTime), isTrue);
      expect(NativeKaHistorySession.diagnostics['kaCalls']! - before, 1);
      for (var i = 0; i < stations.length; i++) {
        expect(
          values(stations[i]),
          values(old[i]),
          reason: 'original station $i',
        );
        expect(stations[i].pgaObservation?.pga, frame.pga[i]);
        expect(stations[i].pgvObservation?.pgv, frame.pgv[i]);
      }
      final projection = StationSummaryProjection();
      addTearDown(projection.dispose);
      project() => projection.project(
        nied: stations,
        kma: [],
        cwa: [],
        palert: [],
        seisjs: [],
        snet: [],
        detection: ShakeDetectionService.idleSnapshot,
        lpgm: null,
        windowEnd: frame.dataTime,
        niedProducer: processor.native,
        changed: const {'nied'},
      );
      final first = project(); // configure summary directory once
      final second = project(); // native KA output buffer consumed directly
      expect(second.niedMaxStation, same(first.niedMaxStation));
      var best = -1, maximum = -1;
      for (var i = 0; i < old.length; i++) {
        if (old[i].level > maximum) {
          maximum = old[i].level;
          best = i;
        }
      }
      expect(second.niedMaxStation, same(stations[best]));
      final capturedHistory = List<int>.of(stations[0].recentLevel);
      processor.dispose();
      expect(stations[0].recentLevel, capturedHistory);
      expect(
        sha256.convert(directory.readAsBytesSync()),
        sha256.convert(directoryBytes),
      );
      expect(
        sha256.convert(observations.readAsBytesSync()),
        sha256.convert(bodyBytes),
      );
    },
    skip: !enabled,
  );

  test(
    'gap boundaries, invalid originals, activity, abnormal counter and clock reset match frozen Dart',
    () {
      final raw = [
        -3.0,
        -2.999,
        -2.5,
        -0.0,
        0.5,
        6.5,
        7.0,
        7.001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      final stations = [
        for (var i = 0; i < raw.length; i++) view(i, LatLng(35 + i / 100, 139)),
      ];
      final old = stations.map(reference).toList();
      final processor = NiedArrayObservationProcessor()..configure(stations);
      addTearDown(processor.dispose);
      final origin = DateTime.utc(2026, 10, 1);
      var time = origin;
      DateTime? previous;
      final increments = [
        0,
        1000,
        1499,
        1500,
        2499,
        2500,
        10000,
        10001,
        65000,
        -2000,
        0,
        1000,
      ];
      for (var step = 0; step < 84; step++) {
        time = time.add(
          Duration(milliseconds: increments[step % increments.length]),
        );
        if (step == 48) {
          processor.resetClock();
          previous = null;
        }
        for (var i = 0; i < stations.length; i++) {
          stations[i].isActive = old[i].isActive = step % 3 == 0;
          if (step > 0 && step % 13 == 0) {
            stations[i].abnormalUpdateCount = old[i].abnormalUpdateCount = 599;
            // Explicit imported-state command; ordinary frames never feed a
            // previous native counter back through the display view.
            processor.native!.setShindoAbnormalCount(i, 599);
          }
        }
        final frame = WhewsStationFrame(
          kind: WhewsStationKind.nied,
          dataTime: time,
          coordinates: stations.map((s) => s.coordinate).toList(),
          values: [
            for (var i = 0; i < raw.length; i++) raw[(i + step) % raw.length],
          ],
        );
        oldApply(old, frame, previous);
        previous = time;
        processor.apply(frame, receivedAt: time);
        for (var i = 0; i < stations.length; i++) {
          expect(
            values(stations[i]),
            values(old[i]),
            reason: 'step $step station $i',
          );
        }
      }
      final held = stations[0].recentLevel.toList();
      expect(
        () => processor.apply(
          WhewsStationFrame(
            kind: WhewsStationKind.nied,
            dataTime: time.add(const Duration(days: 1)),
            coordinates: [],
            values: [],
          ),
          receivedAt: time,
        ),
        throwsArgumentError,
      );
      expect(stations[0].recentLevel, held);
      final native = processor.native! as native_io.NativeKaHistorySession;
      native.withNativeResults((_, count) {
        expect(() => processor.dispose(), throwsStateError);
        expect(() => processor.native!.reset(), throwsStateError);
      });
      processor.native!.reset();
      expect(() => native.withNativeResults((_, count) {}), throwsStateError);
    },
    skip: !enabled,
  );

  test(
    'source replacement and repeated stop release native session and allocations',
    () {
      final baseline =
          NativeStationImageDecoder.memoryStats['rustCurrentBytes'];
      final sessions = NativeKaHistorySession.diagnostics['kaSessions'];
      final processor = NiedArrayObservationProcessor();
      for (var n = 0; n < 20; n++) {
        final stations = [
          view(0, const LatLng(35, 139)),
          view(1, const LatLng(35.1, 139.1)),
        ];
        processor.configure(stations);
        final frame = WhewsStationFrame(
          kind: WhewsStationKind.nied,
          dataTime: DateTime.utc(2026, 10, 1),
          coordinates: stations.map((s) => s.coordinate).toList(),
          values: const [1.5, 3.5],
        );
        processor.apply(frame, receivedAt: frame.dataTime);
        final detached = NiedStation.detachedSnapshot(stations.first);
        final copied = values(detached);
        processor.configure([]);
        expect(values(detached), copied);
        expect(stations.first.recentLevel, [10]);
        expect(NativeKaHistorySession.diagnostics['kaSessions'], sessions);
      }
      processor.dispose();
      processor.dispose();
      expect(
        NativeStationImageDecoder.memoryStats['rustCurrentBytes'],
        baseline,
      );
    },
    skip: !enabled,
  );
}
