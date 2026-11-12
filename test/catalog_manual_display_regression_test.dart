import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/jma_eqlist_service.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/sources/jma_cmt_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_eqlist_service.dart';
import 'package:flutterrhythmquake/services/sources/nowquake_cenc_intensity_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/unified_ui_fonts.dart';
import 'cmt_catalog_display_test.dart' show capturedSolutions;
import 'usgs_shakemap_test.dart' show eventFor, readJson;

dynamic original(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync(encoding: utf8));

/// Raw catalogue captures may carry NaN for an absent numeric upstream field.
/// Keep that sentinel in the immutable comparison instead of serializing the
/// source into JSON (where NaN is invalid JSON).
Object? rawSnapshot(Object? value) {
  if (value is double) {
    if (value.isNaN) return '<NaN>';
    if (value.isInfinite) {
      return value.isNegative ? '<-Infinity>' : '<Infinity>';
    }
    return value;
  }
  if (value is List) return [for (final item in value) rawSnapshot(item)];
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): rawSnapshot(entry.value),
    };
  }
  return value;
}

class _Display extends QuakeProvider {
  _Display([this.cards = const []])
    : super(startCatalogServices: false, nativeUnifiedEvents: true);
  List<UnifiedQuakeData> cards;
  @override
  List<UnifiedQuakeData> get unifiedEvents => cards;
}

const agencyTitles = {
  QuakeSourceType.cenc: '中国地震台网地震信息',
  QuakeSourceType.cencIr: '中国地震台网烈度速报',
  QuakeSourceType.cwa: '中央氣象署地震報告',
  QuakeSourceType.hko: '香港天文台地震报告',
  QuakeSourceType.emsc: '欧洲地中海地震中心',
  QuakeSourceType.bcsf: '法国中央地震研究所',
  QuakeSourceType.gfz: '德国地学研究中心',
  QuakeSourceType.usp: '巴西圣保罗大学',
  QuakeSourceType.kma_eq: '기상청 지진 정보',
  QuakeSourceType.ningxia: '宁夏地震局',
  QuakeSourceType.guangxi: '广西地震局',
  QuakeSourceType.shanxi: '山西地震局',
  QuakeSourceType.beijing: '北京地震局',
  QuakeSourceType.yunnan: '云南地震局',
  QuakeSourceType.bmkg: '印度尼西亚气象气候与地球物理局',
  QuakeSourceType.geonet: '新西兰地球科学局',
  QuakeSourceType.tmd: '泰国气象局',
  QuakeSourceType.ingv: '意大利国家地球物理与火山学研究所',
  QuakeSourceType.nrcan: '加拿大自然资源部',
  QuakeSourceType.mmd: '马来西亚气象局',
  QuakeSourceType.phivolcs: '菲律宾火山与地震研究所',
  QuakeSourceType.sgc: '哥伦比亚地质局',
  QuakeSourceType.ga: '澳大利亚地质局',
  QuakeSourceType.cenais: '古巴国家地震研究中心',
};

String oldInformationCardTitle(QuakeMessage row) {
  final fixed = agencyTitles[row.source];
  if (fixed != null) return fixed;
  switch (row.source) {
    case QuakeSourceType.usgs:
      if (row.reviewType == 'reviewed' || row.reviewType == '正式测定') {
        return 'USGS正式测定';
      }
      return row.reviewType == null ? 'USGS測定' : 'USGS自动测定';
    case QuakeSourceType.fssn:
      if (row.reviewType == '正式(已核实)') return 'FSSN正式测定';
      return row.reviewType == '已确认' ? 'FSSN自动测定' : 'FSSN地震报告';
    case QuakeSourceType.fssnCmt:
      return 'FSSN 地震矩心矩张量解';
    case QuakeSourceType.cencCmt:
      return 'CENC 地震矩心矩张量解';
    case QuakeSourceType.usgsCmt:
      return 'USGS 地震矩心矩张量解';
    case QuakeSourceType.jmaCmt:
      return 'JMA 地震矩心矩张量解';
    case QuakeSourceType.fnetCmt:
      return 'F-net 地震矩心矩张量解';
    case QuakeSourceType.hinetAquaCmt:
      return 'Hi-net AQUA 地震矩心矩张量解';
    case QuakeSourceType.wolfx:
    case QuakeSourceType.p2p:
    case QuakeSourceType.jma_fan:
    case QuakeSourceType.unadapted:
      return row.infoTypeName?.trim().isNotEmpty == true
          ? row.infoTypeName!.trim()
          : '地震信息';
    default:
      return row.infoTypeName?.trim().isNotEmpty == true
          ? row.infoTypeName!.trim()
          : '地震信息';
  }
}

