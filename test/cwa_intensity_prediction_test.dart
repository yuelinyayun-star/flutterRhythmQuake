import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/cwa_intensity_prediction.dart';
import 'package:flutterrhythmquake/core/cwa_prediction_towns.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/ka_shindo_marker_style.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CapturedProvider extends QuakeProvider {
  _CapturedProvider(UnifiedQuakeData event) : unifiedEvents = [event];
  @override
  final List<UnifiedQuakeData> unifiedEvents;
}

Map<String, dynamic> readMap(String path) =>
    jsonDecode(File(path).readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const previewFont = String.fromEnvironment('BADGE_PREVIEW_FONT');
  setUpAll(() async {
    if (previewFont.isNotEmpty) {
      final loader = FontLoader('CwaPreview')
        ..addFont(File(previewFont).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  final reference = readMap(
    'test/fixtures/source_estimation/cwa_1150075_prediction_reference.json',
  );
  final original = Map<String, dynamic>.from(reference['sourcePayload'] as Map);
  final jian = QuakeEventAdapter.convertJian('cwa-eew', original)!;
  final capturedWhews =
      (jsonDecode(
                    File(
                      'test/fixtures/catalog_20260917/whews_all.json',
                    ).readAsStringSync(encoding: utf8),
                  )
                  as List)
              .whereType<Map>()
              .firstWhere((frame) => frame['source'] == 'cwa_eew')['Data']
          as Map;
  final whewsRaw = Map<String, dynamic>.from(capturedWhews);
  final whews = QuakeEventAdapter.convertWhews('cwa_eew', whewsRaw)!;
  // The unchanged WHEWS body is also a compatible FAN protocol input, not a
  // claimed capture from a FAN socket.
  final fan = FanService.decodeEventPayload(whewsRaw, sourceHint: 'cwa_eew')!;
  final wolfxReport =
      (readMap('test/fixtures/history_replay/cwa_1150074.rqreplay')['reports']
                  as List)
              .first
          as Map;
  final wolfxRaw = Map<String, dynamic>.from(
    wolfxReport['sourcePayload'] as Map,
  );
  final wolfx = QuakeEventAdapter.convert('cwaEew', wolfxRaw, 0)!;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'three original EEW parameter sets match all 1104 verified town grades',
    () {
      final references =
          jsonDecode(
                File(
                  'test/fixtures/source_estimation/cwa_town_prediction_reference.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      var checks = 0;
      for (final reference in references.whereType<Map>()) {
        final event = reference['event'] as Map;
        final forecast = CwaIntensityPrediction.predict(
          magnitude: (event['magnitude'] as num).toDouble(),
          depth: (event['depth'] as num).toDouble(),
          lat: (event['latitude'] as num).toDouble(),
          lng: (event['longitude'] as num).toDouble(),
          adjustment: (reference['adjustment'] as num).toDouble(),
        )!;
        expect(forecast.townRanks, reference['townRanks']);
        checks += forecast.townRanks.length;
      }
      expect(checks, 1104);
    },
  );

  test(
    'original replay produces the verified 368-town and 22-county prediction',
    () {
      final rawBefore = jsonEncode(original);
      final eventBefore = jsonEncode(jian.toMap());
      final forecast = cwaForecastForEvent(jian)!;
      expect(forecast.townRanks, hasLength(368));
      expect(forecast.countyRanks, reference['countyMax']);
      expect(forecast.townRanks['高雄市林園區'], 3);
      expect(forecast.maximumRank, 3);
      expect(cwaEewBadgeIntensity(jian), (rank: 3, estimated: true));
      expect(jian.maxIntensity, '-');
      expect(jian.sourcePayload, original);
      expect(jsonEncode(original), rawBefore);
      expect(jsonEncode(jian.toMap()), eventBefore);
    },
  );

  test('all four CWA API adapters feed the shared map predictor', () {
    for (final event in [fan, jian, whews, wolfx]) {
      expect(event.source, 'cwaEew');
      expect(event.useShindo, isTrue);
      expect(cwaForecastForEvent(event), isNotNull, reason: event.apiTypeLabel);
    }
    expect(fan.maxIntensity, '3');
    expect(cwaEewBadgeIntensity(fan), (rank: 3, estimated: false));
    expect(cwaEewBadgeIntensity(whews), (rank: 3, estimated: false));
    expect(fan.sourcePayload, whewsRaw);
    expect(whews.sourcePayload, whewsRaw);
    expect(wolfx.sourcePayload, wolfxRaw);
    expect(cwaEewBadgeIntensity(wolfx), isNull);
  });

  test('shared presentation estimates only the three requested badge paths', () {
    // Display-policy cases reuse the immutable normalized event, not a changed
    // source capture passed through a parser.
    for (final label in ['FAN', 'Jian Project', 'WHEWS']) {
      expect(cwaEewBadgeIntensity(jian.copyWith(apiTypeLabel: label)), (
        rank: 3,
        estimated: true,
      ));
      for (final value in ['0', '3', '5-', '5+', '6-', '6+', '7']) {
        final badge = cwaEewBadgeIntensity(
          jian.copyWith(apiTypeLabel: label, maxIntensity: value),
        )!;
        expect(CwaIntensityPrediction.labels[badge.rank], value);
        expect(badge.estimated, isFalse);
      }
    }
    expect(cwaEewBadgeIntensity(jian.copyWith(apiTypeLabel: 'Wolfx')), isNull);
    final ordinaryCwa = jian.copyWith(
      source: 'cwaEqlist',
      isEew: false,
      warnArea: '',
    );
    expect(cwaForecastForEvent(ordinaryCwa), isNotNull);
    expect(cwaObservedFillAvailable(ordinaryCwa), isFalse);
    expect(
      cwaObservedFillAvailable(
        ordinaryCwa.copyWith(
          warnArea: jsonEncode([
            {'name': '高雄市', 'intensity': '3', 'kind': 'observed'},
          ]),
        ),
      ),
      isTrue,
    );
  });

  test('PGA boundaries retain weak/strong grades without rounding', () {
    for (var i = 0; i < CwaIntensityPrediction.pgaThresholds.length; i++) {
      final threshold = CwaIntensityPrediction.pgaThresholds[i];
      expect(CwaIntensityPrediction.rankForPga(threshold * (1 - 1e-9)), i);
      expect(CwaIntensityPrediction.rankForPga(threshold), i + 1);
      expect(CwaIntensityPrediction.rankForPga(threshold * (1 + 1e-9)), i + 1);
    }
    for (final unknown in ['8', '12', 'NaN', 'Infinity', '5.9', '-']) {
      expect(CwaIntensityPrediction.parseRank(unknown), isNull);
    }
    expect(CwaIntensityPrediction.parseRank('5強'), 6);
    expect(CwaIntensityPrediction.parseRank('6弱'), 7);
  });

  test(
    'township data preserves absent factors and all available site factors',
    () {
      expect(cwaPredictionTowns, hasLength(368));
      expect(cwaPredictionTowns.where((t) => t.site == null), hasLength(10));
      expect(
        cwaPredictionTowns
            .singleWhere((t) => t.county == '高雄市' && t.town == '林園區')
            .site,
        1.319,
      );
    },
  );

  test(
    'cancel, training, invalid inputs and invalid supplied correction do not estimate',
    () {
      for (final event in [
        jian.copyWith(isCanceled: true),
        jian.copyWith(isAssumption: true),
        jian.copyWith(magnitude: double.nan),
        jian.copyWith(depth: -1),
        jian.copyWith(lat: double.nan),
        jian.copyWith(lng: 181),
      ]) {
        expect(cwaForecastForEvent(event), isNull);
        expect(cwaEewBadgeIntensity(event), isNull);
      }
      // Mathematical/protocol validation cases, not rewritten observed reports.
      for (final correction in [null, 0, -1, 'NaN', 'invalid']) {
        expect(
          cwaForecastForEvent(
            jian.copyWith(sourcePayload: {'pgaAdj': correction}),
          ),
          isNull,
        );
      }
      expect(
        cwaForecastForEvent(jian.copyWith(sourcePayload: {'isTraining': true})),
        isNull,
      );
      final before = cwaForecastForEvent(jian)!;
      final adjusted = cwaForecastForEvent(
        jian.copyWith(sourcePayload: {'pgaAdj': 2}),
      )!;
      expect(
        adjusted.countyRanks['高雄市'],
        greaterThan(before.countyRanks['高雄市']!),
      );
      expect(
        cwaForecastForEvent(jian.copyWith(replaySessionId: 'replay')),
        same(before),
      );
    },
  );

  test(
    'missing CWA fields never become valid zero-depth or zero-coordinate estimates',
    () {
      // Standalone invalid protocol input, not altered source observations.
      final incomplete = {'id': 'invalid-protocol', 'magnitude': 4.7};
      final event = FanService.decodeEventPayload(
        incomplete,
        sourceHint: 'cwa_eew',
      )!;
      expect(cwaForecastForEvent(event), isNull);
      expect(cwaEewBadgeIntensity(event), isNull);
    },
  );

  test(
    'regional predictions override matching places only and share cache with badges',
    () {
      final areas = jsonEncode([
        {'name': '高雄市', 'intensity': '5+'},
        {'name': '屏東縣琉球鄉', 'intensity': '6弱'},
      ]);
      final event = jian.copyWith(warnArea: areas);
      final forecast = cwaForecastForEvent(event)!;
      expect(forecast.countyRanks['高雄市'], 6);
      expect(forecast.countyRanks['屏東縣'], 7);
      expect(forecast.countyRanks['臺北市'], 0);
      expect(cwaEewBadgeIntensity(event), (rank: 7, estimated: true));
      expect(cwaForecastForEvent(event), same(forecast));
      final repeated = cwaForecastForEvent(jian)!;
      for (var i = 0; i < 1000; i++) {
        expect(
          cwaForecastForEvent(jian.copyWith(reportNumText: '第$i報')),
          same(repeated),
        );
      }
    },
  );

  test('FAN/WHEWS regional arrays reach the common predictor unchanged', () {
    final areas = [
      {'name': '高雄市', 'intensity': '5+'},
    ];
    // Explicit protocol coverage for optional arrays.
    final raw = {
      'id': 'protocol-area',
      'updates': 1,
      'magnitude': 4.7,
      'latitude': 22.45,
      'longitude': 120.34,
      'depth': 30,
      'shockTime': '2000-01-01 00:00:00',
      'warnArea': areas,
    };
    final before = jsonEncode(raw);
    for (final event in [
      FanService.decodeEventPayload(raw, sourceHint: 'cwa_eew')!,
      QuakeEventAdapter.convertWhews('cwa_eew', raw)!,
    ]) {
      expect(jsonDecode(event.warnArea), areas);
      expect(cwaForecastForEvent(event)!.countyRanks['高雄市'], 6);
      expect(event.sourcePayload, raw);
    }
    expect(jsonEncode(raw), before);
  });

  test(
    'Taiwan fill data excludes mainland, Hong Kong and Macau regions',
    () async {
      TopoJsonLoader.clearCache();
      final data = (await TopoJsonLoader.loadTwEew())!;
      expect(data.source, 'tw');
      expect(data.regions, hasLength(20));
      expect(data.regionMap, contains('高雄市'));
      expect(data.regionMap.containsKey('北京市'), isFalse);
      expect(data.regionMap.containsKey('湾仔区'), isFalse);
      expect(await TopoJsonLoader.loadTwEew(), same(data));
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('CWA badges keep geometry and superscripts at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(UnifiedQuakeData event) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>(
                create: (_) => _CapturedProvider(event),
              ),
              ChangeNotifierProvider(create: (_) => MapStateProvider()),
            ],
            child: MaterialApp(
              theme: ThemeData(
                fontFamily: previewFont.isEmpty ? null : 'CwaPreview',
              ),
              home: const Scaffold(
                body: SingleChildScrollView(child: AlertModule()),
              ),
            ),
          ),
        );
      }

      Finder badgeBox(String label) => find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.constraints?.minWidth == w.constraints?.maxWidth &&
                  w.constraints?.minHeight == w.constraints?.maxHeight &&
                  w.constraints?.minWidth == w.constraints?.minHeight,
            ),
          )
          .first;
      await show(jian);
      expect(find.text('预估震度'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      final box = tester.getSize(badgeBox('预估震度'));
      if (const bool.fromEnvironment('CAPTURE_CWA_PREVIEW')) {
        await tester.pump();
        final card = find.byKey(
          ValueKey(
            'unified_card_${jian.source}_${jian.eventId}_${jian.reportNumText}',
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find
              .descendant(of: card, matching: find.byType(RepaintBoundary))
              .first,
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File(
            'build/test-previews/cwa_badge_${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
        });
      }
      for (final value in ['0', '5+', '6-']) {
        await show(jian.copyWith(maxIntensity: value));
        expect(find.text('预估震度'), findsNothing);
        expect(tester.getSize(badgeBox('震度')), box);
        if (value.length == 2) {
          final main = tester.getRect(find.text(value[0]));
          final suffix = tester.getRect(find.text(value[1]));
          expect(suffix.left, greaterThanOrEqualTo(main.right));
          expect(suffix.bottom, lessThan(main.bottom));
        }
        expect(tester.takeException(), isNull);
      }
      await show(wolfx);
      expect(find.text('预估震度'), findsNothing);
      expect(find.text(wolfx.maxIntensity[0]), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Taiwan polygons render the CWA palette and reuse their list at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final forecast = cwaForecastForEvent(jian)!;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(23.5, 121),
                    initialZoom: 6,
                  ),
                  children: [
                    IntensityFillLayer(
                      source: 'tw',
                      mode: IntensityFillMode.cwa,
                      magnitude: jian.magnitude,
                      depth: jian.depth,
                      hypoLat: jian.lat!,
                      hypoLng: jian.lng!,
                      cwaForecast: forecast,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() => TopoJsonLoader.loadTwEew());
        await tester.pumpAndSettle();
        final polygons = tester
            .widget<PolygonLayer>(find.byType(PolygonLayer))
            .polygons;
        expect(polygons, isNotEmpty);
        final green = KaShindoMarkerStyle.colorForLevel(
          CwaIntensityPrediction.markerLevels[3],
        );
        expect(
          polygons.any(
            (p) =>
                p.color?.toARGB32() == green.withValues(alpha: 0.4).toARGB32(),
          ),
          isTrue,
        );
        final controller = MapController.of(
          tester.element(find.byType(IntensityFillLayer)),
        );
        controller.move(const LatLng(23.4, 120.8), 6.5);
        await tester.pump();
        expect(
          tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons,
          same(polygons),
        );
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_CWA_PREVIEW')) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            var nonblank = 0;
            for (var i = 0; i < pixels.lengthInBytes; i += 4) {
              if (pixels.getUint8(i) != pixels.getUint8(i + 1) ||
                  pixels.getUint8(i + 1) != pixels.getUint8(i + 2)) {
                nonblank++;
              }
            }
            expect(nonblank, greaterThan(100));
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            final file = File(
              'build/test-previews/cwa_map_${size.width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
