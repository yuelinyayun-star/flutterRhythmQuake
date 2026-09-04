import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/jma_lpgm_bulletin.dart';

/// Polls the JMA eqvol Atom feed for VXSE62 long-period observation bulletins.
class JmaLpgmService {
  JmaLpgmService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const String feedUrl =
      'https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml';
  static const Duration refreshInterval = Duration(minutes: 1);
  static const Map<String, String> _headers = {
    'Referer': 'https://www.data.jma.go.jp/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  final http.Client _client;
  final bool _ownsClient;
  final ValueNotifier<JmaLpgmBulletin?> latestNotifier =
      ValueNotifier<JmaLpgmBulletin?>(null);
  // Atom 条目 ID 可能在同一 Serial 修订时保持不变；记录条目内容指纹，
  // 只有 ID 和更新时间/内容都未变化时才跳过详情请求。
  final Map<String, String> _seenEntryFingerprints = {};

  Timer? _timer;
  Timer? _expiryTimer;
  bool _started = false;
  bool _fetching = false;

  JmaLpgmBulletin? get latest => latestNotifier.value;

  void start({Duration interval = refreshInterval}) {
    if (_started) {
      if (latest == null) unawaited(fetchNow());
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
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _started = false;
  }

  void dispose() {
    stop();
    latestNotifier.dispose();
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
        debugPrint('JMA LPGM feed HTTP ${response.statusCode}');
        _expireIfNeeded();
        return;
      }

      final entries = _parseFeedEntries(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      ).where(_isLpgmEntry).toList();
      entries.sort((left, right) {
        final leftTime = left.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightTime =
            right.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightTime.compareTo(leftTime);
      });

      if (entries.isEmpty) {
        _expireIfNeeded();
        return;
      }

      for (final entry in entries.take(5)) {
        final fingerprint = _entryFingerprint(entry);
        if (_seenEntryFingerprints[entry.id] == fingerprint) continue;
        final bulletin = await _fetchDetail(entry);
        if (bulletin == null) continue;
        _seenEntryFingerprints[entry.id] = fingerprint;
        if (_seenEntryFingerprints.length > 200) {
          _seenEntryFingerprints.remove(_seenEntryFingerprints.keys.first);
        }
        if (bulletin.isCanceled) {
          final current = latest;
          if (current != null && current.eventId == bulletin.eventId) {
            // 保留取消报的 eventId，让统一管道能够精确清理同一长周期事件。
            _setLatest(bulletin);
          }
          continue;
        }
        if (!bulletin.isActive()) continue;
        final current = latest;
        if (current == null || _isNewer(bulletin, current)) {
          _setLatest(bulletin);
          break;
        }
      }
      _expireIfNeeded();
    } catch (error) {
      debugPrint('JMA LPGM fetch error: $error');
    } finally {
      _fetching = false;
    }
  }

  /// 接收 Android 前台服务的原始解析结果，保留本服务的 UI 订阅契约。
  void ingestExternal(JmaLpgmBulletin? bulletin) {
    _setLatest(bulletin);
  }

  @visibleForTesting
  JmaLpgmBulletin? parseDetailForTesting(String xml, {String detailUrl = ''}) {
    return _parseDetailXml(xml, detailUrl: detailUrl);
  }

  @visibleForTesting
  List<String> lpgmEntryIdsForTesting(String xml) {
    return _parseFeedEntries(xml).where(_isLpgmEntry).map((e) => e.id).toList();
  }

