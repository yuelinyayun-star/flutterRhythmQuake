import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/jian_cea_eew.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jma_cancellation_regression_test.dart' show officialReference;
import 'eew_api_identity_test.dart' show adapt, records;
import 'jian_cea_effects_test.dart' show model;
import 'early_est_history_merge_test.dart' show unifiedHistory;

const _zip = 'test/fixtures/jma_cancellation_20261016/original_telegrams.zip';
List<UnifiedQuakeData> _originalTelegrams() =>
    ZipDecoder()
        .decodeBytes(File(_zip).readAsBytesSync())
        .files
        .where((file) => file.isFile)
        .map(
          (file) => officialReference(
            jsonDecode(utf8.decode(file.content as List<int>))
                as Map<String, dynamic>,
          ),
        )
        .toList()
      ..sort((a, b) => a.reportTime!.compareTo(b.reportTime!));

Map<String, dynamic> _context(UnifiedQuakeData report) {
  final now = DateTime.now();
  final source = QuakeTime.unifiedInstantUtc(
    report,
    value: report.reportTime ?? report.originTime,
  );
  return {
    'nowUs': now.microsecondsSinceEpoch,
    'nowIso': now.toIso8601String(),
    'sourceNowUs': source.microsecondsSinceEpoch,
    'eewNowUs': source.microsecondsSinceEpoch,
    'localOffsetMinutes': now.timeZoneOffset.inMinutes,
    'volcanoEnabled': true,
    'showStale': false,
    'whitelist': <String>[],
    'blockedSources': <String>[],
    'filters': <String, double>{},
    'historyLoaded': true,
    'historyKeepForever': true,
    'historyMaxPerSource': 15,
  };
}

