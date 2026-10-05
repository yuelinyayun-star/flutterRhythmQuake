import 'dart:collection';
import '../../models/source_payload.dart';
import '../../models/station_history_frame.dart';

/// Lossless JSON table: repeated keys, coordinates, metadata and values are
/// referenced, not rounded, sampled, renamed or stored as image bytes.
class StationJsonArchive {
  static const format = 'station-json-table-v1';

  static Map<String, dynamic> encode(Iterable<StationHistoryFrame> frames) {
    final table = StationJsonTable();
    final references = HashMap<Object, int>.identity();
    final strings = <String, int>{};
    int intern(dynamic value) {
      final Map<dynamic, int>? cache = value is String
          ? strings
          : value is Map || value is List
          ? references
          : null;
      final cached = cache?[value];
      if (cached != null) return cached;
      dynamic node;
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
      final index = table.intern(node);
      if (cache != null) cache[value] = index;
      return index;
    }

    final roots = [for (final frame in frames) intern(frame.toMap())];
    return table.archive(roots);
  }

  static List<StationHistoryFrame> decode(Map archive) {
    if (archive['format'] != format ||
        archive['nodes'] is! List ||
        archive['frames'] is! List) {
      throw const FormatException('测站 JSON 索引无效');
    }
    final nodes = archive['nodes'] as List;
    final values = <dynamic>[];
    final costs = <int>[];
    var cost = 1;
    dynamic reference(dynamic index) {
      if (index is! int || index < 0 || index >= values.length) {
        throw const FormatException('测站 JSON 引用无效');
      }
      cost += costs[index];
      if (cost > 2000000) throw const FormatException('测站 JSON 展开过大');
      return values[index];
    }

    for (final node in nodes) {
      cost = 1;
      if (node is! List) {
        if (node is Map) throw const FormatException('测站 JSON 节点无效');
        values.add(node);
      } else if (node.isNotEmpty && node.first == 'l') {
        values.add(
          snapshotSourcePayloadList(node.skip(1).map(reference).toList()),
        );
      } else if (node.isNotEmpty && node.first == 'm' && node.length.isOdd) {
        final value = <String, dynamic>{};
        for (var i = 1; i < node.length; i += 2) {
          final key = reference(node[i]);
          if (key is! String || value.containsKey(key)) {
            throw const FormatException('测站 JSON 字段无效');
          }
          value[key] = reference(node[i + 1]);
        }
        // Preserve immutable table references when frames capture their payloads.
        values.add(snapshotSourcePayload(value));
      } else {
        throw const FormatException('测站 JSON 节点无效');
      }
      costs.add(cost);
    }
    return [
      for (final root in archive['frames'] as List)
        () {
          cost = 0;
          return StationHistoryFrame.fromMap(reference(root) as Map);
        }(),
    ];
  }
}

/// Hashing only locates candidates; exact node equality resolves collisions.
/// In particular, JSON integers, doubles and signed zero stay distinct.
class StationJsonTable {
  final List<dynamic> nodes = [];
  final Map<Object, int> _indices = {};
  final Map<int, List<int>> _collisions = {};

  Object _scalarKey(dynamic node) => node is num
      ? (node.runtimeType, node, node is double && node.isNegative)
      : (node.runtimeType, node);

  int intern(dynamic node) {
    if (node is! List) {
      final key = _scalarKey(node);
      return _indices.putIfAbsent(key, () {
        nodes.add(node);
        return nodes.length - 1;
      });
    }
    final hash = Object.hashAll(node);
    final existing = _indices[hash];
    if (existing != null) {
      bool matches(int index) {
        final candidate = nodes[index] as List;
        if (candidate.length != node.length) return false;
        for (var i = 0; i < node.length; i++) {
          if (candidate[i] != node[i]) return false;
        }
        return true;
      }

      if (matches(existing)) return existing;
      for (final index in _collisions[hash] ?? const <int>[]) {
        if (matches(index)) return index;
      }
    }
    final index = nodes.length;
    nodes.add(node);
    if (existing == null) {
      _indices[hash] = index;
    } else {
      (_collisions[hash] ??= []).add(index);
    }
    return index;
  }

  /// Merge compact tables without expanding station maps or copying all frames.
  List<int> append(Map archive) {
    if (archive['format'] != StationJsonArchive.format ||
        archive['nodes'] is! List ||
        archive['frames'] is! List) {
      throw const FormatException('Invalid station JSON table');
    }
    final remap = <int>[];
    int reference(dynamic index) {
      if (index is! int || index < 0 || index >= remap.length) {
        throw const FormatException('Invalid station JSON reference');
      }
      return remap[index];
    }

    for (final node in archive['nodes'] as List) {
      if (node is List) {
        if (node.isEmpty ||
            (node.first != 'l' && !(node.first == 'm' && node.length.isOdd))) {
          throw const FormatException('Invalid station JSON node');
        }
        remap.add(intern([node.first, ...node.skip(1).map(reference)]));
      } else {
        if (node is Map) throw const FormatException('Invalid scalar node');
        remap.add(intern(node));
      }
    }
    return (archive['frames'] as List).map(reference).toList();
  }

  Map<String, dynamic> archive(List<int> roots) => {
    'format': StationJsonArchive.format,
    'nodes': nodes,
    'frames': roots,
  };

  void releaseIndex() {
    _indices.clear();
    _collisions.clear();
  }

  Map<String, int> _fields(int root) {
    final node = nodes[root];
    if (node is! List || node.first != 'm') {
      throw const FormatException('Invalid station frame object');
    }
    final fields = <String, int>{};
    for (var i = 1; i < node.length; i += 2) {
      final key = nodes[node[i] as int];
      if (key is! String || fields.containsKey(key)) {
        throw const FormatException('Invalid station frame field');
      }
      fields[key] = node[i + 1] as int;
    }
    return fields;
  }

  DateTime receipt(int root) {
    final fields = _fields(root);
    final index = fields['receivedAt'];
    final value = index == null ? null : nodes[index];
    final time = value is String ? DateTime.tryParse(value) : null;
    if (time == null || !time.isUtc) {
      throw const FormatException('Invalid station frame receipt');
    }
    return time;
  }
}
