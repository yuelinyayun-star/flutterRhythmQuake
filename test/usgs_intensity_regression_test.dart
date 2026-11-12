import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';

import 'support/unified_ui_fonts.dart';

const _directory = 'test/fixtures/usgs_intensity_20261013';
dynamic _read(String file) =>
    jsonDecode(File('$_directory/$file').readAsStringSync(encoding: utf8));

// Select the actual superseded product without editing its values. The event
// view uses that version's original info.json, rather than today's revised M6.8.
UsgsShakeMapFrame _originalFirstVersion() {
  final detail = _read('us6000u214.versions.original.geojson') as Map;
  final product = (detail['properties']['products']['shakemap'] as List)
      .firstWhere((p) => p['properties']['version'] == '1');
  final info = _read('us6000u214.v1.info.original.json');
  final input = info['input']['event_information'] as Map;
  final latitude = double.parse(input['latitude']);
  final longitude = double.parse(input['longitude']);
  return UsgsShakeMapFrame(
    event: QuakeMessage(
      source: QuakeSourceType.usgs,
      eventId: input['event_id'],
      location: getFEName(latitude, longitude),
      magnitude: double.parse(input['magnitude']),
      depth: double.parse(input['depth']),
      latitude: latitude,
      longitude: longitude,
      originTime: DateTime.parse(input['origin_time']),
      timeZone: 0,
    ),
    product: UsgsShakeMapProduct.fromDetail({
      ...detail,
      'properties': {
        ...detail['properties'],
        'products': {
          'shakemap': [product],
        },
      },
    })!,
    contours: UsgsMmiContour.parse(
      _read('us6000u214.v1.cont_mmi.original.json'),
    ),
  );
}

// A projection of an actual saved APP dedupe body key. This is not a captured
// WHEWS wire frame. It reproduces the normalized adapter fields recorded by the
// APP, including the zero which replaced its previous 9.0 display value.
Map<String, dynamic> _savedZeroBody() {
  final keys = (_read('saved-usgs-body-keys.capture.json') as List)
      .cast<String>();
  final row = keys.singleWhere((key) => key.split('|')[7] == '0').split('|');
  return {
    'id': row[0],
    'placeName': row[2],
    'latitude': double.parse(row[3]),
    'longitude': double.parse(row[4]),
    'depth': double.parse(row[5]),
    'magnitude': double.parse(row[6]),
    'maxIntensity': row[7],
    'infoTypeName': row[8],
    'shockTime': row[9],
    'updateTime': DateTime.fromMillisecondsSinceEpoch(
      int.parse(row[10]),
      isUtc: true,
    ).toIso8601String(),
  };
}

// Synthetic boundary contract, kept separate from the original captures.
Map<String, dynamic> _mmiContract(Object? maximum, Object? grid) => {
  'id': 'test-mmi-contract',
  'properties': {
    'products': {
      'shakemap': [
        {
          'status': 'UPDATE',
          'updateTime': 1,
          'properties': {
            'minimum-latitude': 0,
            'maximum-latitude': 1,
            'minimum-longitude': 0,
            'maximum-longitude': 1,
            'maxmmi': maximum,
            'maxmmi-grid': grid,
          },
          'contents': <String, dynamic>{},
        },
      ],
    },
  },
};

class _CardsProvider extends QuakeProvider {
  _CardsProvider(this.cards)
    : super(
        shakeMapService: UsgsShakeMapService(),
        startCatalogServices: false,
      );
  final List<UnifiedQuakeData> cards;
  @override
  List<UnifiedQuakeData> get unifiedDisplayEvents => cards;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('original oceanic v1 uses explicit grid MMI without changing data', () {
    for (final entry in _read('SHA256.json') as List) {
      expect(
        sha256
            .convert(File('$_directory/${entry['file']}').readAsBytesSync())
            .toString(),
        entry['sha256'],
      );
    }
    final frame = _originalFirstVersion();
    final info = _read('us6000u214.v1.info.original.json');
    expect(info['output']['ground_motions']['MMI']['max'], isNull);
    expect(frame.product.maxMmi, 8.195);
    expect(frame.event.magnitude, 6.9);
    expect(frame.event.depth, 10);
    expect(frame.event.originTime, DateTime.parse('2026-10-13T12:23:07.383Z'));
    expect(frame.contours, isNotEmpty);
    final event = QuakeEventAdapter.shakeMapInfo(frame);
    expect(event.maxIntensity, '8.195');
    expect(event.className, 'dark-orange');
    expect(event.reportNumText, '第1版');
    expect(event.rawEvent, same(frame.event));
    final presentation = UnifiedEventPresentation.fromEvent(event);
    expect(presentation.intensityValue, 'VIII');
    expect(presentation.intensityLabel, 'MMI');
  });

