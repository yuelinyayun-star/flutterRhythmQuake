import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage_io.dart'
    as compression;

void main() {
  final original = Directory('build/performance/20261005-app-history-input');
  final recorded = Directory('D:/flutterApp/flutter-nied-regression/20261013-200318/station-history');
  final available = original.existsSync() || recorded.existsSync();
  late Map table;
  Map archive() => {
    'format': StationReplayFrames.format,
    'blocks': [
      StationReplayFrames.encodeBlock(
        table,
        compression.compress(JsonUtf8Encoder().convert(table)),
      ),
    ],
  };
  setUp(() {
    if (!available) return;
    if (!original.existsSync()) {
      for (final file in recorded.listSync().whereType<File>()) {
        final envelope = jsonDecode(file.readAsStringSync(encoding: utf8)) as Map;
        if ((envelope['key'] as String).contains('station_archive_nied_')) {
          table = StationArchiveStorage.decode(envelope['value'] as String);
          return;
        }
      }
      throw StateError('Recorded NIED archive is missing');
    }
    final files = original.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    table = jsonDecode(files.first.readAsStringSync(encoding: utf8)) as Map;
  });
  final skip = !available
      ? 'Requires retained original server checkpoint'
      : false;
  test('original live checkpoint is lossless and can be released', () {
    final frames = StationReplayFrames.decode(archive());
    final expected = StationJsonArchive.decode(table);
    expect(
      frames.entries.map((e) => e.receivedAt),
      orderedEquals(expected.map((e) => e.receivedAt)),
    );
    expect(
      frames.map((e) => jsonEncode(e.toMap())),
      orderedEquals(expected.map((e) => jsonEncode(e.toMap()))),
    );
    frames.release();
    expect(
      jsonEncode(frames.first.toMap()),
      jsonEncode(expected.first.toMap()),
    );
    expect(() => frames.length = 0, throwsUnsupportedError);
  }, skip: skip);
  test('display eviction cannot invalidate a slower inference reader', () {
    final rawFrame = StationJsonArchive.decode(table).first;
    final oneFrame = StationJsonArchive.encode([rawFrame]);
    final body = compression.compress(JsonUtf8Encoder().convert(oneFrame));
    final frames = StationReplayFrames.decode({
      'format': StationReplayFrames.format,
      'blocks': [
        for (var i = 0; i < 9; i++)
          StationReplayFrames.encodeBlock(oneFrame, body),
      ],
    });
    final reader = StationReplayReadCursor();
    addTearDown(reader.dispose);
    final retained = reader.load(frames.entries.first);
    for (final entry in frames.entries) {
      entry.load();
    }
    expect(reader.load(frames.entries.first), same(retained));
    expect(reader.decodedBlocks, 1);
    expect(retained.toMap(), rawFrame.toMap());
    for (final entry in frames.entries) {
      reader.load(entry);
    }
    expect(reader.cachedBlocks, lessThanOrEqualTo(7));
    reader.dispose();
    expect(reader.cachedBlocks, 0);
  }, skip: skip);
  test('off-thread block load is lossless and shares the completed graph', () async {
    final frames = StationReplayFrames.decode(archive());
    final entry = frames.entries.first;
    expect(entry.cachedFrame, isNull);
    final first = entry.loadAsync();
    final second = entry.loadAsync();
    final frame = await first;
    expect(await second, same(frame));
    expect(frame.toMap(), StationJsonArchive.decode(table).first.toMap());
    final reader = StationReplayReadCursor();
    addTearDown(reader.dispose);
    expect(await reader.loadAsync(entry), same(frame));
    frames.release();
    expect(entry.cachedFrame, isNull);
    expect(await reader.loadAsync(entry), same(frame));
  }, skip: skip);

  test('release during block decode does not repopulate the released cache', () async {
    final frames = StationReplayFrames.decode(archive());
    final entry = frames.entries.first;
    final pending = entry.loadAsync();
    frames.release();
    expect((await pending).receivedAt, entry.receivedAt);
    expect(entry.cachedFrame, isNull);
  }, skip: skip);
  test('damaged compressed body fails before returning a frame', () {
    final value = archive();
    value['blocks'][0]['data'] = base64.encode([0]);
    expect(
      () => StationReplayFrames.decode(value).first,
      throwsFormatException,
    );
  }, skip: skip);
  test('altered index cannot silently shift station replay time', () {
    final value = archive();
    value['blocks'][0]['frames'][0][0] = '2026-10-05T00:00:00.000000Z';
    expect(
      () => StationReplayFrames.decode(value).first,
      throwsFormatException,
    );
  }, skip: skip);
}
