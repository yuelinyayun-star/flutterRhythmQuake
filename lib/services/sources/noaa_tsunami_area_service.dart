import 'api_json_decoder.dart';
import 'dart:convert';
import 'source_http_client.dart';
import '../native_jma_tsunami.dart';

import 'package:http/http.dart' as http;

import '../../models/tsunami_message.dart';

class NoaaTsunamiAreaService {
  NoaaTsunamiAreaService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<List<TsunamiAreaInfo>> fetch(String rawUrl) async =>
      (await fetchDetail(rawUrl))?.areas ?? const [];

  /// Fetch all source fields, including forecast/observed station amplitudes.
  Future<NoaaTsunamiDetail?> fetchDetail(String rawUrl) async {
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null ||
        !{'www.tsunami.gov', 'tsunami.gov'}.contains(parsed.host) ||
        !parsed.path.startsWith('/events/') ||
        !parsed.path.endsWith('.json')) {
      return null;
    }
    final url = parsed.replace(scheme: 'https', port: 443);
    final client = _client ?? createSourceHttpClient();
    try {
      final response = await client
          .get(url)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      if (NativeJmaTsunami.supported) {
        final result = await NativeJmaTsunami.prepareAsync({
          'op': 'noaaDetail',
          'json': utf8.decode(response.bodyBytes),
          'requestedPath': url.path,
        });
        return NoaaTsunamiDetail(
          Map<String, dynamic>.from(result['detail'] as Map),
          [
            for (final area in result['areas'] as List)
              TsunamiAreaInfo.fromJson(Map<String, dynamic>.from(area as Map)),
          ],
        );
      }
      final decoded = decodeApiJsonBytes(response.bodyBytes);
      if (decoded is! Map) return null;
      final detail = Map<String, dynamic>.from(decoded);
      return NoaaTsunamiDetail(detail, parseAreas(detail));
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  static List<TsunamiAreaInfo> parseAreas(Map<String, dynamic> detail) {
    final alerts = detail['alerts'];
    if (alerts is! Map || alerts['areaList'] is! List) return const [];
    final areas = <TsunamiAreaInfo>[];
    for (final group in alerts['areaList'] as List) {
      for (final raw in group is List ? group : [group]) {
        if (raw is! Map) continue;
        final area = Map<String, dynamic>.from(raw);
        final category =
            area['category']?.toString().trim().toLowerCase() ?? '';
        final grade = switch (category) {
          'warning' => TsunamiGrade.warning,
          'advisory' || 'watch' => TsunamiGrade.watch,
          _ => TsunamiGrade.none,
        };
        if (grade == TsunamiGrade.none) continue;
        final start = area['bkp_start_location']?.toString().trim() ?? '';
        final end = area['bkp_end_location']?.toString().trim() ?? '';
        if (start.isEmpty && end.isEmpty) continue;
        final name = start.isEmpty
            ? end
            : end.isEmpty || start == end
            ? start
            : '$start - $end';
        areas.add(TsunamiAreaInfo(name: name, grade: grade));
      }
    }
    return areas;
  }
}

class NoaaTsunamiDetail {
  const NoaaTsunamiDetail(this.raw, this.areas);
  final Map<String, dynamic> raw;
  final List<TsunamiAreaInfo> areas;
}