Object _snapshot(QuakeProvider provider) {
  Map<String, dynamic> body(UnifiedQuakeData e) =>
      Map.of(e.toMap())..remove('arrivedAt');
  return {
    'active': [for (final e in provider.unifiedEvents) body(e)],
    'history': [
      for (final g in provider.eewHistory)
        {
          'id': g.eventId,
          'reports': [for (final e in g.reports) body(e)],
        },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().enabled = false;
  });
  tearDown(() {
    SoundEffectService().enabled = true;
    TtsService().enabled = true;
  });

  test(
    '43 unmodified official telegrams match the retained Dart pipeline after every report',
    () async {
      final before = sha256.convert(File(_zip).readAsBytesSync());
      final reports = _originalTelegrams();
      expect(reports, hasLength(43));
      final traces = <List<Object>>[];
      for (final native in [false, true]) {
        SharedPreferences.setMockInitialValues({});
        var sourceNow = QuakeTime.unifiedInstantUtc(
          reports.first,
          value: reports.first.reportTime,
        );
        final provider = QuakeProvider(
          startCatalogServices: false,
          nativeUnifiedEvents: native,
          eewClock: () => sourceNow,
        );
        try {
          await provider.eewHistoryReadyForTest;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final trace = <Object>[];
          for (final event in reports) {
            sourceNow = QuakeTime.unifiedInstantUtc(
              event,
              value: event.reportTime,
            );
            provider.handleUnifiedEventForTest(event);
            trace.add(_snapshot(provider));
          }
          traces.add(trace);
        } finally {
          provider.dispose();
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      for (var j = 0; j < reports.length; j++) {
        expect(
          traces[1][j],
          traces[0][j],
          reason:
              'original telegram $j / ${reports[j].eventId} ${reports[j].reportNumText}',
        );
      }
      expect(sha256.convert(File(_zip).readAsBytesSync()), before);
    },
  );

  test(
    '44 captured multi-source identities preserve keys and merge decisions',
    () async {
      final owners = <QuakeProvider>[];
      try {
        for (final native in [false, true]) {
          SharedPreferences.setMockInitialValues({});
          final p = QuakeProvider(
            startCatalogServices: false,
            nativeUnifiedEvents: native,
          );
          await p.eewHistoryReadyForTest;
          owners.add(p);
        }
        for (final record in records) {
          final event = adapt(record);
          expect(
            owners[1].unifiedEventKeyForTest(event),
            owners[0].unifiedEventKeyForTest(event),
          );
          final before = owners[0].unifiedToQuakeMessageForTest(event).toMap();
          final after = owners[1].unifiedToQuakeMessageForTest(event).toMap();
          if (event.originTime == null) {
            before.remove('originTime');
            after.remove('originTime');
          }
          expect(
            after,
            before,
            reason: 'UI fields ${event.source} ${event.apiTypeLabel}',
          );
        }
      } finally {
        for (final p in owners) {
          p.dispose();
        }
      }
    },
  );

  test(
    'catalog row merge matches existing policy for original histories in both orders',
    () {
      final mapper = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      addTearDown(mapper.dispose);
      final catalog = <String, List<QuakeMessage>>{
        'cencEqlist': [
          ...QuakeEventAdapter.convertWolfxCencEqlist(
            Map<String, dynamic>.from(
              jsonDecode(
                    File(
                      'test/fixtures/cenc_history_20261014/wolfx.original.json',
                    ).readAsStringSync(encoding: utf8),
                  )
                  as Map,
            ),
          ),
          for (final raw
              in (jsonDecode(
                        File(
                          'test/fixtures/cenc_history_20261014/jian.original.json',
                        ).readAsStringSync(encoding: utf8),
                      )
                      as Map)['Data']
                  as List)
            mapper.unifiedToQuakeMessageForTest(
              QuakeEventAdapter.convertJian(
                'cenc',
                Map<String, dynamic>.from(raw),
                isHistory: true,
              )!,
            ),
        ],
        'earlyEst':
            (jsonDecode(
                      File(
                        'test/fixtures/early_est_history_20261009.original.json',
                      ).readAsStringSync(encoding: utf8),
                    )
                    as List)
                .map((e) => QuakeMessage.fromMap(Map<String, dynamic>.from(e)))
                .toList(),
        for (final bucket
            in jsonDecode(
                  File(
                    'test/fixtures/cmt_history_20261009.original.json',
                  ).readAsStringSync(encoding: utf8),
                )
                as List)
          bucket['source'] as String: [
            for (final row in bucket['rows'] as List)
              QuakeMessage.fromMap(Map<String, dynamic>.from(row)),
          ],
      };
      final manager = EqlistManager();
      manager.onAnyUpdated = null;
      for (final entry in catalog.entries) {
        for (final reverse in [false, true]) {
          final before = manager.getAllBuckets()[entry.key];
          before?.clear();
          final incoming = reverse
              ? entry.value.reversed.toList()
              : entry.value;
          manager.onBucketUpsert = null;
          final expected = <List<QuakeMessage>>[];
          for (final event in [...incoming, ...incoming.reversed]) {
            manager.upsertBucketItem(entry.key, event, replayOnly: true);
            expected.add(List.of(manager.getAllBuckets()[entry.key]!));
          }
          manager.getAllBuckets()[entry.key]!.clear();
          final owner = NativeUnifiedEventOwner(onBatch: (_, _) {});
          try {
            manager.onBucketUpsert = (bucket, current, incoming, replayOnly) =>
                owner.upsertBucket(
                  bucket,
                  current,
                  incoming,
                  replayOnly: replayOnly,
                );
            var j = 0;
            for (final event in [...incoming, ...incoming.reversed]) {
              manager.upsertBucketItem(entry.key, event, replayOnly: true);
              expect(
                manager.getAllBuckets()[entry.key],
                expected[j++],
                reason: '${entry.key} reverse=$reverse',
              );
            }
          } finally {
            manager.onBucketUpsert = null;
            manager.getAllBuckets()[entry.key]!.clear();
            owner.dispose();
          }
        }
      }
    },
  );

  test(
    'derived warning effects match current badge rules without writing estimates',
    () {
      final owner = NativeUnifiedEventOwner(onBatch: (_, _) {});
      addTearDown(owner.dispose);
      for (final event in [
        for (var m = 0.1; m < 10; m += 0.125) model(magnitude: m),
        model(magnitude: 6).copyWith(isHistory: true),
        model(magnitude: 6).copyWith(sourcePayload: {'isWarn': false}),
        model(magnitude: 6).copyWith(isCanceled: true),
        model(magnitude: 6).copyWith(maxIntensity: '6.5'),
        model(magnitude: 6).copyWith(magnitude: double.nan),
      ]) {
        expect(
          owner.query('effectiveWarn', event: event),
          effectiveEewWarn(event),
        );
        expect(event.isWarn, isFalse);
      }
    },
  );

  test('persisted identity formatting keeps Dart boundary rounding', () {
    final owner = NativeUnifiedEventOwner(onBatch: (_, _) {});
    addTearDown(owner.dispose);
    for (final value in [
      0.0,
      -0.0,
      0.0000001,
      0.000001,
      0.0000125,
      -0.0000125,
      1.0625,
      -1.0625,
      12.3455,
      126.0825,
      1e20,
      1e21,
    ]) {
      for (final places in [0, 1, 3, 6]) {
        expect(
          owner.queryRaw({
            'op': 'formatNumbers',
            'value': value,
            'places': places,
          }),
          [value.toString(), value.toStringAsFixed(places)],
          reason: '$value / $places',
        );
      }
    }
  });

  test(
    'saved summaries release original views without losing native revision state',
    () {
      final report = _originalTelegrams().first;
      final owner = NativeUnifiedEventOwner(onBatch: (_, _) {});
      addTearDown(owner.dispose);
      owner.send({
        'op': 'seedHistory',
        'groups': [
          [owner.describe(report)],
        ],
        'firstArrivedUs': [DateTime.now().microsecondsSinceEpoch],
        'eventIds': [report.eventId],
        'context': _context(report),
      });
      expect(owner.retainsView(report), isTrue);
      final summary = UnifiedQuakeData.fromMap(
        Map.of(report.toMap())
          ..remove('sourcePayload')
          ..remove('rawEvent'),
      );
      expect(summary.sourcePayload, isNull);
      owner.rebindHistory([report], [summary]);
      expect(owner.retainsView(report), isFalse);
      expect(owner.retainsView(summary), isTrue);
      expect(owner.retainedViewCount, 1);
      expect(owner.key(summary), owner.key(report));
      expect(
        owner.retainedViewCount,
        1,
        reason: 'read-only key query cannot retain the original report',
      );
    },
  );

  test('history fallback intensity keeps the original calculation', () {
    final owner = NativeUnifiedEventOwner(onBatch: (_, _) {});
    addTearDown(owner.dispose);
    for (final depth in [
      -1.0,
      0.0,
      10.0,
      50.0,
      300.0,
      700.0,
      double.nan,
      double.infinity,
    ]) {
      for (var mag = 0.0; mag <= 10; mag += 0.125) {
        final event = model(magnitude: mag).copyWith(depth: depth);
        expect(
          owner.messageFields(event)['fallbackIntensity'],
          IntensityCalculator.calcCsisLevel(mag, depth, 0),
          reason: 'M$mag depth=$depth',
        );
      }
    }
  });

  test(
    'real native worker waits for bootstrap, expires cancellation and closes cleanly',
    () async {
      final baseline = NativeUnifiedEventOwner.diagnostics;
      final reports = _originalTelegrams();
      final cancellation = reports.singleWhere((e) => e.isCanceled);
      final batches = <Map<String, dynamic>>[];
      final active = <UnifiedQuakeData>[];
      final owner = NativeUnifiedEventOwner(
        manualClock: false,
        onBatch: (batch, pool) {
          batches.add(batch);
          active
            ..clear()
            ..addAll([for (final id in batch['active'] as List) pool[id]!]);
        },
      );
      try {
        owner.admit(cancellation, _context(cancellation));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(active, isEmpty);
        expect(batches, isEmpty);
        owner.send({'op': 'ready'});
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(active.single.isCanceled, isTrue);
        expect(active.single.sourcePayload, cancellation.sourcePayload);
        expect(
          NativeUnifiedEventOwner.diagnostics['workers'],
          baseline['workers']! + 1,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20100));
        expect(active, isEmpty);
        expect(
          batches
              .expand((b) => b['actions'] as List)
              .where((a) => a[0] == 'removed'),
          hasLength(1),
        );
        final stats = owner.queryRaw({'op': 'runtimeStats'}) as Map;
        expect(
          stats['deadlineWakes'],
          lessThanOrEqualTo(3),
          reason: 'idle session uses deadlines, not a polling loop',
        );
      } finally {
        owner.dispose();
      }
      expect(NativeUnifiedEventOwner.diagnostics, baseline);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'original telegram burst runs on the worker with bounded queues',
    () async {
      final baseline = NativeUnifiedEventOwner.diagnostics;
      final owner = NativeUnifiedEventOwner(
        manualClock: false,
        onBatch: (_, _) {},
      );
      final reports = _originalTelegrams();
      try {
        owner.send({'op': 'ready'});
        final submit = Stopwatch()..start();
        for (final report in reports) {
          owner.admit(report, _context(report));
        }
        submit.stop();
        Map stats = {};
        for (var j = 0; j < 200; j++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          stats = owner.queryRaw({'op': 'runtimeStats'}) as Map;
          if (stats['commands'] == reports.length + 1 &&
              stats['outstanding'] == 0)
            break;
        }
        expect(stats['commands'], reports.length + 1);
        expect(stats['queued'], 0);
        expect(stats['outstanding'], 0);
        final metrics = {
          'originalTelegrams': reports.length,
          'submitUs': submit.elapsedMicroseconds,
          ...stats,
        };
        File(
          'tmp/unified_event_owner_20261019/worker_metrics.json',
        ).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(metrics),
          encoding: utf8,
        );
        print('Unified native component metrics: $metrics');
      } finally {
        owner.dispose();
      }
      expect(NativeUnifiedEventOwner.diagnostics, baseline);
    },
  );

  test(
    'asynchronous catalog binding preserves report order and a concurrent UI snapshot',
    () async {
      final baseline = NativeUnifiedEventOwner.diagnostics;
      final text = File(
        'test/fixtures/early_est_history_20261009.original.json',
      ).readAsStringSync(encoding: utf8);
      final rows = (jsonDecode(text) as List)
          .map((e) => QuakeMessage.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final older = rows.singleWhere((e) => e.apiTypeLabel == 'Jian Project');
      final newer = rows.singleWhere((e) => e.apiTypeLabel == 'WHEWS');
      final manager = EqlistManager();
      manager.onAnyUpdated = null;
      manager.onBucketUpsert = null;
      manager.onBucketUpsertAsync = null;
      manager.upsertBucketItem('earlyEst', older);
      final list = manager.getAllBuckets()['earlyEst']!..clear();
      final owner = NativeUnifiedEventOwner(
        manualClock: false,
        onBatch: (_, _) {},
      );
      owner.send({'op': 'ready'});
      try {
        manager.onBucketUpsertAsync = (bucket, current, event, replayOnly) =>
            owner.upsertBucketAsync(
              bucket,
              current,
              event,
              replayOnly: replayOnly,
            );
        for (final row in [older, newer, older, newer]) {
          manager.upsertBucketItem('earlyEst', row, replayOnly: true);
        }
        await manager.waitForBucketBindings().timeout(
          const Duration(seconds: 3),
        );
        expect(list, [newer]);
        list.clear();
        final entered = Completer<void>(), release = Completer<void>();
        var calls = 0;
        manager.onBucketUpsertAsync =
            (bucket, current, event, replayOnly) async {
              if (calls++ == 0) {
                entered.complete();
                await release.future;
              }
              return owner.upsertBucketAsync(
                bucket,
                current,
                event,
                replayOnly: replayOnly,
              );
            };
        manager.upsertBucketItem('earlyEst', older, replayOnly: true);
        await entered.future;
        list.add(newer);
        release.complete();
        await manager.waitForBucketBindings().timeout(
          const Duration(seconds: 3),
        );
        expect(calls, 2, reason: 'rebind against the replacement snapshot');
        expect(list, [newer]);
        expect(
          File(
            'test/fixtures/early_est_history_20261009.original.json',
          ).readAsStringSync(encoding: utf8),
          text,
        );
      } finally {
        manager.onBucketUpsertAsync = null;
        list.clear();
        owner.dispose();
      }
      expect(NativeUnifiedEventOwner.diagnostics, baseline);
    },
  );

  test(
    'pending history rows block an older live Early-est before UI binding',
    () async {
      final rows =
          (jsonDecode(
                    File(
                      'test/fixtures/early_est_history_20261009.original.json',
                    ).readAsStringSync(encoding: utf8),
                  )
                  as List)
              .map((e) => QuakeMessage.fromMap(Map<String, dynamic>.from(e)))
              .toList();
      final history = unifiedHistory(
        rows.singleWhere((e) => e.apiTypeLabel == 'WHEWS'),
      );
      final older = unifiedHistory(
        rows.singleWhere((e) => e.apiTypeLabel == 'Jian Project'),
      ).copyWith(isHistory: false);
      final active = <UnifiedQuakeData>[];
      final owner = NativeUnifiedEventOwner(
        manualClock: false,
        onBatch: (batch, pool) {
          active
            ..clear()
            ..addAll([for (final id in batch['active'] as List) pool[id]!]);
        },
      );
      try {
        owner.send({'op': 'ready'});
        owner.admit(history, _context(history));
        owner.admit(older, _context(older));
        for (var j = 0; j < 100; j++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if ((owner.queryRaw({'op': 'runtimeStats'}) as Map)['commands'] == 3)
            break;
        }
        expect(active, isEmpty);
      } finally {
        owner.dispose();
      }
    },
  );
}
