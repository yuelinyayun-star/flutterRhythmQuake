import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/background_station_history_recorder.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/history_storage_io.dart';

Future<List<StationHistoryFrame>> _hydrate(dynamic frames) async => [
  for (final entry in StationReplayFrames.describe(
    frames as List<StationHistoryFrame>,
  ))
    await entry.loadAsync(),
];

const String _preferenceKey = 'unified_eew_history_recorder_test';

UnifiedQuakeData _eewEvent(String eventId, {int reportNum = 1}) {
  final now = DateTime.now().toUtc();
  return UnifiedQuakeData(
    source: 'jmaEew',
    origin: 1,
    eventId: eventId,
    isEew: true,
    timeZone: 0,
    titleText: '紧急地震速报',
    reportNumText: '第$reportNum报',
    useShindo: true,
    maxIntensity: '5-',
    className: 'orange',
    hypocenter: '测试区域',
    originTime: now.subtract(const Duration(minutes: 1)),
    reportTime: now,
    magnitude: 5,
    depth: 10,
    depthText: '深度: 10km',
    lat: 30,
    lng: 120,
  );
}

Map<String, dynamic> _frameMap(
  String kind,
  DateTime receivedAt, {
  Map<String, dynamic>? detection,
}) => {
  'receivedAt': receivedAt.toUtc().toIso8601String(),
  'snapshot': {
    'kind': kind,
    'stations': [
      {'id': 's1', 'level': 2},
    ],
    if (detection != null) 'detection': detection,
  },
  'originalJson': {'raw': kind},
};

const _detection = {
  'stage': 'detected',
  'weakCount': 1,
  'detectedCount': 2,
  'strongCount': 0,
  'maxShindo': 3,
  'gridCells': <String, dynamic>{},
  'detectedStations': <Map<String, dynamic>>[
    {
      'code': 's1',
      'prefecture': '奈良',
      'detectReason': 'auto',
      'level': 2,
      'jmaShindo': 2,
      'detectState': 1,
    },
  ],
};

Future<
  (
    Directory,
    EewHistoryStore,
    BackgroundStationHistoryRecorder,
    List<List<Map<String, dynamic>>> ended,
  )
>
_recorderFixture(SharedPreferences prefs, DateTime Function()? clock) async {
  final temp = await Directory.systemTemp.createTemp('rq-recorder-test');
  final storage = DirectoryHistoryStorage('${temp.path}/replay_history/v3');
  final store = EewHistoryStore(
    preferenceKey: _preferenceKey,
    storage: storage,
  );
  final ended = <List<Map<String, dynamic>>>[];
  final recorder = BackgroundStationHistoryRecorder(
    preferenceKey: _preferenceKey,
    onRecordingEnded: ended.add,
    store: store,
    clock: clock,
  );
  return (temp, store, recorder, ended);
}

