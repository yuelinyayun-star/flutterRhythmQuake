import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';

class _CapturedProvider extends QuakeProvider {
  _CapturedProvider(UnifiedQuakeData event)
    : unifiedEvents = [event],
      super(startCatalogServices: false);
  @override
  final List<UnifiedQuakeData> unifiedEvents;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const previewFont = String.fromEnvironment('JIAN_UI_PREVIEW_FONT');
  setUpAll(() async {
    if (previewFont.isNotEmpty) {
      final loader = FontLoader('JianUiPreview')
        ..addFont(File(previewFont).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  final captureText = File(
    'test/fixtures/jian/all.json',
  ).readAsStringSync(encoding: utf8);
  final captured = jsonDecode(captureText) as Map;
  Map<String, dynamic> raw(String type) => Map<String, dynamic>.from(
    (captured['source：$type'] as Map)['Data'] as Map,
  );
  UnifiedQuakeData event(String type) =>
      QuakeEventAdapter.convertJian(type, raw(type))!;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);
  tearDownAll(
    () => expect(
      File('test/fixtures/jian/all.json').readAsStringSync(encoding: utf8),
      captureText,
    ),
  );

  for (final (type, label, value, color) in [
    ('cea', '预估烈度', 'VI', const Color(0xFFF7E757)),
    ('cea-pr', '预估烈度', 'IV', const Color(0xFF3FAFFF)),
    ('sa', '预估烈度', 'V', const Color(0xFF5FDF8F)),
    ('cwa-eew', '预估震度', '3', const Color(0xFF5FDF8F)),
  ]) {
    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'original $type badge, header and border share color at $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final parsed = event(type);
          final original = jsonEncode(parsed.toMap());
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<QuakeProvider>(
                  create: (_) => _CapturedProvider(parsed),
                ),
                ChangeNotifierProvider(create: (_) => MapStateProvider()),
              ],
              child: MaterialApp(
                theme: ThemeData(
                  fontFamily: previewFont.isEmpty ? null : 'JianUiPreview',
                ),
                home: const Scaffold(
                  body: SingleChildScrollView(child: AlertModule()),
                ),
              ),
            ),
          );
          expect(find.text(label), findsOneWidget);
          expect(tester.widget<Text>(find.text(value)).style?.color, color);
          expect(
            tester.widget<Text>(find.text(label)).style?.color,
            color.withValues(alpha: .6),
          );
          final header = find
              .ancestor(
                of: find.text(UnifiedEventPresentation.fromEvent(parsed).title),
                matching: find.byType(Container),
              )
              .first;
          expect(
            (tester.widget<Container>(header).decoration as BoxDecoration)
                .color,
            color.withAlpha(200),
          );
          final card = find.byKey(
            ValueKey(
              'unified_card_${parsed.source}_${parsed.eventId}_${parsed.reportNumText}',
            ),
          );
          final borders = tester
              .widgetList<Container>(
                find.descendant(of: card, matching: find.byType(Container)),
              )
              .map((c) => c.decoration)
              .whereType<BoxDecoration>()
              .map((d) => d.border)
              .whereType<Border>();
          expect(
            borders.any((b) => b.top.color == color.withValues(alpha: .35)),
            isTrue,
          );
          expect(jsonEncode(parsed.toMap()), original);
          expect(parsed.sourcePayload, raw(type));
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('CAPTURE_JIAN_UI_FIX') &&
              width == 1280) {
            await tester.pump();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find
                  .descendant(of: card, matching: find.byType(RepaintBoundary))
                  .first,
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              final file = File('build/test-previews/jian_fixed_$type.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            });
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  test('actual CENC pair shares unified identity in either arrival order', () {
    final native = QuakeEventAdapter.convertWolfxCencEqlist(
      Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/cenc_history_20261009/wolfx.original.json',
              ).readAsStringSync(encoding: utf8),
            )
            as Map,
      ),
    ).first;
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final full = QuakeEventAdapter.catalogInfo(native, 'cencEqlist');
    final minute = QuakeEventAdapter.convertJian(
      'cenc',
      Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/cenc_history_20261009/jian.original.json',
              ).readAsStringSync(encoding: utf8),
            )
            as Map,
      ),
    )!;
    for (final reports in [
      [full, minute],
      [minute, full],
    ]) {
      final seen = <String, DateTime>{};
      final firstKey = catalogCanonicalEventId(reports.first, seen);
      for (final key in catalogReportKeys(reports.first, seen)) {
        seen[key] = DateTime.now().toUtc();
      }
      expect(catalogCanonicalEventId(reports.last, seen), firstKey);
    }
    expect(compareCencUnifiedOriginPrecision(full, minute), -1);
    expect(compareCencUnifiedOriginPrecision(minute, full), 1);
    expect(full.originTime?.second, 53);
    expect(minute.originTime?.second, 0);
    expect(minute.sourcePayload?['id'], 'CD.20261009122537.626_M');
  });

  test(
    'original Jian SA display number is retained but is not an increasing sequence',
    () {
      final parsed = event('sa');
      expect(parsed.reportNumText, '第1報');
      expect(parsed.hasReportSequence, isFalse);
      expect(
        UnifiedQuakeData.fromMap(parsed.toMap()).hasReportSequence,
        isFalse,
      );
      expect(parsed.sourcePayload, raw('sa'));
    },
  );

  for (final preciseFirst in [true, false]) {
    test(
      'CENC active card retains full report and one arrival, preciseFirst=$preciseFirst',
      () {
        final provider = QuakeProvider(startCatalogServices: false);
        addTearDown(provider.dispose);
        final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
        final clock = DateTime.now().toUtc().add(const Duration(hours: 8));
        final fullTime = DateTime(
          clock.year,
          clock.month,
          clock.day,
          clock.hour,
          clock.minute - 1,
          53,
        );
        final full = UnifiedQuakeData(
          source: 'cencEqlist',
          origin: 0,
          eventId: 'CD.20261010000000.001',
          isEew: false,
          timeZone: 8,
          titleText: '中国地震台网地震信息',
          reportNumText: '正式测定',
          useShindo: false,
          maxIntensity: '4',
          className: 'blue',
          hypocenter: 'model lifecycle state',
          magnitude: 3.8,
          depth: 23,
          lat: 30.29,
          lng: 102.85,
          originTime: fullTime,
          apiTypeLabel: 'Wolfx',
          useSourceTimeForExpiry: true,
        );
        final minute = full.copyWith(
          origin: QuakeEventAdapter.jianOrigin,
          apiTypeLabel: 'Jian Project',
          eventId: '${full.eventId}_M',
          originTime: DateTime(
            fullTime.year,
            fullTime.month,
            fullTime.day,
            fullTime.hour,
            fullTime.minute,
          ),
        );
        final reports = preciseFirst ? [full, minute] : [minute, full];
        var notifications = 0;
        provider.onUnifiedEventNotified = (_, _) => notifications++;
        provider.handleUnifiedEventForTest(reports.first);
        final firstArrival = provider.unifiedEvents.single.arrivedAt;
        expect(
          background.process(reports.first).type,
          BackgroundEventResultType.newEvent,
        );
        provider.handleUnifiedEventForTest(reports.last);
        expect(
          background.process(reports.last).type,
          preciseFirst
              ? BackgroundEventResultType.dropped
              : BackgroundEventResultType.update,
        );
        expect(provider.unifiedEvents, hasLength(1));
        expect(provider.unifiedEvents.single.eventId, full.eventId);
        expect(provider.unifiedEvents.single.originTime, fullTime);
        expect(provider.unifiedEvents.single.arrivedAt, firstArrival);
        expect(notifications, 1);
        provider.handleUnifiedEventForTest(minute);
        expect(
          background.process(minute).type,
          BackgroundEventResultType.dropped,
        );
        expect(provider.unifiedEvents.single.originTime, fullTime);
        provider.dismissUnifiedEventForTest(full);
        provider.handleUnifiedEventForTest(minute);
        expect(provider.unifiedEvents, isEmpty);
      },
    );
  }

  for (final type in ['usgs', 'geonet']) {
    test(
      'original $type Automatic status survives model, list and handoff',
      () {
        final parsed = event(type);
        final provider = QuakeProvider();
        addTearDown(provider.dispose);
        final row = provider.unifiedToQuakeMessageForTest(parsed);
        expect(raw(type)['infoTypeName'], 'Automatic');
        expect(parsed.reviewType, 'automatic');
        expect(row.reviewType, 'automatic');
        expect(row.infoTypeName, 'Automatic');
        expect(
          UnifiedEventPresentation.fromEvent(parsed).title,
          endsWith(' 自动'),
        );
        expect(
          UnifiedQuakeData.fromMap(parsed.toMap()).reviewType,
          'automatic',
        );
        expect(parsed.sourcePayload, raw(type));
      },
    );
  }

  for (final type in ['jma', 'jma-eew', 'kma', 'kma-eew']) {
    test(
      'original $type card displays the source instant in computer timezone',
      () {
        final parsed = event(type);
        final instant = DateTime.fromMillisecondsSinceEpoch(
          raw(type)['originTime'] as int,
          isUtc: true,
        );
        final expected =
            '${QuakeTime.formatWallClock(instant.toLocal())} (${QuakeTime.formatTimeZone(instant.toLocal().timeZoneOffset)})';
        expect(UnifiedEventPresentation.fromEvent(parsed).timeText, expected);
        expect(QuakeTime.unifiedInstantUtc(parsed), instant);
        expect(parsed.timeZone, 9);
        expect(parsed.sourcePayload, raw(type));
      },
    );
  }

  test(
    'published original JMA information does not manufacture report text',
    () {
      final parsed = event('jma');
      expect(parsed.reportNumText, isEmpty);
      expect(
        UnifiedEventPresentation.fromEvent(parsed).title,
        raw('jma')['title'],
      );
      expect(parsed.sourcePayload, raw('jma'));
    },
  );

  for (final status in ['訂正', '取消']) {
    test('JMA $status protocol status reaches unified title', () {
      // Minimal documented status-contract case, not a captured earthquake.
      final contract = {
        'id': 'status-contract-only',
        'title': '震源・震度情報',
        'infoType': status,
        'serial': 2,
      };
      final before = jsonEncode(contract);
      final parsed = QuakeEventAdapter.convertJian('jma', contract)!;
      expect(
        UnifiedEventPresentation.fromEvent(parsed).title,
        '震源・震度情報 $status',
      );
      expect(parsed.isCanceled, status == '取消');
      expect(jsonEncode(contract), before);
      expect(parsed.sourcePayload, contract);
    });
  }

  // Explicit model-level lifecycle states, independent of captured wire data.
  // No capture is rewritten, retimed or injected into a real connection.
  test(
    'SA fixed-number live body changes update both processors; reconnect cannot roll back',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final first = _liveModel(source: 'sa', magnitude: 4.5);
      final revision = _liveModel(
        source: 'sa',
        magnitude: 4.8,
        originTime: first.originTime,
      );
      provider.handleUnifiedEventForTest(first);
      expect(
        background.process(first).type,
        BackgroundEventResultType.newEvent,
      );
      provider.handleUnifiedEventForTest(revision);
      expect(
        background.process(revision).type,
        BackgroundEventResultType.update,
      );
      for (final repeat in [
        revision,
        first.copyWith(isSnapshot: true),
        first.copyWith(origin: 1, apiTypeLabel: 'FAN'),
      ]) {
        provider.handleUnifiedEventForTest(repeat);
        expect(
          background.process(repeat).type,
          BackgroundEventResultType.dropped,
        );
      }
      expect(provider.unifiedEvents.single.magnitude, 4.8);
      expect(provider.unifiedEvents.single.reportNumText, '第1報');
    },
  );

  test(
    'review-only update is accepted once, and automatic copies cannot replace it',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final automatic = _liveInfoModel('automatic');
      final reviewed = _liveInfoModel(
        'reviewed',
        originTime: automatic.originTime,
      );
      provider.handleUnifiedEventForTest(automatic);
      expect(
        background.process(automatic).type,
        BackgroundEventResultType.newEvent,
      );
      provider.handleUnifiedEventForTest(reviewed);
      expect(
        background.process(reviewed).type,
        BackgroundEventResultType.update,
      );
      for (final stale in [reviewed, automatic]) {
        provider.handleUnifiedEventForTest(stale);
        expect(
          background.process(stale).type,
          BackgroundEventResultType.dropped,
        );
      }
      expect(provider.unifiedEvents.single.reviewType, 'reviewed');
      expect(
        provider.historyBySource['usgsEqlist']!.first.reviewType,
        'reviewed',
      );
    },
  );

  for (final source in ['sa', 'kmaEew']) {
    test(
      '$source unsequenced warning/final changes are not mistaken for duplicate bodies',
      () {
        final provider = QuakeProvider(startCatalogServices: false);
        addTearDown(provider.dispose);
        final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
        final first = _liveModel(source: source, magnitude: 4.5);
        final warning = first.copyWith(isWarn: true);
        final finalReport = warning.copyWith(isFinal: true);
        provider.handleUnifiedEventForTest(first);
        expect(
          background.process(first).type,
          BackgroundEventResultType.newEvent,
        );
        for (final revision in [warning, finalReport]) {
          provider.handleUnifiedEventForTest(revision);
          expect(
            background.process(revision).type,
            BackgroundEventResultType.update,
          );
          expect(provider.unifiedEvents.single.isWarn, isTrue);
          expect(provider.unifiedEvents.single.isFinal, revision.isFinal);
          provider.handleUnifiedEventForTest(revision);
          expect(
            background.process(revision).type,
            BackgroundEventResultType.dropped,
          );
        }
      },
    );
  }

  test(
    'first review upgrade survives closed automatic card and persisted Android state',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final automatic =
          _liveInfoModel(
            'automatic',
            originTime: DateTime.now()
                .toUtc()
                .add(const Duration(hours: 8))
                .subtract(const Duration(minutes: 2)),
          ).copyWith(
            reportTime: DateTime.now()
                .toUtc()
                .add(const Duration(hours: 8))
                .subtract(const Duration(minutes: 1)),
          );
      final reviewed = _liveInfoModel(
        'reviewed',
        originTime: automatic.originTime,
      );
      provider.handleUnifiedEventForTest(automatic);
      provider.dismissUnifiedEventForTest(automatic);
      provider.handleUnifiedEventForTest(reviewed);
      expect(provider.unifiedEvents.single.reviewType, 'reviewed');
      provider.dismissUnifiedEventForTest(reviewed);
      provider.handleUnifiedEventForTest(reviewed);
      expect(provider.unifiedEvents, isEmpty);

      final first = BackgroundEventProcessor(sourceInfoMagFilters: {});
      first.process(automatic);
      final resumed = BackgroundEventProcessor(
        sourceInfoMagFilters: {},
        seenUnifiedInfoEvents: Map.of(first.seenUnifiedInfoEvents),
      );
      expect(
        resumed.process(reviewed).type,
        BackgroundEventResultType.newEvent,
      );
      final closed = BackgroundEventProcessor(
        sourceInfoMagFilters: {},
        seenUnifiedInfoEvents: Map.of(resumed.seenUnifiedInfoEvents),
      );
      expect(closed.process(reviewed).type, BackgroundEventResultType.dropped);
    },
  );

  test(
    'list review metadata cannot be rolled back by an automatic transport',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final automatic = _liveInfoModel('automatic');
      final reviewed = _liveInfoModel(
        'reviewed',
        originTime: automatic.originTime,
      );
      final manager = EqlistManager();
      manager.updateUsgsList(const []);
      for (final report in [automatic, reviewed, automatic]) {
        manager.upsertBucketItem(
          'usgsEqlist',
          provider.unifiedToQuakeMessageForTest(report),
        );
      }
      expect(manager.usgsList.single.reviewType, 'reviewed');
    },
  );
}

