import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/china_fault_service.dart';
import 'package:flutterrhythmquake/widgets/map/china_fault_layer.dart';
import 'package:flutterrhythmquake/services/japan_fault_service.dart';
import 'package:flutterrhythmquake/widgets/map/japan_fault_layer.dart';
import 'package:flutterrhythmquake/widgets/map/cached_fault_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = File(ChinaFaultService.assetPath).readAsStringSync();

  test('fault overlay defaults off and only notifies on real changes', () {
    final provider = MapStateProvider();
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);
    expect(provider.isOverlayEnabled('cnFault'), isFalse);
    expect(provider.isOverlayEnabled('jpFault'), isFalse);
    provider.setOverlayEnabled('cnFault', false);
    expect(notifications, 0);
    provider.setOverlayEnabled('cnFault', true);
    provider.setOverlayEnabled('cnFault', true);
    expect(provider.isOverlayEnabled('cnFault'), isTrue);
    expect(notifications, 1);
    provider.setOverlayEnabled('cnFault', false);
    expect(notifications, 2);
    provider.setOverlayEnabled('jpFault', true);
    expect(provider.isOverlayEnabled('cnFault'), isFalse);
    expect(provider.isOverlayEnabled('jpFault'), isTrue);
    expect(notifications, 3);
  });

  test('original KA topology matches topojson-client 3.1.0 geometry', () {
    final lines = parseChinaFaults(source);
    expect(lines, hasLength(2608));
    expect(lines.fold<int>(0, (n, l) => n + l.points.length), 48439);
    final canonical = lines
        .map(
          (line) => [
            line.name,
            line.age,
            line.points
                .map(
                  (p) => [
                    p.longitude.toStringAsFixed(9),
                    p.latitude.toStringAsFixed(9),
                  ],
                )
                .toList(),
          ],
        )
        .toList();
    expect(
      sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
      '73ac1e59669311bbde4aecaa21838d24b2d88b705526de0daa94c4627375e6f3',
    );
    expect(chinaFaultColor('Qh'), const Color(0x80FF0000));
    expect(chinaFaultColor('Qp3'), const Color(0x80FFA500));
    expect(chinaFaultColor('Qp1-QP2'), const Color(0x80008000));
  });

  test('concurrent loads share one parse and failures can retry', () async {
    var loads = 0;
    final service = ChinaFaultService(
      loadAsset: () async {
        loads++;
        return source;
      },
    );
    final first = service.load();
    expect(identical(first, service.load()), isTrue);
    final data = await first;
    expect(identical(data, await service.load()), isTrue);
    expect(loads, 1);
    var attempts = 0;
    final retry = ChinaFaultService(
      loadAsset: () async {
        if (attempts++ == 0) throw const FormatException('test failure');
        return source;
      },
    );
    await expectLater(retry.load(), throwsFormatException);
    expect(await retry.load(), hasLength(2608));
  });

  for (final japan in [false, true]) {
    for (final size in [const Size(1280, 720), const Size(430, 850)]) {
      testWidgets(
        '${japan ? 'Japan' : 'China'} faults render and preserve map gestures at $size',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = MapController();
          addTearDown(controller.dispose);
          final key = GlobalKey();
          var loads = 0;
          final service = ChinaFaultService(
            loadAsset: () async {
              loads++;
              return source;
            },
          );
          final japanService = JapanFaultService(
            loadAsset: () async {
              loads++;
              return File(JapanFaultService.assetPath).readAsBytesSync();
            },
          );
          await tester.runAsync(() async {
            if (japan) {
              await japanService.load();
            } else {
              await service.load();
            }
          });
          final enabled = ValueNotifier(true);
          addTearDown(enabled.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: RepaintBoundary(
                key: key,
                child: FlutterMap(
                  mapController: controller,
                  options: MapOptions(
                    initialCenter: japan
                        ? const LatLng(37, 137)
                        : const LatLng(35, 104),
                    initialZoom: 4,
                    backgroundColor: Color(0xFFF2F2F2),
                  ),
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: enabled,
                      builder: (_, value, child) => value
                          ? (japan
                                ? JapanFaultLayer(service: japanService)
                                : ChinaFaultLayer(service: service))
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.runAsync(() async {});
          await tester.pumpAndSettle();
          expect(find.byType(CachedFaultLayer), findsOneWidget);
          final before = tester.widget<CachedFaultLayer>(
            find.byType(CachedFaultLayer),
          );
          expect(CachedFaultLayer.strokeWidth, 1.5);
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            var colored = 0;
            for (var i = 0; i < rgba.lengthInBytes; i += 4) {
              if (rgba.getUint8(i) != rgba.getUint8(i + 1)) colored++;
            }
            expect(colored, greaterThan(500));
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final directory = Directory('tmp/china_fault_review')
              ..createSync(recursive: true);
            File(
              '${directory.path}/${japan ? 'japan' : 'china'}-faults-${size.width.toInt()}.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
          });
          final center = controller.camera.center;
          await tester.drag(find.byType(FlutterMap), const Offset(100, 35));
          await tester.pumpAndSettle();
          expect(controller.camera.center, isNot(center));
          expect(
            identical(
              before,
              tester.widget<CachedFaultLayer>(find.byType(CachedFaultLayer)),
            ),
            isTrue,
          );
          controller.move(
            japan ? const LatLng(35, 137) : const LatLng(30, 104),
            8,
          );
          await tester.pumpAndSettle();
          enabled.value = false;
          await tester.pumpAndSettle();
          expect(find.byType(CachedFaultLayer), findsNothing);
          enabled.value = true;
          await tester.pump();
          await tester.runAsync(() async {});
          await tester.pumpAndSettle();
          expect(loads, 1);
          expect(find.byType(CachedFaultLayer), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