  Future<JmaLpgmBulletin?> _fetchDetail(_FeedEntry entry) async {
    final url = entry.link;
    if (url == null) return null;
    try {
      final response = await _client
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _parseDetailXml(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        detailUrl: url.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  JmaLpgmBulletin? _parseDetailXml(String xml, {String detailUrl = ''}) {
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
    if (!_isLpgmTitle(title) && !_isLpgmTitle(headTitle)) return null;

    final eventId = _tag(head, 'EventID').trim();
    if (eventId.isEmpty) return null;

    final infoType = _decode(_tag(head, 'InfoType'));
    final serial = int.tryParse(_tag(head, 'Serial').trim()) ?? 1;
    final headline = _section(head, 'Headline');
    final headlineText = _decode(_tag(headline ?? '', 'Text'));
    final reportTime = _date(_tag(head, 'ReportDateTime'));

    if (infoType.contains('取消')) {
      return JmaLpgmBulletin(
        eventId: eventId,
        serial: serial,
        infoType: infoType,
        headline: headlineText,
        maxInt: '',
        maxLgInt: 0,
        lgCategory: '',
        reportTime: reportTime,
        detailUrl: detailUrl,
      );
    }

    final body = _section(xml, 'Body');
    final earthquake = _section(body ?? '', 'Earthquake');
    final observation = _section(
      _section(body ?? '', 'Intensity') ?? '',
      'Observation',
    );

    final hypocenterArea = _section(
      _section(earthquake ?? '', 'Hypocenter') ?? '',
      'Area',
    );
    final coordinate = _parseCoordinate(
      _tagWithOptionalPrefix(hypocenterArea ?? '', 'Coordinate'),
    );
    final magnitude = _finiteDouble(
      _tagWithOptionalPrefix(earthquake ?? '', 'Magnitude'),
    );

    final regions = <JmaLpgmRegion>[];
    final stations = <JmaLpgmStation>[];
    for (final prefXml in _allSections(observation ?? '', 'Pref')) {
      final prefecture = _decode(_tag(prefXml, 'Name'));
      for (final areaXml in _allSections(prefXml, 'Area')) {
        final areaName = _decode(_tag(areaXml, 'Name'));
        final areaCode = _tag(areaXml, 'Code').trim();
        final areaLgInt = int.tryParse(_tag(areaXml, 'MaxLgInt').trim()) ?? 0;
        if (areaName.isNotEmpty && areaLgInt >= 1) {
          regions.add(
            JmaLpgmRegion(
              name: areaName,
              code: areaCode,
              maxLgInt: areaLgInt,
              maxInt: jmaLpgmXmlIntLabel(_tag(areaXml, 'MaxInt')),
            ),
          );
        }
        for (final stationXml in _allSections(areaXml, 'IntensityStation')) {
          final station = _parseStation(
            stationXml,
            prefecture: prefecture,
            area: areaName,
          );
          if (station != null) stations.add(station);
        }
      }
    }

    if (regions.isEmpty) {
      regions.addAll(_parseHeadlineRegions(headline ?? ''));
    }

    return JmaLpgmBulletin(
      eventId: eventId,
      serial: serial,
      infoType: infoType,
      headline: headlineText,
      maxInt: jmaLpgmXmlIntLabel(_tag(observation ?? '', 'MaxInt')),
      maxLgInt: int.tryParse(_tag(observation ?? '', 'MaxLgInt').trim()) ?? 0,
      lgCategory: _tag(observation ?? '', 'LgCategory').trim(),
      originTime: _date(_tag(earthquake ?? '', 'OriginTime')),
      reportTime: reportTime,
      hypocenter: _decode(_tag(hypocenterArea ?? '', 'Name')),
      latitude: coordinate?.$1,
      longitude: coordinate?.$2,
      depthKm: coordinate?.$3,
      magnitude: magnitude,
      detailUrl: detailUrl.isNotEmpty
          ? detailUrl
          : _decode(_tag(body ?? '', 'URI')),
      regions: List.unmodifiable(regions),
      stations: List.unmodifiable(stations),
    );
  }

  JmaLpgmStation? _parseStation(
    String xml, {
    required String prefecture,
    required String area,
  }) {
    final name = _decode(_tag(xml, 'Name'));
    final lgInt = int.tryParse(_tag(xml, 'LgInt').trim()) ?? 0;
    if (name.isEmpty || lgInt < 1) return null;
    return JmaLpgmStation(
      name: name,
      code: _tag(xml, 'Code').trim(),
      intensity: jmaLpgmXmlIntLabel(_tag(xml, 'Int')),
      lgInt: lgInt,
      sva: _finiteDouble(_tag(xml, 'Sva')),
      lgIntPerPeriod: _parsePeriodValues(xml, 'LgIntPerPeriod'),
      svaPerPeriod: _parsePeriodValues(xml, 'SvaPerPeriod'),
      prefecture: prefecture,
      area: area,
    );
  }

  List<JmaLpgmPeriodValue> _parsePeriodValues(String xml, String tag) {
    final values = <JmaLpgmPeriodValue>[];
    final pattern = RegExp(
      '<(?:[A-Za-z0-9_]+:)?$tag\\b([^>]*)>(.*?)</(?:[A-Za-z0-9_]+:)?$tag>',
      dotAll: true,
    );
    var index = 1;
    for (final match in pattern.allMatches(xml)) {
      final attributes = match.group(1) ?? '';
      final raw = match.group(2)?.trim() ?? '';
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite) {
        index++;
        continue;
      }
      final band =
          int.tryParse(_attr(attributes, 'PeriodicBand') ?? '') ?? index;
      values.add(JmaLpgmPeriodValue(band: band, value: value));
      index++;
    }
    return List.unmodifiable(values);
  }

  List<JmaLpgmRegion> _parseHeadlineRegions(String headline) {
    final regions = <JmaLpgmRegion>[];
    for (final information in _allSections(headline, 'Information')) {
      for (final item in _allSections(information, 'Item')) {
        final kindName = _decode(_tag(_section(item, 'Kind') ?? '', 'Name'));
        final lgInt = _classFromKindName(kindName);
        if (lgInt < 1) continue;
        for (final areaXml in _allSections(item, 'Area')) {
          final name = _decode(_tag(areaXml, 'Name'));
          if (name.isEmpty) continue;
          regions.add(
            JmaLpgmRegion(
              name: name,
              code: _tag(areaXml, 'Code').trim(),
              maxLgInt: lgInt,
            ),
          );
        }
      }
    }
    return regions;
  }

  int _classFromKindName(String name) {
    final match = RegExp(r'階級\s*([1-4１-４])').firstMatch(name);
    final digit = (match?.group(1) ?? '')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4');
    return int.tryParse(digit) ?? 0;
  }

  (double, double, double?)? _parseCoordinate(String raw) {
    final match = RegExp(
      r'([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)(?:([+-]\d+(?:\.\d+)?))?/',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final latitude = double.tryParse(match.group(1) ?? '');
    final longitude = double.tryParse(match.group(2) ?? '');
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }
    final depthRaw = match.group(3);
    double? depthKm;
    if (depthRaw != null) {
      final meters = double.tryParse(depthRaw);
      if (meters != null && meters.isFinite) {
        depthKm = meters.abs() / 1000.0;
      }
    }
    return (latitude, longitude, depthKm);
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

  bool _isLpgmEntry(_FeedEntry entry) {
    if (entry.id.toUpperCase().contains('VXSE62')) return true;
    return _isLpgmTitle('${entry.title} ${entry.content}');
  }

  bool _isLpgmTitle(String text) => text.contains('長周期地震動に関する観測情報');

  String _entryFingerprint(_FeedEntry entry) {
    return [
      entry.id,
      entry.updated?.toUtc().toIso8601String() ?? '',
      entry.link?.toString() ?? '',
      entry.title,
      entry.content,
    ].join('|');
  }

  bool _isNewer(JmaLpgmBulletin incoming, JmaLpgmBulletin current) {
    if (incoming.eventId != current.eventId) {
      final incomingTime = incoming.originTime ?? incoming.reportTime;
      final currentTime = current.originTime ?? current.reportTime;
      if (incomingTime != null && currentTime != null) {
        return incomingTime.isAfter(currentTime);
      }
      return incomingTime != null;
    }
    return incoming.serial >= current.serial;
  }

  void _expireIfNeeded() {
    final current = latest;
    if (current != null && !current.isActive()) {
      _setLatest(null);
    }
  }

  void _setLatest(JmaLpgmBulletin? bulletin) {
    if (latest?.signature == bulletin?.signature) return;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    latestNotifier.value = bulletin;
    if (bulletin != null && bulletin.isActive()) {
      final stamp = bulletin.reportTime ?? bulletin.originTime;
      if (stamp != null) {
        final remaining =
            const Duration(minutes: 1) -
            DateTime.now().toUtc().difference(stamp.toUtc());
        _expiryTimer = Timer(
          remaining.isNegative ? Duration.zero : remaining,
          _expireIfNeeded,
        );
      }
    }
    if (bulletin != null) {
      debugPrint(
        'JMA LPGM bulletin ${bulletin.eventId} '
        'class ${bulletin.maxLgInt} (${bulletin.stations.length} stations)',
      );
    }
  }

  String? _section(String xml, String tag) {
    return RegExp(
      '<(?:[A-Za-z0-9_]+:)?$tag(?:\\s[^>]*)?>(.*?)</(?:[A-Za-z0-9_]+:)?$tag>',
      dotAll: true,
    ).firstMatch(xml)?.group(1);
  }

  List<String> _allSections(String xml, String tag) {
    return RegExp(
      '<(?:[A-Za-z0-9_]+:)?$tag(?:\\s[^>]*)?>(.*?)</(?:[A-Za-z0-9_]+:)?$tag>',
      dotAll: true,
    ).allMatches(xml).map((match) => match.group(1) ?? '').toList();
  }

  String _tag(String xml, String tag) => _section(xml, tag) ?? '';

  String _tagWithOptionalPrefix(String xml, String tag) => _tag(xml, tag);

  String? _attr(String attributes, String name) {
    return RegExp('$name="([^"]*)"').firstMatch(attributes)?.group(1)?.trim();
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