/// Historical card presentation appends an actual report marker for ordinary
/// catalogue sources. JMA observation bulletins are the established exception:
/// their plain serial remains metadata, while a revision/cancellation suffix is
/// visibly retained. Keep this expected value independent from the selection
/// path that is under regression test.
String oldVisibleInformationCardTitle(QuakeMessage row) {
  final title = oldInformationCardTitle(row);
  final rawReport = row.reportNumText?.trim() ?? '';
  final report = rawReport.toLowerCase() == 'reviewed' ? '' : rawReport;
  if (report.isEmpty) return title;
  if (row.source == QuakeSourceType.jma_fan ||
      row.source == QuakeSourceType.p2p) {
    final serial = RegExp(
      r'^第\s*[0-9０-９]+\s*[報报](.*)$',
    ).firstMatch(report);
    if (serial != null) {
      final suffix = (serial.group(1) ?? '').trim();
      if (suffix.isEmpty) return title;
      final wrapped = RegExp(r'^[（(]([^）)]+)[）)]$').firstMatch(suffix);
      final status = wrapped?.group(1)?.trim() ?? suffix;
      return status.isEmpty ? title : '$title $status';
    }
  }
  return '$title $report';
}

List<QuakeMessage> jianRows(QuakeProvider mapper) {
  final packet = original('catalog_20260917/jian_all.json') as Map;
  return [
    for (final entry in packet.entries)
      if (entry.key.toString().startsWith('source：'))
        if (QuakeEventAdapter.convertJian(
              entry.key.toString().substring('source：'.length),
              Map<String, dynamic>.from(entry.value['Data']),
            )
            case final event?)
          if (!event.isEew) mapper.unifiedToQuakeMessageForTest(event),
  ];
}

QuakeMessage _fssn(bool cmt) => FanService.decodeFssnPayload(
  Map<String, dynamic>.from(
    original('fssn_direct_20261017/initial_all.original.json')[cmt
        ? 'fssn-cmt'
        : 'fssn']['Data'],
  ),
  cmt: cmt,
)!.message;

QuakeMessage fssn() => _fssn(false);
QuakeMessage fssnCmt() => _fssn(true);

QuakeMessage usgs(QuakeProvider mapper) {
  final payload = UsgsEqlistService().normalizeFeatureForUnifiedUi(
    readJson('us6000u0xi.detail.original.geojson'),
  )!;
  return mapper.unifiedToQuakeMessageForTest(
    QuakeEventAdapter.convert('usgsEqlist', payload, 0)!,
  );
}

/// CENC instrument-intensity reports use their own map product source and
/// title, so cover their original upstream frame beside ordinary CENC rows.
QuakeMessage cencIr(QuakeProvider mapper) {
  final raw =
      original('cenc_ir_mojiang_20260914170727.json') as Map<String, dynamic>;
  return mapper.unifiedToQuakeMessageForTest(
    NowQuakeCencIntensityService.unifiedInfoFromJson(raw)!,
  );
}

