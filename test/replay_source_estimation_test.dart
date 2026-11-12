import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/debug/replay_source_estimation.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_state.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_worker.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_station_phase_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'queued playback loads only the current frame and stop releases pending loaders',
    () async {
      final replay = ReplaySourceEstimation();
      addTearDown(replay.dispose);
      final now = DateTime.utc(2026, 10, 14);
      replay.start('queue-test', () => now);
      var loads = 0;
      final pending = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        pending.add(
          replay.processEntry(
            StationReplayEntry(now, 'nied', '$i', () {
              loads++;
              return StationHistoryFrame(
                receivedAt: now,
                snapshot: {'kind': 'nied', 'stations': []},
              );
            }),
          ),
        );
      }
      expect(loads, 1);
      expect(replay.pendingFrames, 19);
      replay.stop();
      await Future.wait(pending);
      expect(loads, 1);
      expect(replay.pendingFrames, 0);
      expect(replay.isIdle, isTrue);
    },
  );

  test(
    'original saved NIED frames infer with EEW recording context, live state isolated',
    () async {
      final directory = Directory(
        'D:/flutterApp/flutter-nied-regression/20261013-200318',
      );
      if (!directory.existsSync()) {
        markTestSkipped('Original local recording required');
        return;
      }
      final record =
          jsonDecode(
                File(
                  '${directory.path}/eew/1cc3760b8dd1caeb6c2461e91eac3a944e0522d432132ab071f3ee2c28777fb6.json',
                ).readAsStringSync(),
              )
              as Map;
      final group = jsonDecode(record['value'] as String) as Map;
      expect(group['reports'], hasLength(4));
      final keys = (group['stationArchiveKeys'] as List).toSet();
      final files = <File>[];
      final frames = <StationHistoryFrame>[];
      final hashes = <String, String>{};
      for (final file in Directory(
        '${directory.path}/station-history',
      ).listSync().whereType<File>()) {
        final doc = jsonDecode(file.readAsStringSync()) as Map;
        if (!keys.contains(
              (doc['key'] as String).replaceFirst('flutter.', ''),
            ) ||
            !(doc['key'] as String).contains('station_archive_nied_'))
          continue;
        files.add(file);
        hashes[file.path] = sha256.convert(file.readAsBytesSync()).toString();
        frames.addAll(
          StationJsonArchive.decode(
            StationArchiveStorage.decode(doc['value'] as String),
          ),
        );
      }
      frames.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      expect(frames, isNotEmpty);
      // Functional regression of the actual recorded entry window. Full-length
      // performance runs belong to the paced Profile APP harness, not JIT tests.
      if (frames.length > 60) frames.removeRange(60, frames.length);
      final live = StationEventTracker.instance.currentNiedEvent.value;
      final livePAlert = PAlertSourceState.events.value;
      final replay = ReplaySourceEstimation();
      addTearDown(replay.dispose);
      final fullWorker = NiedSourceEstimationWorker();
      addTearDown(fullWorker.dispose);
      var clock = frames.first.receivedAt;
      replay.start('original-recording', () => clock);
      var estimates = 0;
      var processed = 0;
      final watch = Stopwatch()..start();
      for (final frame in frames) {
        clock = frame.receivedAt;
        final reference = await fullWorker.processStations(
          ForegroundStationPayload.decodeNied(frame.snapshot['stations']),
        );
        await replay.process(frame);
        final source = replay.nied?.estimate;
        final fullSource = reference?.event?.estimate;
        expect(
          source == null
              ? null
              : [
                  source.latitude,
                  source.longitude,
                  source.depthKm,
                  source.magnitude,
                  source.originTime,
                  source.confidence,
                ],
          fullSource == null
              ? null
              : [
                  fullSource.latitude,
                  fullSource.longitude,
                  fullSource.depthKm,
                  fullSource.magnitude,
                  fullSource.originTime,
                  fullSource.confidence,
                ],
        );
        if (replay.nied != null && reference!.event != null) {
          expect(
            replay.nied!.records.every((r) => r.observationHistory.isEmpty),
            isTrue,
          );
          const classifier = SourceStationPhaseClassifier();
          expect(
            classifier
                .classify(replay.nied!)
                .stations
                .map((r) => r.phase)
                .toList(),
            classifier
                .classify(reference.event!)
                .stations
                .map((r) => r.phase)
                .toList(),
          );
        }
        processed++;
        if (replay.nied?.estimate != null) estimates++;
        if (estimates >= 10) break;
      }
      expect(replay.error, isNull);
      expect(estimates, greaterThan(0));
      expect(StationEventTracker.instance.currentNiedEvent.value, same(live));
      expect(PAlertSourceState.events.value, same(livePAlert));
      for (final file in files) {
        expect(
          sha256.convert(file.readAsBytesSync()).toString(),
          hashes[file.path],
        );
      }
      print(
        'ORIGINAL HISTORY REPLAY processed=$processed estimates=$estimates elapsedMs=${watch.elapsedMilliseconds}',
      );
      replay.stop();
      expect(replay.nied, isNull);
      expect(replay.palert, isEmpty);
      expect(replay.session, isNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
