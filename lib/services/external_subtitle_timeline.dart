import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/utils/eew_event_identity.dart';
import '../core/utils/quake_time.dart';
import '../models/unified_event_presentation.dart';
import '../models/unified_quake_data.dart';

typedef SubtitleLine = ({
  String text,
  String style,
  bool japanese,
  bool hidden,
  String badge,
});

SubtitleLine _line(
  String text,
  String style, {
  bool japanese = false,
  String badge = '',
}) =>
    (text: text, style: style, japanese: japanese, hidden: false, badge: badge);

const _domesticNames = {'ceaEew', 'scEew', 'cqEew', 'fjEew'};
const _informationAgencies = {
  'cwaEqlist': 'CWA',
  'p2pJmaEqlist': 'JMA',
  'jmaEqlist': 'JMA',
  'cencEqlist': 'CENC',
  'usgsEqlist': 'USGS',
};

/// Presentation of already-admitted unified events. It owns no feed or
/// earthquake expiry policy. EEW membership comes from the unified snapshot.
class ExternalSubtitleTimeline {
  static const _rotationMs = 10000;
  static const _infoPageMs = 4000;
  static const _infoTitleMs = _infoPageMs;
  static const _areaPageMs = 2800;
  static const _openingMs = 500;
  static const _blinkMs = 1150;
  static const _visibleMs = 600;

  final _eew = <(String, String), _EewSubtitle>{};
  final _info = <(String, String), _InformationSubtitle>{};
  final _presentedInfo = <(String, String), List<List<SubtitleLine>>>{};
  (String, String)? _selected;
  int? _rotateAt;
  int? nextChangeAt;

  void update(Iterable<UnifiedQuakeData> events, int now) {
    final present = <(String, String)>{};
    final currentInfo = <(String, String)>{};
    (String, String)? changedEew;
    for (final event in events) {
      // The replay controller publishes active reports here with both catalog
      // flags cleared and a session ID scoped to the current playback.
      if (event.isHistory || event.isSnapshot) continue;
      if (event.isEew) {
        if (event.isCanceled || event.source == 'iclEew') continue;
        final agency = _domesticNames.contains(event.source)
            ? 'CEA'
            : event.source;
        final key = (agency, canonicalEewEventId(event));
        // The unified snapshot puts its preferred member first. CEA transport
        // variants of that bulletin share one caption.
        if (present.add(key) && _updateEew(key, event, now)) {
          changedEew ??= key;
        }
      } else if (_informationAgencies[event.source] case final agency?
          when !event.isJmaLpgm && !event.isVolcanoEvent) {
        final key = (agency, event.eventId);
        if (!currentInfo.add(key)) continue;
        if (event.isCanceled) {
          _info.remove(key);
          _presentedInfo.remove(key);
          continue;
        }
        _updateInformation(key, event, now);
      }
    }
    _eew.removeWhere((key, _) => !present.contains(key));
    _info.removeWhere(
      (key, item) => item.event.isReplay && !currentInfo.contains(key),
    );
    _presentedInfo.removeWhere(
      (key, _) => !currentInfo.contains(key) && !_info.containsKey(key),
    );
    if (changedEew != null || !_eew.containsKey(_selected)) {
      _selected = changedEew ?? _eew.keys.firstOrNull;
      _rotateAt = _selected == null ? null : now + _rotationMs;
    }
    if (_selected != null) {
      for (final item in _info.values) {
        item.belowEew = true;
      }
    }
  }

  bool _updateEew((String, String) key, UnifiedQuakeData event, int now) {
    final old = _eew[key];
    if (identical(old?.event, event)) return false;
    final areas = event.source == 'jmaEew'
        ? _jmaAreaPages(event)
        : const <String>[];
    final lines = _eewLines(event, domestic: key.$1 == 'CEA', areas: areas);
    final changed = <int>{
      for (var i = 0; i < lines.length; i++)
        if (old == null || old.lines[i] != lines[i]) i,
    };
    if (old != null && !listEquals(old.areaPages, areas)) changed.add(2);
    if (changed.isEmpty && old!.event.isWarn == event.isWarn) {
      old.event = event;
      return false;
    }
    if (old != null && old.event.isWarn != event.isWarn) changed.add(0);
    _eew[key] = _EewSubtitle(event, lines, now, changed, old == null, areas);
    return true;
  }

