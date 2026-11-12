// October audit regressions: imported preparation and replay disposal both
// assert corrected behavior against the unchanged original data.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/history_replay_directory_io.dart';
import 'package:flutterrhythmquake/services/debug/replay_source_estimation.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const originalPath = 'test/fixtures/history_replay/cwa_1150074.rqreplay';
  test(
    'imported file-backed package plays without saved-history selection',
    () async {
      final original = File(originalPath);
      final digest = sha256.convert(original.readAsBytesSync());
      final package = await importReplayFile(originalPath);
      var loaderCalls = 0;
      final controller = HistoryReplayController(
        onReport: (_) {},
        onClear: (_) {},
        loadHistoryGroup: (group) async {
          loaderCalls++;
          return group;
        },
      );
      try {
        expect(package.hasFileReports, isTrue);
        controller.importPackages([package]);
        await controller.playPrepared();
        expect(controller.active, isTrue);
        expect(loaderCalls, 0);
        expect(sha256.convert(original.readAsBytesSync()), digest);
        debugPrint(
          'REPLAY_IMPORT_FIXED hasFileReports=true active=true historyLoaderCalls=0',
        );
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'disposing active replay releases its native inference worker',
    () async {
      final replay = ReplaySourceEstimation.instance;
      replay.stop();
      final baseline = NativeStationRuntime.workers;
      final package = HistoryReplayPackage.decode(
        File(originalPath).readAsStringSync(),
      );
      final frameFile = File(
        'test/fixtures/palert_cwa_1150077_20261017/f1b0e996430b3a1dfd1e5659835decb276a0abb7c88a719a7a734f0cc5c9f9ee.json',
      );
      final frameDigest = sha256.convert(frameFile.readAsBytesSync());
      final record = jsonDecode(frameFile.readAsStringSync()) as Map;
      final frame = StationJsonArchive.decode(
        StationArchiveStorage.decode(record['value'] as String),
      ).first;
      // Different original events are used only to exercise resource ownership,
      // not to infer that the observation belongs to the CWA report above.
      final controller = HistoryReplayController(
        onReport: (_) {},
        onClear: (_) {},
      );
      var disposed = false;
      try {
        controller.load(package);
        controller.play();
        final ownedSession = replay.session;
        expect(ownedSession, isNotNull);
        await replay.process(frame);
        expect(replay.error, isNull);
        final liveBefore = NativeStationRuntime.workers;
        expect(liveBefore, greaterThan(baseline));
        controller.dispose();
        disposed = true;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(replay.session, isNull);
        expect(NativeStationRuntime.workers, baseline);
        expect(sha256.convert(frameFile.readAsBytesSync()), frameDigest);
        debugPrint(
          'REPLAY_DISPOSE_FIXED baseline=$baseline before=$liveBefore after=${NativeStationRuntime.workers} sessionRetained=false',
        );
      } finally {
        if (!disposed) controller.dispose();
        replay.stop();
        for (
          var i = 0;
          i < 100 && NativeStationRuntime.workers > baseline;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(NativeStationRuntime.workers, baseline);
      }
    },
    skip: !NativeStationRuntime.supported,
  );
}
