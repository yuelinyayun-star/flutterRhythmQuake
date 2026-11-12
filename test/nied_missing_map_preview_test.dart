import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/native_station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory(
    'tmp/captures/nied_false_detection_20261102_111827_jst_lmoni',
  );
  testWidgets(
    'render real original-frame missing and recovery stations with the production map widget',
    (tester) async {
      final snapshots = <List<NiedStation>>[];
      await tester.runAsync(() async {
        final font = File('C:/Windows/Fonts/msyh.ttc');
        if (await font.exists()) {
          final bytes = await font.readAsBytes();
          await (FontLoader(
            'NiedPreview',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
        final service = LmoniImageService()..start();
        try {
          for (var i = 0; i < 3; i++) {
            final bytes = File(
              '${dir.path}/2026110211160$i.jma_s.gif',
            ).readAsBytesSync();
            final scan = await NiedBackgroundWorker.instance.scanFrame(
              surfaceBytes: bytes,
              configs: service.backgroundScanConfigs,
              configSignature: service.backgroundScanConfigSignature,
            );
            final ready = service.stationStream.firstWhere((v) => v != null);
            service.processSampledFrame(
              scan!,
              surfaceGifBytes: bytes,
              dataTime: DateTime.parse('2026-11-02T11:16:0$i+09:00'),
              receivedAt: DateTime.now(),
            );
            snapshots.add(
              (await ready)!.map(NiedStation.detachedSnapshot).toList(),
            );
          }
        } finally {
          service.stop();
          NiedBackgroundWorker.instance.stop();
        }
      });
      tester.view.physicalSize = const Size(1200, 460);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final titles = ['正常', '当前帧缺测', '数据恢复'];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'NiedPreview',
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: const Color(0xff202124),
              body: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Column(
                        children: [
                          const SizedBox(height: 18),
                          Text(
                            titles[i],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '2026-11-02 11:16:0$i JST',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: FlutterMap(
                                options: MapOptions(
                                  backgroundColor: const Color(0xff202124),
                                  initialCenter: snapshots[i]
                                      .firstWhere((s) => s.code == 'TYM002')
                                      .coordinate,
                                  initialZoom: 12,
                                ),
                                children: [
                                  NiedIntensityLayer(stations: snapshots[i]),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: snapshots[i]
                                            .firstWhere(
                                              (s) => s.code == 'TYM002',
                                            )
                                            .coordinate,
                                        width: 100,
                                        height: 50,
                                        alignment: Alignment.bottomCenter,
                                        child: const Align(
                                          alignment: Alignment.topCenter,
                                          child: Text(
                                            'TYM002',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            i == 1 ? '灰色点 · 缺测，不显示震度数字' : '原配色、原透明度',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 22),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final picture =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'tmp/cloud_vgpub_20261101/nied-missing-map-preview.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        picture.dispose();
      });
      expect(tester.takeException(), isNull);
    },
    skip: !NativeStationImageDecoder.supported || !dir.existsSync(),
  );
}
