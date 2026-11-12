import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_history.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'support/dart_ka_station_reference.dart';
import 'support/nied_replay_fixture.dart';

List<Object?> kaValues(dynamic station) => [
  station.level,
  station.ascend,
  station.triggerStamp,
  station.activity,
  station.abnormalUpdateCount,
  List<int>.of(station.recentLevel as List<int>),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = NativeKaHistorySession.supported;
  for (final expiry in [-1, 0, 1, 2, 10, 60, 100]) {
    test(
      'native KA preserves original history semantics expire=$expiry',
      () {
        final native = NativeKaHistorySession(1);
        addTearDown(native.dispose);
        final old = DartKaStationReference(
          id: 1,
          code: '日本站',
          name: '原值',
          coordinate: const LatLng(35, 139),
          network: 'K-NET',
          prefecture: '',
          expireSeconds: expiry,
        );
        final station = NiedStation(
          id: 1,
          code: old.code,
          name: old.name,
          coordinate: old.coordinate,
          network: old.network,
          prefecture: '',
          expireSeconds: expiry,
        )..recentLevel = native.histories.single;
        final random = Random(404);
        for (var i = 0; i < 2200; i++) {
          if (i % 97 == 0) {
            // Controlled boundary histories, distinct from raw-data benchmarks.
            final replacement = List<int>.generate(
              i % 75,
              (_) => random.nextInt(25) - 3,
            );
            old.recentLevel = List<int>.of(replacement);
            station.recentLevel = List<int>.of(replacement);
          }
          if (i % 101 == 0) {
            final counter = i % 3 == 0 ? null : (i % 5 == 0 ? -2 : 599);
            old.abnormalUpdateCount = counter;
            station.abnormalUpdateCount = counter;
          }
          final active = i % 3 == 0;
          final stamp = DateTime.fromMicrosecondsSinceEpoch(
            1781085680000123 + i * 1000000,
            isUtc: i.isEven,
          );
          old.isActive = station.isActive = active;
          old.lastDataTime = station.lastDataTime = i % 7 == 0 ? null : stamp;
          old.lastUpdate = station.lastUpdate = i % 11 == 0 ? null : stamp;
          final level = i % 29 < 5 ? -1 : random.nextInt(30) - 5;
          old.update(level);
          station.update(level);
          expect(
            kaValues(station),
            kaValues(old),
            reason: 'expire=$expiry frame=$i',
          );
        }
        final detached = NiedStation.detachedSnapshot(station);
        final values = kaValues(detached);
        station.update(20);
        expect(kaValues(detached), values);
        final ownedBeforeClose = List<int>.of(station.recentLevel);
        native.dispose();
        native.dispose();
        expect(station.recentLevel, ownedBeforeClose);
        station.update(-1); // Retained station remains independently usable.
        expect(() => native.process(), throwsStateError);
        expect(NativeKaHistorySession.diagnostics['kaSessions'], 0);
        expect(NativeKaHistorySession.diagnostics['rustCurrentBytes'], 0);
      },
      skip: !enabled,
    );
  }
  test(
    'batch order, original list mutation, reset and shared buffer ownership',
    () {
      final native = NativeKaHistorySession(3);
      addTearDown(native.dispose);
      native.histories[0].addAll([0, 3, -1, 0]);
      native.histories[1].insertAll(0, [9, -1, -1]);
      native.histories[1][0] = 8;
      native.histories[2].add(20);
      expect(native.histories[0], [0, 3, -1, 0]);
      expect(native.histories[1], [8, -1, -1]);
      for (var i = 0; i < 3; i++) {
        native.writeInput(
          i,
          level: i == 1 ? -1 : 5,
          expireSeconds: 10,
          baseTimeMilliseconds: 1781085680000,
          isActive: false,
          abnormalUpdateCount: null,
        );
      }
      native.process();
      final owned = List<int>.of(native.histories[1]);
      final detached = native.histories[1].detachedCopy()..add(19);
      expect(owned, [-1, 8, -1, -1]);
      expect(detached, [-1, 8, -1, -1, 19]);
      expect(native.result(1).level, 8);
      native.histories[2].clear();
      expect(native.histories[1], owned);
      native.histories[0].replace(List<int>.generate(75, (i) => i - 3));
      expect(native.histories[0].detachedCopy(), List<int>.generate(75, (i) => i - 3));
      expect(native.histories[1].detachedCopy(), owned);
      native.reset();
      expect(native.histories.every((h) => h.isEmpty), isTrue);
      expect(owned, [-1, 8, -1, -1]);
      native.dispose();
      expect(NativeKaHistorySession.diagnostics['rustCurrentBytes'], 0);
    },
    skip: !enabled,
  );
  test(
    '51 original GIF frames preserve all 83334 KA station states',
    () async {
      final image = LmoniImageService()..useNativeKaHistory = true;
      image.start();
      addTearDown(image.stop);
      List<DartKaStationReference>? old;
      var count = 0;
      for (var second = 20; second <= 70; second++) {
        final time = DateTime(2026, 6, 10, 18, 1, second);
        final file = File(
          'tmp/captures/20260610_180130_jst_nara_m36/${formatNiedTimeKey(time)}.lmoni.jma_s.gif',
        );
        final hash = sha256.convert(file.readAsBytesSync());
        final raw = (await decodeNiedGifFile(file))!;
        final next = image.stationStream.firstWhere((s) => s != null);
        image.processPixels(raw.packedRgb, dataTime: time, receivedAt: time);
        final stations = (await next)!;
        expect(stations.length, 1634);
        old ??= [
          for (final s in stations)
            DartKaStationReference(
              id: s.id,
              code: s.code,
              name: s.name,
              coordinate: s.coordinate,
              network: s.network,
              prefecture: s.prefecture,
              expireSeconds: s.expireSeconds,
            ),
        ];
        for (var i = 0; i < stations.length; i++) {
          final ref = old[i]
            ..lastDataTime = time
            ..lastUpdate = time;
          ref.updateFromContinuousShindo(stations[i].gifObservation?.shindo);
          expect(
            kaValues(stations[i]),
            kaValues(ref),
            reason: '${file.path} ${stations[i].code}',
          );
          expect(kaValues(NiedStation.detachedSnapshot(stations[i])), kaValues(ref));
          count++;
        }
        expect(sha256.convert(file.readAsBytesSync()), hash);
      }
      expect(count, 83334);
      image.stop();
      expect(NativeKaHistorySession.diagnostics['kaSessions'], 0);
      expect(NativeKaHistorySession.diagnostics['rustCurrentBytes'], 0);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
