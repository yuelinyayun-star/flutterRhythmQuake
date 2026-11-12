import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../models/station_history_frame.dart';
import 'station_archive_storage.dart';
import 'station_json_archive.dart';
import 'native_station_replay_block.dart';
import 'station_archive_storage_web.dart'
    if (dart.library.io) 'station_archive_storage_io.dart'
    as compression;

class StationReplayEntry {
  final DateTime receivedAt;
  final String kind;
  final String? identity;
  final StationHistoryFrame Function() load;
  const StationReplayEntry(this.receivedAt, this.kind, this.identity, this.load)
    : _block = null,
      _index = 0,
      filePath = null,
      _fileLoad = null;

  StationReplayEntry.file(
    this.receivedAt,
    this.kind,
    this.identity, {
    required this.filePath,
    required Future<StationHistoryFrame> Function() load,
  }) : _fileLoad = load,
       _block = null,
       _index = 0,
       load = (() =>
           throw StateError('Read a station frame file asynchronously'));

  final String? filePath;
  final Future<StationHistoryFrame> Function()? _fileLoad;

  StationReplayEntry._archived(
    this.receivedAt,
    this.kind,
    this.identity,
    this.load,
    this._block,
    this._index,
  ) : filePath = null,
      _fileLoad = null;
  final _BlockCache? _block;
  final int _index;
  StationHistoryFrame? get cachedFrame => _fileLoad != null
      ? null
      : (_block == null || _block._frames != null ? load() : null);

  Future<StationHistoryFrame> loadAsync() async {
    if (_fileLoad != null) {
      return _fileLoad();
    }
    final block = _block;
    if (block == null) {
      return load();
    }
    final frames = await block.loadAsync();
    return block._frames == null ? frames[_index] : load();
  }
}

/// A second cursor must not evict blocks still used by the first cursor. Only
/// compressed originals are shared; decoded blocks have bounded reader owners.
class StationReplayReadCursor {
  final _copies = <_BlockCache, _BlockCache>{};
  final _current = <_BlockCache, int>{};
  int _generation = 0;
  int decodedBlocks = 0;
  int get cachedBlocks => _current.length;

  StationHistoryFrame load(StationReplayEntry entry) {
    final original = entry._block;
    if (original == null) {
      return entry.load();
    }
    final cache = _copies.putIfAbsent(
      original,
      () => _BlockCache(original.block)..lastReceipt = original.lastReceipt,
    );
    for (final old in _current.keys.toList()) {
      if (old.lastReceipt!.isBefore(entry.receivedAt)) {
        _current.remove(old);
        old.release();
      }
    }
    _current.remove(cache);
    if (cache._frames == null) {
      decodedBlocks++;
    }
    final frames = cache.load();
    _current[cache] = cache.expandedBytes;
    while (_current.length > 7 ||
        (_current.length > 1 &&
            _current.values.fold<int>(0, (a, b) => a + b) > 32 * 1024 * 1024)) {
      final oldest = _current.keys.first;
      _current.remove(oldest);
      oldest.release();
    }
    return frames[entry._index];
  }

  Future<StationHistoryFrame> loadAsync(StationReplayEntry entry) async {
    final original = entry._block;
    if (original == null) {
      return entry.loadAsync();
    }
    final generation = _generation;
    final cache = _copies.putIfAbsent(
      original,
      () => _BlockCache(original.block)..lastReceipt = original.lastReceipt,
    );
    for (final old in _current.keys.toList()) {
      if (old.lastReceipt!.isBefore(entry.receivedAt)) {
        _current.remove(old);
        old.release();
      }
    }
    _current.remove(cache);
    // Frames are immutable. Independent cache owners may retain the same
    // decoded graph; releasing one owner never mutates the other owner's data.
    if (cache._frames == null && original._frames != null) {
      cache._frames = original._frames;
      cache.expandedBytes = original.expandedBytes;
    }
    if (cache._frames == null) {
      decodedBlocks++;
    }
    final frames = await cache.loadAsync();
    if (generation == _generation) {
      _current[cache] = cache.expandedBytes;
      while (_current.length > 7 ||
          (_current.length > 1 &&
              _current.values.fold<int>(0, (a, b) => a + b) >
                  32 * 1024 * 1024)) {
        final oldest = _current.keys.first;
        _current.remove(oldest);
        oldest.release();
      }
    }
    return frames[entry._index];
  }

