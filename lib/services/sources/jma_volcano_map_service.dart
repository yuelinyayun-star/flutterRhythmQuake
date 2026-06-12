import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/jma_volcano_site.dart';

class JmaVolcanoMapService {
  static final JmaVolcanoMapService _instance =
      JmaVolcanoMapService._internal();
  factory JmaVolcanoMapService() => _instance;
  JmaVolcanoMapService._internal();

  static const String _volcanoListUrl =
      'https://www.jma.go.jp/bosai/volcano/const/volcano_list.json';
  static const String _warningUrl =
      'https://www.jma.go.jp/bosai/volcano/data/warning.json';
  static const String _eruptionUrl =
      'https://www.jma.go.jp/bosai/volcano/data/eruption.json';
  static const String _infoUrl =
      'https://www.jma.go.jp/bosai/volcano/data/info.json';

  static const Map<String, String> _headers = {
    'Referer': 'https://www.jma.go.jp/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  Timer? _timer;
  final List<JmaVolcanoSite> _sites = [];
  bool _started = false;

  void Function(List<JmaVolcanoSite>)? onSitesUpdated;

  List<JmaVolcanoSite> get sites => List.unmodifiable(_sites);

  void start({Duration interval = const Duration(minutes: 10)}) {
    if (_started) return;
    _started = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => fetchNow());
    unawaited(fetchNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> fetchNow() async {
    try {
      final responses = await Future.wait([
        _getJson(_volcanoListUrl),
        _getJson(_warningUrl),
        _getJson(_eruptionUrl),
        _getJson(_infoUrl),
      ]);

      final listRaw = responses[0];
      final warningRaw = responses[1];
      final eruptionRaw = responses[2];
      final infoRaw = responses[3];

      if (listRaw is! List) {
        debugPrint('JMA Volcano map: volcano_list is not a list');
        return;
      }

      final warningList = warningRaw is List
          ? warningRaw.whereType<Map>().map(_mapOf).toList()
          : const <Map<String, dynamic>>[];
      final eruptionList = eruptionRaw is List
          ? eruptionRaw.whereType<Map>().map(_mapOf).toList()
          : const <Map<String, dynamic>>[];
      final infoList = infoRaw is List
          ? infoRaw.whereType<Map>().map(_mapOf).toList()
          : const <Map<String, dynamic>>[];

      final warningByEventId = <String, _WarningState>{};
      for (final warning in warningList) {
        final state = _parseWarningState(warning);
        if (state == null) continue;
        warningByEventId[state.code] = state;
      }

      final infoByEventId = <String, Map<String, dynamic>>{};
      for (final info in infoList) {
        final eventId = '${info['eventId'] ?? ''}'.trim();
        if (eventId.isEmpty) continue;
        final current = infoByEventId[eventId];
        if (current == null) {
          infoByEventId[eventId] = info;
          continue;
        }
        final currentTime = _parseDate(current['reportDatetime']);
        final nextTime = _parseDate(info['reportDatetime']);
        if (nextTime != null &&
            (currentTime == null || nextTime.isAfter(currentTime))) {
          infoByEventId[eventId] = info;
        }
      }

      final eruptionByEventId = <String, Map<String, dynamic>>{};
      for (final eruption in eruptionList) {
        final eventId = '${eruption['eventId'] ?? ''}'.trim();
        if (eventId.isEmpty) continue;
        final current = eruptionByEventId[eventId];
        if (current == null) {
          eruptionByEventId[eventId] = eruption;
          continue;
        }
        final currentTime = _parseDate(current['reportDatetime']);
        final nextTime = _parseDate(eruption['reportDatetime']);
        if (nextTime != null &&
            (currentTime == null || nextTime.isAfter(currentTime))) {
          eruptionByEventId[eventId] = eruption;
        }
      }

      final sites = <JmaVolcanoSite>[];
      for (final raw in listRaw.whereType<Map>()) {
        final site = _buildSite(
          _mapOf(raw),
          warningByEventId,
          infoByEventId,
          eruptionByEventId,
        );
        if (site != null) sites.add(site);
      }

      sites.sort((a, b) {
        final levelCompare = b.alertLevel.compareTo(a.alertLevel);
        if (levelCompare != 0) return levelCompare;
        final aTime = a.latestReportTime;
        final bTime = b.latestReportTime;
        if (aTime != null && bTime != null) {
          final timeCompare = bTime.compareTo(aTime);
          if (timeCompare != 0) return timeCompare;
        } else if (aTime != null) {
          return -1;
        } else if (bTime != null) {
          return 1;
        }
        return a.code.compareTo(b.code);
      });

      _sites
        ..clear()
        ..addAll(sites);
      onSitesUpdated?.call(List.unmodifiable(_sites));
      debugPrint('JMA Volcano map: ${_sites.length} sites updated');
    } catch (e) {
      debugPrint('JMA Volcano map fetch error: $e');
    }
  }

  Future<dynamic> _getJson(String url) async {
    final resp = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} for $url');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
  }

  Map<String, dynamic> _mapOf(Map raw) => Map<String, dynamic>.from(raw);

  JmaVolcanoSite? _buildSite(
    Map<String, dynamic> raw,
    Map<String, _WarningState> warningByEventId,
    Map<String, Map<String, dynamic>> infoByEventId,
    Map<String, Map<String, dynamic>> eruptionByEventId,
  ) {
    final code = '${raw['code'] ?? ''}'.trim();
    if (code.isEmpty) return null;

    final latlon = raw['latlon'];
    if (latlon is! List || latlon.length < 2) return null;
    final latitude = double.tryParse('${latlon[0]}');
    final longitude = double.tryParse('${latlon[1]}');
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }

    final warning = warningByEventId[code];
    final info = infoByEventId[code];
    final eruption = eruptionByEventId[code];
    final warningReportTime = warning?.reportTime;
    final infoReportTime = _parseDate(info?['reportDatetime']);
    final eruptionReportTime = _parseDate(eruption?['reportDatetime']);

    return JmaVolcanoSite(
      code: code,
      nameJp: '${raw['name_jp'] ?? ''}',
      nameEn: '${raw['name_en'] ?? ''}',
      latitude: latitude,
      longitude: longitude,
      levelOperation: raw['levelOperation'] == true,
      alertLevel: warning?.level ?? 0,
      hasWarning: warning != null,
      hasRecentInfo: info != null && info['within120'] == true,
      hasRecentEruption: eruption != null,
      warningKindCode: warning?.kindCode,
      warningKindName: warning?.kindName,
      warningAlarm: warning?.alarm,
      warningReportTime: warningReportTime,
      infoHeadTitle: info == null ? null : '${info['headTitle'] ?? ''}',
      infoReportTime: infoReportTime,
      eruptionReportTime: eruptionReportTime,
    );
  }