/// TREM's official CWA list is a separate transport from Jian/WHEWS.  Cover
/// its original rows here rather than assuming an agency-level title test
/// proves the HTTP source path.
List<QuakeMessage> tremCwaRows(QuakeProvider mapper) {
  final source = File(
    'test/fixtures/cwa_catalog_20261028/trem_list.original.json',
  );
  final originalBytes = source.readAsBytesSync();
  final records = jsonDecode(utf8.decode(originalBytes)) as List;
  final rows = <QuakeMessage>[];
  for (final record in records) {
    final raw = Map<String, dynamic>.from(record as Map);
    final before = jsonEncode(raw);
    final event = QuakeEventAdapter.convert('cwaEqlist', raw, 0);
    expect(event, isNotNull, reason: 'TREM ${raw['id']} must adapt');
    expect(jsonEncode(raw), before, reason: 'TREM raw body was modified');
    rows.add(mapper.unifiedToQuakeMessageForTest(event!));
  }
  expect(source.readAsBytesSync(), originalBytes);
  return rows;
}

/// Wolfx CENC list payloads also bypass the Jian/WHEWS adapters.  They retain
/// their exact timestamp/ID fields before the manual map presentation path.
List<QuakeMessage> wolfxCencRows() {
  final source = File(
    'test/fixtures/cenc_history_20261014/wolfx.original.json',
  );
  final originalBytes = source.readAsBytesSync();
  final raw = Map<String, dynamic>.from(jsonDecode(utf8.decode(originalBytes)));
  final before = jsonEncode(raw);
  final rows = QuakeEventAdapter.convertWolfxCencEqlist(raw);
  expect(rows, isNotEmpty, reason: 'Wolfx CENC payload must adapt');
  expect(jsonEncode(raw), before, reason: 'Wolfx CENC raw body was modified');
  expect(source.readAsBytesSync(), originalBytes);
  return rows;
}

/// Keep JMA CMT in the catalogue matrix from the captured official HTML.
/// Unlike the other CMT captures, this source is parsed from its production
/// table before it is adapted, so the matrix covers the actual source path.
QuakeMessage jmaCmt(QuakeProvider mapper) {
  final html = File(
    'test/fixtures/jma_cmt_20261110/top.original.html',
  ).readAsStringSync(encoding: utf8);
  final parsed = JmaCmtService().parseHtmlForTest(html);
  expect(parsed, isNotEmpty, reason: 'official JMA CMT page must parse');
  final event = QuakeEventAdapter.convert(
    'jmaCmt',
    Map<String, dynamic>.from(parsed.first),
    0,
  );
  expect(event, isNotNull, reason: 'official JMA CMT row must adapt');
  return mapper.unifiedToQuakeMessageForTest(event!);
}

/// P2P's raw JMA feed is an independent normal-information entry.  Keep all
/// captured bulletin kinds in the same manual-map regression matrix instead
/// of treating one DetailScale row as evidence for Destination, ScalePrompt
/// and Foreign reports.
List<QuakeMessage> p2pRows(QuakeProvider mapper) {
  final source = File('test/fixtures/event_render_20261104/p2p.original.json');
  final originalBytes = source.readAsBytesSync();
  final records = jsonDecode(utf8.decode(originalBytes)) as List;
  final rows = <QuakeMessage>[];
  for (final record in records) {
    final raw = Map<String, dynamic>.from(record as Map);
    final before = jsonEncode(raw);
    final event = QuakeEventAdapter.convert('jmaEqlist', raw, 2);
    expect(event, isNotNull, reason: 'P2P ${raw['_id']} must adapt');
    expect(jsonEncode(raw), before, reason: 'P2P raw body was modified');
    rows.add(mapper.unifiedToQuakeMessageForTest(event!));
  }
  expect(source.readAsBytesSync(), originalBytes);
  return rows;
}

