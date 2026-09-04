import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/jma_megaquake_advisory.dart';

/// Polls the JMA eqvol Atom feed for Nankai Trough and
/// Hokkaido/Sanriku subsequent-earthquake advisories.
///
/// Kept as a sidebar bulletin, not a map layer:
/// - VYSE50 南海トラフ地震臨時情報
/// - VYSE51 南海トラフ地震関連解説情報（定例外）
/// - VYSE52 南海トラフ地震関連解説情報（定例）
/// - VYSE60 北海道・三陸沖後発地震注意情報
class JmaMegaquakeAdvisoryService {
  JmaMegaquakeAdvisoryService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _now = now ?? DateTime.now;

  static const String feedUrl =
      'https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml';
  static const Duration refreshInterval = Duration(minutes: 10);
  static const Map<String, String> _headers = {
    'Referer': 'https://www.data.jma.go.jp/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final ValueNotifier<List<JmaMegaquakeAdvisory>> activeNotifier =
      ValueNotifier<List<JmaMegaquakeAdvisory>>(const []);
  final Map<JmaMegaquakeFamily, JmaMegaquakeAdvisory> _byFamily = {};
  final Set<String> _seenIds = {};

  Timer? _timer;
  Timer? _expireTimer;
  bool _started = false;
  bool _fetching = false;

  List<JmaMegaquakeAdvisory> get active => activeNotifier.value;

  void start({Duration interval = refreshInterval}) {
    if (_started) {
      if (active.isEmpty) unawaited(fetchNow());
      return;
    }
    _started = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(fetchNow()));
    unawaited(fetchNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _expireTimer?.cancel();
    _expireTimer = null;
    _started = false;
  }

  void dispose() {
    stop();
    activeNotifier.dispose();
    if (_ownsClient) _client.close();
  }

  Future<void> fetchNow() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final response = await _client
          .get(Uri.parse(feedUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('JMA megaquake feed HTTP ${response.statusCode}');
        _expireIfNeeded();
        return;
      }

      final entries = _parseFeedEntries(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      ).where(_isTargetEntry).toList();
      entries.sort((left, right) {
        final leftTime = left.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightTime =
            right.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightTime.compareTo(leftTime);
      });

      for (final entry in entries.take(12)) {
        if (_seenIds.contains(entry.id)) continue;
        final advisory = await _fetchDetail(entry);
        _seenIds.add(entry.id);
        if (_seenIds.length > 200) {
          _seenIds.remove(_seenIds.first);
        }
        if (advisory == null) continue;
        _ingest(advisory);
      }
      _expireIfNeeded();
    } catch (error) {
      debugPrint('JMA megaquake fetch error: $error');
    } finally {
      _fetching = false;
    }
  }

  @visibleForTesting
  JmaMegaquakeAdvisory? parseDetailForTesting(
    String xml, {
    String id = '',
    String detailUrl = '',
    String telegramHint = '',
  }) {
    return _parseDetailXml(
      xml,
      id: id,
      detailUrl: detailUrl,
      telegramHint: telegramHint,
    );
  }

  @visibleForTesting
  List<String> targetEntryIdsForTesting(String xml) {
    return _parseFeedEntries(
      xml,
    ).where(_isTargetEntry).map((entry) => entry.id).toList();
  }

  @visibleForTesting
  void ingestForTesting(JmaMegaquakeAdvisory advisory) {
    _ingest(advisory);
    _expireIfNeeded();
  }

  /// 接收 Android 前台服务已经完成请求和过期判断的结果。
  void ingestExternal(List<JmaMegaquakeAdvisory> advisories) {
    _byFamily.clear();
    for (final advisory in advisories) {
      if (_isActive(advisory)) _byFamily[advisory.family] = advisory;
    }
    activeNotifier.value = _sortedActive();
  }

  Future<JmaMegaquakeAdvisory?> _fetchDetail(_FeedEntry entry) async {
    final url = entry.link;
    if (url == null) return null;
    try {
      final response = await _client
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _parseDetailXml(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        id: entry.id,
        detailUrl: url.toString(),
        telegramHint: _telegramCodeFrom(entry.id, url.toString(), entry.title),
      );
    } catch (_) {
      return null;
    }
  }

