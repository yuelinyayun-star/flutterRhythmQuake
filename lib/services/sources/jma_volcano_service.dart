import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/volcano_bulletin.dart';

class JmaVolcanoService {
  static final JmaVolcanoService _instance = JmaVolcanoService._internal();
  factory JmaVolcanoService() => _instance;
  JmaVolcanoService._internal();

  static const String _feedUrl =
      'https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml';
  static const String _longFeedUrl =
      'https://www.data.jma.go.jp/developer/xml/feed/eqvol_l.xml';

  static const Map<String, String> _headers = {
    'Referer': 'https://www.data.jma.go.jp/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  static const int _maxCacheSize = 40;
  static const int _maxSeenIds = 200;
  static const String _seenIdsKey = 'jma_volcano_seen_ids';
  static const String _cacheKey = 'jma_volcano_cache';
  static const String _longFeedSyncKey = 'jma_volcano_long_feed_last_sync';
  static const Duration _longFeedMinInterval = Duration(hours: 3);

  Timer? _timer;
  bool _primed = false;
  final Set<String> _seenIds = {};
  final List<VolcanoBulletin> _latest = [];
  bool _cacheLoaded = false;

  void Function(List<VolcanoBulletin>)? onBulletinsUpdated;

  List<VolcanoBulletin> get latestBulletins => List.unmodifiable(_latest);

  void start({Duration interval = const Duration(minutes: 1)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => fetchNow());
    unawaited(_bootstrap());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _bootstrap() async {
    await _loadSeenIds();
    await _loadCachedBulletins();
    await _syncLongFeedIfNeeded(force: _latest.isEmpty);
    await fetchNow();
  }

  Future<void> fetchNow() async {
    try {
      final resp = await http
          .get(Uri.parse(_feedUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        debugPrint('JMA Volcano feed HTTP ${resp.statusCode}');
        return;
      }

      final xml = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final entries = _parseFeedEntries(xml).where(_isVolcanoEntry).toList();
      if (entries.isEmpty) return;

      final newEntries = entries
          .where((e) => !_seenIds.contains(e.id))
          .toList();
      if (newEntries.isEmpty) {
        if (_latest.isEmpty) {
          final seededEntries = entries.take(_maxCacheSize).toList();
          final seeded = await _buildBulletins(seededEntries);
          if (seeded.isNotEmpty) {
            _latest
              ..clear()
              ..addAll(seeded);
            _recordSeenIds(seededEntries.map((e) => e.id));
            _primed = true;
            await _saveCachedBulletins();
            debugPrint('JMA Volcano bootstrap seed: ${_latest.length} items');
            onBulletinsUpdated?.call(List.unmodifiable(_latest));
          }
        } else if (!_primed) {
          _primed = true;
          debugPrint('JMA Volcano cache restored: ${_latest.length} items');
          onBulletinsUpdated?.call(List.unmodifiable(_latest));
        }
        return;
      }

      final parsed = await _buildBulletins(newEntries);
      _recordSeenIds(newEntries.map((e) => e.id));
      _trimSeenIds();
      await _saveSeenIds();

      if (parsed.isEmpty) return;

      _mergeLatest(parsed);

      _primed = true;
      await _saveCachedBulletins();
      debugPrint('JMA Volcano intake: ${parsed.length} new bulletin(s)');
      onBulletinsUpdated?.call(List.unmodifiable(_latest));
    } catch (e) {
      debugPrint('JMA Volcano fetch error: $e');
    }
  }

  Future<void> _syncLongFeedIfNeeded({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final lastSyncRaw = prefs.getString(_longFeedSyncKey);
        final lastSync = lastSyncRaw == null
            ? null
            : DateTime.tryParse(lastSyncRaw);
        if (lastSync != null &&
            DateTime.now().difference(lastSync) < _longFeedMinInterval) {
          return;
        }
      }

      final resp = await http
          .get(Uri.parse(_longFeedUrl), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        debugPrint('JMA Volcano long feed HTTP ${resp.statusCode}');
        return;
      }

      final xml = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final entries = _parseFeedEntries(xml).where(_isVolcanoEntry).toList();
      if (entries.isEmpty) {
        await prefs.setString(
          _longFeedSyncKey,
          DateTime.now().toIso8601String(),
        );
        return;
      }

      final newEntries = entries
          .where((e) => !_seenIds.contains(e.id))
          .toList();
      if (newEntries.isNotEmpty) {
        final parsed = await _buildBulletins(newEntries);
        if (parsed.isNotEmpty) {
          _mergeLatest(parsed);
          _recordSeenIds(newEntries.map((e) => e.id));
          await _saveCachedBulletins();
          _primed = true;
          debugPrint(
            'JMA Volcano long feed intake: ${parsed.length} bulletin(s)',
          );
          onBulletinsUpdated?.call(List.unmodifiable(_latest));
        }
      } else if (_latest.isEmpty) {
        final seededEntries = entries.take(_maxCacheSize).toList();
        final seeded = await _buildBulletins(seededEntries);
        if (seeded.isNotEmpty) {
          _latest
            ..clear()
            ..addAll(seeded);
          _recordSeenIds(seededEntries.map((e) => e.id));
          await _saveCachedBulletins();
          _primed = true;
          debugPrint('JMA Volcano long feed seed: ${seeded.length} items');
          onBulletinsUpdated?.call(List.unmodifiable(_latest));
        }
      }

      await prefs.setString(_longFeedSyncKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('JMA Volcano long feed error: $e');
    }
  }

  Future<List<VolcanoBulletin>> _buildBulletins(
    List<_FeedEntry> entries,
  ) async {
    final parsed = <VolcanoBulletin>[];
    for (final entry in entries) {
      final detail = await _fetchDetail(entry.link);
      parsed.add(_buildBulletin(entry, detail));
    }
    return parsed;
  }

  Future<void> _loadSeenIds() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_seenIdsKey) ?? const [];
      if (list.isNotEmpty) {
        _seenIds.addAll(list);
      }
    } catch (_) {}
  }

