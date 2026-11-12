import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/services/sources/native_replay_log_session.dart';

// Protocol controls exercise archive semantics; no control event enters APP.
void main() {
  group('native replay archive', () {
    late Directory root;
    late NativeReplayLogSession owner;
    const stamp = '20260610_180130';
    setUp(() {
      root = Directory.systemTemp.createTempSync('rq_archive_验证_');
      owner = NativeReplayLogSession();
    });
    tearDown(() async {
      owner.dispose();
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (NativeReplayLogSession.activeWorkers != 0 &&
          DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(NativeReplayLogSession.activeWorkers, 0);
      final resolved = root.resolveSymbolicLinksSync();
      expect(
        resolved,
        startsWith(Directory.systemTemp.resolveSymbolicLinksSync()),
      );
      root.deleteSync(recursive: true);
    });
    void start({bool disk = true}) => owner.start(
      sessionStart: '2026-06-10T18:01:30.000',
      stamp: stamp,
      outputDirectory: root.path,
      writeToDisk: disk,
    );
    Map<String, dynamic> output() =>
        jsonDecode(
              File('${root.path}/nied_replay_$stamp.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    Map<String, dynamic> row(int n) => {
      'type': 'frame',
      'sequence': n,
      'station_levels': {'站あ': n},
      'unknown': null,
    };

    test(
      'ordered records and counters survive repeated incremental saves',
      () async {
        start();
        for (var i = 0; i < 200; i++) {
          owner.append(2, row(i));
          if (i % 17 == 0) await owner.save();
        }
        owner.append(3, {'type': 'detection', 'max_shindo': -1});
        owner.append(4, {'type': 'epicenter', 'lat': null, 'lng': null});
        owner.append(5, {
          'type': 'source_trigger',
          'metadata': {'raw': '中日🫧'},
        });
        await owner.save();
        final result = output();
        expect(
          (result['frames'] as List).take(200).toList(),
          List.generate(200, row),
        );
        expect(result['frame_count'], 200);
        expect(result['detection_count'], 1);
        expect(result['epicenter_count'], 1);
        expect(result['gif_capture_count'], 0);
        expect(owner.readRecords(), result['frames']);
      },
    );
    test(
      'source record literal is retained including floating point spelling',
      () async {
        start();
        final raw =
            '{"type":"frame","raw":1.0000000000000002,"negative_zero":-0.0,"literal":"未知"}';
        owner.appendRaw(2, utf8.encode(raw));
        await owner.save();
        expect(
          File('${root.path}/nied_replay_$stamp.json').readAsStringSync(),
          contains(raw),
        );
        expect(output()['frames'], [jsonDecode(raw)]);
      },
    );
    test(
      'original GIF cache rolls at 30, dedupes, preserves bytes and package',
      () async {
        final bytes = File(
          'test/fixtures/nied_recovery/20260610180130.lmoni.jma_s.gif',
        ).readAsBytesSync();
        for (var i = 0; i < 35; i++) {
          owner.capture({
            'jst': '2026-06-10T18:01:30.000',
            'url': 'https://example.invalid/raw/$i.gif',
            'layer': 'jma_s',
            'fallback_name': 'fallback.gif',
          }, bytes);
        }
        start();
        owner.append(2, row(0));
        owner.capture({
          'jst': '2026-06-10T18:01:30.000',
          'url': 'https://example.invalid/raw/34.gif',
          'layer': 'jma_s',
          'fallback_name': 'fallback.gif',
        }, bytes);
        await owner.save();
        final result = output(),
            dir = Directory(result['capture_directory'] as String);
        expect(result['gif_capture_count'], 30);
        expect(
          (result['captured_gifs'] as List).first['path'],
          'raw/jma_s/5.gif',
        );
        expect(File('${dir.path}/raw/jma_s/34.gif').readAsBytesSync(), bytes);
        expect(File('${dir.path}/raw/jma_s/0.gif').existsSync(), isFalse);
        expect(
          jsonDecode(File('${dir.path}/nied_replay.json').readAsStringSync()),
          result,
        );
        final manifest =
            jsonDecode(
                  File('${dir.path}/capture_manifest.json').readAsStringSync(),
                )
                as Map;
        expect(manifest['schemaVersion'], 'nied_capture_v1');
        expect(manifest['gifCount'], 30);
        expect(manifest['frames'], result['captured_gifs']);
      },
    );
    test(
      'late first GIF includes every previously saved record in package',
      () async {
        start();
        for (var i = 0; i < 100; i++) {
          owner.append(2, row(i));
        }
        await owner.save();
        expect(output()['capture_directory'], isNull);
        final bytes = File(
          'test/fixtures/nied_recovery/20260610180130.lmoni.jma_s.gif',
        ).readAsBytesSync();
        owner.capture({
          'jst': '2026-06-10T18:01:30.000',
          'url': 'https://example.invalid/震%20あ.gif?q=1',
          'layer': 'jma_s',
          'fallback_name': 'fallback.gif',
        }, bytes);
        for (var i = 100; i < 110; i++) {
          owner.append(2, row(i));
        }
        await owner.save();
        final result = output();
        expect((result['frames'] as List).length, 110);
        expect(
          (result['captured_gifs'] as List).single['path'],
          'raw/jma_s/震 あ.gif',
        );
        expect(
          jsonDecode(
            File(
              '${result['capture_directory']}/nied_replay.json',
            ).readAsStringSync(),
          ),
          result,
        );
      },
    );
    test(
      'native auto-save at 80 records and stop flushes unsaved tail',
      () async {
        start();
        for (var i = 0; i < 80; i++) {
          owner.append(2, row(i));
        }
        owner.barrier();
        expect(output()['frame_count'], 80);
        for (var i = 80; i < 85; i++) {
          owner.append(2, row(i));
        }
        owner.stopSync();
        expect(output()['frame_count'], 85);
        owner.append(2, row(86));
        await owner.save();
        expect(output()['frame_count'], 85);
      },
    );
    test(
      'new session resets records and GIF dedupe, flushes prior session',
      () async {
        start();
        owner.append(2, row(1));
        owner.start(
          sessionStart: '2026-06-10T18:02:00.000',
          stamp: '20260610_180200',
          outputDirectory: root.path,
          writeToDisk: true,
        );
        owner.append(2, row(2));
        await owner.save();
        expect(output()['frames'], [row(1)]);
        final next = jsonDecode(
          File(
            '${root.path}/nied_replay_20260610_180200.json',
          ).readAsStringSync(),
        );
        expect(next['frames'], [row(2)]);
      },
    );
    test('non-disk mode only materializes records on explicit query', () async {
      start(disk: false);
      owner.append(2, row(0));
      await owner.save();
      expect(root.listSync(), isEmpty);
      expect(owner.readRecords(), [row(0)]);
    });
    test('IO failure is reported and a fresh session can recover', () async {
      final file = File('${root.path}/blocked')
        ..writeAsStringSync('existing file');
      owner.start(
        sessionStart: '2026-06-10T18:01:30.000',
        stamp: stamp,
        outputDirectory: file.path,
        writeToDisk: true,
      );
      owner.append(2, row(1));
      await expectLater(owner.save(), throwsA(isA<StateError>()));
      expect(owner.lastStatus['error'], isNotNull);
      // Disable disk for the failed session before closing its journals by
      // releasing it; a new owner must never fabricate a successful old save.
      owner.dispose();
      owner = NativeReplayLogSession();
      start();
      owner.append(2, row(2));
      await owner.save();
      expect(output()['frames'], [row(2)]);
    });
    test(
      'failed autosave retains the 80-record and 15-second retry cadence',
      () async {
        owner.dispose();
        final notices = <Map<String, dynamic>>[];
        owner = NativeReplayLogSession(onStatus: notices.add);
        final blocked = File('${root.path}/blocked-auto')
          ..writeAsStringSync('protocol control');
        owner.start(
          sessionStart: '2026-06-10T18:01:30.000',
          stamp: stamp,
          outputDirectory: blocked.path,
          writeToDisk: true,
        );
        for (var i = 0; i < 160; i++) {
          owner.append(2, row(i));
        }
        owner.barrier();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(notices.where((n) => n['error'] != null).length, 1);
        expect(owner.readRecords().length, 160);
      },
    );
    test(
      'unsafe GIF paths report an error without writing outside capture',
      () async {
        start();
        owner.capture({
          'jst': '2026-06-10T18:01:30.000',
          'url': 'https://example.invalid/a.gif',
          'layer': '../escape',
          'fallback_name': 'x.gif',
        }, utf8.encode('protocol bytes'));
        owner.barrier();
        expect(owner.refreshStatus()['error'], isNotNull);
        expect(root.listSync(), isEmpty);
      },
    );
    test(
      '20320 frozen real records survive archive ownership transfer',
      () async {
        final source = File(
          'tmp/native_replay_logger_baseline_20261016_204500/original/nied_replay_20261016_114940.json',
        );
        if (!source.existsSync()) {
          markTestSkipped('Local immutable original archive required');
          return;
        }
        final original = jsonDecode(source.readAsStringSync()) as Map;
        start();
        for (final record in original['frames'] as List) {
          final r = Map<String, dynamic>.from(record as Map);
          final op = const {
            'frame': 2,
            'detection': 3,
            'epicenter': 4,
            'source_trigger': 5,
          }[r['type']]!;
          owner.append(op, r);
        }
        await owner.save();
        final result = output();
        expect(result['frames'], original['frames']);
        for (final key in [
          'frame_count',
          'detection_count',
          'epicenter_count',
        ]) {
          expect(result[key], original[key]);
        }
      },
    );
  }, skip: !NativeReplayLogSession.supported);

  test('logger UI bridge flushes final records when disabled', () async {
    if (!NativeReplayLogSession.supported) {
      markTestSkipped('Native archive required');
      return;
    }
    final directory = Directory.systemTemp.createTempSync('rq_logger_bridge_');
    final logger = NiedReplayLogger.instance;
    logger.resetForTest(writeToDisk: true, outputDirectory: directory.path);
    try {
      logger.setEnabled(true);
      expect(logger.archiveBackend, 'rust-replay-archive-v1');
      logger.logFetchParse(
        jstTime: DateTime(2026, 6, 10, 18, 1, 30),
        gifUrl: 'https://example.invalid/20260610180130.gif',
        success: true,
      );
      logger.setEnabled(false);
      final path = logger.lastLogPath!;
      expect(
        (jsonDecode(File(path).readAsStringSync()) as Map)['frame_count'],
        1,
      );
      expect(logger.debugRecords.length, 1);
    } finally {
      logger.resetForTest();
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (NativeReplayLogSession.activeWorkers != 0 &&
          DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final resolved = directory.resolveSymbolicLinksSync();
      expect(
        resolved,
        startsWith(Directory.systemTemp.resolveSymbolicLinksSync()),
      );
      directory.deleteSync(recursive: true);
    }
  });
}