  JmaMegaquakeAdvisory? _parseDetailXml(
    String xml, {
    required String id,
    required String detailUrl,
    required String telegramHint,
  }) {
    final control = _section(xml, 'Control');
    final head = _section(xml, 'Head');
    if (head == null) return null;

    final status = _decode(_tag(control ?? '', 'Status'));
    if (status.contains('訓練') ||
        status.contains('试验') ||
        status.contains('試験')) {
      return null;
    }

    final title = _decode(_tag(control ?? '', 'Title'));
    final headTitle = _decode(_tag(head, 'Title'));
    final telegramCode = _telegramCodeFrom(
      id,
      detailUrl,
      '$title $headTitle $telegramHint',
    );
    if (telegramCode.isEmpty &&
        !_looksLikeMegaquakeTitle('$title $headTitle')) {
      return null;
    }

    final eventId = _tag(head, 'EventID').trim();
    if (eventId.isEmpty) return null;

    final infoType = _decode(_tag(head, 'InfoType'));
    final serial = _decode(_tag(head, 'Serial'));
    final headline = _decode(_tag(_section(head, 'Headline') ?? '', 'Text'));
    final reportTime = _date(_tag(head, 'ReportDateTime'));

    final body = _section(xml, 'Body');
    final earthquakeInfo = _section(body ?? '', 'EarthquakeInfo');
    final infoSerial = _section(earthquakeInfo ?? '', 'InfoSerial');
    final serialName = _decode(_tag(infoSerial ?? '', 'Name'));
    final serialCode = _tag(infoSerial ?? '', 'Code').trim();

    var resolvedCode = telegramCode.isNotEmpty
        ? telegramCode
        : _telegramCodeFromTitle('$title $headTitle');
    if (serialCode == '200') {
      resolvedCode = 'VYSE52';
    } else if ((serialCode == '210' || serialCode == '219') &&
        (resolvedCode.isEmpty || resolvedCode == 'VYSE52')) {
      resolvedCode = 'VYSE51';
    }

    final family = resolvedCode == 'VYSE60'
        ? JmaMegaquakeFamily.hokkaidoSanriku
        : JmaMegaquakeFamily.nankai;
    final keyword = jmaMegaquakeKeywordFrom(
      serialCode: serialCode,
      serialName: serialName,
      headTitle: headTitle,
      telegramCode: resolvedCode,
    );

    final bodyText = _firstNonEmpty([
      _decode(_tag(earthquakeInfo ?? '', 'Text')),
      _decode(_tag(body ?? '', 'Text')),
      headline,
    ]);
    final nextAdvisory = _decode(_tag(body ?? '', 'NextAdvisory'));
    final expiresAt = reportTime?.add(jmaMegaquakeTtl(keyword));

    return JmaMegaquakeAdvisory(
      id: id.isNotEmpty ? id : '$resolvedCode|$eventId|$serialCode',
      eventId: eventId,
      family: family,
      telegramCode: resolvedCode,
      keyword: keyword,
      title: title.isNotEmpty ? title : headTitle,
      headTitle: headTitle,
      infoType: infoType,
      serial: serial,
      serialName: serialName,
      serialCode: serialCode,
      headline: headline,
      bodyText: bodyText,
      nextAdvisory: nextAdvisory,
      reportTime: reportTime,
      expiresAt: expiresAt,
      detailUrl: detailUrl,
    );
  }

  void _ingest(JmaMegaquakeAdvisory advisory) {
    if (advisory.isCanceled) {
      final existing = _byFamily[advisory.family];
      // 取消报只清除同一事件族中的同一 EventID，且不能倒退覆盖新报。
      if (existing != null &&
          existing.eventId == advisory.eventId &&
          _reportTimeIsCurrent(advisory, existing)) {
        _byFamily.remove(advisory.family);
      }
      _publish();
      return;
    }
    if (!_isActive(advisory)) return;

    final existing = _byFamily[advisory.family];
    if (existing != null &&
        _isActive(existing) &&
        advisory.family == JmaMegaquakeFamily.nankai &&
        advisory.telegramCode == 'VYSE51' &&
        (existing.keyword == JmaMegaquakeKeyword.megaquakeWarning ||
            existing.keyword == JmaMegaquakeKeyword.megaquakeAdvisory ||
            existing.keyword == JmaMegaquakeKeyword.investigating)) {
      _byFamily[advisory.family] = existing.copyWith(
        id: advisory.id,
        telegramCode: advisory.telegramCode,
        title: advisory.title,
        headTitle: advisory.headTitle,
        infoType: advisory.infoType,
        serial: advisory.serial,
        serialName: advisory.serialName.isNotEmpty
            ? advisory.serialName
            : existing.serialName,
        serialCode: advisory.serialCode.isNotEmpty
            ? advisory.serialCode
            : existing.serialCode,
        headline: advisory.headline.isNotEmpty
            ? advisory.headline
            : existing.headline,
        bodyText: advisory.bodyText.isNotEmpty
            ? advisory.bodyText
            : existing.bodyText,
        nextAdvisory: advisory.nextAdvisory.isNotEmpty
            ? advisory.nextAdvisory
            : existing.nextAdvisory,
        reportTime: advisory.reportTime ?? existing.reportTime,
        detailUrl: advisory.detailUrl.isNotEmpty
            ? advisory.detailUrl
            : existing.detailUrl,
      );
      _publish();
      return;
    }
    if (existing != null &&
        _isActive(existing) &&
        jmaMegaquakePriority(advisory.keyword) <
            jmaMegaquakePriority(existing.keyword)) {
      return;
    }

    _byFamily[advisory.family] = advisory;
    _publish();
  }