  void _updateInformation(
    (String, String) key,
    UnifiedQuakeData event,
    int now,
  ) {
    final current = _info[key];
    if (identical(current?.event, event)) return;
    final agency = key.$1;
    final pages = _informationPages(event, agency);
    if (pages.isEmpty) return;
    final previous = _presentedInfo[key];
    if (previous != null &&
        previous.length == pages.length &&
        Iterable<int>.generate(
          pages.length,
        ).every((index) => listEquals(previous[index], pages[index]))) {
      current?.event = event;
      return;
    }
    _presentedInfo[key] = pages;
    if (current == null) {
      final titleUntil = now + _infoTitleMs;
      _info[key] = _InformationSubtitle(
        event,
        pages,
        _line('${agency}情报', 'infoTitle', japanese: agency == 'JMA'),
        titleUntil,
        titleUntil + _infoPageMs,
      );
    } else {
      current.event = event;
      current.pages = pages;
      current.index = math.min(current.index, pages.length - 1);
    }
  }

  List<SubtitleLine> frame(int now) {
    nextChangeAt = null;
    final rotateAt = _rotateAt;
    if (_eew.length > 1 && rotateAt != null) {
      if (now >= rotateAt) {
        final keys = _eew.keys.toList();
        final advances = 1 + (now - rotateAt) ~/ _rotationMs;
        _selected = keys[(keys.indexOf(_selected!) + advances) % keys.length];
        _rotateAt = rotateAt + advances * _rotationMs;
      }
      _wakeAt(_rotateAt!);
    }

    _info.removeWhere((_, item) {
      if (now < item.titleUntil) _wakeAt(item.titleUntil);
      if (now >= item.nextPageAt) {
        final pages = 1 + (now - item.nextPageAt) ~/ _infoPageMs;
        item.index += pages;
        item.nextPageAt += pages * _infoPageMs;
      }
      if (item.index >= item.pages.length) return true;
      _wakeAt(item.nextPageAt);
      return false;
    });

    final eew = _eew[_selected];
    final upper = _info.values.where((item) => !item.belowEew);
    final lower = _info.values.where((item) => item.belowEew);
    final lines = <SubtitleLine>[
      if (eew != null) ..._eewFrame(eew, now),
      for (final item in upper) ...[_line('', 'gap'), ...item.frame(now)],
      if (lower.isNotEmpty) _line('', 'belowEew'),
      for (final item in lower) ...[...item.frame(now), _line('', 'gap')],
    ];
    return lines;
  }

  List<SubtitleLine> _eewFrame(_EewSubtitle track, int now) {
    final age = now - track.changedAt;
    final opening = track.first && age < _openingMs;
    if (opening) {
      _wakeAt(track.changedAt + _openingMs);
      return [track.lines.first];
    }
    final lines = List<SubtitleLine>.of(track.lines);
    final areas = track.areaPages;
    if (areas.length > 1) {
      final elapsed = age - (track.first ? _openingMs + 3 * _blinkMs : 0);
      final page = elapsed < 0 ? 0 : elapsed ~/ _areaPageMs;
      lines[2] = _line(areas[page % areas.length], 'jmaAreas', japanese: true);
      _wakeAt(now - elapsed + (page + 1) * _areaPageMs);
    }
    final blinkAge = age - (track.first ? _openingMs : 0);
    final cycles = track.first ? 3 : 2;
    if (blinkAge < cycles * _blinkMs) {
      final phase = blinkAge % _blinkMs;
      final threshold = track.first ? _visibleMs : _blinkMs - _visibleMs;
      final hide = track.first ? phase >= threshold : phase < threshold;
      _wakeAt(now + (phase < threshold ? threshold - phase : _blinkMs - phase));
      if (hide) {
        for (final index in track.changed) {
          final line = lines[index];
          lines[index] = (
            text: line.text,
            style: line.style,
            japanese: line.japanese,
            hidden: true,
            badge: line.badge,
          );
        }
      }
    }
    return lines.where((line) => line.text.isNotEmpty).toList();
  }

