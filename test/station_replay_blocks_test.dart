import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage_io.dart'
    as compression;

void main() {
  final original = Directory('build/performance/20261005-app-history-input');
  final available = original.existsSync();
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
