import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/tsunami_message.dart';
import 'native_tsunami_regions.dart';
import 'sources/native_http_client.dart';

/// Rust prepares source geometry or named coastal zones; Dart passes bytes only.
class TsunamiRegionService {
  TsunamiRegionService({http.Client? client}) : _client = client;
  final http.Client? _client;
  static final _documents = <String, Future<Uint8List>>{};

  Future<List<Map<String, dynamic>>> load(TsunamiMessage message) async {
    if (!NativeTsunamiRegions.supported) return const [];
    final data = {
      'source': message.source.name,
      'grade': message.grade.name,
      'bulletinLevel': message.bulletinLevel,
      'sourcePayload': message.sourcePayload,
      'areas': [for (final area in message.areas) area.toJson()],
    };
    final inline = await NativeTsunamiRegions.prepare({
      'op': 'geometry',
      'message': data,
    });
    final regions = [
      for (final row in inline['regions'] as List)
        Map<String, dynamic>.from(row as Map),
    ];
    if (regions.isNotEmpty) return regions;
    if (!message.isActive) return _coastalBaseMap(message, data);
    final plan = await NativeTsunamiRegions.prepare({
      'op': 'plan',
      'message': data,
    });
    if ((plan['resources'] as List).isEmpty) {
      return _coastalBaseMap(message, data);
    }
    final client =
        _client ??
        NativeHttpClient(requestTimeout: const Duration(seconds: 10));
    try {
      for (final resource in plan['resources'] as List) {
        final url = resource['url'] as String;
        final key =
            '${message.source.name}|${message.eventId}|${message.reportNumber}|${message.reportTime}|$url';
        try {
          final body = _client != null
              ? await _fetch(client, url)
              : await _documents.putIfAbsent(key, () => _fetch(client, url));
          while (_documents.length > 6) {
            _documents.remove(_documents.keys.first);
          }
          final result = await NativeTsunamiRegions.prepare({
            'op': 'geometry',
            'format': resource['format'],
            'message': data,
          }, document: body);
          regions.addAll([
            for (final row in result['regions'] as List)
              Map<String, dynamic>.from(row as Map),
          ]);
          if (regions.isNotEmpty) break;
        } catch (error) {
          _documents.remove(key);
          debugPrint('${message.source.displayLabel} 海啸区域加载失败: $error');
        }
      }
    } finally {
      if (_client == null) client.close();
    }
    // A report-specific document can explicitly cancel or have no active area.
    // Its empty result must not reactivate zones from the static base map.
    return regions;
  }

  Future<List<Map<String, dynamic>>> _coastalBaseMap(
    TsunamiMessage message,
    Map<String, dynamic> data,
  ) async {
    if (message.source == TsunamiSource.nmefc &&
        message.isActive &&
        message.areas.isNotEmpty &&
        !message.isCancellation) {
      final bytes = await rootBundle.load(
        'assets/maps/nmefc.named-coasts.geo.json',
      );
      final result = await NativeTsunamiRegions.prepare(
        {'op': 'geometry', 'format': 'nmefcNamedCoasts', 'message': data},
        document: bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
      );
      final unmatched = result['unmatchedAreas'] as List? ?? const [];
      if (unmatched.isNotEmpty) debugPrint('NMEFC 未匹配到已核验岸段: $unmatched');
      return [
        for (final row in result['regions'] as List)
          Map<String, dynamic>.from(row as Map),
      ];
    }
    if (message.source != TsunamiSource.cwa ||
        message.areas.isEmpty ||
        message.isCancellation) {
      return const [];
    }
    final bytes = await rootBundle.load('assets/maps/tw.tsunami.geo.json');
    final result = await NativeTsunamiRegions.prepare(
      {'op': 'geometry', 'format': 'cwaCoastlines', 'message': data},
      document: bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ),
    );
    return [
      for (final row in result['regions'] as List)
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<Uint8List> _fetch(http.Client client, String url) async {
    final response = await client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', Uri.parse(url));
    }
    if (response.bodyBytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Warning geometry exceeds size limit');
    }
    return response.bodyBytes;
  }
}