  void _wakeAt(int at) {
    final next = nextChangeAt;
    nextChangeAt = next == null ? at : math.min(next, at);
  }
}

class _EewSubtitle {
  _EewSubtitle(
    this.event,
    this.lines,
    this.changedAt,
    this.changed,
    this.first,
    this.areaPages,
  );

  UnifiedQuakeData event;
  final List<SubtitleLine> lines;
  final int changedAt;
  final Set<int> changed;
  final bool first;
  final List<String> areaPages;
}

class _InformationSubtitle {
  _InformationSubtitle(
    this.event,
    this.pages,
    this.title,
    this.titleUntil,
    this.nextPageAt,
  );

  UnifiedQuakeData event;
  List<List<SubtitleLine>> pages;
  final SubtitleLine title;
  final int titleUntil;
  int nextPageAt;
  int index = 0;
  bool belowEew = false;

  List<SubtitleLine> frame(int now) =>
      now < titleUntil ? [title] : pages[index];
}

List<SubtitleLine> _eewLines(
  UnifiedQuakeData event, {
  required bool domestic,
  required List<String> areas,
}) {
  final value = UnifiedEventPresentation.fromEvent(event);
  final japanese = event.source == 'jmaEew';
  final taiwan = event.source == 'cwaEew';
  final warning = switch (event.sourcePayload?['body']) {
    {'comments': {'warning': {'text': final String message}}} => message,
    _ => '',
  };
  final plum = event.isJmaPlumEew;
  final body = plum
      ? _plumSubtitleBody(event, value.primaryText, warning)
      : japanese
      ? '${value.primaryText}で地震${warning.isEmpty ? '' : '　$warning'}'
      : event.source == 'sasmex'
      ? value.primaryText
      : '${value.primaryText}${taiwan ? '發生地震' : '发生地震'}';
  return [
    _line(
      _eewTitle(event, domestic: domestic, japanese: japanese),
      'eewTitle',
      japanese: japanese,
    ),
    _line(body, 'eewBody', japanese: japanese),
    _line(
      areas.firstOrNull ?? (plum ? '' : value.compactSecondaryText),
      areas.isEmpty ? 'eewDetail' : 'jmaAreas',
      japanese: japanese,
    ),
    if (japanese)
      _line(
        areas.isNotEmpty && !plum && event.magnitude >= 0
            ? value.compactSecondaryText
            : '',
        'eewDetail',
        japanese: true,
      ),
  ];
}

String _eewTitle(
  UnifiedQuakeData event, {
  required bool domestic,
  required bool japanese,
}) {
  if (domestic) return '中国地震台网地震预警';
  if (japanese && event.isWarn) return '緊急地震速報（警報）';
  return switch (event.source) {
    'kmaEew' || 'kma-eew' => '韩国气象厅地震预警',
    'sa' => '美国ShakeAlert地震预警',
    _ => event.displayTitleText,
  };
}

final _jmaPrefecturePrefix = RegExp(r'^(?:北海道|東京都|[^　\s]+?[府県])');

String _plumSubtitleBody(UnifiedQuakeData event, String place, String warning) {
  final hasPlace = place.isNotEmpty && place != '震源 調査中';
  if (!event.isWarn) return hasPlace ? '仮定震源　$place' : '仮定震源';
  final message = warning.isEmpty ? '強い揺れに警戒' : warning;
  if (!hasPlace) return message;
  final region = _jmaPrefecturePrefix.stringMatch(place) ?? place;
  return '$regionで地震　$message';
}

List<Map> _regions(UnifiedQuakeData event) {
  if (event.warnArea.isEmpty) return const [];
  try {
    final decoded = jsonDecode(event.warnArea);
    return decoded is List ? decoded.whereType<Map>().toList() : const [];
  } on FormatException {
    return const [];
  }
}

Iterable<String> _groups(Iterable<String> items, int size) sync* {
  final names = items.where((name) => name.isNotEmpty).toList();
  for (var i = 0; i < names.length; i += size) {
    yield names.skip(i).take(size).join('　');
  }
}