  _WarningState? _parseWarningState(Map<String, dynamic> raw) {
    final eventId = '${raw['eventId'] ?? ''}'.trim();
    if (eventId.isEmpty) return null;
    final reportTime = _parseDate(raw['reportDatetime']);

    String? volcanoCode;
    String? kindCode;
    String? kindName;
    String? alarm;

    final infos = raw['volcanoInfos'];
    if (infos is List) {
      for (final infoRaw in infos.whereType<Map>()) {
        final items = infoRaw['items'];
        if (items is! List || items.isEmpty) continue;
        final firstItem = items.first;
        if (firstItem is! Map) continue;
        final item = _mapOf(firstItem);
        final areas = item['areas'];
        if (areas is! List || areas.isEmpty || areas.first is! Map) continue;
        final firstArea = _mapOf(areas.first as Map);
        final areaCode = '${firstArea['code'] ?? ''}'.trim();
        if (areaCode == eventId && volcanoCode == null) {
          volcanoCode = areaCode;
          kindCode = '${item['code'] ?? ''}'.trim();
          kindName = '${item['name'] ?? ''}'.trim();
          continue;
        }
        alarm ??= '${item['name'] ?? ''}'.trim();
      }
    }

    if (volcanoCode == null) return null;
    return _WarningState(
      code: volcanoCode,
      level: _alertLevelFromKindCode(kindCode),
      kindCode: kindCode,
      kindName: kindName,
      alarm: alarm,
      reportTime: reportTime,
    );
  }

  int _alertLevelFromKindCode(String? code) {
    switch (code) {
      case '15':
      case '25':
        return 5;
      case '14':
        return 4;
      case '13':
      case '23':
      case '36':
        return 3;
      case '12':
      case '22':
        return 2;
      case '11':
      case '21':
      case '35':
        return 1;
      default:
        return 0;
    }
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    final text = '$raw'.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

class _WarningState {
  final String code;
  final int level;
  final String? kindCode;
  final String? kindName;
  final String? alarm;
  final DateTime? reportTime;

  const _WarningState({
    required this.code,
    required this.level,
    required this.kindCode,
    required this.kindName,
    required this.alarm,
    required this.reportTime,
  });
}
