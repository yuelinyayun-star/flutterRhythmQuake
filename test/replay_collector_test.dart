import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/snet_station.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/collector/jian_collector_feed.dart';
import 'package:flutterrhythmquake/services/collector/replay_collector.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/replay_station_display.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late HistoryReplayPackage fixture;
  late DateTime now;
  late ReplayCollector collector;

  ReplayCollector create({Set<String> stations = const {'snet', 'lpgm'}}) =>
      ReplayCollector(
        spool: Directory('${temporary.path}/active'),
        output: Directory('${temporary.path}/outbox'),
        stations: stations,
        now: () => now,
      );

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('rq_collector_test_');
    fixture = HistoryReplayPackage.decode(
      await File(
        'test/fixtures/history_replay/cwa_1150074.rqreplay',
      ).readAsString(),
    );
    now = fixture.reports.first.arrivedAt!.toUtc();
    collector = create();
    await collector.open();
  });
  tearDown(() async {
    await collector.close();
    await temporary.delete(recursive: true);
  });

  test(
    'unchanged recorded CWA reports survive checkpoint, restart and export',
    () async {
      for (final report in fixture.reports) {
        expect(collector.addEvent(report), isTrue);
        expect(collector.addEvent(report), isFalse);
      }
      expect(await collector.tick(finalize: false), isEmpty);
      await collector.close();
      collector = create();
      await collector.open();
      expect(collector.activeCount, 1);
      now = now.add(const Duration(hours: 1));
      final files = await collector.tick();
      expect(files, hasLength(1));
      final replay = HistoryReplayPackage.decode(
        await files.single.readAsString(),
      );
      expect(
        replay.reports.map((e) => e.sourcePayload),
        unorderedEquals(fixture.reports.map((e) => e.sourcePayload)),
      );
      expect(replay.captureEndedAt, isNotNull);
      expect(await collector.tick(), isEmpty);
    },
  );

  test(
    'nonempty S-net model fixture survives capture, compact file and map playback',
    () async {
      // Explicit serialization fixture, NOT a claim of a live observation.
      final station = SnetStation(
        code: 'N.S1N01',
        name: 'S-net serialization fixture',
        coordinate: const LatLng(35.8968, 141.0535),
        depth: 0,
        network: '0120A',
        type: 'acceleration',
        intensity: 1.25,
        shindo: 1.25,
        level: 9,
        pixelX: 137,
        pixelY: 403,
        isActive: true,
        pressure: 0.125,
        lastUpdate: now,
      );
      final expected = ForegroundStationPayload.snet([station]);
      collector.addEvent(fixture.reports.first);
      final capture = StationHistoryCapture();
      capture.addListener(collector.addStation);
      capture.publish('snet', () => expected, receivedAt: now);
      collector.addStation(
        StationHistoryFrame(
          receivedAt: now,
          snapshot: {
            'kind': 'lpgm',
            'dataTime': now.toIso8601String(),
            'maxSva': 0.0,
            'maxClass': 0,
            'topStations': [],
          },
        ),
      );
      await collector.tick(finalize: false);
      now = now.add(const Duration(hours: 1));
      final text = await (await collector.tick()).single.readAsString();
      expect(
        jsonDecode(text)['stationArchive']['format'],
        'station-json-gzip-blocks-v1',
      );
      expect(text, isNot(contains('imageBytes')));
      final replay = HistoryReplayPackage.decode(text);
      expect(
        replay.stationFrames.map((e) => e.kind),
        containsAll(['snet', 'lpgm']),
      );
      final frame = replay.stationFrames.singleWhere((e) => e.kind == 'snet');
      expect(frame.snapshot, expected);
      final display = ReplayStationDisplay()..update({'snet': frame});
      expect(ForegroundStationPayload.snet(display.snet), expected);
    },
  );

  test(
    'disabled station is absent and GQ/ICL/history inputs cannot create captures',
    () async {
      collector.addEvent(fixture.reports.first);
      collector.addStation(
        StationHistoryFrame(
          receivedAt: now,
          snapshot: {'kind': 'nied', 'stations': []},
        ),
      );
      expect(
        collector.addEvent(
          fixture.reports.first.copyWith(source: 'globalQuakeEew'),
        ),
        isFalse,
      );
      expect(
        collector.addEvent(fixture.reports.first.copyWith(isHistory: true)),
        isFalse,
      );
      final iclResponse =
          jsonDecode(
                await File(
                  'test/fixtures/chinaeew_icl/98943021.json',
                ).readAsString(),
              )
              as Map;
      final rawIcl = Map<String, dynamic>.from(
        (iclResponse['data'] as List).first as Map,
      );
      final icl = QuakeEventAdapter.convertChinaEewIcl(rawIcl)!;
      expect(icl.sourcePayload, rawIcl);
      expect(ReplayCollector.excludedEventSources, contains(icl.source));
      expect(collector.addEvent(icl), isFalse);
      now = now.add(const Duration(hours: 1));
      final replay = HistoryReplayPackage.decode(
        await (await collector.tick()).single.readAsString(),
      );
      expect(replay.stationFrames, isEmpty);
    },
  );

  test(
    'capture does not end at the last report or before its station tail',
    () async {
      collector.addEvent(fixture.reports.first);
      now = now.add(const Duration(seconds: 30));
      expect(await collector.tick(), isEmpty);
      expect(collector.activeCount, 1);
    },
  );

  test('no-event observations are not written to disk', () async {
    collector.addStation(
      StationHistoryFrame(
        receivedAt: now,
        snapshot: {'kind': 'snet', 'stations': []},
      ),
    );
    await collector.tick();
    expect(await collector.output.list().toList(), isEmpty);
    expect(
      await collector.spool.list().where((e) => e is Directory).toList(),
      isEmpty,
    );
  });

  test('SeedLink station configuration is not accepted by the collector', () {
    expect(() => create(stations: {'seedlink'}), throwsArgumentError);
    expect(() => create(stations: {'fdsn'}), throwsArgumentError);
  });

  test('stale reconnect report does not create another replay', () {
    now = now.add(const Duration(hours: 1));
    expect(collector.addEvent(fixture.reports.first), isFalse);
    expect(collector.activeCount, 0);
  });

  test('simultaneous original CWA and CEA captures both survive', () async {
    final cea = HistoryReplayPackage.decode(
      await File(
        'test/fixtures/history_replay/cea_202609290220.rqreplay',
      ).readAsString(),
    );
    collector.addEvent(fixture.reports.first);
    for (final event in cea.reports) {
      collector.addEvent(event);
    }
    expect(collector.activeCount, 2);
    await collector.tick(finalize: false);
    now = now.add(const Duration(hours: 1));
    final files = await collector.tick();
    expect(files, hasLength(2));
    final sources = <String>{};
    for (final file in files) {
      sources.add(
        HistoryReplayPackage.decode(
          await file.readAsString(),
        ).reports.first.source,
      );
    }
    expect(sources, {'cwaEew', 'ceaEew'});
  });

  test('overlapping windows share compressed chunks across restart', () async {
    final cea = HistoryReplayPackage.decode(
      await File(
        'test/fixtures/history_replay/cea_202609290220.rqreplay',
      ).readAsString(),
    );
    collector.addEvent(fixture.reports.first);
    for (final event in cea.reports) {
      collector.addEvent(event);
    }
    final frame = StationHistoryFrame(
      receivedAt: now,
      snapshot: {'kind': 'snet', 'stations': []},
    );
    collector.addStation(frame);
    await collector.tick(finalize: false);
    final chunks = await Directory(
      '${collector.spool.path}/chunks',
    ).list().where((e) => e is File).toList();
    expect(chunks, hasLength(1));
    expect(chunks.single.path, endsWith('.stations.json.gz'));
    final bytes = await File(chunks.single.path).readAsBytes();
    expect(
      StationJsonArchive.decode(
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map,
      ).single.toMap(),
      frame.toMap(),
    );
    await collector.close();
    collector = create();
    await collector.open();
    now = now.add(const Duration(hours: 1));
    final files = await collector.tick();
    expect(files, hasLength(2));
    for (final file in files) {
      expect(
        HistoryReplayPackage.decode(
          await file.readAsString(),
        ).stationFrames.single.toMap(),
        frame.toMap(),
      );
    }
    expect(
      await Directory('${collector.spool.path}/chunks').list().toList(),
      isEmpty,
    );
  });

  test(
    'old uncompressed checkpoints still export with their original values',
    () async {
      collector.addEvent(fixture.reports.first);
      await collector.tick(finalize: false);
      final directory =
          (await collector.spool
                  .list()
                  .where((e) => e is Directory && !e.path.endsWith('/chunks'))
                  .toList())
              .single;
      final frame = StationHistoryFrame(
        receivedAt: now,
        snapshot: {'kind': 'snet', 'stations': []},
      );
      await File('${directory.path}/old.stations.json').writeAsString(
        jsonEncode(StationJsonArchive.encode([frame])),
        encoding: utf8,
      );
      now = now.add(const Duration(hours: 1));
      final replay = HistoryReplayPackage.decode(
        await (await collector.tick()).single.readAsString(),
      );
      expect(replay.stationFrames.single.toMap(), frame.toMap());
    },
  );

  test(
    'Jian saved original snapshot decoding admits EEW only, never GQ/catalogs',
    () async {
      final raw =
          jsonDecode(await File('test/fixtures/jian/all.json').readAsString())
              as Map<String, dynamic>;
      final events = JianCollectorFeed.decodeFrame(raw).toList();
      expect(events, isNotEmpty);
      expect(
        events.every((e) => e.isEew && e.source != 'globalQuakeEew'),
        isTrue,
      );
      expect(events.every((e) => e.sourcePayload?.isNotEmpty == true), isTrue);
      expect(events.every((e) => e.arrivedAt?.isUtc == true), isTrue);
      expect(
        JianCollectorFeed.decodeFrame({'type': 'globalQuakeEew', 'Data': {}}),
        isEmpty,
      );
    },
  );

  test(
    'original Jian body passes feed admission, checkpoint and export',
    () async {
      final capture =
          jsonDecode(
                await File(
                  'test/fixtures/jian/all.json',
                ).readAsString(encoding: utf8),
              )
              as Map<String, dynamic>;
      final original = Map<String, dynamic>.from(
        (capture['source：cea'] as Map)['Data'] as Map,
      );
      final originalJson = jsonEncode(original);
      final sourceEvent = QuakeEventAdapter.convertJian('cea', original)!;
      expect(sourceEvent.arrivedAt, isNull);
      expect(collector.addEvent(sourceEvent), isFalse);
      // Place the test clock at this unchanged capture's original event time.
      now = QuakeTime.unifiedInstantUtc(
        sourceEvent,
      ).add(const Duration(seconds: 30));
      for (final frame in [
        {'type': 'cea', 'Data': original},
        {
          'type': 'all',
          'source：cea': {'Data': original},
        },
      ]) {
        final event = JianCollectorFeed.decodeFrame(
          frame,
          receivedAt: now,
        ).single;
        expect(event.arrivedAt, now);
        expect(event.originTime, sourceEvent.originTime);
        expect(event.reportTime, sourceEvent.reportTime);
        expect(event.sourcePayload, original);
        final isFirst = collector.activeCount == 0;
        expect(collector.addEvent(event), isFirst);
      }
      expect(collector.activeCount, 1);
      expect(await collector.tick(finalize: false), isEmpty);
      now = now.add(const Duration(hours: 1));
      final saved = (await collector.tick()).single;
      final replay = HistoryReplayPackage.decode(
        await saved.readAsString(encoding: utf8),
      );
      expect(replay.reports.single.sourcePayload, original);
      expect(jsonEncode(original), originalJson);
      expect(replay.reports.single.arrivedAt, isNotNull);
      expect(collector.activeCount, 0);
    },
  );
}