List<String> _jmaAreaPages(UnifiedQuakeData event) {
  final raw = event.sourcePayload;
  final body = raw?['body'];
  final prefectures = _areaNames(body is Map ? body['prefectures'] : null);
  final zones = _areaNames(body is Map ? body['zones'] : null);
  if (prefectures.isNotEmpty) {
    final pages = _paginateJmaAreas(prefectures);
    if (pages.length <= 1 || zones.isEmpty) return pages;
    final zoneByPrefecture = <String, String>{};
    for (final zone in zones) {
      final members = prefectures
          .where((name) => _jmaZonePrefectures[zone]?.contains(name) == true)
          .toList();
      if (members.length >= 2) {
        for (final name in members) {
          zoneByPrefecture[name] = zone;
        }
      }
    }
    return _paginateJmaAreas(
      prefectures.map((name) => zoneByPrefecture[name] ?? name).toSet(),
    );
  }
  final intensity = body is Map ? body['intensity'] : null;
  final rows = intensity is Map ? intensity['regions'] : null;
  if (rows is List) {
    final names = _areaNames(
      rows
          .whereType<Map>()
          .where((row) => !event.isWarn || row['isWarning'] == true)
          .toList(),
    );
    return _paginateJmaAreas(names.isEmpty ? zones : names);
  }
  final normalized = _areaNames(_regions(event));
  if (normalized.isNotEmpty || !event.isJmaPlumEew) {
    return _paginateJmaAreas(normalized);
  }
  final warningAreas = raw?['warningAreas'];
  if (warningAreas is! List) return const [];
  final prefectureAreas = _areaNames(
    warningAreas
        .whereType<Map>()
        .where((row) => row['scope'] == '緊急地震速報（府県予報区）')
        .toList(),
  );
  return _paginateJmaAreas(
    prefectureAreas.isEmpty ? _areaNames(warningAreas) : prefectureAreas,
  );
}

Set<String> _areaNames(Object? items) => {
  if (items is List)
    for (final row in items.whereType<Map>())
      if (row['name'] case final String name when name.isNotEmpty) name,
};

const _jmaZonePrefectures = {
  '東北': {'青森', '岩手', '宮城', '秋田', '山形', '福島'},
  '関東': {'茨城', '栃木', '群馬', '埼玉', '千葉', '東京', '神奈川'},
  '北陸': {'富山', '石川', '福井'},
  '甲信': {'山梨', '長野'},
  '東海': {'岐阜', '静岡', '愛知', '三重'},
  '近畿': {'滋賀', '京都', '大阪', '兵庫', '奈良', '和歌山'},
  '中国': {'鳥取', '島根', '岡山', '広島', '山口'},
  '四国': {'徳島', '香川', '愛媛', '高知'},
  '九州': {'福岡', '佐賀', '熊本', '大分', '長崎', '宮崎', '鹿児島'},
  '沖縄': {'沖縄本島', '大東島', '宮古島', '八重山'},
};

