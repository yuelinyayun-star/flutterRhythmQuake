import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/eew_event_group.dart';
import '../debug/history_replay.dart';
import '../debug/station_replay_blocks.dart';
import '../debug/station_archive_storage_io.dart' as compression;

/// Returns a durable temporary path and digest, never a second whole-file string.
Future<(String, String, int)> exportCaptureFile(
  (String, String) request,
) async {
  final (path, temporaryPath) = request;
  final manifest =
      jsonDecode(await File('$path/event.json').readAsString()) as Map;
  final group = EewEventGroup.fromMap(
    manifest['group'] as Map,
  ).copyWith(captureEndedAt: DateTime.parse(manifest['end'] as String));
  final legacy = await Directory(path)
      .list(followLinks: false)
      .where((e) => e is File && e.path.endsWith('.stations.json'))
      .cast<File>()
      .toList();
  legacy.sort((a, b) => a.path.compareTo(b.path));
  final shared = (manifest['chunks'] as List? ?? const []).cast<String>();
  final chunks = [
    ...legacy,
    for (final name in shared)
      File('${Directory(path).parent.path}/chunks/${validateChunkName(name)}'),
  ];
  final replay = HistoryReplayPackage.fromGroup(
    group,
    hasArchivedStations: chunks.isNotEmpty,
  );
  final destination = File(temporaryPath);
  await destination.parent.create(recursive: true);
  final handle = destination.openSync(mode: FileMode.write);
  final sink = _ReplayBytes(handle);
  var complete = false;
  try {
    final metadata = jsonEncode(replay.exportMetadata());
    sink.add(utf8.encode(metadata.substring(0, metadata.length - 1)));
    if (chunks.isNotEmpty) {
      sink.add(
        utf8.encode(
          ',"stationArchive":{"format":${jsonEncode(StationReplayFrames.format)},"blocks":[',
        ),
      );
    }
    var first = true;
    for (final chunk in chunks) {
      if (await chunk.length() > HistoryReplayPackage.maxBytes) {
        throw const FormatException('Station chunk exceeds size limit');
      }
      final bytes = await chunk.readAsBytes();
      final compressed = chunk.path.endsWith('.gz')
          ? bytes
          : compression.compress(bytes);
      final table =
          jsonDecode(
                utf8.decode(
                  chunk.path.endsWith('.gz')
                      ? compression.expand(bytes, HistoryReplayPackage.maxBytes)
                      : bytes,
                ),
              )
              as Map;
      final block = StationReplayFrames.encodeBlock(table, compressed);
      for (final item in block['frames'] as List) {
        if (DateTime.parse(
              item[0] as String,
            ).difference(replay.times.first).abs() >
            HistoryReplayPackage.maxDuration) {
          throw const FormatException('Invalid station replay time span');
        }
      }
      if (!first) sink.add(const [44]);
      sink.add(JsonUtf8Encoder().convert(block));
      first = false;
    }
    if (chunks.isNotEmpty) sink.add(utf8.encode(']}'));
    sink.add(const [125]);
    sink.close();
    handle.flushSync();
    complete = true;
    return (destination.path, sink.digest.toString(), sink.length);
  } finally {
    handle.closeSync();
    if (!complete && destination.existsSync()) destination.deleteSync();
  }
}

String validateChunkName(String name) {
  if (!RegExp(r'^\d+_[a-f0-9]{64}\.stations\.json\.gz$').hasMatch(name)) {
    throw const FormatException('Invalid shared station chunk name');
  }
  return name;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _ReplayBytes implements Sink<List<int>> {
  _ReplayBytes(this.handle) {
    hashing = sha256.startChunkedConversion(result);
  }
  final RandomAccessFile handle;
  final _DigestSink result = _DigestSink();
  late final ByteConversionSink hashing;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int length = 0;
  Digest get digest => result.value!;
  @override
  void add(List<int> bytes) {
    length += bytes.length;
    if (length > HistoryReplayPackage.maxBytes) {
      throw const FormatException('Replay exceeds 128 MiB; capture retained');
    }
    _buffer.add(bytes);
    if (_buffer.length >= 64 * 1024) _flush();
  }

  @override
  void close() {
    _flush();
    hashing.close();
  }

  void _flush() {
    if (_buffer.isEmpty) return;
    final bytes = _buffer.takeBytes();
    handle.writeFromSync(bytes);
    hashing.add(bytes);
  }
}
