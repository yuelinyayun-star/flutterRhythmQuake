import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/native_replay_history_files_io.dart';
import 'package:flutterrhythmquake/services/replay_history_files.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';

void main() {
  final available = NativeReplayHistoryFiles.supported;
  late Directory temporary;
  late NativeReplayHistoryFiles native;
  late ReplayHistoryFiles reference;
  late Map<String, dynamic> report;
  setUp(() async {
    if (!available) {
      return;
    }
    temporary = await Directory.systemTemp.createTemp('rq-native-history-');
    final root = '${temporary.path}/历史_日本語';
    native = NativeReplayHistoryFiles(root);
    reference = ReplayHistoryFiles(root);
    final replay =
        jsonDecode(
              await File(
                'test/fixtures/history_replay/cwa_1150074.rqreplay',
              ).readAsString(encoding: utf8),
            )
            as Map;
    report = Map<String, dynamic>.from(
      (replay['reports'] as List).first as Map,
    );
  });
  tearDown(() async {
    if (!available) {
      return;
    }
    native.dispose();
    expect(NativeReplayHistoryFiles.results, 0);
    await temporary.delete(recursive: true);
  });

  test(
    'original reports retain exact JSON bytes and work in both backends',
    () async {
      const key = 'private_event_花蓮_日本語';
      final digest = await native.writeReport(key, report);
      expect(
        await File(reference.reportPath(key, digest)).readAsBytes(),
        JsonUtf8Encoder().convert(report),
      );
      expect(await reference.readReport(key, digest), report);
      final before = await File(
        reference.reportPath(key, digest),
      ).lastModified();
      expect(await native.writeReport(key, report), digest);
      expect(
        await File(reference.reportPath(key, digest)).lastModified(),
        before,
      );
      expect(await native.readReport(key, digest), report);
      await File(reference.reportPath(key, digest)).writeAsString('corrupt');
      await expectLater(native.readReport(key, digest), throwsFormatException);
      await expectLater(native.writeReport(key, report), throwsFormatException);
      await expectLater(
        native.readReport(key, '../escape'),
        throwsFormatException,
      );
    },
    skip: !available,
  );

  test(
    'old gzip is preserved and new gzip is readable by the frozen backend',
    () async {
      // Original captured observation JSON; this tests persistence, not a claim
      // that these observations belong to the historical CWA earthquake.
      final original = jsonDecode(
        await File(
          'test/fixtures/whews_nied/observations.json',
        ).readAsString(encoding: utf8),
      );
      final frame = <String, dynamic>{'originalJson': original};
      await reference.writeFrame('old-frame', frame);
      final file = File(reference.framePath('old-frame'));
      final bytes = await file.readAsBytes();
      final modified = await file.lastModified();
      await native.writeFrame('old-frame', frame);
      expect(await file.readAsBytes(), bytes);
      expect(await file.lastModified(), modified);
      expect(await native.readFrame('old-frame'), frame);
      await native.writeFrame('native-frame', frame);
      expect(await reference.readFrame('native-frame'), frame);
      await expectLater(
        native.writeFrame('native-frame', report),
        throwsFormatException,
      );
      expect(await reference.readFrame('native-frame'), frame);
    },
    skip: !available,
  );

  test(
    'record replacement is atomic and namespaces remain separate',
    () async {
      expect(await native.record('public'), isNull);
      await native.writeRecord('public', '原文_日本語', {'event': report});
      await native.writeRecord('personal', 'private', null);
      final before = await reference.record('public');
      final obstruction = Directory(
        '${reference.recordPath('public')}.pending',
      );
      await obstruction.create();
      await expectLater(
        native.writeRecord('public', 'replacement', null),
        throwsStateError,
      );
      expect(await reference.record('public'), before);
      expect(await native.record('personal'), {
        'key': 'personal',
        'value': 'private',
      });
      await obstruction.delete();
      await native.writeRecord('public', 'committed', null);
      expect((await native.record('public'))!['value'], 'committed');
      await native.remove('public');
      expect(await reference.record('public'), isNull);
      expect((await native.record('personal'))!['value'], 'private');
    },
    skip: !available,
  );

  test(
    'event retention does not remove shared frames or another event',
    () async {
      const key = 'ns_event_one';
      await native.writeReport(key, report);
      await native.writeReport('ns_event_two', report);
      await native.writeFrame('shared', {
        'originalJson': report['sourcePayload'],
      });
      await native.remove(key);
      expect(await Directory(reference.eventPath(key)).exists(), isFalse);
      expect(
        await Directory(reference.eventPath('ns_event_two')).exists(),
        isTrue,
      );
      expect(await File(reference.framePath('shared')).exists(), isTrue);
      await native.remove('shared', frame: true);
      await native.remove('shared', frame: true);
      expect(await File(reference.framePath('shared')).exists(), isFalse);
    },
    skip: !available,
  );

  test(
    'storage protocol preserves integer types, float bits and Unicode',
    () async {
      // Explicit serialization edge cases, not invented observation readings.
      final values = <String, dynamic>{
        '中文_日本語': ['島', '🌊'],
        'integer': 9223372036854775807,
        'negativeZero': -0.0,
        'double': 1.0000000000000002,
        'empty': '',
        'null': null,
      };
      await native.writeFrame('serialization', values);
      final restored = await native.readFrame('serialization');
      expect(
        JsonUtf8Encoder().convert(restored),
        JsonUtf8Encoder().convert(values),
      );
      expect(restored['integer'], isA<int>());
      expect((restored['negativeZero'] as double).isNegative, isTrue);
    },
    skip: !available,
  );

  test(
    'worker uses native files and acknowledges close after owner release',
    () async {
      final baseline = NativeReplayHistoryFiles.sessions;
      final calls = NativeReplayHistoryFiles.calls;
      final worker = await WindowsPreferencesWorker.start(
        '${temporary.path}/worker',
      );
      expect(NativeReplayHistoryFiles.sessions, baseline + 1);
      try {
        await worker.replayFileOperation('write', ['index', 'saved', null]);
        expect(await worker.replayFileOperation('read', ['index']), 'saved');
        expect(NativeReplayHistoryFiles.calls, greaterThan(calls));
      } finally {
        await worker.close();
      }
      expect(NativeReplayHistoryFiles.sessions, baseline);
      expect(NativeReplayHistoryFiles.results, 0);
    },
    skip: !available,
  );

  test(
    'dispose releases the owner once and prevents later operations',
    () async {
      final baseline = NativeReplayHistoryFiles.sessions;
      native.dispose();
      native.dispose();
      expect(NativeReplayHistoryFiles.sessions, baseline - 1);
      await expectLater(native.record('index'), throwsStateError);
      expect(() => NativeReplayHistoryFiles('relative-root'), throwsStateError);
    },
    skip: !available,
  );
}
