import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/external_subtitle_timeline.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_eqlist_service.dart';
import 'package:flutterrhythmquake/widgets/ui/external_subtitle_host.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jma_cancellation_regression_test.dart' show officialReference;

Map<String, dynamic> original(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;

final subtitleCwa = QuakeEventAdapter.convert(
  'cwaEqlist',
  original('source_estimation/cwa_report_115068_original.json'),
  0,
)!;

final subtitleUsgs = QuakeEventAdapter.convert(
  'usgsEqlist',
  UsgsEqlistService().normalizeFeatureForUnifiedUi(
    original('usgs_shakemap/us6000u0xi.detail.original.geojson'),
  )!,
  0,
)!;

final subtitleCenc = QuakeEventAdapter.convert(
  'cencEqlist',
  Map<String, dynamic>.from(
    original('cenc_history_20261014/wolfx.original.json')['No1'] as Map,
  ),
  0,
)!;

final subtitleJmaEew = ZipDecoder()
    .decodeBytes(
      File(
        'test/fixtures/jma_cancellation_20261016/original_telegrams.zip',
      ).readAsBytesSync(),
    )
    .files
    .where((entry) => entry.isFile)
    .map((entry) => officialReference(jsonDecode(utf8.decode(entry.content))))
    .where((report) => report.isWarn && !report.isCanceled)
    .toList();

UnifiedQuakeData plumForecast(int number) => QuakeEventAdapter.convertWhews(
  'jma_eew',
  original('jma_plum_20261106/whews_report_0$number.json'),
)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'APP replay sends unified UI EEW and information to the subtitle window',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'external_earthquake_subtitles': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final sound = SoundEffectService();
      final wasEnabled = sound.enabled;
      sound.enabled = false;
      addTearDown(() => sound.enabled = wasEnabled);

      final provider = QuakeProvider(startCatalogServices: false);
      final messenger = tester.binding.defaultBinaryMessenger;
      var rows = <Map>[];
      messenger.setMockMethodCallHandler(ExternalSubtitleSettings.channel, (
        call,
      ) async {
        if (call.method == 'present') {
          rows = (call.arguments as List).cast<Map>();
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          ExternalSubtitleSettings.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider(
              create: (_) => ExternalSubtitleSettings(prefs),
            ),
          ],
          child: const ExternalSubtitleHost(child: SizedBox.shrink()),
        ),
      );

      try {
        for (final original in [
          subtitleJmaEew.first,
          plumForecast(1),
          subtitleCwa,
        ]) {
          final replay = provider.historyReplay;
          replay.load(
            HistoryReplayPackage.fromGroup(
              EewEventGroup(
                eventId: original.eventId,
                reports: [original],
                firstArrivedAt: HistoryReplayPackage.reportInstant(original)!,
              ),
            ),
          );
          replay.play();
          await tester.pump();
          final visible = provider.unifiedDisplayEvents.single;
          expect(visible.isReplay, isTrue);
          expect(visible.sourcePayload, original.sourcePayload);
          expect(visible.originTime, original.originTime);
          if (original.isEew) {
            expect(
              rows.single['text'],
              original.isJmaPlumEew ? '緊急地震速報（予報）（PLUM）' : '緊急地震速報（警報）',
            );
          } else {
            final title = rows.singleWhere((row) => row['style'] != 'gap');
            expect(title['style'], 'infoTitle');
            expect(title['text'], 'CWA情报');
          }
          replay.stop();
          await tester.pump();
          expect(provider.unifiedDisplayEvents, isEmpty);
          expect(rows, isEmpty);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        await tester.pump();
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  test('catalog history and startup snapshots do not start subtitles', () {
    final timeline = ExternalSubtitleTimeline()
      ..update([
        subtitleCwa.copyWith(isHistory: true),
        subtitleJmaEew.first.copyWith(isSnapshot: true),
      ], 0);
    expect(timeline.frame(0), isEmpty);
  });

  test('concurrent information reuses the two unified presentations', () {
    final timeline = ExternalSubtitleTimeline()
      ..update([subtitleCwa, subtitleUsgs, subtitleCenc], 0);
    final cwa = UnifiedEventPresentation.fromEvent(subtitleCwa);
    final usgs = UnifiedEventPresentation.fromEvent(subtitleUsgs);
    final cenc = UnifiedEventPresentation.fromEvent(subtitleCenc);
    expect(
      timeline
          .frame(3999)
          .where((row) => row.style != 'gap')
          .map((row) => row.text),
      ['CWA情报', 'USGS情报', 'CENC情报'],
    );
    final headline = timeline.frame(4000).map((row) => row.text).toList();
    expect(headline, contains(contains(cwa.primaryText)));
    expect(headline, contains(contains(usgs.primaryText)));
    expect(headline, contains(contains(cenc.primaryText)));
    expect(
      timeline.frame(4000).where((row) => row.style == 'infoTitle'),
      isEmpty,
    );
    expect(
      usgs.primaryText,
      isNot(
        original(
          'usgs_shakemap/us6000u0xi.detail.original.geojson',
        )['properties']['place'],
      ),
    );
    expect(
      timeline.frame(9000).map((row) => row.text),
      containsAll([usgs.primaryText, usgs.compactSecondaryText]),
    );
    final finalPage = timeline.frame(
      4000 + 4000 * (2 + subtitleCwa.warnArea.length),
    );
    expect(finalPage, isEmpty);
    timeline.update([subtitleCwa, subtitleUsgs, subtitleCenc], 900000);
    expect(timeline.frame(900000), isEmpty);
  });

  test('information remains below after the active EEW leaves', () {
    final eew = subtitleJmaEew.first;
    final timeline = ExternalSubtitleTimeline()
      ..update([eew, subtitleCwa, subtitleUsgs], 0);
    final withEew = timeline.frame(0);
    expect(withEew.first.style, 'eewTitle');
    final lowerStart = withEew.indexWhere((row) => row.style == 'belowEew');
    expect(lowerStart, greaterThan(0));
    timeline.update([subtitleCwa, subtitleUsgs], 500);
    expect(timeline.frame(500), withEew.sublist(lowerStart));
    expect(
      timeline.frame(9000).map((row) => row.text),
      contains(
        UnifiedEventPresentation.fromEvent(subtitleUsgs).compactSecondaryText,
      ),
    );
  });

  test(
    'JMA warning retains Japanese text and never exposes a page delimiter',
    () {
      final report = subtitleJmaEew.first;
      final timeline = ExternalSubtitleTimeline()..update([report], 0);
      expect(timeline.frame(0).single.text, '緊急地震速報（警報）');
      final complete = timeline.frame(4000);
      expect(complete.every((row) => row.japanese && !row.hidden), isTrue);
      expect(complete.map((row) => row.style), [
        'eewTitle',
        'eewBody',
        'jmaAreas',
        'eewDetail',
      ]);
      expect(
        complete.last.text,
        UnifiedEventPresentation.fromEvent(report).compactSecondaryText,
      );
      expect(complete.last.text, allOf(contains('M9.9'), contains('140km')));
      expect(timeline.frame(7000).last, complete.last);
      expect(complete.map((row) => row.text).join(), isNot(contains('\u001f')));
      expect(complete.map((row) => row.text).join(), isNot(contains('追加')));
    },
  );

  test('JMA observed intensity keeps the badge separate from region names', () {
    final reports =
        jsonDecode(
              File(
                'test/fixtures/jma_lpgm_20261108/p2p_551_live_all_reports.original.json',
              ).readAsStringSync(encoding: utf8),
            )
            as List;
    final raw = reports.cast<Map<String, dynamic>>().firstWhere(
      (report) => report['issue']['type'] == 'DetailScale',
    );
    final report = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
    final timeline = ExternalSubtitleTimeline()..update([report], 0);
    expect(timeline.frame(0).last.text, 'JMA情报');
    expect(
      timeline.frame(4000).where((row) => row.style == 'infoTitle'),
      isEmpty,
    );
    final singleRegion = timeline
        .frame(8000)
        .singleWhere((row) => row.badge.isNotEmpty);
    expect(singleRegion.japanese, isTrue);
    expect(singleRegion.badge, '震度5強');
    expect(singleRegion.text, '愛知県西部');
    final regions = timeline
        .frame(12000)
        .singleWhere((row) => row.badge.isNotEmpty);
    expect(regions.badge, '震度5弱');
    expect(regions.text.split('　'), hasLength(3));
  });

  test('EEW subtitles keep the established translated source titles', () {
    final kma = UnifiedQuakeData.empty.copyWith(
      source: 'kmaEew',
      isEew: true,
      titleText: '기상청 지진조기경보',
      hypocenter: '경상북도',
      magnitude: 3.5,
      depth: 10,
    );
    final shakeAlert = UnifiedQuakeData.empty.copyWith(
      source: 'sa',
      isEew: true,
      titleText: 'ShakeAlert Earthquake Early Warning',
      hypocenter: 'California',
      magnitude: 4.2,
      depth: 8,
    );

    final timeline = ExternalSubtitleTimeline()..update([kma], 0);
    expect(timeline.frame(0).single.text, '韩国气象厅地震预警');

    timeline.update([shakeAlert], 1000);
    expect(timeline.frame(1000).single.text, '美国ShakeAlert地震预警');
  });

  test('captured PLUM forecasts label the assumption without parameters', () {
    final timeline = ExternalSubtitleTimeline();
    for (var number = 1; number <= 5; number++) {
      final report = plumForecast(number);
      expect(report.isJmaPlumEew, isTrue);
      expect(report.depth, 10);
      expect(report.magnitude, -1);
      final at = number * 10000;
      timeline.update([report], at);
      expect(timeline.frame(at + 4000).map((row) => row.text), [
        '緊急地震速報（予報）（PLUM）',
        '仮定震源　福島県中通り',
      ]);
    }
  });

  test('PLUM warning follows the broadcast and retains its warning areas', () {
    // Presentation inputs from JMA's first public warning on March 16, 2022,
    // 23:36:55.6 JST (table 1-4 and figure 1-3). No wire capture is available.
    final report = UnifiedQuakeData.empty.copyWith(
      source: 'jmaEew',
      origin: 4,
      isEew: true,
      isWarn: true,
      isAssumption: true,
      timeZone: 9,
      titleText: '緊急地震速報（警報）',
      hypocenter: '福島県浜通り',
      depth: 10,
      magnitude: 1,
      warnArea: jsonEncode([
        {'name': '宮城'},
        {'name': '福島'},
      ]),
    );
    final timeline = ExternalSubtitleTimeline()..update([report], 0);
    final complete = timeline.frame(4000);
    expect(complete.map((row) => row.text), [
      '緊急地震速報（警報）',
      '福島県で地震　強い揺れに警戒',
      '宮城　福島',
    ]);
    expect(complete.last.style, 'jmaAreas');
  });

  test(
    'selects a single EEW and ignores an otherwise identical report number',
    () {
      final captures =
          jsonDecode(
                File(
                  'test/fixtures/eew_identity_20261013/reports.original.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      UnifiedQuakeData wolfx(String wire, String api, String unified) =>
          QuakeEventAdapter.convert(
            unified,
            captures.firstWhere(
              (frame) => frame['source'] == wire && frame['api'] == api,
            )['raw'],
            0,
          )!;
      final jma = wolfx('jma_eew', 'wolfx', 'jmaEew');
      final domestic = wolfx('cenc_eew', 'wolfx-http', 'ceaEew');
      final timeline = ExternalSubtitleTimeline()..update([jma, domestic], 0);
      Iterable<String> titles(int now) => timeline
          .frame(now)
          .where((row) => row.style == 'eewTitle')
          .map((row) => row.text);
      expect(titles(0), [jma.displayTitleText]);
      expect(titles(10000), ['中国地震台网地震预警']);
      timeline.update([jma.copyWith(reportNumText: '第99報'), domestic], 11000);
      expect(titles(11000), ['中国地震台网地震预警']);
      expect(titles(20000), [jma.displayTitleText]);
    },
  );
}