UnifiedQuakeData _liveModel({
  required String source,
  required double magnitude,
  DateTime? originTime,
}) => UnifiedQuakeData(
  source: source,
  origin: QuakeEventAdapter.jianOrigin,
  eventId: 'model-only-lifecycle',
  isEew: true,
  timeZone: 8,
  titleText: 'ShakeAlert Earthquake Early Warning',
  reportNumText: '第1報',
  useShindo: false,
  maxIntensity: '-',
  className: 'gray',
  hypocenter: 'model lifecycle state',
  magnitude: magnitude,
  depth: 10,
  lat: 34,
  lng: -118,
  originTime:
      originTime ?? DateTime.now().toUtc().add(const Duration(hours: 8)),
  hasReportSequence: false,
  useSourceTimeForExpiry: true,
  apiTypeLabel: 'Jian Project',
);

UnifiedQuakeData _liveInfoModel(String status, {DateTime? originTime}) =>
    UnifiedQuakeData(
      source: 'usgsEqlist',
      origin: QuakeEventAdapter.jianOrigin,
      eventId: 'model-only-review-lifecycle',
      isEew: false,
      timeZone: 8,
      titleText: 'USGS 地震信息',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '4',
      className: 'blue',
      hypocenter: 'model lifecycle state',
      magnitude: 4.5,
      depth: 10,
      lat: 34,
      lng: -118,
      originTime:
          originTime ?? DateTime.now().toUtc().add(const Duration(hours: 8)),
      useSourceTimeForExpiry: true,
      apiTypeLabel: 'Jian Project',
      sourcePayload: {'infoTypeName': status},
    );