Future<Directory> _deleteLater(Directory temp) async {
  addTearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });
  return temp;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recorder persists forwarded UI frames, dedups and finalizes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final (temp, _, recorder, ended) = await _recorderFixture(prefs, null);
    await _deleteLater(temp);

    final event = _eewEvent('rec-e2e');
    final seedKey = EewHistoryStore.recordKeyFor(
      _preferenceKey,
      event.source,
      event.eventId,
    );
    await recorder.setRecording(
      true,
      groups: [
        {
          'recordKey': seedKey,
          'firstArrivedAt': DateTime.now().toUtc().toIso8601String(),
          'latest': event.toMap(),
        },
      ],
      enabledKinds: ['nied'],
      preferences: prefs,
    );

    final base = DateTime.now().toUtc();
    await recorder.acceptUiFrame(
      _frameMap('nied', base, detection: _detection),
    );
    await recorder.acceptUiFrame(
      _frameMap('nied', base.add(const Duration(seconds: 1))),
    );
    // 重复帧必须去重。
    await recorder.acceptUiFrame(_frameMap('nied', base));
    await recorder.setRecording(false, preferences: prefs);

    expect(ended, hasLength(1));
    expect(ended.single, hasLength(1));
    final frameKeys = (ended.single.single['frameKeys'] as List).cast<String>();
    expect(frameKeys, hasLength(2));
    expect(ended.single.single['key'], seedKey);

    // UI isolate 侧（同一磁盘目录）必须能完整恢复。
    final uiStore = EewHistoryStore(
      preferenceKey: _preferenceKey,
      storage: DirectoryHistoryStorage('${temp.path}/replay_history/v3'),
    );
    final restored = await uiStore.restoreForStartup(
      prefs,
      lazyReports: true,
      migrateLegacy: false,
    );
    expect(restored, hasLength(1));
    expect(uiStore.recordKey(restored.single), seedKey);
    expect(
      restored.single.storedStations!.frameKeys.toSet(),
      frameKeys.toSet(),
    );

    final hydrated = await uiStore.loadStationFrames(restored.single);
    final frames = await _hydrate(hydrated.stationFrames);
    expect(frames, hasLength(2));
    expect(
      frames.map((frame) => (frame as dynamic).kind),
      everyElement('nied'),
    );
    expect(
      frames.map((frame) => (frame as dynamic).snapshot['detection']?['stage']),
      contains('detected'),
    );
    expect(
      frames.map(
        (frame) => ((frame as dynamic).originalJson?['raw'] as String?) ?? '',
      ),
      everyElement('nied'),
    );
  });

  test(
    'background payloads take over once UI forwarding goes silent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime.utc(2026, 1, 1, 12);
      final (temp, _, recorder, ended) = await _recorderFixture(
        prefs,
        () => now,
      );
      await _deleteLater(temp);

      final event = _eewEvent('rec-fallback');
      await recorder.setRecording(
        true,
        groups: [
          {
            'recordKey': EewHistoryStore.recordKeyFor(
              _preferenceKey,
              event.source,
              event.eventId,
            ),
            'firstArrivedAt': now.toIso8601String(),
            'latest': event.toMap(),
          },
        ],
        enabledKinds: ['nied', 'kma'],
        preferences: prefs,
      );

      await recorder.acceptUiFrame(_frameMap('nied', now));
      // UI 帧仍然新鲜：后台 payload 不应重复写入。
      now = now.add(const Duration(seconds: 1));
      recorder.observeStationPayload({
        'kind': 'nied',
        'stations': <Map<String, dynamic>>[],
      });
      // UI 引擎死亡 4 秒后，后台 payload 兜底录制。
      now = now.add(const Duration(seconds: 6));
      recorder.observeStationPayload({
        'kind': 'nied',
        'stations': <Map<String, dynamic>>[
          {'id': 'fallback', 'level': 3},
        ],
        'originalJson': {'raw': 'fallback'},
      });
      now = now.add(const Duration(seconds: 1));
      recorder.observeStationPayload({
        'kind': 'kma',
        'stations': <Map<String, dynamic>>[
          {'id': 'kma1', 'level': 1},
        ],
      });
      // 未启用的 kind 不应落盘。
      recorder.observeStationPayload({
        'kind': 'snet',
        'stations': <Map<String, dynamic>>[],
      });

      await recorder.setRecording(false, preferences: prefs);
      expect(ended, hasLength(1));
      final records = {
        for (final record in ended.single)
          record['key'] as String: (record['frameKeys'] as List).cast<String>(),
      };
      expect(records, hasLength(1));
      expect(records.values.single, hasLength(3));

      final uiStore = EewHistoryStore(
        preferenceKey: _preferenceKey,
        storage: DirectoryHistoryStorage('${temp.path}/replay_history/v3'),
      );
      final restored = await uiStore.restoreForStartup(
        prefs,
        lazyReports: true,
        migrateLegacy: false,
      );
      final hydrated = await uiStore.loadStationFrames(restored.single);
      final frames = await _hydrate(hydrated.stationFrames);
      final kinds = frames.map((frame) => (frame as dynamic).kind).toSet();
      expect(kinds, {'nied', 'kma'});
      final fallback = frames.firstWhere(
        (frame) => ((frame as dynamic).snapshot['stations'] as List).any(
          (station) => station is Map && station['id'] == 'fallback',
        ),
      );
      expect((fallback as dynamic).originalJson?['raw'], 'fallback');
    },
  );

  test('UI adopt plus save keeps background frames on disk', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final (temp, _, recorder, ended) = await _recorderFixture(prefs, null);
    await _deleteLater(temp);

    final event = _eewEvent('rec-reconcile');
    final recordKey = EewHistoryStore.recordKeyFor(
      _preferenceKey,
      event.source,
      event.eventId,
    );
    await recorder.setRecording(
      true,
      groups: [
        {
          'recordKey': recordKey,
          'firstArrivedAt': DateTime.now().toUtc().toIso8601String(),
          'latest': event.toMap(),
        },
      ],
      enabledKinds: ['nied'],
      preferences: prefs,
    );
    final base = DateTime.now().toUtc();
    await recorder.acceptUiFrame(_frameMap('nied', base));
    await recorder.acceptUiFrame(
      _frameMap('nied', base.add(const Duration(seconds: 1))),
    );
    await recorder.setRecording(false, preferences: prefs);
    final backgroundKeys = (ended.single.single['frameKeys'] as List)
        .cast<String>();

    // UI 侧恢复 + 对账合并 + 本地持久化，之后磁盘不得丢失后台帧。
    final uiStore = EewHistoryStore(
      preferenceKey: _preferenceKey,
      storage: DirectoryHistoryStorage('${temp.path}/replay_history/v3'),
    );
    final groups = await uiStore.restoreForStartup(
      prefs,
      lazyReports: true,
      migrateLegacy: false,
    );
    expect(groups, hasLength(1));
    final index = groups.indexWhere(
      (group) => uiStore.recordKey(group) == recordKey,
    );
    final adopted = uiStore.adoptStoredFrameKeys(
      recordKey,
      groups[index],
      backgroundKeys,
    );
    await uiStore.save(prefs, [adopted]);

    final verifyStore = EewHistoryStore(
      preferenceKey: _preferenceKey,
      storage: DirectoryHistoryStorage('${temp.path}/replay_history/v3'),
    );
    final reRestored = await verifyStore.restoreForStartup(
      prefs,
      lazyReports: true,
      migrateLegacy: false,
    );
    expect(reRestored, hasLength(1));
    final refs = reRestored.single.storedStations!;
    expect(refs.frameKeys.toSet(), containsAll(backgroundKeys));
    expect(refs.frameKeys.toSet(), backgroundKeys.toSet());
    final hydrated = await verifyStore.loadStationFrames(reRestored.single);
    expect(await _hydrate(hydrated.stationFrames), hasLength(2));

    // 未知记录可从磁盘恢复。
    final diskRecord = await uiStore.restoreRecordFromDisk(recordKey);
    expect(diskRecord, isNotNull);
    expect(
      diskRecord!.storedStations!.frameKeys.toSet(),
      refs.frameKeys.toSet(),
    );
  });

  test('a second recording window extends the same record', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final (temp, _, recorder, ended) = await _recorderFixture(prefs, null);
    await _deleteLater(temp);

    final event = _eewEvent('rec-window');
    final seed = {
      'recordKey': EewHistoryStore.recordKeyFor(
        _preferenceKey,
        event.source,
        event.eventId,
      ),
      'firstArrivedAt': DateTime.now().toUtc().toIso8601String(),
      'latest': event.toMap(),
    };
    await recorder.setRecording(true, groups: [seed], preferences: prefs);
    final base = DateTime.now().toUtc();
    await recorder.acceptUiFrame(_frameMap('nied', base));
    await recorder.setRecording(false, preferences: prefs);
    await recorder.setRecording(true, groups: [seed], preferences: prefs);
    await recorder.acceptUiFrame(
      _frameMap('nied', base.add(const Duration(seconds: 2))),
    );
    await recorder.setRecording(false, preferences: prefs);

    expect(ended, hasLength(2));
    final uiStore = EewHistoryStore(
      preferenceKey: _preferenceKey,
      storage: DirectoryHistoryStorage('${temp.path}/replay_history/v3'),
    );
    final restored = await uiStore.restoreForStartup(
      prefs,
      lazyReports: true,
      migrateLegacy: false,
    );
    expect(restored, hasLength(1));
    final hydrated = await uiStore.loadStationFrames(restored.single);
    expect(await _hydrate(hydrated.stationFrames), hasLength(2));
  });
}
