import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_station_frame.dart';

import 'support/nied_replay_fixture.dart';
import 'support/nied_station_snapshot_reference.dart';

List<Object?> inferenceValues(NiedStation station) =>
    stationSnapshotValues(station)
      ..removeLast() // UI timers are not inference inputs.
      ..removeAt(23); // KA history stays with its calculation owner.

Future<List<NiedStation>> originalFirstFrame() async {
  final service = LmoniImageService()..start();
  try {
    final stamp = DateTime(2026, 6, 10, 18, 1, 20);
    final raw = (await decodeNiedGifFile(
      File(
        'tmp/captures/20260610_180130_jst_nara_m36/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif',
      ),
    ))!;
    final next = service.stationStream.firstWhere((value) => value != null);
    service.processPixels(raw.packedRgb, dataTime: stamp, receivedAt: stamp);
    return [
      for (final station in (await next)!)
        NiedStation.detachedSnapshot(station),
    ];
  } finally {
    service.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '51 original GIF frames preserve every inference input without recopying catalogue or KA history',
    () async {
      final service = LmoniImageService()..start();
      final encoder = NiedSourceStationEncoder();
      final decoder = NiedSourceStationDecoder();
      addTearDown(service.stop);
      addTearDown(decoder.dispose);
      List<NiedStation>? previous;
      var catalogueMessages = 0, compared = 0, historyValuesNotSent = 0;
      final hashes = <File, String>{};
      for (var second = 20; second <= 70; second++) {
        final stamp = DateTime(2026, 6, 10, 18, 1, second);
        final file = File(
          'tmp/captures/20260610_180130_jst_nara_m36/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif',
        );
        hashes[file] = sha256.convert(file.readAsBytesSync()).toString();
        final raw = (await decodeNiedGifFile(file))!;
        final next = service.stationStream.firstWhere((value) => value != null);
        service.processPixels(
          raw.packedRgb,
          dataTime: stamp,
          receivedAt: stamp,
        );
        final stations = (await next)!;
        expect(stations.length, 1634);
        final frame = encoder.capture(stations);
        if (frame.includesCatalogue) catalogueMessages++;
        expect(frame.numericBytes, 1634 * 128);
        final decoded = decoder.apply(frame);
        if (previous != null) expect(identical(decoded, previous), isTrue);
        for (var index = 0; index < stations.length; index++) {
          expect(
            inferenceValues(decoded[index]),
            inferenceValues(stations[index]),
          );
          expect(decoded[index].recentLevel, isEmpty);
          expect(decoded[index].activeTimer, isNull);
          historyValuesNotSent += stations[index].recentLevel.length;
          compared++;
        }
        previous = decoded;
      }
      expect(compared, 83334);
      expect(catalogueMessages, 1);
      expect(historyValuesNotSent, greaterThan(0));
      for (final entry in hashes.entries) {
        expect(
          sha256.convert(entry.key.readAsBytesSync()).toString(),
          entry.value,
        );
      }
    },
  );

  test(
    'capture isolates mutable observations and preserves nullable microsecond timestamps and negative counts',
    () async {
      // Controlled transport boundaries on a captured station, not a modified
      // earthquake replay or performance input.
      final source = (await originalFirstFrame()).first;
      final encoder = NiedSourceStationEncoder(),
          decoder = NiedSourceStationDecoder();
      addTearDown(decoder.dispose);
      for (final count in <int?>[null, -1, 0, 600]) {
        for (final time in <DateTime?>[
          null,
          DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
          DateTime.fromMicrosecondsSinceEpoch(-1),
          DateTime(2026, 10, 12, 1, 2, 3, 4, 567),
        ]) {
          source.abnormalUpdateCount = count;
          source.lastUpdate = time;
          source.lastDataTime = time?.toUtc();
          source.lastReceivedAt = time?.toLocal();
          source.gifLayerQualityFlags[NiedGifLayer.peakVelocity] = {'missing'};
          final expected = inferenceValues(source);
          final frame = encoder.capture([source]);
          source.gifLayerQualityFlags[NiedGifLayer.peakVelocity]!.add('later');
          expect(inferenceValues(decoder.apply(frame).single), expected);
        }
      }
      // The same epoch value can have different UTC/local representations in
      // one frame. Timestamp reuse must not merge those representations.
      final other = NiedStation.detachedSnapshot(source);
      source.lastUpdate = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
      source.lastDataTime = DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true);
      other.lastUpdate = DateTime.fromMicrosecondsSinceEpoch(0);
      other.lastDataTime = null;
      final expected = [inferenceValues(source), inferenceValues(other)];
      expect(
        decoder.apply(encoder.capture([source, other])).map(inferenceValues),
        expected,
      );
    },
  );

  test(
    'catalogue reorder, replacement, empty frame and reset invalidate exactly',
    () async {
      final stations = (await originalFirstFrame()).take(2).toList();
      final encoder = NiedSourceStationEncoder(),
          decoder = NiedSourceStationDecoder();
      addTearDown(decoder.dispose);
      var frame = encoder.capture(stations);
      final first = decoder.apply(frame).first;
      expect(frame.includesCatalogue, isTrue);
      frame = encoder.capture(stations);
      expect(frame.includesCatalogue, isFalse);
      expect(identical(decoder.apply(frame).first, first), isTrue);
      frame = encoder.capture(stations.reversed.toList());
      expect(frame.includesCatalogue, isTrue);
      expect(decoder.apply(frame).first.code, stations.last.code);
      frame = encoder.capture([]);
      expect(frame.includesCatalogue, isTrue);
      expect(decoder.apply(frame), isEmpty);
      encoder.reset();
      frame = encoder.capture(stations);
      expect(frame.includesCatalogue, isTrue);
      expect(decoder.apply(frame).length, 2);
      decoder.dispose();
      expect(() => decoder.apply(encoder.capture(stations)), throwsStateError);
    },
  );

  test(
    'reuse and disposal cancel old frame holds without changing live station timers',
    () async {
      final source = (await originalFirstFrame()).first;
      fakeAsync((async) {
        final encoder = NiedSourceStationEncoder(),
            decoder = NiedSourceStationDecoder();
        source.setActive();
        final liveTimer = source.activeTimer!;
        var station = decoder.apply(encoder.capture([source])).single;
        station.setActive();
        final previousTimer = station.activeTimer!;
        station = decoder.apply(encoder.capture([source])).single;
        expect(previousTimer.isActive, isFalse);
        expect(liveTimer.isActive, isTrue);
        expect(station.isActive, source.isActive);
        station.setActive();
        final lastTimer = station.activeTimer!;
        decoder.dispose();
        expect(lastTimer.isActive, isFalse);
        expect(liveTimer.isActive, isTrue);
        source.terminate();
      });
    },
  );
}
