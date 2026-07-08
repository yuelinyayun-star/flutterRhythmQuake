import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/replay_package.dart';
import 'package:flutterrhythmquake/core/replay/replay_versions.dart';

void main() {
  const packageDirectories = [
    'tmp/captures/20260610_180130_jst_nara_m36',
    'tmp/captures/20260614_175604_jst_window41',
    'tmp/captures/20260620_115047_jst_satsuma_m26_d179',
    'tmp/captures/20260620_141903_jst_kyoto_s_m18_d12',
    'tmp/captures/20260620_184442_jst_ibaraki_offshore_m19_ref',
    'tmp/captures/20260620_212527_jst_iwate_offshore_m34_ref',
  ];

  test('all replay packages are structurally complete', () {
    for (final path in packageDirectories) {
      final packageDirectory = Directory(path);
      final manifest = ReplayPackageManifest.fromJson(
        _readJson(File('${packageDirectory.path}/manifest.json')),
      );
      final frameIndex = ReplayFrameIndex.fromJson(
        _readJson(File('${packageDirectory.path}/frames/index.json')),
      );

      expect(manifest.validate(), isEmpty, reason: path);
      expect(frameIndex.validateAgainst(manifest), isEmpty, reason: path);

      for (final frame in frameIndex.frames) {
        expect(
          frame.layers.keys.toSet(),
          manifest.layers.toSet(),
          reason: '$path:${frame.observedAt}',
        );
        for (final layer in frame.layers.values) {
          if (!layer.available) continue;
          final file = File('${packageDirectory.path}/${layer.path}');
          expect(file.existsSync(), isTrue, reason: file.path);
          expect(file.lengthSync(), layer.bytes, reason: file.path);
        }
      }
    }
  });

  test('Ibaraki replay package is structurally complete', () {
    final packageDirectory = Directory(
      'tmp/captures/20260620_184442_jst_ibaraki_offshore_m19_ref',
    );
    final manifest = ReplayPackageManifest.fromJson(
      _readJson(File('${packageDirectory.path}/manifest.json')),
    );
    final frameIndex = ReplayFrameIndex.fromJson(
      _readJson(File('${packageDirectory.path}/frames/index.json')),
    );

    expect(manifest.validate(), isEmpty);
    expect(frameIndex.validateAgainst(manifest), isEmpty);
    expect(manifest.decoderVersion, ReplayDataVersions.niedGifDecoder);
    expect(manifest.stationDbVersion, ReplayDataVersions.niedStationDb);
    expect(manifest.expectedTimestampCount, 151);
    expect(manifest.missingFrames, isEmpty);
    expect(frameIndex.frames, hasLength(151));

    for (final frame in frameIndex.frames) {
      expect(frame.layers.keys, containsAll(['jma_s', 'jma_b']));
      for (final layer in frame.layers.values) {
        expect(layer.available, isTrue);
        expect(layer.qualityFlags, isEmpty);
        final file = File('${packageDirectory.path}/${layer.path}');
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(file.lengthSync(), layer.bytes);
      }
    }

    final stations = _readJson(File('${packageDirectory.path}/stations.json'));
    expect(stations['stationDbVersion'], ReplayDataVersions.niedStationDb);
    expect(
      stations['stations'],
      isA<List<Object?>>().having(
        (value) => value.length,
        'station count',
        1749,
      ),
    );

    final truth = _readJson(File('${packageDirectory.path}/truth.json'));
    expect(truth['status'], 'reference_only');
    expect(truth['agency'], 'EQuake');
    expect(truth['eventId'], isNull);
    expect(
      (truth['eventLabels']! as Map<String, Object?>)['catalogTruthVerified'],
      isFalse,
    );
  });

  test('manifest rejects unsafe and inconsistent structure', () {
    final manifest = ReplayPackageManifest.fromJson({
      'schemaVersion': 1,
      'packageId': 'bad',
      'caseType': 'event',
      'timeZone': 'Asia/Tokyo',
      'startTime': '2026-06-20T18:44:12+09:00',
      'endTime': '2026-06-20T18:44:14+09:00',
      'expectedFrameIntervalMs': 1000,
      'expectedTimestampCount': 2,
      'decoderVersion': ReplayDataVersions.niedGifDecoder,
      'stationDbVersion': ReplayDataVersions.niedStationDb,
      'sensorSelectionPolicy': 'test',
      'rawLayout': 'flat_capture_v1',
      'frameIndexPath': '../frames.json',
      'stationSnapshotPath': 'stations.json',
      'truthPath': null,
      'layers': ['jma_s'],
      'missingFrames': <Object?>[],
      'sourceUrlTemplates': {'jma_s': 'https://example.invalid/{stamp}'},
      'provenance': <String, Object?>{},
    });

    expect(
      manifest.validate(),
      containsAll([
        'expected_timestamp_count_mismatch',
        'missing_event_truth_path',
        'unsafe_path:../frames.json',
      ]),
    );
  });

  test('frame index preserves live receipt provenance', () {
    final manifest = ReplayPackageManifest.fromJson({
      'schemaVersion': 1,
      'packageId': 'live',
      'caseType': 'noise',
      'timeZone': 'Asia/Tokyo',
      'startTime': '2026-06-20T18:44:12+09:00',
      'endTime': '2026-06-20T18:44:13+09:00',
      'expectedFrameIntervalMs': 1000,
      'expectedTimestampCount': 2,
      'decoderVersion': ReplayDataVersions.niedGifDecoder,
      'stationDbVersion': ReplayDataVersions.niedStationDb,
      'sensorSelectionPolicy': 'test',
      'rawLayout': 'flat_capture_v1',
      'frameIndexPath': 'frames/index.json',
      'stationSnapshotPath': 'stations.json',
      'truthPath': null,
      'layers': ['jma_s'],
      'missingFrames': <Object?>[],
      'sourceUrlTemplates': {'jma_s': 'https://example.invalid/{stamp}'},
      'provenance': {
        'captureMode': 'live',
        'receivedAtStatus': 'observed_live_fetch_completion',
      },
    });
    final frameIndex = ReplayFrameIndex.fromJson({
      'schemaVersion': 1,
      'packageId': 'live',
      'frames': [
        {
          'observedAt': '2026-06-20T18:44:12+09:00',
          'receivedAt': '2026-06-20T09:44:15.200Z',
          'layers': {
            'jma_s': {
              'available': true,
              'path': '20260620184412.jma_s.gif',
              'bytes': 123,
              'sha256': 'abc',
              'sourceUrl': 'https://example.invalid/frame.gif',
              'requestStartedAt': '2026-06-20T09:44:15.000Z',
              'receivedAt': '2026-06-20T09:44:15.200Z',
              'retrievedAt': '2026-06-20T09:44:15.200Z',
              'retrievalDurationMs': 200,
              'receiveDelayMs': 3200,
              'attempts': 2,
              'qualityFlags': ['clock_unsynchronized'],
            },
          },
        },
        {
          'observedAt': '2026-06-20T18:44:13+09:00',
          'receivedAt': '2026-06-20T09:44:16.100Z',
          'layers': {
            'jma_s': {
              'available': true,
              'path': '20260620184413.jma_s.gif',
              'bytes': 124,
              'sha256': 'def',
              'sourceUrl': 'https://example.invalid/frame.gif',
              'requestStartedAt': '2026-06-20T09:44:16.000Z',
              'receivedAt': '2026-06-20T09:44:16.100Z',
              'retrievedAt': '2026-06-20T09:44:16.100Z',
              'retrievalDurationMs': 100,
              'receiveDelayMs': 3100,
              'attempts': 1,
              'qualityFlags': ['clock_unsynchronized'],
            },
          },
        },
      ],
    });

    expect(manifest.validate(), isEmpty);
    expect(frameIndex.validateAgainst(manifest), isEmpty);
    expect(frameIndex.frames.first.receivedAt, isNotNull);
    expect(frameIndex.frames.first.layers['jma_s']!.receiveDelayMs, 3200);
    expect(frameIndex.frames.first.layers['jma_s']!.attempts, 2);
  });

  test('frame index rejects incomplete available layer', () {
    final manifest = ReplayPackageManifest.fromJson({
      'schemaVersion': 1,
      'packageId': 'bad-layer',
      'caseType': 'noise',
      'timeZone': 'Asia/Tokyo',
      'startTime': '2026-06-20T18:44:12+09:00',
      'endTime': '2026-06-20T18:44:13+09:00',
      'expectedFrameIntervalMs': 1000,
      'expectedTimestampCount': 2,
      'decoderVersion': ReplayDataVersions.niedGifDecoder,
      'stationDbVersion': ReplayDataVersions.niedStationDb,
      'sensorSelectionPolicy': 'test',
      'rawLayout': 'flat_capture_v1',
      'frameIndexPath': 'frames/index.json',
      'stationSnapshotPath': 'stations.json',
      'truthPath': null,
      'layers': ['jma_s'],
      'missingFrames': <Object?>[],
      'sourceUrlTemplates': {'jma_s': 'https://example.invalid/{stamp}'},
      'provenance': <String, Object?>{},
    });
    final frameIndex = ReplayFrameIndex.fromJson({
      'schemaVersion': 1,
      'packageId': 'bad-layer',
      'frames': [
        {
          'observedAt': '2026-06-20T18:44:12+09:00',
          'receivedAt': null,
          'layers': {
            'jma_s': {
              'available': true,
              'path': '../unsafe.gif',
              'bytes': 0,
              'sha256': null,
              'sourceUrl': null,
              'requestStartedAt': null,
              'receivedAt': null,
              'retrievedAt': null,
              'retrievalDurationMs': null,
              'receiveDelayMs': null,
              'attempts': null,
              'qualityFlags': <Object?>[],
            },
          },
        },
        {
          'observedAt': '2026-06-20T18:44:13+09:00',
          'receivedAt': null,
          'layers': {
            'jma_s': {
              'available': false,
              'path': null,
              'bytes': null,
              'sha256': null,
              'sourceUrl': null,
              'requestStartedAt': null,
              'receivedAt': null,
              'retrievedAt': null,
              'retrievalDurationMs': null,
              'receiveDelayMs': null,
              'attempts': null,
              'qualityFlags': ['missing'],
            },
          },
        },
      ],
    });

    final issues = frameIndex.validateAgainst(manifest);
    expect(issues, contains(startsWith('incomplete_available_layer:')));
    expect(issues, contains(startsWith('unsafe_layer_path:')));
  });
}

Map<String, Object?> _readJson(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}
