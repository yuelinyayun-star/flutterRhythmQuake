import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/whews_nied_station_metadata.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';

import 'support/nied_replay_fixture.dart';

// Retain the original v1 encoder as a byte-for-byte compatibility reference.
Map<String, dynamic> referenceArchive(Iterable<StationHistoryFrame> frames) {
  final nodes = <dynamic>[];
  final indices = <String, int>{};
  int intern(dynamic value) {
    final dynamic node;
    if (value is Map) {
      node = [
        'm',
        for (final entry in value.entries) ...[
          intern(entry.key as String),
          intern(entry.value),
        ],
      ];
    } else if (value is List) {
      node = ['l', for (final item in value) intern(item)];
    } else {
      node = value;
    }
    final key = jsonEncode(node);
    final previous = indices[key];
    if (previous != null) return previous;
    final index = nodes.length;
    nodes.add(node);
    indices[key] = index;
    return index;
  }

  final roots = [for (final frame in frames) intern(frame.toMap())];
  return {'format': StationJsonArchive.format, 'nodes': nodes, 'frames': roots};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captured station archive remains byte-compatible and lossless', () async {
    final metadata =
        jsonDecode(
              File('test/fixtures/whews_nied/stations.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final observations =
        jsonDecode(
              File(
                'test/fixtures/whews_nied/observations.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final before = jsonEncode([metadata, observations]);
    final service = WhewsStationService(
      kind: WhewsStationKind.nied,
      apiToken: '',
    );
    addTearDown(service.dispose);
    final accepted = service.frameStream.first;
    service.handleMessageForTesting(metadata);
    service.handleMessageForTesting(observations);
    final networkFrame = await accepted;
    final stations = buildWhewsNiedStations(networkFrame.coordinates);
    for (var i = 0; i < stations.length; i++) {
      final value = networkFrame.values[i];
      stations[i].updateFromContinuousShindo(
        whewsNiedSnetValueIsValid(value) ? value : null,
      );
    }
    final snapshot = ForegroundStationPayload.nied(
      stations,
      source: 'whews',
      includeTrackingHistory: false,
    );
    final frame = StationHistoryFrame(
      receivedAt: DateTime.parse('2026-09-08T10:47:23.899674Z'),
      snapshot: snapshot,
      originalJson: networkFrame.originalJson,
    );
    // Repeated immutable input exercises sharing without inventing observations.
    final frames = List<StationHistoryFrame>.filled(30, frame);
    final referenceWatch = Stopwatch()..start();
    final reference = jsonEncode(referenceArchive(frames));
    referenceWatch.stop();
    final encodeWatch = Stopwatch()..start();
    final encoded = jsonEncode(StationJsonArchive.encode(frames));
    encodeWatch.stop();
    expect(encoded, reference);
    final decodeWatch = Stopwatch()..start();
    final restored = StationJsonArchive.decode(jsonDecode(encoded) as Map);
    decodeWatch.stop();
    expect(restored.map((f) => f.toMap()), frames.map((f) => f.toMap()));
    expect(
      identical(
        restored.first.snapshot['stations'],
        restored.last.snapshot['stations'],
      ),
      isTrue,
      reason: 'Repeated immutable station arrays are not copied',
    );
    final decodedStations = restored.first.snapshot['stations'] as List;
    expect(() => decodedStations.clear(), throwsUnsupportedError);
    expect(() => decodedStations[0] = null, throwsUnsupportedError);
    expect(
      () => (decodedStations.first as Map).clear(),
      throwsUnsupportedError,
    );
    final decodedMetadata = restored.first.originalJson!['metadata'] as Map;
    final coordinates = decodedMetadata['stations'] as List;
    expect(() => coordinates.clear(), throwsUnsupportedError);
    expect(() => (coordinates.first as Map).clear(), throwsUnsupportedError);
    expect(jsonEncode([metadata, observations]), before);
    final display = ForegroundStationPayload.decodeNied(
      restored.last.snapshot['stations'],
    );
    expect(
      ForegroundStationPayload.nied(
        display,
        source: 'whews',
        includeTrackingHistory: false,
      ),
      snapshot,
    );
    if (const bool.fromEnvironment('STATION_ARCHIVE_BENCHMARK')) {
      debugPrint(
        'STATION_ARCHIVE: frames=${frames.length}, stations=${stations.length}, '
        'bytes=${utf8.encode(encoded).length}, '
        'referenceEncodeUs=${referenceWatch.elapsedMicroseconds}, '
        'encodeUs=${encodeWatch.elapsedMicroseconds}, '
        'decodeUs=${decodeWatch.elapsedMicroseconds}',
      );
    }
  });

  test('immutable list reuse still isolates mutable source arrays', () {
    final metadata =
        jsonDecode(
              File('test/fixtures/whews_nied/stations.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final before = jsonEncode(metadata);
    final snapshot = snapshotSourcePayload(metadata);
    final coordinates = snapshot['stations'] as List;
    final reused = snapshotSourcePayload({'stations': coordinates});
    expect(identical(reused['stations'], coordinates), isTrue);
    final mutable = metadata['stations'] as List;
    (mutable.first as Map).clear();
    mutable.clear();
    expect(jsonEncode(snapshot), before);
    expect(() => coordinates.add(null), throwsUnsupportedError);
    expect(() => coordinates.sort((a, b) => 0), throwsUnsupportedError);
    expect(() => coordinates.length = 0, throwsUnsupportedError);
    expect(
      () => (coordinates.first as Map)['latitude'] = null,
      throwsUnsupportedError,
    );
  });

  test(
    'unmodified consecutive GIF frames retain every station and timestamp',
    () async {
      final files =
          Directory('test/fixtures/nied_recovery')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.gif'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(18));
      final service = LmoniImageService()..start();
      addTearDown(service.stop);
      final frames = <StationHistoryFrame>[];
      for (final file in files) {
        final key = file.uri.pathSegments.last.substring(0, 14);
        final stamp = DateTime(
          int.parse(key.substring(0, 4)),
          int.parse(key.substring(4, 6)),
          int.parse(key.substring(6, 8)),
          int.parse(key.substring(8, 10)),
          int.parse(key.substring(10, 12)),
          int.parse(key.substring(12, 14)),
        );
        final decoded = (await decodeNiedGifFile(file))!;
        final accepted = service.stationStream.firstWhere(
          (stations) => stations != null,
        );
        service.processPixels(
          decoded.packedRgb,
          dataTime: stamp,
          receivedAt: stamp,
        );
        final stations = (await accepted)!;
        frames.add(
          StationHistoryFrame(
            receivedAt: DateTime.utc(
              stamp.year,
              stamp.month,
              stamp.day,
              stamp.hour,
              stamp.minute,
              stamp.second,
            ).subtract(const Duration(hours: 9)),
            snapshot: ForegroundStationPayload.nied(
              stations,
              source: 'lmoni',
              includeTrackingHistory: false,
            ),
          ),
        );
      }
      final referenceWatch = Stopwatch()..start();
      final reference = jsonEncode(referenceArchive(frames));
      referenceWatch.stop();
      final encodeWatch = Stopwatch()..start();
      final encoded = jsonEncode(StationJsonArchive.encode(frames));
      encodeWatch.stop();
      expect(encoded, reference);
      final restored = StationJsonArchive.decode(jsonDecode(encoded) as Map);
      expect(restored.map((f) => f.toMap()), frames.map((f) => f.toMap()));
      for (final frame in restored) {
        final stations = ForegroundStationPayload.decodeNied(
          frame.snapshot['stations'],
        );
        expect(stations, hasLength(1630));
        expect(
          ForegroundStationPayload.nied(
            stations,
            source: 'lmoni',
            includeTrackingHistory: false,
          ),
          frame.snapshot,
        );
      }
      if (const bool.fromEnvironment('STATION_ARCHIVE_BENCHMARK')) {
        debugPrint(
          'STATION_GIF_ARCHIVE: frames=${frames.length}, stations=1630, '
          'bytes=${utf8.encode(encoded).length}, '
          'referenceEncodeUs=${referenceWatch.elapsedMicroseconds}, '
          'encodeUs=${encodeWatch.elapsedMicroseconds}',
        );
      }
    },
  );
}