  test('only finite in-range ShakeMap maxima can reach the badge palette', () {
    for (final invalid in [
      null,
      '',
      'nan',
      'NaN',
      'Infinity',
      '-Infinity',
      0,
      -1,
      13,
    ]) {
      final fallback = UsgsShakeMapProduct.fromDetail(
        _mmiContract(invalid, '8.195'),
      )!;
      expect(fallback.maxMmi, 8.195, reason: '$invalid');
      final absent = UsgsShakeMapProduct.fromDetail(
        _mmiContract(invalid, invalid),
      )!;
      expect(absent.maxMmi, isNull, reason: '$invalid');
    }
    expect(
      UsgsShakeMapProduct.fromDetail(_mmiContract('4.25', '8.195'))!.maxMmi,
      4.25,
    );
  });

  test(
    'saved WHEWS USGS zero uses the existing CSIS estimate, preserving zero',
    () {
      final raw = _savedZeroBody();
      final original = jsonEncode(raw);
      final event = QuakeEventAdapter.convertWhews('usgs', raw)!;
      final estimate = IntensityCalculator.calcCsisLevel(6.9, 10, 0);
      expect(estimate, 9);
      expect(event.maxIntensity, '9.0');
      expect(event.className, 'red');
      expect(event.sourcePayload!['maxIntensity'], '0');
      expect(jsonEncode(raw), original);
      expect(UnifiedEventPresentation.fromEvent(event).intensityValue, 'IX');
    },
  );

  test(
    'WHEWS USGS valid low intensity stays low; invalid fields never round NaN',
    () {
      // These are explicit adapter boundary cases, not altered source captures.
      for (final value in ['1', 'Ⅰ', 'Ⅳ', '4.25']) {
        final raw = <String, dynamic>{
          'id': 'test-reported-mmi',
          'maxIntensity': value,
        };
        final event = QuakeEventAdapter.convertWhews('usgs', raw)!;
        expect(event.maxIntensity, value);
        expect(event.sourcePayload!['maxIntensity'], value);
      }
      for (final value in ['NaN', 'Infinity', '-1', '13', '0', '']) {
        final event = QuakeEventAdapter.convertWhews('usgs', {
          'id': 'test-unusable-mmi',
          'maxIntensity': value,
        })!;
        expect(event.maxIntensity, '-');
        expect(event.className, 'gray');
      }
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
      'both corrected cards render and paginate without overflow at $size',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        SoundEffectService().enabled = false;
        addTearDown(() => SoundEffectService().enabled = true);
        await tester.runAsync(loadUnifiedUiFonts);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final shakeMap = QuakeEventAdapter.shakeMapInfo(
          _originalFirstVersion(),
        );
        final usgs = QuakeEventAdapter.convertWhews('usgs', _savedZeroBody())!;
        final provider = _CardsProvider([shakeMap, usgs]);
        final map = MapStateProvider();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: map),
            ],
            child: MaterialApp(
              theme: unifiedUiTestTheme(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: boundary,
                    child: SizedBox(width: 420, child: AlertModule()),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('VIII'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('VIII')).style!.color,
          const Color(0xFFFF4F00),
        );
        expect(find.text('未知'), findsNothing);
        if (size.shortestSide < 600) {
          await tester.pump(const Duration(seconds: 5));
        }
        expect(find.text('IX'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('IX')).style!.color,
          const Color(0xFFDF0F0F),
        );
        expect(find.text('I'), findsNothing);
        expect(tester.takeException(), isNull);
        final preview = Platform.environment['RHYTHMQUAKE_USGS_PREVIEW'];
        if (preview != null && size.shortestSide >= 600) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(preview).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
        map.dispose();
      },
    );
  }
}
