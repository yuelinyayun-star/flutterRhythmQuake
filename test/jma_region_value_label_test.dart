import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_region_value_badge_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_region_value_label.dart';
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('badge follows SREV square-root scaling at different viewports', () {
    for (final viewport in const [Size(1584, 850), Size(430, 900)]) {
      final edges = <double>[];
      for (final zoom in [4.0, 7.0, 10.0, 12.0]) {
        final world = 256.0 * math.pow(2, zoom);
        final screen = math.min(viewport.width / 480, viewport.height / 360);
        final expected =
            2.2 * screen * (4 + math.sqrt(world / (3600 * screen)));
        final edge = jmaRegionValueBadgeEdge(world, viewport);
        expect(edge, closeTo(expected, 1e-9));
        if (edges.isNotEmpty) expect(edge, greaterThan(edges.last));
        edges.add(edge);
      }
      expect(edges.last / edges.first, greaterThan(2.5));
      debugPrint('SREV_BADGE_SCALE viewport=$viewport zoom4/7/10/12=$edges');
    }
  });

  test(
    'bundled digit ink is visually centered, including narrow digit 1',
    () async {
      await loadUnifiedUiFonts();
      final centers = <(String, double, double)>[];
      for (final digit in '01234567'.split('')) {
        final text = TextPainter(
          text: TextSpan(text: digit, style: jmaRegionValueTextStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final ink = jmaRegionValueInkBounds(text, digit);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(4);
        text.paint(
          canvas,
          const Offset(20, 20) - jmaRegionValueOpticalCenter(text, digit, ink),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(160, 160);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var left = 160, top = 160, right = -1, bottom = -1;
        for (var y = 0; y < 160; y++) {
          for (var x = 0; x < 160; x++) {
            if (pixels.getUint8((y * 160 + x) * 4 + 3) < 128) continue;
            left = math.min(left, x);
            right = math.max(right, x);
            top = math.min(top, y);
            bottom = math.max(bottom, y);
          }
        }
        expect(right, greaterThan(left));
        var centerX = (left + right + 1) / 8;
        if (digit == '1') {
          // Check the main upright stroke below the flag, not the full outline.
          var stemLeft = 160, stemRight = -1;
          for (var y = 84; y < 104; y++) {
            for (var x = 0; x < 160; x++) {
              if (pixels.getUint8((y * 160 + x) * 4 + 3) < 128) continue;
              stemLeft = math.min(stemLeft, x);
              stemRight = math.max(stemRight, x);
            }
          }
          expect(stemRight, greaterThan(stemLeft));
          centerX = (stemLeft + stemRight + 1) / 8;
        }
        centers.add((digit, centerX, (top + bottom + 1) / 8));
        image.dispose();
        picture.dispose();
        text.dispose();
      }
      debugPrint('DIGIT_INK_CENTERS $centers');
      for (final (digit, x, y) in centers) {
        expect(x, closeTo(20, .4), reason: '$digit horizontal ink center');
        expect(y, closeTo(20, .4), reason: '$digit vertical ink center');
      }
    },
  );

  test(
    'region label uses the main outline area center rather than its widest lobe',
    () {
      final region = TopoJsonRegion(
        name: 'renderer center contract',
        polygons: [
          const [
            LatLng(1, 1),
            LatLng(1, 6),
            LatLng(2, 6),
            LatLng(2, 2),
            LatLng(5, 2),
            LatLng(5, 1),
          ],
        ],
      );
      final polygon = Polygon(points: region.polygons.single);
      final expected = const PolygonLabelPlacementCalculator.centroid()(
        polygon,
      );
      final point = JmaRegionValuePlacement.forRegion(region)(polygon);
      // This L-shaped centroid is outside; correction stays in the nearby lobe.
      expect(point.latitude, lessThan(expected.latitude));
      expect(point.longitude, lessThan(expected.longitude));
      final rectangle = TopoJsonRegion(
        name: 'rectangle',
        polygons: [
          const [LatLng(1, 1), LatLng(1, 5), LatLng(3, 5), LatLng(3, 1)],
        ],
      );
      expect(
        JmaRegionValuePlacement.forRegion(rectangle)(
          Polygon(points: rectangle.polygons.single),
        ),
        const LatLng(2, 3),
      );
    },
  );

  test(
    'weak/strong keep the main digit size with a smaller aligned suffix',
    () async {
      await loadUnifiedUiFonts();
      for (final value in ['5-', '5+', '6-', '6+']) {
        final layout = JmaRegionValueBadgeTextLayout(
          Polygon(
            points: const [],
            label: value,
            labelStyle: jmaRegionValueTextStyle,
          ),
        );
        expect(layout.main.text!.style!.fontSize, 20);
        expect(layout.suffix!.text!.style!.fontSize, 11);
        expect(layout.ink.width, lessThanOrEqualTo(28));
        expect(layout.ink.height, lessThanOrEqualTo(22));
        layout.dispose();
      }
    },
  );

  test(
    'four original information classes opt in; original EEW/foreign do not',
    () {
      final files = [
        File('test/fixtures/jma_camera_20261030/p2p_history.original.json'),
        File('test/fixtures/catalog_20260917/whews_all.json'),
      ];
      final hashes = [
        for (final f in files) sha256.convert(f.readAsBytesSync()),
      ];
      final p2p =
          jsonDecode(files.first.readAsStringSync(encoding: utf8)) as List;
      for (final i in [23, 24, 25]) {
        final event = QuakeEventAdapter.convert(
          'jmaEqlist',
          Map<String, dynamic>.from(p2p[i]),
          2,
        )!;
        expect(showJmaInformationRegionValues(event), isTrue);
      }
      final foreign = p2p.firstWhere((r) => r['issue']['type'] == 'Foreign');
      expect(
        showJmaInformationRegionValues(
          QuakeEventAdapter.convert(
            'jmaEqlist',
            Map<String, dynamic>.from(foreign),
            2,
          )!,
        ),
        isFalse,
      );
      final whews =
          jsonDecode(files.last.readAsStringSync(encoding: utf8)) as List;
      for (final source in ['jma', 'jma_eew']) {
        final frame = whews.singleWhere((r) => r['source'] == source);
        final event = QuakeEventAdapter.convertWhews(
          source,
          Map<String, dynamic>.from(frame['Data']),
        )!;
        expect(showJmaInformationRegionValues(event), source == 'jma');
      }
      for (var i = 0; i < files.length; i++) {
        expect(sha256.convert(files[i].readAsBytesSync()), hashes[i]);
      }
    },
  );

  test(
    'region labels preserve zero, weak/strong and the existing fill scale',
    () {
      final samples = <double, String>{
        0: '0',
        1: '1',
        2: '2',
        3: '3',
        4: '4',
        4.5: '5-',
        5: '5+',
        5.5: '6-',
        6: '6+',
        7: '7',
      };
      for (final sample in samples.entries) {
        expect(jmaRegionValueText(sample.key), sample.value);
      }
      // The existing reported-zero fill carries 0.5 as its class sentinel.
      expect(jmaRegionValueText(.5, className: 'dark-gray'), '0');
      expect(jmaRegionValueText(3.49), '3');
      expect(jmaRegionValueText(3.5), '4');
    },
  );

  test(
    'one cached interior position uses the main concave component, not an island',
    () {
      // Renderer geometry contract, not fabricated earthquake observations.
      final region = TopoJsonRegion(
        name: 'concave renderer contract',
        polygons: [
          const [LatLng(0, 0), LatLng(0, .1), LatLng(.1, .1), LatLng(.1, 0)],
          const [
            LatLng(1, 1),
            LatLng(1, 5),
            LatLng(5, 5),
            LatLng(5, 4),
            LatLng(2, 4),
            LatLng(2, 2),
            LatLng(5, 2),
            LatLng(5, 1),
          ],
        ],
      );
      final before = jsonEncode([
        for (final p in region.polygons)
          [
            for (final v in p) [v.latitude, v.longitude],
          ],
      ]);
      final placement = JmaRegionValuePlacement.forRegion(region);
      expect(placement.polygonIndex, 1);
      expect(
        identical(placement, JmaRegionValuePlacement.forRegion(region)),
        isTrue,
      );
      final polygon = Polygon(
        points: region.polygons[1],
        label: '3',
        labelPlacementCalculator: placement,
      );
      final point = polygon.labelPosition;
      final insideLeft =
          point.longitude > 1 &&
          point.longitude < 2 &&
          point.latitude > 1 &&
          point.latitude < 5;
      final insideBottom =
          point.longitude > 1 &&
          point.longitude < 5 &&
          point.latitude > 1 &&
          point.latitude < 2;
      final insideRight =
          point.longitude > 4 &&
          point.longitude < 5 &&
          point.latitude > 1 &&
          point.latitude < 5;
      expect(insideLeft || insideBottom || insideRight, isTrue);
      expect(identical(point, placement(polygon)), isTrue);
      final newStyle = Polygon(
        points: region.polygons[1],
        label: '4',
        labelPlacementCalculator: placement,
      );
      expect(identical(point, newStyle.labelPosition), isTrue);
      expect(
        jsonEncode([
          for (final p in region.polygons)
            [
              for (final v in p) [v.latitude, v.longitude],
            ],
        ]),
        before,
      );
    },
  );

  testWidgets(
    'labels preserve fill geometry/color/callback and cache through rebuilds and pan/zoom',
    (tester) async {
      await tester.runAsync(loadUnifiedUiFonts);
      await tester.runAsync(TopoJsonLoader.loadJpEew);
      final input = File(
        'test/fixtures/jma_camera_20261030/p2p_history.original.json',
      );
      final bytes = input.readAsBytesSync(),
          hash = sha256.convert(input.readAsBytesSync());
      final raw = (jsonDecode(utf8.decode(bytes)) as List)[23] as Map;
      final event = QuakeEventAdapter.convert(
        'jmaEqlist',
        Map<String, dynamic>.from(raw),
        2,
      )!;
      final controller = MapController();
      var callbacks = 0;
      List<TopoJsonRegion>? geometry;
      Widget host({bool values = false}) => MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: const MapOptions(
            initialCenter: LatLng(37.4, 141.5),
            initialZoom: 7,
          ),
          children: [
            IntensityFillLayer(
              key: const ValueKey('fill'),
              source: 'jp',
              mode: IntensityFillMode.jma,
              magnitude: event.magnitude,
              depth: event.depth,
              hypoLat: event.lat!,
              hypoLng: event.lng!,
              warnAreaJson: event.warnArea,
              opacity: .55,
              showRegionValues: values,
              onInformationGeometry: (v) {
                callbacks++;
                geometry = v;
              },
            ),
          ],
        ),
      );
      await tester.pumpWidget(host());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      List<Polygon> polygons() =>
          tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons;
      final original = polygons();
      expect(original, isNotEmpty);
      expect(original.every((p) => p.label == null), isTrue);
      expect(
        original.every((p) => p.labelStyle == const TextStyle()),
        isTrue,
        reason: 'Disabled labels must keep the original default style',
      );
      final calls = callbacks;
      final painted = geometry;
      await tester.pumpWidget(host(values: true));
      await tester.pump();
      final labelled = polygons();
      expect(labelled.length, original.length);
      for (var i = 0; i < labelled.length; i++) {
        expect(identical(labelled[i].points, original[i].points), isTrue);
        expect(labelled[i].color, original[i].color);
        expect(labelled[i].borderColor, original[i].borderColor);
        expect(labelled[i].borderStrokeWidth, original[i].borderStrokeWidth);
      }
      final labels = labelled.where((p) => p.label != null).toList();
      expect(
        labelled
            .where((p) => p.label == null)
            .every((p) => p.labelStyle == const TextStyle()),
        isTrue,
        reason: 'Unlabelled island components must not build label styles',
      );
      expect(
        tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygonLabels,
        isFalse,
      );
      void checkBadgeGeometry() {
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<JmaRegionValueBadgePainter>()
            .single;
        expect(painter.labels, isNotEmpty);
        final camera = controller.camera;
        expect(
          painter.edge,
          closeTo(
            jmaRegionValueBadgeEdge(camera.getWorldWidthAtZoom(), camera.size),
            1e-9,
          ),
        );
        final rectangles = <Rect>[];
        for (final label in painter.labels) {
          final expected =
              camera.projectAtZoom(label.polygon.labelPosition) -
              camera.pixelOrigin;
          expect((label.point - expected).distance, lessThan(.000001));
          final rectangle = Rect.fromCenter(
            center: label.point,
            width: painter.edge,
            height: painter.edge,
          ).inflate(3);
          expect(rectangles.any((r) => r.overlaps(rectangle)), isFalse);
          rectangles.add(rectangle);
        }
      }

      checkBadgeGeometry();
      await tester.runAsync(() async {
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<JmaRegionValueBadgePainter>()
            .single;
        final point =
            painter.labels.first.point - Offset(painter.edge * .34, 0);
        for (final background in const [
          Color(0xFF4499FF),
          Color(0xFF44BB66),
          Color(0xFFDDDD00),
        ]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..drawColor(background, BlendMode.src);
          painter.paint(canvas, controller.camera.size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(800, 600);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset = (point.dy.floor() * 800 + point.dx.floor()) * 4;
          for (var channel = 0; channel < 3; channel++) {
            final source = (background.toARGB32() >> (16 - channel * 8)) & 255;
            final badge = jmaRegionValueBadgeColor(
              painter.labels.first.polygon.color!,
            );
            final foreground = (badge.toARGB32() >> (16 - channel * 8)) & 255;
            expect(
              pixels.getUint8(offset + channel),
              closeTo(source * (1 - badge.a) + foreground * badge.a, 1.1),
              reason:
                  'badge uses its own region color and slight transparency without a dark overlay',
            );
          }
          image.dispose();
          picture.dispose();
        }
      });
      expect(labels.length, painted!.length);
      expect(
        labels.every(
          (p) =>
              p.labelStyle ==
              jmaRegionValueTextStyle.copyWith(
                color: jmaRegionValueBadgeForeground(p.color!),
              ),
        ),
        isTrue,
      );
      final texts = labels.map((p) => p.textPainter).toList();
      final anchors = labels.map((p) => p.labelPosition).toList();
      final watch = Stopwatch()..start();
      for (var frame = 0; frame < 40; frame++) {
        controller.move(
          LatLng(37.4 + frame * .001, 141.5),
          6.5 + (frame % 4) * .1,
        );
        await tester.pumpWidget(host(values: true));
        await tester.pump();
        expect(identical(polygons(), labelled), isTrue);
        checkBadgeGeometry();
      }
      for (var i = 0; i < labels.length; i++) {
        expect(identical(labels[i].textPainter, texts[i]), isTrue);
        expect(identical(labels[i].labelPosition, anchors[i]), isTrue);
      }
      expect(callbacks, calls);
      expect(sha256.convert(input.readAsBytesSync()), hash);
      expect(tester.takeException(), isNull);
      debugPrint(
        'REGION_LABEL_CACHE labels=${labels.length} panZoomFrames=40 newPolygonLists=0 newAnchors=0 newTextPainters=0 elapsedMs=${watch.elapsedMilliseconds}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(find.byType(JmaRegionValueBadgeLayer), findsNothing);
      controller.dispose();
    },
  );
}