List<String> _paginateJmaAreas(Iterable<String> names) {
  final measure = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
  final rows = <String>[];
  var line = '';
  for (final name in names) {
    final candidate = line.isEmpty ? name : '$line　$name';
    measure.text = TextSpan(
      text: candidate,
      style: const TextStyle(
        fontFamily: 'Yu Gothic UI',
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
    measure.layout();
    if (line.isNotEmpty && measure.width > 384) {
      rows.add(line);
      line = name;
    } else {
      line = candidate;
    }
  }
  measure.dispose();
  if (line.isNotEmpty) rows.add(line);
  return [
    for (var i = 0; i < rows.length; i += 3) rows.skip(i).take(3).join('\n'),
  ];
}

List<List<SubtitleLine>> _informationPages(
  UnifiedQuakeData event,
  String agency,
) {
  final value = UnifiedEventPresentation.fromEvent(event);
  final japanese = agency == 'JMA';
  final taiwan = agency == 'CWA';
  final time = _occurrenceTime(event, japanese: japanese);
  final place = value.primaryText;
  final regions = _regions(event);
  if (!japanese) {
    final happens = taiwan ? '發生地震' : '发生地震';
    return [
      [
        _line('$time$place$happens', 'info'),
        if (taiwan && value.intensityValue.isNotEmpty)
          _line('最大震度${value.intensityValue}', 'infoDetail'),
      ],
      if (taiwan) ..._intensityPages(regions, japanese: false),
      [_line(place, 'info'), _line(value.compactSecondaryText, 'infoDetail')],
    ];
  }

  final raw = event.sourcePayload;
  final report = raw?['report'];
  final comments = report is Map ? report['comments'] : raw?['comments'];
  final body = raw?['body'];
  final bodyComments = body is Map ? body['comments'] : null;
  final forecast = comments is Map ? comments['forecast'] : null;
  final bodyForecast = bodyComments is Map ? bodyComments['forecast'] : null;
  final tsunami = [
    if (forecast is String) ...forecast.split('\n'),
    if (bodyForecast is Map && bodyForecast['text'] is String)
      ...(bodyForecast['text'] as String).split('\n'),
    if (raw?['comments'] case {'var': final String text}) ...text.split('\n'),
  ].where((text) => text.contains('津波')).firstOrNull;
  final intensity = _jmaIntensity(value.intensityValue);
  final observation = report is Map ? report['observation'] : null;
  final prefectures = observation is Map ? observation['prefs'] : null;
  final maximumAreas = _areaNames(
    (prefectures is List ? prefectures.whereType<Map>() : regions)
        .where(
          (area) =>
              _jmaIntensity('${area['int'] ?? area['intensity']}') == intensity,
        )
        .toList(),
  );
  final hasHypocenter = place.isNotEmpty && place != '震源 調査中';
  final region = hasHypocenter ? place : maximumAreas.join('・');
  return [
    [
      _line(
        '$time${region.isEmpty ? '' : '$regionで'}${intensity.isEmpty ? '地震' : '震度$intensity'}',
        'info',
        japanese: true,
      ),
      if (tsunami != null) _line(tsunami, 'infoDetail', japanese: true),
    ],
    ..._intensityPages(regions, japanese: true),
    if (hasHypocenter && (event.depth >= 0 || event.magnitude >= 0))
      [
        _line('震源は$place', 'info', japanese: true),
        _line(
          [
            if (event.depth == 0) 'ごく浅い',
            if (event.depth > 0) '深さ${event.depth.round()}キロ',
            if (event.magnitude >= 0)
              'マグニチュード${event.magnitude.toStringAsFixed(1)}',
          ].join('　'),
          'infoDetail',
          japanese: true,
        ),
      ],
  ];
}

Iterable<List<SubtitleLine>> _intensityPages(
  List<Map> areas, {
  required bool japanese,
}) sync* {
  final groups = <String, Set<String>>{};
  for (final area in areas) {
    final raw = '${area['intensity'] ?? ''}';
    final intensity = japanese ? _jmaIntensity(raw) : raw;
    final name = '${area['name'] ?? ''}';
    if (intensity.isEmpty || intensity == '0' || name.isEmpty) continue;
    (groups[intensity] ??= {}).add(name);
  }
  int order(String label) {
    const values = ['1', '2', '3', '4', '5弱', '5', '5強', '6弱', '6', '6強', '7'];
    return values.indexOf(label);
  }

  final levels = groups.keys.toList()
    ..sort((a, b) => order(b).compareTo(order(a)));
  for (final intensity in levels) {
    for (final text in _groups(groups[intensity]!, 3)) {
      yield [_line(text, 'info', japanese: japanese, badge: '震度$intensity')];
    }
  }
}

String _jmaIntensity(String raw) => switch (raw.trim()) {
  '5-' || '5弱' => '5弱',
  '5+' || '5強' => '5強',
  '6-' || '6弱' => '6弱',
  '6+' || '6強' => '6強',
  '1' || '2' || '3' || '4' || '7' => raw.trim(),
  _ => '',
};

String _occurrenceTime(UnifiedQuakeData event, {required bool japanese}) {
  if (event.originTime == null) return '';
  final local = QuakeTime.unifiedInstantUtc(event).toLocal();
  final morning = local.hour < 12;
  final hour = local.hour % 12;
  if (japanese) return '${morning ? '午前' : '午後'}$hour時${local.minute}分ごろ';
  return '${morning ? '上午' : '下午'}${hour == 0 ? 12 : hour}时${local.minute}分左右';
}
