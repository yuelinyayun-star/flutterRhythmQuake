import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/native_replay_policy.dart';
import 'package:flutterrhythmquake/services/native_replay_policy_portable.dart'
    as reference;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native policy preserves source time parsing and field precedence', () {
    final before = NativeReplayPolicy.calls;
    final times = <dynamic>[
      null,
      '',
      'invalid',
      '2026-09-29 02:20:44',
      '2026/9/29 2:20:44.123456',
      '2026-09-29T02:20:44.123456+08:00',
      '2026-09-28T18:20:44.123456Z',
      '2026-09-28T18:20:44.123456z',
      '2026-09-29T02:20:44.123456+0800',
      '2026-09-29T02:20:44.123456-05:30',
      '2026-09-29T02Z',
      '2026-09-29T02:20Z',
      '2026-09-29T02:20:44,123456Z',
      '2026-09-29T02:20:44.123456789Z',
      '2026-9-29T2:20:44Z',
      '2026-09-29junkZ',
      '2026-09-29T02:20:44Zjunk',
      '2026-09-29',
      '20260929',
      '20260929T022044.123456Z',
      '2026-09-29 02:20',
      '2026-09-29 trailing',
      '2026-13-01 25:61:61',
      0,
      -0.123456,
      1790619644.123456,
      1790619644123,
    ];
    for (final zone in [-12, 0, 8, 9, 14]) {
      for (final value in times) {
        for (final field in [
          'ReportTime',
          'reportTime',
          'AnnouncedTime',
          'createTime',
          'updateTime',
          'issue',
        ]) {
          final request = <String, dynamic>{
            'op': 'reportInstant',
            'timeZone': zone,
            'sourcePayload': {
              field: field == 'issue' ? {'time': value} : value,
            },
          };
          expect(
            NativeReplayPolicy.prepare(request),
            reference.NativeReplayPolicy.prepare(request),
            reason: '$zone/$field/$value',
          );
        }
      }
    }
    if (NativeReplayPolicy.supported) {
      expect(NativeReplayPolicy.calls, greaterThan(before));
      expect(NativeReplayPolicy.outputs, 0);
    }
  });

  test(
    'actual original payloads and stored/explicit times keep precedence',
    () {
      for (final path in [
        'test/fixtures/history_replay/cwa_1150074.rqreplay',
        'test/fixtures/history_replay/cea_202609290220.rqreplay',
        'test/fixtures/global_quake/captured_report_only_20261018.json',
      ]) {
        final file = File(path), bytes = File(path).readAsBytesSync();
        final hash = sha256.convert(bytes);
        for (final report
            in jsonDecode(utf8.decode(bytes))['reports'] as List) {
          for (final stored in [null, 0, 1234567890123456]) {
            final request = <String, dynamic>{
              'op': 'reportInstant',
              'reportTime': report['reportTime'],
              'timeZone': report['timeZone'],
              'sourcePayload': report['sourcePayload'],
              'hasStoredRef': stored != null,
              'storedReportInstant': stored,
            };
            expect(
              NativeReplayPolicy.prepare(request),
              reference.NativeReplayPolicy.prepare(request),
            );
          }
        }
        expect(sha256.convert(file.readAsBytesSync()), hash);
      }
    },
  );

  test(
    'FFI frees every result including errors; needs-history keeps old guards',
    () {
      for (final stored in [false, true]) {
        for (final files in [false, true]) {
          for (final stations in [false, true]) {
            final request = <String, dynamic>{
              'op': 'needsHistory',
              'hasStoredReports': stored,
              'hasFileReports': files,
              'hasStoredStations': stations,
            };
            expect(
              NativeReplayPolicy.prepare(request),
              (stored && !files) || stations,
            );
          }
          expect(
            NativeReplayPolicy.prepare({
              'op': 'needsHistory',
              'hasStoredReports': true,
              'hasFileReports': true,
              'hasStoredStations': false,
              'storedSelection': true,
            }),
            isTrue,
          );
        }
      }
      for (var i = 0; i < 300; i++) {
        expect(
          () => NativeReplayPolicy.prepare({'op': 'invalid'}),
          throwsStateError,
        );
      }
      if (NativeReplayPolicy.supported) expect(NativeReplayPolicy.outputs, 0);
    },
  );
}
