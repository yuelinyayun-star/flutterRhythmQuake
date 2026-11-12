import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_worker.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/services/debug/native_station_replay_block.dart';
import 'native_palert_runtime_test.dart' show earthquakeFrames, until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original compressed archive -> native reader -> native source session -> final UI views',
    () async {
      const directory = 'test/fixtures/palert_cwa_1150077_20261017';
      final manifest =
          jsonDecode(
                File(
                  '$directory/manifest.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      final archive = StationReplayFrames.decode({
        'format': StationReplayFrames.format,
        'blocks': [
          for (final entry in manifest)
            (() {
              final envelope = jsonDecode(
                File(
                  '$directory/${entry['file']}',
                ).readAsStringSync(encoding: utf8),
              );
              final value = envelope['value'] as String;
              return StationReplayFrames.encodeBlock(
                StationArchiveStorage.decode(value),
                base64.decode(
                  value.substring(StationArchiveStorage.prefix.length),
                ),
              );
            })(),
        ],
      });
      final expected = earthquakeFrames();
      final reader = StationReplayReadCursor();
      final native = PAlertSourceWorker(),
          reference = PAlertSourceWorker.dartReferenceForTesting();
      var outputs = 0;
      try {
        expect(archive.entries.length, expected.length);
        for (var frame = 0; frame < expected.length; frame++) {
          final actual = await reader.loadAsync(archive.entries[frame]);
          final saved = expected[frame];
          expect(
            packedSourceJsonTransport(actual.snapshot),
            isNotNull,
            reason: 'opaque native frame $frame',
          );
          expect(
            jsonEncode(actual.toMap()),
            jsonEncode(saved.toMap()),
            reason: 'original values and key order $frame',
          );
          final a = await native.processRecordedSnapshot(
            actual.snapshot,
            receivedAt: actual.receivedAt,
          );
          final b = await reference.processRecordedSnapshot(
            saved.snapshot,
            receivedAt: saved.receivedAt,
          );
          expect(a!.length, b!.length, reason: 'outputs $frame');
          for (var i = 0; i < a.length; i++) {
            final x = a[i].estimate!, y = b[i].estimate!;
            expect(a[i].eventId, b[i].eventId, reason: 'identity $frame');
            expect(
              [
                x.latitude,
                x.longitude,
                x.depthKm,
                x.originTime,
                x.confidence,
                x.supportingStationCount,
              ],
              [
                y.latitude,
                y.longitude,
                y.depthKm,
                y.originTime,
                y.confidence,
                y.supportingStationCount,
              ],
              reason: 'source $frame',
            );
            if (y.magnitude == null) {
              expect(x.magnitude, isNull);
            } else {
              expect(x.magnitude, closeTo(y.magnitude!, 1e-12));
            }
            for (final key in y.diagnostics.keys) {
              final value = y.diagnostics[key];
              if (value is double) {
                expect(
                  x.diagnostics[key],
                  closeTo(value, 1e-8),
                  reason: '$key $frame',
                );
              } else {
                expect(x.diagnostics[key], value, reason: '$key $frame');
              }
            }
          }
          if (a.isNotEmpty) outputs++;
        }
        expect(outputs, 15);
        debugPrint(
          'NATIVE_PALERT_REPLAY originalFrames=${expected.length} sourceFrames=$outputs',
        );
      } finally {
        reader.dispose();
        archive.release();
        native.dispose();
        reference.dispose();
        await until(() => NativeStationRuntime.workers == 0);
      }
    },
    skip: !NativeStationReplayBlock.supported,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