  void dispose() {
    _generation++;
    for (final cache in _copies.values) {
      cache.release();
    }
    _current.clear();
    _copies.clear();
  }
}

/// Only lightweight frame descriptors are retained; each block owns one cache.
class StationReplayFrames extends ListBase<StationHistoryFrame> {
  static const format = 'station-json-gzip-blocks-v1';
  final List<StationReplayEntry> entries;
  final Map? archive;
  final List<void Function()> _release;

  StationReplayFrames(
    this.entries, {
    this.archive,
    List<void Function()> release = const [],
  }) : _release = release;

  factory StationReplayFrames.decode(Map archive) {
    final blocks = archive['blocks'];
    if (archive['format'] != format ||
        blocks is! List ||
        blocks.length > 8192) {
      throw const FormatException('Invalid compressed station archive');
    }
    final entries = <StationReplayEntry>[];
    final caches = <_BlockCache>[];
    // Local archives interleave by source. Bound the current working set, and
    // release blocks whose last receipt is behind the playback cursor.
    final current = <_BlockCache, int>{};
    for (final value in blocks) {
      if (value is! Map ||
          value['data'] is! String ||
          value['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String) ||
          value['frames'] is! List) {
        throw const FormatException('Invalid compressed station block');
      }
      final cache = _BlockCache(value);
      caches.add(cache);
      final frames = value['frames'] as List;
      if (entries.length + frames.length > 1000000) {
        throw const FormatException('Too many station replay frames');
      }
      for (var i = 0; i < frames.length; i++) {
        final item = frames[i];
        if (item is! List ||
            item.length != 2 ||
            item[0] is! String ||
            !StationHistoryFrame.kinds.contains(item[1])) {
          throw const FormatException('Invalid station block index');
        }
        final receipt = DateTime.tryParse(item[0] as String);
        if (receipt == null || !receipt.isUtc) {
          throw const FormatException('Invalid station block time');
        }
        final index = i;
        if (cache.lastReceipt == null || receipt.isAfter(cache.lastReceipt!)) {
          cache.lastReceipt = receipt;
        }
        entries.add(
          StationReplayEntry._archived(
            receipt,
            item[1] as String,
            '${value['sha256']}:$index',
            () {
              for (final old in current.keys.toList()) {
                if (old.lastReceipt!.isBefore(receipt)) {
                  current.remove(old);
                  old.release();
                }
              }
              current.remove(cache);
              final decoded = cache.load();
              current[cache] = cache.expandedBytes;
              while (current.length > 7 ||
                  (current.length > 1 &&
                      current.values.fold<int>(0, (a, b) => a + b) >
                          32 * 1024 * 1024)) {
                final oldest = current.keys.first;
                current.remove(oldest);
                oldest.release();
              }
              return decoded[index];
            },
            cache,
            index,
          ),
        );
      }
    }
    entries.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return StationReplayFrames(
      entries,
      archive: archive,
      release: [
        () {
          for (final cache in caches) {
            cache.release();
          }
          current.clear();
        },
      ],
    );
  }

  static Iterable<StationReplayEntry> describe(
    List<StationHistoryFrame> frames,
  ) {
    if (frames is StationReplayFrames) {
      return frames.entries;
    }
    return frames.map(
      (frame) =>
          StationReplayEntry(frame.receivedAt, frame.kind, null, () => frame),
    );
  }

  static Map<String, dynamic> encodeBlock(Map table, List<int> compressed) => {
    'sha256': sha256.convert(compressed).toString(),
    'frames': indexTable(table),
    'data': base64.encode(compressed),
  };

  /// Read receipt and source directly from the original compact JSON table.
  static List<List<String>> indexTable(Map table) {
    if (table['format'] != StationJsonArchive.format ||
        table['nodes'] is! List ||
        table['frames'] is! List) {
      throw const FormatException('Invalid station JSON table');
    }
    final nodes = table['nodes'] as List;
    dynamic field(dynamic root, String name) {
      if (root is! int || root < 0 || root >= nodes.length) {
        throw const FormatException('Invalid station index reference');
      }
      final node = nodes[root];
      if (node is! List ||
          node.isEmpty ||
          node.first != 'm' ||
          !node.length.isOdd) {
        throw const FormatException('Invalid station index object');
      }
      dynamic result;
      var found = false;
      for (var i = 1; i < node.length; i += 2) {
        final key = node[i], value = node[i + 1];
        if (key is! int ||
            value is! int ||
            key < 0 ||
            value < 0 ||
            key >= root ||
            value >= root) {
          throw const FormatException('Invalid station index field');
        }
        if (nodes[key] == name) {
          if (found) {
            throw const FormatException('Duplicate station index field');
          }
          result = value;
          found = true;
        }
      }
      if (!found) {
        throw const FormatException('Missing station index field');
      }
      return result;
    }

    return [
      for (final root in table['frames'] as List)
        () {
          final time = nodes[field(root, 'receivedAt') as int];
          final kind = nodes[field(field(root, 'snapshot'), 'kind') as int];
          final receipt = time is String ? DateTime.tryParse(time) : null;
          if (receipt == null ||
              !receipt.isUtc ||
              !StationHistoryFrame.kinds.contains(kind)) {
            throw const FormatException('Invalid station frame index');
          }
          return [time as String, kind as String];
        }(),
    ];
  }

  void release() {
    for (final callback in _release) {
      callback();
    }
  }

  @override
  int get length => entries.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable station replay');
  @override
  StationHistoryFrame operator [](int index) => entries[index].load();
  @override
  void operator []=(int index, StationHistoryFrame value) =>
      throw UnsupportedError('Immutable station replay');
}

class _BlockCache {
  final Map block;
  List<StationHistoryFrame>? _frames;
  Future<List<StationHistoryFrame>>? _loading;
  int _generation = 0;
  DateTime? lastReceipt;
  int expandedBytes = 0;
  _BlockCache(this.block);
  void release() {
    _generation++;
    _frames = null;
    _loading = null;
  }

