import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_detector.dart';
import 'package:flutterrhythmquake/services/sources/native_station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';

import 'support/dart_ka_detector_reference.dart' as old;
import 'support/nied_replay_fixture.dart';

Int64List packKaRows(List<List<Object?>> rows) {
  final packed = Int64List(rows.length * 6);
  final values = Float64List.view(packed.buffer);
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index], offset = index * 6;
    packed[offset] = row[0] as int;
    values[offset + 1] = (row[1] as num).toDouble();
    packed[offset + 2] = row[2] as int;
    packed[offset + 3] = row[3] == true ? 1 : 0;
    values[offset + 4] = (row[4] as num).toDouble();
    packed[offset + 5] = row[5] as int;
  }
  return packed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = NativeKaDetector.supported;
  const config = <List<Object?>>[
    [0, 35.0, 139.0, '甲'],
    [1, 35.05, 139.05, '乙'],
    [2, 35.1, 139.1, '丙'],
  ];

  test(
    'ordered chains, thresholds and raw floating point contracts match Dart',
    () {
      final reference = old.DartKaDetectorReference()..configure(config);
      addTearDown(reference.dispose);
      final native = NativeKaDetector(
        adjacency: reference.adjacency,
        distance: reference.distance,
      );
      addTearDown(native.dispose);
      final random = math.Random(416);
      for (var frame = 0; frame < 500; frame++) {
        // Controlled ABI/threshold contracts; not altered earthquake captures.
        final rows = <List<Object?>>[
          for (var index = 0; index < 3; index++)
            [
              random.nextInt(22) - 1,
              frame % 41 == 0
                  ? double.nan
                  : frame % 43 == 0
                  ? double.infinity
                  : frame % 47 == 0
                  ? -0.0
                  : random.nextInt(40) / 2.0,
              random.nextInt(6),
              random.nextBool(),
              -0.0,
              frame % 13 == 0 ? 0 : 1790000000000 + random.nextInt(90000),
            ],
        ];
        final packed = packKaRows(rows),
            original = List<int>.of(packKaRows(rows));
        for (final sensitivity in [-1, 1, 2, 3, 4]) {
          for (final held in [false, true]) {
            native.writePacked(packed);
            final value = native.process(
              sensitivity: sensitivity,
              hadActiveGrid: held,
            );
            final expected = reference.detect(
              rows,
              sensitivity: sensitivity,
              hadActiveGrid: held,
            );
            expect(
              value.activeIndices,
              expected['activeIndices'],
              reason: 'frame $frame sensitivity $sensitivity held $held',
            );
            expect(value.strongestIndex, expected['strongestIndex']);
            expect(packed, original);
          }
        }
      }
    },
    skip: !enabled,
  );

  test(
    'original chain insertion order resolves strongest ties and owns outputs',
    () {
      final native = NativeKaDetector(
        adjacency: [
          [0, 2],
          [1, 0],
          [2, 1],
        ],
        distance: (_, _) => 0.0,
      );
      addTearDown(native.dispose);
      for (var index = 0; index < 3; index++) {
        native.writeInput(
          index,
          kaLevel: index == 0 ? 10 : 20,
          activity: 20,
          ascend: 3,
          isActive: true,
          triggerStamp: 0,
        );
      }
      final first = native.process(sensitivity: 2, hadActiveGrid: false);
      expect(first.activeIndices, [0, 1, 2]);
      expect(first.strongestIndex, 2);
      for (var index = 0; index < 3; index++) {
        native.writeInput(
          index,
          kaLevel: -1,
          activity: 0,
          ascend: 0,
          isActive: false,
          triggerStamp: 0,
        );
      }
      expect(
        native.process(sensitivity: 2, hadActiveGrid: false).activeIndices,
        isEmpty,
      );
      expect(first.activeIndices, [0, 1, 2]);
      native.dispose();
      native.dispose();
      expect(
        () => native.process(sensitivity: 2, hadActiveGrid: false),
        throwsStateError,
      );
      expect(NativeKaDetector.diagnostics['kaDetectorSessions'], 0);
    },
    skip: !enabled,
  );

  test(
    'distance preparation exceptions prevent partial native sessions',
    () {
      final sessions = NativeKaDetector.diagnostics['kaDetectorSessions'];
      expect(
        () => NativeKaDetector(
          adjacency: const [
            [0, 1],
            [0, 1],
          ],
          distance: (_, _) => throw StateError('distance contract'),
        ),
        throwsStateError,
      );
      expect(NativeKaDetector.diagnostics['kaDetectorSessions'], sessions);
      final native = NativeKaDetector(
        adjacency: const [
          [0, 1],
          [0, 1],
        ],
        distance: (_, _) => 0.0,
      );
      addTearDown(native.dispose);
      for (var index = 0; index < 2; index++) {
        native.writeInput(
          index,
          kaLevel: 10,
          activity: 20,
          ascend: 3,
          isActive: false,
          triggerStamp: 0,
        );
      }
      expect(
        native.process(sensitivity: 2, hadActiveGrid: false).activeIndices,
        [0, 1],
      );
      expect(() => native.writePacked(Int64List(1)), throwsArgumentError);
      expect(
        () => NativeKaDetector(
          adjacency: [
            [1],
          ],
          distance: (_, _) => 0,
        ),
        throwsArgumentError,
      );
    },
    skip: !enabled,
  );

  test(
    'background reconfiguration and stop explicitly release native sessions',
    () async {
      final worker = NiedBackgroundWorker.instance;
      addTearDown(worker.stop);
      await worker.configureDetector(
        signature: 'native-layout-3',
        stations: config,
      );
      expect((await worker.detectorDiagnostics())['backend'], 'rust-abi-1');
      expect(NativeKaDetector.diagnostics['kaDetectorSessions'], 1);
      await worker.configureDetector(
        signature: 'native-layout-2',
        stations: config.take(2).toList(),
      );
      expect(NativeKaDetector.diagnostics['kaDetectorSessions'], 1);
      worker.stop();
      for (
        var attempt = 0;
        attempt < 200 &&
            NativeKaDetector.diagnostics['kaDetectorSessions'] != 0;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(NativeKaDetector.diagnostics['kaDetectorSessions'], 0);
    },
    skip: !enabled,
  );

  test(
    '51 untouched GIF frames match old KA spatial detection in both workers',
    () async {
      final image = LmoniImageService()
        ..useNativeKaHistory = true
        ..start();
      final before = old.NiedBackgroundWorker.instance,
          after = NiedBackgroundWorker.instance;
      addTearDown(image.stop);
      addTearDown(before.stop);
      addTearDown(after.stop);
      final hashes = <String, String>{};
      var records = 0, activeFrames = 0;
      for (var second = 20; second <= 70; second++) {
        final stamp = DateTime(2026, 6, 10, 18, 1, second);
        final file = File(
          'tmp/captures/20260610_180130_jst_nara_m36/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif',
        );
        hashes[file.path] = sha256.convert(file.readAsBytesSync()).toString();
        final raw = (await decodeNiedGifFile(file))!;
        final next = image.stationStream.firstWhere((value) => value != null);
        image.processPixels(raw.packedRgb, dataTime: stamp, receivedAt: stamp);
        final stations = (await next)!;
        if (second == 20) {
          final layout = <List<Object?>>[
            for (final station in stations)
              [
                station.id,
                station.coordinate.latitude,
                station.coordinate.longitude,
                station.code,
              ],
          ];
          expect(
            await before.configureDetector(
              signature: 'original-51',
              stations: layout,
            ),
            hasLength(stations.length),
          );
          expect(
            await after.configureDetector(
              signature: 'original-51',
              stations: layout,
            ),
            hasLength(stations.length),
          );
        }
        final input = [
          for (final station in stations)
            NiedDetectionInput(
              kaLevel: station.kaLevel,
              activity: station.activity,
              ascend: station.ascend,
              isActive: station.isActive,
              continuousShindo: station.continuousShindo,
              triggerStamp: station.triggerStamp,
            ),
        ];
        final legacy = [
          for (final station in input)
            old.NiedDetectionInput(
              kaLevel: station.kaLevel,
              activity: station.activity,
              ascend: station.ascend,
              isActive: station.isActive,
              continuousShindo: station.continuousShindo,
              triggerStamp: station.triggerStamp,
            ),
        ];
        for (final sensitivity in [1, 2, 3]) {
          for (final held in [false, true]) {
            final expected = await before.detect(
              stations: legacy,
              sensitivity: sensitivity,
              hadActiveGrid: held,
            );
            final current = await after.detect(
              stations: input,
              sensitivity: sensitivity,
              hadActiveGrid: held,
            );
            expect(expected, isNotNull);
            expect(current, isNotNull);
            expect(
              current!.activeIndices,
              expected!.activeIndices,
              reason: '${formatNiedTimeKey(stamp)} sensitivity $sensitivity',
            );
            expect(current.strongestIndex, expected.strongestIndex);
            if (sensitivity == 2 && !held && current.activeIndices.isNotEmpty)
              activeFrames++;
          }
        }
        records += stations.length;
      }
      for (final entry in hashes.entries) {
        expect(
          sha256.convert(File(entry.key).readAsBytesSync()).toString(),
          entry.value,
        );
      }
      expect(records, 83334);
      expect((await after.detectorDiagnostics())['backend'], 'rust-abi-1');
      image.stop();
      before.stop();
      after.stop();
      for (
        var attempt = 0;
        attempt < 200 &&
            NativeKaDetector.diagnostics['kaDetectorSessions'] != 0;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(NativeKaDetector.diagnostics['kaDetectorSessions'], 0);
      // ignore: avoid_print
      print(
        jsonEncode({
          'frames': 51,
          'stationInputs': records,
          'activeFrames': activeFrames,
          'native': NativeStationImageDecoder.memoryStats,
        }),
      );
    },
    skip: !enabled,
  );
}
