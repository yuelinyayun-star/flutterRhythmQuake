import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/widgets/ui/history_replay_file_io.dart'
    as replay_file;

import 'history_replay_test.dart' as recorded;

void main() {
  late Directory temp;
  late File file;
  late List<int> bytes;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rhythmquake-replay-file-');
    file = File('${temp.path}/saved.rqreplay');
    final package = HistoryReplayPackage.fromGroup(
      recorded.group([recorded.recordedEew()]),
    );
    bytes = utf8.encode(package.encode());
    await file.writeAsBytes(bytes);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('native reader preserves saved UTF-8 replay bytes', () async {
    final loaded = await replay_file.readBytes(
      file.path,
      maxBytes: HistoryReplayPackage.maxBytes,
    );
    expect(loaded, bytes);
    expect(
      HistoryReplayPackage.decode(utf8.decode(loaded)).reports.single.toMap(),
      HistoryReplayPackage.decode(utf8.decode(bytes)).reports.single.toMap(),
    );
  });

  test('native reader accepts a file exactly at the limit', () async {
    expect(
      await replay_file.readBytes(file.path, maxBytes: bytes.length),
      bytes,
    );
  });

  test('native reader rejects bytes exceeding the limit', () async {
    await expectLater(
      replay_file.readBytes(file.path, maxBytes: bytes.length - 1),
      throwsFormatException,
    );
  });

  test('native reader reports missing files', () async {
    await expectLater(
      replay_file.readBytes('${temp.path}/missing', maxBytes: bytes.length),
      throwsA(isA<FileSystemException>()),
    );
  });
}
