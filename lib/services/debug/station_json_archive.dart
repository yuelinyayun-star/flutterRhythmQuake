import 'dart:convert';
import '../../models/source_payload.dart';
import '../../models/station_history_frame.dart';

/// Lossless JSON table: repeated keys, coordinates, metadata and values are
/// referenced, not rounded, sampled, renamed or stored as image bytes.
class StationJsonArchive {
  static const format = 'station-json-table-v1';

  static Map<String, dynamic> encode(Iterable<StationHistoryFrame> frames) {
    final nodes = <dynamic>[];
    final indices = <String, int>{};
    int intern(dynamic value) {
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
      final key = jsonEncode(node);
      final previous = indices[key];
      if (previous != null) return previous;
      final index = nodes.length;
      nodes.add(node);
      indices[key] = index;
      return index;
    }

    final roots = [for (final frame in frames) intern(frame.toMap())];
    return {'format': format, 'nodes': nodes, 'frames': roots};
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
        values.add(List.unmodifiable(node.skip(1).map(reference)));
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