  List<StationHistoryFrame> load() {
    if (_frames != null) {
      return _frames!;
    }
    final result = _decodeStationReplayBlock(block);
    expandedBytes = result.$2;
    return _frames = result.$1;
  }

  Future<List<StationHistoryFrame>> loadAsync() {
    if (_frames != null) {
      return Future.value(_frames);
    }
    if (_loading != null) {
      return _loading!;
    }
    final generation = _generation;
    late final Future<List<StationHistoryFrame>> task;
    task =
        (NativeStationReplayBlock.supported
                ? NativeStationReplayBlock.decodeAsync(block)
                : compute(
                    _decodeStationReplayBlock,
                    block,
                    debugLabel: 'station-replay-block',
                  ))
            .then((result) {
              if (generation == _generation) {
                expandedBytes = result.$2;
                _frames = result.$1;
              }
              return result.$1;
            })
            .whenComplete(() {
              if (identical(_loading, task)) {
                _loading = null;
              }
            });
    return _loading = task;
  }
}

// compute uses Isolate.run on native platforms: the completed immutable graph
// is transferred with Isolate.exit, without another graph copy on the UI thread.
(List<StationHistoryFrame>, int) _decodeStationReplayBlock(Map block) {
  if (NativeStationReplayBlock.supported) {
    return NativeStationReplayBlock.decode(block);
  }
  final bytes = base64.decode(block['data'] as String);
  if (sha256.convert(bytes).toString() != block['sha256']) {
    throw const FormatException('Station block checksum mismatch');
  }
  final expanded = compression.expand(
    bytes,
    StationArchiveStorage.maxExpandedBytes,
  );
  final table = jsonDecode(utf8.decode(expanded)) as Map;
  final frames = StationJsonArchive.decode(table);
  final index = block['frames'] as List;
  if (frames.length != index.length) {
    throw const FormatException('Station block frame count mismatch');
  }
  for (var i = 0; i < frames.length; i++) {
    if (frames[i].receivedAt != DateTime.parse(index[i][0] as String) ||
        frames[i].kind != index[i][1]) {
      throw const FormatException('Station block index mismatch');
    }
  }
  return (frames, expanded.length);
}
