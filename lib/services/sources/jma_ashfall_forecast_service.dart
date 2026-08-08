import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../models/volcano_event_data.dart';

/// Reads the official JMA XML only when a current WHEWS ashfall bulletin
/// needs its structured AshInfo data. It does not run a background poller.
class JmaAshfallForecastService {
  JmaAshfallForecastService({http.Client? client}) : _client = client;

  static const String _feedUrl =
      'https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml';
  static const Map<String, String> _headers = {
    'Referer': 'https://www.data.jma.go.jp/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  final http.Client? _client;

  Future<List<VolcanoAshfallWindow>> fetchFor(VolcanoEventData volcano) async {
    if (!volcano.isAshfallForecast ||
        volcano.volcanoCode.trim().isEmpty ||
        volcano.reportTime == null) {
      return const [];
    }

    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(_feedUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];

      final entries = _parseFeedEntries(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      ).where((entry) => entry.id.contains(volcano.kindCode)).toList();
      if (entries.isEmpty) return const [];

      final expectedUtc = _sourceClockToUtc(volcano.reportTime!, 9);
      entries.sort((left, right) {
        final leftDelta = _utcDifference(left.updated, expectedUtc);
        final rightDelta = _utcDifference(right.updated, expectedUtc);
        return leftDelta.compareTo(rightDelta);
      });

      // The official short feed has a small bounded candidate set. Match by
      // EventID before accepting a detailed XML document.
      for (final entry in entries.take(18)) {
        final url = entry.link;
        if (url == null) continue;
        final detailResponse = await client
            .get(url, headers: _headers)
            .timeout(const Duration(seconds: 15));
        if (detailResponse.statusCode != 200) continue;
        final detail = _parseDetail(
          utf8.decode(detailResponse.bodyBytes, allowMalformed: true),
        );
        if (detail == null ||
            detail.eventId != volcano.volcanoCode.trim() ||
            detail.windows.isEmpty) {
          continue;
        }
        return detail.windows;
      }
      return const [];
    } catch (_) {
      return const [];
    } finally {
      if (_client == null) client.close();
    }
  }

  @visibleForTesting
  List<VolcanoAshfallWindow> parseDetailForTesting(String xml) {
    return _parseDetail(xml)?.windows ?? const [];
  }

  static int _utcDifference(DateTime? time, DateTime expected) {
    if (time == null) return 1 << 30;
    return time.toUtc().difference(expected).inSeconds.abs();
  }

  static DateTime _sourceClockToUtc(DateTime sourceClock, int offsetHours) {
    return DateTime.utc(
      sourceClock.year,
      sourceClock.month,
      sourceClock.day,
      sourceClock.hour,
      sourceClock.minute,
      sourceClock.second,
      sourceClock.millisecond,
      sourceClock.microsecond,
    ).subtract(Duration(hours: offsetHours));
  }

  List<_FeedEntry> _parseFeedEntries(String xml) {
    final entries = <_FeedEntry>[];
    final entryPattern = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    for (final match in entryPattern.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final id = _tag(block, 'id').trim();
      final href = RegExp(
        r'<link[^>]*href="([^"]+)"[^>]*/?>',
      ).firstMatch(block)?.group(1)?.trim();
      if (id.isEmpty || href == null || href.isEmpty) continue;
      entries.add(
        _FeedEntry(
          id: id,
          link: Uri.tryParse(href),
          updated: _date(_tag(block, 'updated')),
        ),
      );
    }
    return entries;
  }

  _AshfallDetail? _parseDetail(String xml) {
    final head = _section(xml, 'Head');
    final body = _section(xml, 'Body');
    if (head == null || body == null) return null;
    final eventId = _tag(head, 'EventID').trim();
    if (eventId.isEmpty) return null;

    final windows = <VolcanoAshfallWindow>[];
    final ashInfoPattern = RegExp(
      r'<AshInfo\b([^>]*)>(.*?)</AshInfo>',
      dotAll: true,
    );
    for (final match in ashInfoPattern.allMatches(body)) {
      final attributes = match.group(1) ?? '';
      final block = match.group(2) ?? '';
      final label =
          RegExp(r'type="([^"]+)"').firstMatch(attributes)?.group(1)?.trim() ??
          '';
      final items = <VolcanoAshfallItem>[];
      for (final itemMatch in RegExp(
        r'<Item\b[^>]*>(.*?)</Item>',
        dotAll: true,
      ).allMatches(block)) {
        final item = _parseItem(itemMatch.group(1) ?? '');
        if (item != null) items.add(item);
      }
      if (items.isEmpty) continue;
      windows.add(
        VolcanoAshfallWindow(
          label: _decode(label),
          startTime: _date(_tag(block, 'StartTime')),
          endTime: _date(_tag(block, 'EndTime')),
          items: List.unmodifiable(items),
        ),
      );
    }
    return _AshfallDetail(
      eventId: eventId,
      windows: List.unmodifiable(windows),
    );
  }