  Future<void> _saveSeenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenIdsKey, _seenIds.toList());
    } catch (_) {}
  }

  void _recordSeenIds(Iterable<String> ids) {
    _seenIds.addAll(ids.where((id) => id.isNotEmpty));
    _trimSeenIds();
    unawaited(_saveSeenIds());
  }

  Future<void> _loadCachedBulletins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final items = <VolcanoBulletin>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final parsed = VolcanoBulletin.fromJson(item);
          if (_isVolcanoBulletin(parsed)) items.add(parsed);
        } else if (item is Map) {
          final parsed = VolcanoBulletin.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (_isVolcanoBulletin(parsed)) items.add(parsed);
        }
      }
      if (items.isEmpty) return;
      _latest
        ..clear()
        ..addAll(items.take(_maxCacheSize));
      _primed = true;
      onBulletinsUpdated?.call(List.unmodifiable(_latest));
      debugPrint('JMA Volcano cache loaded: ${_latest.length} items');
    } catch (_) {}
  }

  Future<void> _saveCachedBulletins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(_latest.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _trimSeenIds() {
    if (_seenIds.length <= _maxSeenIds) return;
    final overflow = _seenIds.length - _maxSeenIds;
    final items = _seenIds.toList();
    for (var i = 0; i < overflow; i++) {
      _seenIds.remove(items[i]);
    }
  }

  void _mergeLatest(List<VolcanoBulletin> incoming) {
    final merged = <String, VolcanoBulletin>{};
    for (final item in [...incoming, ..._latest]) {
      if (!_isVolcanoBulletin(item)) continue;
      merged[item.id] = item;
    }
    final sorted = merged.values.toList()
      ..sort((a, b) {
        final aTime = a.reportTime ?? a.fetchedAt;
        final bTime = b.reportTime ?? b.fetchedAt;
        return bTime.compareTo(aTime);
      });
    _latest
      ..clear()
      ..addAll(sorted.take(_maxCacheSize));
  }

  bool _isVolcanoEntry(_FeedEntry entry) {
    final code =
        RegExp(r'_([A-Z0-9]{6})_').firstMatch(entry.id)?.group(1) ?? '';
    if (code.startsWith('VFVO')) return true;
    final text = '${entry.title} ${entry.content}';
    return text.contains('火山') ||
        text.contains('降灰') ||
        text.contains('噴火') ||
        text.contains('噴煙');
  }

  bool _isVolcanoBulletin(VolcanoBulletin bulletin) {
    final text = [
      bulletin.feedTitle,
      bulletin.bulletinTitle,
      bulletin.infoKind,
      bulletin.summary,
      bulletin.volcanoName ?? '',
      bulletin.alertLevelText ?? '',
    ].join(' ');
    return text.contains('火山') ||
        text.contains('降灰') ||
        text.contains('噴火') ||
        text.contains('噴煙') ||
        bulletin.volcanoName?.trim().isNotEmpty == true;
  }

  List<_FeedEntry> _parseFeedEntries(String xml) {
    final entries = <_FeedEntry>[];
    final entryRegex = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    for (final match in entryRegex.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final id = _extractTag(block, 'id')?.trim() ?? '';
      final link = RegExp(
        r'<link[^>]*href="([^"]+)"[^>]*/?>',
        dotAll: true,
      ).firstMatch(block)?.group(1)?.trim();
      if (id.isEmpty || link == null || link.isEmpty) continue;
      entries.add(
        _FeedEntry(
          id: id,
          link: Uri.tryParse(link),
          title: _decodeText(_extractTag(block, 'title')?.trim() ?? ''),
          updated: _parseDate(_extractTag(block, 'updated')),
          content: _decodeText(_extractTag(block, 'content')?.trim() ?? ''),
        ),
      );
    }
    return entries;
  }

  Future<_BulletinDetail?> _fetchDetail(Uri? url) async {
    if (url == null) return null;
    try {
      final resp = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final xml = utf8.decode(resp.bodyBytes, allowMalformed: true);
      return _parseDetailXml(xml);
    } catch (_) {
      return null;
    }
  }

  _BulletinDetail? _parseDetailXml(String xml) {
    final control = _extractSection(xml, 'Control');
    final head = _extractSection(xml, 'Head');
    final body = _extractSection(xml, 'Body');
    if (head == null) return null;

    final feedTitle = _decodeText(_extractTag(control ?? '', 'Title') ?? '');
    final bulletinTitle = _decodeText(_extractTag(head, 'Title') ?? '');
    final infoKind = _decodeText(_extractTag(head, 'InfoKind') ?? feedTitle);
    final reportTime = _parseDate(_extractTag(head, 'ReportDateTime'));
    final targetTime = _parseDate(_extractTag(head, 'TargetDateTime'));
    final validTime = _parseDate(_extractTag(head, 'ValidDateTime'));
    final headline = _extractSection(head, 'Headline');
    final summary = _decodeText(_extractTag(headline ?? '', 'Text') ?? '');
    final coordinate = _parseCoordinate(body);

    final volcanoName = _parseVolcanoName(bulletinTitle, summary);
    final alertLevelText = _parseAlertLevel(summary, bulletinTitle);
    final targetAreas = _parseAreasFromSections(head, body);
    final ashAreas = _parseAshAreas(body);
    final plumeDirections = _parsePlumeDirections(body);

    return _BulletinDetail(
      feedTitle: feedTitle,
      bulletinTitle: bulletinTitle,
      infoKind: infoKind.isEmpty ? feedTitle : infoKind,
      summary: summary.isEmpty ? bulletinTitle : summary,
      volcanoName: volcanoName,
      alertLevelText: alertLevelText,
      latitude: coordinate?.$1,
      longitude: coordinate?.$2,
      reportTime: reportTime,
      targetTime: targetTime,
      validTime: validTime,
      targetAreas: targetAreas,
      ashAreas: ashAreas,
      plumeDirections: plumeDirections,
    );
  }

  VolcanoBulletin _buildBulletin(_FeedEntry entry, _BulletinDetail? detail) {
    final summaryFromContent = _summarizeContent(entry.content);
    final detailSummary = detail?.summary ?? '';
    final normalizedSummary = detailSummary.isNotEmpty
        ? detailSummary
        : (summaryFromContent.isNotEmpty ? summaryFromContent : entry.title);
    return VolcanoBulletin(
      id: entry.id,
      feedTitle: detail?.feedTitle ?? entry.title,
      bulletinTitle: detail?.bulletinTitle ?? entry.title,
      infoKind: detail?.infoKind ?? entry.title,
      summary: normalizedSummary,
      volcanoName:
          detail?.volcanoName ?? _parseVolcanoName(entry.title, entry.content),
      alertLevelText:
          detail?.alertLevelText ??
          _parseAlertLevel(entry.content, entry.title),
      latitude: detail?.latitude,
      longitude: detail?.longitude,
      reportTime: detail?.reportTime ?? entry.updated,
      targetTime: detail?.targetTime,
      validTime: detail?.validTime,
      targetAreas: detail?.targetAreas ?? const [],
      ashAreas: detail?.ashAreas ?? const [],
      plumeDirections: detail?.plumeDirections ?? const [],
      sourceUrl: entry.link,
      fetchedAt: DateTime.now(),
    );
  }

  List<String> _parseAreasFromSections(String? head, String? body) {
    final result = <String>{};
    for (final section in [head, body]) {
      if (section == null) continue;
      for (final block in _allSections(section, 'Information')) {
        for (final areaBlock in _allSections(block, 'Area')) {
          final areaName = _extractTag(areaBlock, 'Name');
          if (areaName != null && areaName.trim().isNotEmpty) {
            result.add(_decodeText(areaName.trim()));
          }
        }
      }
      for (final areaBlock in _allSections(section, 'Area')) {
        final areaName = _extractTag(areaBlock, 'Name');
        if (areaName != null && areaName.trim().isNotEmpty) {
          result.add(_decodeText(areaName.trim()));
        }
      }
    }
    return result.toList();
  }

  List<String> _parseAshAreas(String? body) {
    if (body == null) return const [];
    final result = <String>{};
    for (final ashInfo in _allSections(body, 'AshInfo')) {
      for (final areaBlock in _allSections(ashInfo, 'Area')) {
        final areaName = _extractTag(areaBlock, 'Name');
        if (areaName != null && areaName.trim().isNotEmpty) {
          result.add(_decodeText(areaName.trim()));
        }
      }
    }
    return result.toList();
  }

  List<String> _parsePlumeDirections(String? body) {
    if (body == null) return const [];
    final result = <String>{};
    for (final ashInfo in _allSections(body, 'AshInfo')) {
      final property = _extractSection(ashInfo, 'Property');
      final dir = _extractTag(property ?? ashInfo, 'PlumeDirection');
      if (dir != null && dir.trim().isNotEmpty) {
        result.add(_decodeText(dir.trim()));
      }
    }
    return result.toList();
  }

  String? _parseVolcanoName(String title, String summary) {
    final patterns = [
      RegExp(r'火山名[ 　]+(.+?)[ 　]+'),
      RegExp(r'【火山名[ 　]+(.+?)[ 　]+'),
      RegExp(r'^(.+?)[ 　]+降灰予報'),
    ];
    for (final text in [title, summary]) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);
        if (match != null) {
          final value = match.group(1)?.trim();
          if (value != null && value.isNotEmpty) return _decodeText(value);
        }
      }
    }
    return null;
  }

  String? _parseAlertLevel(String summary, String title) {
    final text = '$title $summary';
    final patterns = [
      RegExp(r'噴火警戒レベル[0-9一二三四五六七八九十]+(?:[（(][^)）]+[)）])?'),
      RegExp(r'警戒レベル[0-9一二三四五六七八九十]+(?:[（(][^)）]+[)）])?'),
      RegExp(r'降灰予報'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return _decodeText(match.group(0)!.trim());
      }
    }
    return null;
  }

  (double, double)? _parseCoordinate(String? body) {
    if (body == null) return null;
    final match = RegExp(
      r'([+-]\d{4,5}(?:\.\d+)?)([+-]\d{5,6}(?:\.\d+)?)([+-]\d+(?:\.\d+)?)/',
    ).firstMatch(body);
    if (match == null) return null;
    final lat = _parseJmaDegreeMinute(match.group(1)!);
    final lon = _parseJmaDegreeMinute(match.group(2)!);
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
      return null;
    }
    return (lat, lon);
  }

  double? _parseJmaDegreeMinute(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final sign = text.startsWith('-') ? -1.0 : 1.0;
    final numeric = double.tryParse(text.replaceAll('+', ''));
    if (numeric == null || !numeric.isFinite) return null;
    final deg = (numeric / 100).floor();
    final minutes = numeric - deg * 100;
    final result = sign * (deg + minutes / 60.0);
    return result.isFinite ? result : null;
  }

  String _summarizeContent(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  String? _extractSection(String xml, String tag) {
    final match = RegExp(
      '<$tag(?:\\s[^>]*)?>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(xml);
    return match?.group(1);
  }

  List<String> _allSections(String xml, String tag) {
    final result = <String>[];
    final regex = RegExp('<$tag(?:\\s[^>]*)?>(.*?)</$tag>', dotAll: true);
    for (final match in regex.allMatches(xml)) {
      final value = match.group(1);
      if (value != null) result.add(value);
    }
    return result;
  }

  String? _extractTag(String xml, String tag) {
    final match = RegExp(
      '<$tag(?:\\s[^>]*)?>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(xml);
    return match?.group(1);
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _decodeText(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', '\'')
        .trim();
  }
}

class _FeedEntry {
  final String id;
  final Uri? link;
  final String title;
  final DateTime? updated;
  final String content;

  const _FeedEntry({
    required this.id,
    required this.link,
    required this.title,
    required this.updated,
    required this.content,
  });
}

class _BulletinDetail {
  final String feedTitle;
  final String bulletinTitle;
  final String infoKind;
  final String summary;
  final String? volcanoName;
  final String? alertLevelText;
  final double? latitude;
  final double? longitude;
  final DateTime? reportTime;
  final DateTime? targetTime;
  final DateTime? validTime;
  final List<String> targetAreas;
  final List<String> ashAreas;
  final List<String> plumeDirections;

  const _BulletinDetail({
    required this.feedTitle,
    required this.bulletinTitle,
    required this.infoKind,
    required this.summary,
    required this.volcanoName,
    required this.alertLevelText,
    required this.latitude,
    required this.longitude,
    required this.reportTime,
    required this.targetTime,
    required this.validTime,
    required this.targetAreas,
    required this.ashAreas,
    required this.plumeDirections,
  });
}