  void _expireIfNeeded() {
    final stale = _byFamily.entries
        .where((entry) => !_isActive(entry.value))
        .map((entry) => entry.key)
        .toList();
    if (stale.isEmpty && _sortedActive().length == active.length) {
      return;
    }
    for (final family in stale) {
      _byFamily.remove(family);
    }
    _publish();
  }

  void _publish() {
    final next = _sortedActive();
    final current = active;
    if (current.length == next.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (current[i].signature != next[i].signature) {
          same = false;
          break;
        }
      }
      if (same) {
        _scheduleExpiry();
        return;
      }
    }
    activeNotifier.value = next;
    for (final advisory in next) {
      debugPrint(
        'JMA megaquake ${advisory.telegramCode} '
        '${advisory.keywordLabel} ${advisory.eventId}',
      );
    }
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expireTimer?.cancel();
    _expireTimer = null;
    DateTime? soonest;
    for (final advisory in _byFamily.values) {
      final expiresAt = advisory.expiresAt;
      if (expiresAt == null) continue;
      if (soonest == null || expiresAt.isBefore(soonest)) {
        soonest = expiresAt;
      }
    }
    if (soonest == null) return;
    final delay = soonest.toUtc().difference(_now().toUtc());
    if (delay <= Duration.zero) {
      _expireIfNeeded();
      return;
    }
    _expireTimer = Timer(delay, _expireIfNeeded);
  }

  List<JmaMegaquakeAdvisory> _sortedActive() {
    final items = _byFamily.values.where(_isActive).toList()
      ..sort((left, right) {
        final priority = jmaMegaquakePriority(
          right.keyword,
        ).compareTo(jmaMegaquakePriority(left.keyword));
        if (priority != 0) return priority;
        final leftTime =
            left.reportTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightTime =
            right.reportTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightTime.compareTo(leftTime);
      });
    return List<JmaMegaquakeAdvisory>.unmodifiable(items);
  }

  bool _isActive(JmaMegaquakeAdvisory advisory) =>
      advisory.isActive(now: _now());

  bool _reportTimeIsCurrent(
    JmaMegaquakeAdvisory incoming,
    JmaMegaquakeAdvisory existing,
  ) {
    final incomingTime = incoming.reportTime;
    final existingTime = existing.reportTime;
    if (incomingTime == null || existingTime == null) return true;
    return !incomingTime.toUtc().isBefore(existingTime.toUtc());
  }

  List<_FeedEntry> _parseFeedEntries(String xml) {
    final entries = <_FeedEntry>[];
    for (final match in RegExp(
      r'<entry>(.*?)</entry>',
      dotAll: true,
    ).allMatches(xml)) {
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
          title: _decode(_tag(block, 'title')),
          updated: _date(_tag(block, 'updated')),
          content: _decode(_tag(block, 'content')),
        ),
      );
    }
    return entries;
  }

  bool _isTargetEntry(_FeedEntry entry) {
    final haystack = '${entry.id} ${entry.link} ${entry.title} ${entry.content}'
        .toUpperCase();
    if (haystack.contains('VYSE50') ||
        haystack.contains('VYSE51') ||
        haystack.contains('VYSE52') ||
        haystack.contains('VYSE60')) {
      return true;
    }
    return _looksLikeMegaquakeTitle('${entry.title} ${entry.content}');
  }

  bool _looksLikeMegaquakeTitle(String text) {
    return text.contains('南海トラフ地震臨時情報') ||
        text.contains('南海トラフ地震関連解説情報') ||
        text.contains('北海道・三陸沖後発');
  }

  String _telegramCodeFrom(String id, String url, String title) {
    final haystack = '$id $url $title'.toUpperCase();
    for (final code in const ['VYSE50', 'VYSE51', 'VYSE52', 'VYSE60']) {
      if (haystack.contains(code)) return code;
    }
    return _telegramCodeFromTitle(title);
  }

  String _telegramCodeFromTitle(String title) {
    if (title.contains('北海道・三陸沖後発')) return 'VYSE60';
    if (title.contains('南海トラフ地震臨時情報')) return 'VYSE50';
    if (title.contains('南海トラフ地震関連解説情報')) return 'VYSE51';
    return '';
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String? _section(String xml, String tag) {
    return RegExp(
      '<(?:[A-Za-z0-9_]+:)?$tag(?:\\s[^>]*)?>(.*?)</(?:[A-Za-z0-9_]+:)?$tag>',
      dotAll: true,
    ).firstMatch(xml)?.group(1);
  }

  String _tag(String xml, String tag) => _section(xml, tag) ?? '';

  DateTime? _date(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : DateTime.tryParse(trimmed);
  }

  String _decode(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .trim();
  }
}

class _FeedEntry {
  const _FeedEntry({
    required this.id,
    required this.link,
    required this.title,
    required this.updated,
    required this.content,
  });

  final String id;
  final Uri? link;
  final String title;
  final DateTime? updated;
  final String content;
}