  VolcanoAshfallItem? _parseItem(String xml) {
    final kind = _section(xml, 'Kind');
    final property = _section(kind ?? '', 'Property');
    final phenomenon = _decode(_tag(kind ?? '', 'Name')).trim();
    if (phenomenon.isEmpty) return null;

    final areaNames = <String>[];
    final areaCodes = <String>[];
    final seenAreas = <String>{};
    for (final areaBlock in RegExp(
      r'<Area\b[^>]*>(.*?)</Area>',
      dotAll: true,
    ).allMatches(xml)) {
      final areaXml = areaBlock.group(1) ?? '';
      final name = _decode(_tag(areaXml, 'Name')).trim();
      final code = _tag(areaXml, 'Code').trim();
      if (name.isEmpty || !seenAreas.add('$name|$code')) continue;
      areaNames.add(name);
      areaCodes.add(code);
    }

    final polygons = <List<VolcanoAshfallCoordinate>>[];
    final polygonPattern = RegExp(
      r'<(?:[A-Za-z0-9_]+:)?Polygon\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?Polygon>',
      dotAll: true,
    );
    for (final polygonMatch in polygonPattern.allMatches(property ?? '')) {
      final points = _parsePolygon(_decode(polygonMatch.group(1) ?? ''));
      if (points.length >= 3) polygons.add(List.unmodifiable(points));
    }

    return VolcanoAshfallItem(
      phenomenon: phenomenon,
      phenomenonCode: _tag(kind ?? '', 'Code').trim(),
      areaNames: List.unmodifiable(areaNames),
      areaCodes: List.unmodifiable(areaCodes),
      plumeDirection: _decode(
        _tagWithOptionalPrefix(property ?? '', 'PlumeDirection'),
      ).trim(),
      distanceKm: _finiteDouble(_tag(property ?? '', 'Distance')),
      sizeCm: _finiteDouble(_tag(property ?? '', 'Size')),
      polygons: List.unmodifiable(polygons),
    );
  }

  List<VolcanoAshfallCoordinate> _parsePolygon(String raw) {
    final points = <VolcanoAshfallCoordinate>[];
    final coordinatePattern = RegExp(
      r'([+-]\d{1,2}(?:\.\d+)?)([+-]\d{2,3}(?:\.\d+)?)',
    );
    for (final match in coordinatePattern.allMatches(raw)) {
      final latitude = double.tryParse(match.group(1) ?? '');
      final longitude = double.tryParse(match.group(2) ?? '');
      if (latitude == null ||
          longitude == null ||
          !latitude.isFinite ||
          !longitude.isFinite) {
        continue;
      }
      points.add(
        VolcanoAshfallCoordinate(latitude: latitude, longitude: longitude),
      );
    }
    return points;
  }

  String? _section(String xml, String tag) {
    return RegExp(
      '<$tag(?:\\s[^>]*)?>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(xml)?.group(1);
  }

  String _tag(String xml, String tag) {
    return _section(xml, tag) ?? '';
  }

  String _tagWithOptionalPrefix(String xml, String tag) {
    return RegExp(
          '<(?:[A-Za-z0-9_]+:)?$tag(?:\\s[^>]*)?>(.*?)</(?:[A-Za-z0-9_]+:)?$tag>',
          dotAll: true,
        ).firstMatch(xml)?.group(1) ??
        '';
  }

  DateTime? _date(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : DateTime.tryParse(trimmed);
  }

  double? _finiteDouble(String value) {
    final result = double.tryParse(value.trim());
    return result != null && result.isFinite ? result : null;
  }

  String _decode(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}

class _FeedEntry {
  final String id;
  final Uri? link;
  final DateTime? updated;

  const _FeedEntry({
    required this.id,
    required this.link,
    required this.updated,
  });
}

class _AshfallDetail {
  final String eventId;
  final List<VolcanoAshfallWindow> windows;

  const _AshfallDetail({required this.eventId, required this.windows});
}