/// FUNVISIS is an independent WHEWS catalog source. Its documented upstream
/// sample must take the same history-card and manual-map route as other
/// catalog rows, without altering its original data object.
QuakeMessage funvisisRow(QuakeProvider mapper) {
  final source = File('test/fixtures/funvisis_documented_20261008.json');
  final originalBytes = source.readAsBytesSync();
  final envelope = jsonDecode(utf8.decode(originalBytes)) as Map;
  final raw = Map<String, dynamic>.from(envelope['Data'] as Map);
  final before = jsonEncode(raw);
  final event = QuakeEventAdapter.convertWhews('funvisis', raw);
  expect(event, isNotNull, reason: 'FUNVISIS sample must adapt');
  expect(jsonEncode(raw), before, reason: 'FUNVISIS raw body was modified');
  expect(source.readAsBytesSync(), originalBytes);
  return mapper.unifiedToQuakeMessageForTest(event!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'real agency rows use established titles in card, map and render entry',
    () {
      final provider = _Display();
      addTearDown(provider.dispose);
      final rows = jianRows(provider);
      var covered = 0;
      final audit = <Map<String, dynamic>>[];
      for (final row in rows) {
        final expected = agencyTitles[row.source];
        if (expected == null) continue;
        covered++;
        final before = rawSnapshot(row.toMap());
        provider.selectHistoryMapProducts(row);
        final card = provider.unifiedDisplayEvents.single;
        expect(card.titleText, expected, reason: row.source.name);
        expect(provider.selectedInformationMapEvent!.titleText, expected);
        expect(provider.informationMapEventFor(row).titleText, expected);
        expect(card.rawEvent, same(row));
        expect(card.isEew, isFalse);
        expect(card.isHistory, isTrue);
        expect(rawSnapshot(row.toMap()), before);
        audit.add({
          'source': row.source.name,
          'id': row.eventId,
          'rowTitle': row.infoTypeName,
          'review': row.reviewType,
          'oldCorrectTitle': expected,
          'actualTitle': UnifiedEventPresentation.fromEvent(card).title,
        });
      }
      expect(covered, greaterThanOrEqualTo(19));
      expect(provider.unifiedEvents, isEmpty);
      expect(provider.historyList, isEmpty);
      final file = File('tmp/catalog_title_audit_20261110/agency-results.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(audit),
        encoding: utf8,
      );
    },
  );

  test(
    'every captured selectable catalogue source keeps its old title and match boundary',
    () {
      final provider = _Display();
      final matcher = _Display();
      addTearDown(provider.dispose);
      addTearDown(matcher.dispose);
      final rows = <QuakeMessage>[
        ...jianRows(provider),
        fssn(),
        fssnCmt(),
        usgs(provider),
        cencIr(provider),
        ...tremCwaRows(provider),
        ...wolfxCencRows(),
        jmaCmt(provider),
        ...p2pRows(provider),
        funvisisRow(provider),
        ...capturedSolutions().values,
      ];
      final whews = original('catalog_20260917/whews_all.json') as List;
      for (final entry in whews) {
        final source = entry['source']?.toString();
        final data = entry['Data'];
        if (source == null || data is! Map) continue;
        final event = QuakeEventAdapter.convertWhews(
          source,
          Map<String, dynamic>.from(data),
        );
        if (event == null || event.isEew) continue;
        rows.add(provider.unifiedToQuakeMessageForTest(event));
      }

      final checkedSources = <QuakeSourceType>{};
      final matrix = <Map<String, Object?>>[];
      for (final row in rows) {
        final before = rawSnapshot(row.toMap());
        final expected = oldInformationCardTitle(row);
        provider.selectHistoryMapProducts(row);
        final selected = provider.unifiedDisplayEvents.single;
        expect(
          selected.titleText,
          expected,
          reason: '${row.source}:${row.eventId}',
        );
        expect(
          UnifiedEventPresentation.fromEvent(selected).title,
          oldVisibleInformationCardTitle(row),
          reason: 'visible card title ${row.source}:${row.eventId}',
        );
        expect(provider.selectedInformationMapEvent!.titleText, expected);
        expect(provider.informationMapEventFor(row).titleText, expected);
        expect(selected.rawEvent, same(row));
        expect(rawSnapshot(row.toMap()), before);
        matrix.add({
          'source': row.source.name,
          'eventId': row.eventId,
          'upstreamTitle': row.infoTypeName,
          'reviewType': row.reviewType,
          'mapCardTitle': selected.titleText,
          'visibleCardTitle': UnifiedEventPresentation.fromEvent(selected).title,
          'mapSource': selected.source,
        });

        if (!checkedSources.add(row.source)) continue;
        final live = QuakeEventAdapter.catalogInfo(row, selected.source);
        matcher.cards = [live];
        matcher.selectHistoryMapProducts(row);
        expect(
          matcher.unifiedDisplayEvents.single,
          same(live),
          reason: 'same row must reuse retained event: ${row.source}',
        );

        final unrelated = live.copyWith(
          eventId: '${live.eventId}-unrelated',
          originTime: live.originTime?.add(const Duration(days: 2)),
          lat: (live.lat ?? 0) + 1,
          lng: (live.lng ?? 0) + 1,
        );
        matcher.cards = [unrelated];
        matcher.selectHistoryMapProducts(row);
        final unrelatedDisplay = matcher.unifiedDisplayEvents;
        final unrelatedDisplayDescription = unrelatedDisplay
            .map((item) => '${item.source}/${item.eventId}/${item.titleText}')
            .join(', ');
        expect(
          unrelatedDisplay,
          hasLength(2),
          reason:
              'another event must stay separate from the clicked row: '
              '${row.source}; display=$unrelatedDisplayDescription',
        );
        expect(
          unrelatedDisplay.first.rawEvent,
          same(row),
          reason:
              'another event must not replace selection: ${row.source}; '
              'display=$unrelatedDisplayDescription',
        );
        expect(unrelatedDisplay.last, same(unrelated));
      }
      final missingAgencyRows = agencyTitles.keys
          .where((source) => !checkedSources.contains(source))
          .map((source) => source.name)
          .toList();
      final matrixFile = File(
        'tmp/catalog_title_audit_20261110/captured-source-matrix.json',
      );
      matrixFile.parent.createSync(recursive: true);
      matrixFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(matrix),
        encoding: utf8,
      );
      expect(
        missingAgencyRows,
        ['guangxi'],
        reason:
            'only Guangxi lacks an original JIAN capture and a JIAN '
            'source-map entry; all captured selectable agencies must remain '
            'covered: $missingAgencyRows',
      );
      expect(checkedSources, contains(QuakeSourceType.jmaCmt));
      expect(rows, hasLength(270));
      expect(checkedSources, hasLength(56));

      // Every source identity is explicitly accounted for. The remaining
      // identities do not have the history-list/manual-map entry this test
      // protects: their raw-input tests exercise the EEW, station, or
      // detection pipeline directly. Guangxi has an adapter contract test but
      // no retained upstream body, so it must remain visible as an audit gap.
      const notManualHistorySources = <QuakeSourceType>{
        QuakeSourceType.wolfx, // JMA EEW
        QuakeSourceType.nied, // station observation stream
        QuakeSourceType.sc_eew,
        QuakeSourceType.fj_eew,
        QuakeSourceType.cq_eew,
        QuakeSourceType.cwa_eew,
        QuakeSourceType.cea,
        QuakeSourceType.cea_pr,
        QuakeSourceType.sa,
        QuakeSourceType.kma_eew_fan,
        QuakeSourceType.icl,
        QuakeSourceType.sasmex,
        QuakeSourceType.guangxi, // no retained original source body
      };
      expect(
        {...checkedSources, ...notManualHistorySources},
        QuakeSourceType.values.toSet(),
        reason:
            'a newly added source must be classified into the raw history '
            'matrix or a separately tested special pipeline',
      );
    },
  );

  test(
    'real JMA HTTP types retain their own titles after live card expires',
    () async {
      final bytes = File(
        'test/fixtures/jma_voice/p2p_history_20260921.json',
      ).readAsBytesSync();
      final httpSource = JmaEqlistService.forTesting(
        MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      addTearDown(httpSource.stop);
      List<QuakeMessage> rows = [];
      httpSource.onListUpdated = (value) => rows = value;
      await httpSource.fetch();
      final provider = _Display();
      addTearDown(provider.dispose);
      final titles = <String>{};
      for (final row in rows) {
        titles.add(row.infoTypeName!);
        final before = jsonEncode(row.toMap());
        provider.selectHistoryMapProducts(row);
        expect(
          provider.unifiedDisplayEvents.single.titleText,
          row.infoTypeName,
        );
        expect(
          provider.selectedInformationMapEvent!.titleText,
          row.infoTypeName,
        );
        expect(
          provider.informationMapEventFor(row).titleText,
          row.infoTypeName,
        );
        expect(jsonEncode(row.toMap()), before);
      }
      expect(titles, contains('各地の震度情報'));
      // Destination/ScalePrompt in this capture do not pass the existing HTTP
      // list's completeness filter. Test those original reports separately.
      expect(titles, {'各地の震度情報'});
    },
  );

  test(
    'original JMA bulletin kinds are not replaced by one agency heading',
    () {
      final provider = _Display();
      addTearDown(provider.dispose);
      final kinds = <String>{};
      for (final raw
          in original('event_render_20261104/p2p.original.json') as List) {
        final event = QuakeEventAdapter.convert(
          'jmaEqlist',
          Map<String, dynamic>.from(raw),
          2,
        );
        if (event == null) continue;
        kinds.add(raw['issue']['type'] as String);
        final row = provider.unifiedToQuakeMessageForTest(event);
        provider.selectHistoryMapProducts(row);
        expect(provider.unifiedDisplayEvents.single.titleText, event.titleText);
        expect(
          provider.selectedInformationMapEvent!.titleText,
          event.titleText,
        );
        expect(provider.selectedInformationMapEvent!.warnArea, event.warnArea);
      }
      expect(
        kinds,
        containsAll(['DetailScale', 'Destination', 'ScalePrompt', 'Foreign']),
      );
    },
  );

  test('real USGS and FSSN rows retain their established title rules', () {
    final provider = _Display();
    addTearDown(provider.dispose);
    final rows = [usgs(provider), fssn()];
    expect(rows.first.reviewType, 'reviewed');
    // The direct source's original row exposes infoTypeName, with no
    // reviewType. Preserve the old information card's fallback for that row.
    expect(rows.last.reviewType, isNull);
    for (final (index, row) in rows.indexed) {
      provider.selectHistoryMapProducts(row);
      final expected = index == 0 ? 'USGS正式测定' : 'FSSN地震报告';
      final event = provider.unifiedDisplayEvents.single;
      expect(UnifiedEventPresentation.fromEvent(event).title, expected);
      expect(provider.selectedInformationMapEvent!.titleText, expected);
      expect(event.rawEvent, same(row));
    }
  });

  test('mechanism titles and same-ID product matching stay distinct', () {
    final origins = eventFor(readJson('us6000u0xi.detail.original.geojson'));
    final solutions = capturedSolutions();
    final cmt = solutions['usgsCmt']!;
    expect(origins.eventId, cmt.eventId);
    final live = QuakeEventAdapter.catalogInfo(origins, 'usgsEqlist');
    final provider = _Display([live]);
    addTearDown(provider.dispose);
    for (final entry in solutions.entries) {
      provider.selectHistoryMapProducts(entry.value);
      expect(provider.unifiedDisplayEvents, hasLength(2));
      final selected = provider.unifiedDisplayEvents.first;
      expect(selected.source, entry.key);
      expect(selected.titleText, entry.value.infoTypeName);
      expect(selected.rawEvent, same(entry.value));
      expect(selected.momentTensor?.toMap(), entry.value.momentTensor?.toMap());
      expect(provider.unifiedDisplayEvents.last, same(live));
    }
    provider.selectHistoryMapProducts(null);
    expect(provider.unifiedDisplayEvents.single, same(live));
  });

  test('selected JMA row reuses its retained full bulletin only', () {
    final originals =
        original('event_render_20261104/p2p.original.json') as List;
    final raw = Map<String, dynamic>.from(
      originals.firstWhere((e) => e['issue']['type'] == 'DetailScale'),
    );
    final full = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
    final otherRaw = Map<String, dynamic>.from(
      originals.firstWhere(
        (e) =>
            e['issue']['type'] == 'DetailScale' &&
            e['earthquake']['time'] != raw['earthquake']['time'],
      ),
    );
    final other = QuakeEventAdapter.convert('jmaEqlist', otherRaw, 2)!;
    final provider = _Display([other, full]);
    addTearDown(provider.dispose);
    final row = provider.unifiedToQuakeMessageForTest(full);
    final originalRows = jsonEncode([row.toMap(), full.toMap(), other.toMap()]);
    provider.selectHistoryMapProducts(row);
    expect(provider.unifiedDisplayEvents, [full, other]);
    expect(provider.selectedInformationMapEvent, same(full));
    expect(provider.informationMapEventFor(row), same(full));
    expect(
      jsonEncode([row.toMap(), full.toMap(), other.toMap()]),
      originalRows,
    );
    provider.selectHistoryMapProducts(null);
    expect(provider.unifiedDisplayEvents, [other, full]);
  });

  // Explicit presentation contracts for review states not all represented in
  // the captured batch. They are separate models, never modified raw reports.
  for (final (source, review, verify, title) in [
    (QuakeSourceType.usgs, 'automatic', null, 'USGS自动测定'),
    (QuakeSourceType.usgs, null, null, 'USGS測定'),
    (QuakeSourceType.fssn, '正式(已核实)', null, 'FSSN正式测定'),
    (QuakeSourceType.fssn, '已确认', null, 'FSSN自动测定'),
    (QuakeSourceType.hko, null, 'Y', '香港天文台已核实'),
    (QuakeSourceType.hko, null, 'N', '香港天文台初步报告'),
  ]) {
    test('original status presentation $source / $review / $verify', () {
      final row = QuakeMessage(
        source: source,
        eventId: 'presentation-contract',
        location: '',
        magnitude: 4,
        latitude: 20,
        longitude: 120,
        depth: 10,
        originTime: DateTime(2026, 9, 17),
        reviewType: review,
        verify: verify,
      );
      final provider = _Display();
      addTearDown(provider.dispose);
      provider.selectHistoryMapProducts(row);
      expect(
        UnifiedEventPresentation.fromEvent(
          provider.unifiedDisplayEvents.single,
        ).title,
        title,
      );
    });
  }

  for (final size in [const Size(420, 850), const Size(1280, 850)]) {
    testWidgets('actual manual card titles at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(loadUnifiedUiFonts);
      final provider = _Display();
      final map = MapStateProvider();
      final jma = (original('jma_voice/p2p_history_20260921.json') as List)
          .firstWhere((e) => e['issue']['type'] == 'DetailScale');
      final rows = [
        provider.unifiedToQuakeMessageForTest(
          QuakeEventAdapter.convert(
            'jmaEqlist',
            Map<String, dynamic>.from(jma),
            2,
          )!,
        ),
        usgs(provider),
        fssn(),
        jianRows(
          provider,
        ).firstWhere((row) => row.source == QuakeSourceType.cwa),
      ];
      final titles = [
        rows[0].infoTypeName!,
        'USGS正式测定',
        'FSSN地震报告',
        '中央氣象署地震報告',
      ];
      final boundary = GlobalKey();
      for (final (index, row) in rows.indexed) {
        provider.selectHistoryMapProducts(row);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: map),
            ],
            child: MaterialApp(
              theme: unifiedUiTestTheme(),
              home: Scaffold(
                backgroundColor: const Color(0xff202124),
                body: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: boundary,
                    child: const SizedBox(width: 600, child: AlertModule()),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(titles[index]), findsOneWidget);
        expect(find.text('日本气象厅地震信息'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'tmp/catalog_title_audit_20261110/'
            '${row.source.name}-${size.width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      map.dispose();
    });
  }
}
