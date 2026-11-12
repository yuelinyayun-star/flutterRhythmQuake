import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/services/nmefc_coastal_map_service.dart';
import 'package:flutterrhythmquake/widgets/ui/nmefc_coastal_map_panel.dart';

const coastalUrl =
    'https://obs.nmefc.cn/Warning/TsunamiAdvice/202404030758_2_file/Coastal_Forecast_Point.jpg';

// Transport/UI protocol case using the original, unchanged official JPG bytes.
// It is not a captured realtime warning and is never injected into the APP.
TsunamiMessage protocol(int number, {String url = coastalUrl}) =>
    TsunamiMessage(
      source: TsunamiSource.nmefc,
      eventId: 'protocol-coastal-map',
      reportNumber: number,
      reportTime: '2024-04-03 08:52:00',
      timeZone: 8,
      grade: TsunamiGrade.warning,
      coastalMapUrl: url,
      amplitudeMapUrl: 'https://obs.nmefc.cn/protocol/amplitude.jpg',
    );

Future<void> settleImage(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find
        .byType(RawImage)
        .evaluate()
        .any((e) => (e.widget as RawImage).image != null)) {
      return;
    }
    if (tester.takeException() case final Object error) throw error;
  }
  fail('Official coastal image was not decoded');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'NMEFC coastal image through native report plan',
    () {
      test(
        'missing chart does not substitute amplitude and repeated reports load once',
        () async {
          final jpg = File(
            'test/fixtures/tsunami_regions/Coastal_Forecast_Point_20240403_B2.original.jpg',
          ).readAsBytesSync();
          var requests = 0;
          final client = MockClient((request) async {
            requests++;
            expect(request.url.toString(), coastalUrl);
            expect(request.headers['Cache-Control'], 'no-cache');
            return http.Response.bytes(jpg, 200);
          });
          addTearDown(client.close);
          final service = NmefcCoastalMapService(client: client);
          final archive =
              jsonDecode(
                    File(
                      'test/fixtures/catalog_20260917/whews_all.json',
                    ).readAsStringSync(),
                  )
                  as List;
          final raw = Map<String, dynamic>.from(
            archive.singleWhere((e) => e['source'] == 'tsunami')['Data'] as Map,
          );
          final before = jsonEncode(raw);
          final captured = await TsunamiMessage.parseNmefcTsunamiAsync(raw);
          expect(await service.load(captured), isNull);
          expect(requests, 0);
          expect(jsonEncode(raw), before);
          final first = await service.load(protocol(2));
          expect(first!.bytes, jpg);
          expect(identical(await service.load(protocol(2)), first), isTrue);
          expect(requests, 1);
          expect((await service.load(protocol(3)))!.caption, contains('第3报'));
          expect(requests, 2);
        },
      );

      test(
        'failed requests are retryable and cache retains only two reports',
        () async {
          var requests = 0;
          final client = MockClient((_) async {
            requests++;
            return requests == 1
                ? http.Response('', 503)
                : http.Response.bytes([1], 200);
          });
          addTearDown(client.close);
          final service = NmefcCoastalMapService(client: client);
          await expectLater(
            service.load(protocol(1)),
            throwsA(isA<http.ClientException>()),
          );
          await service.load(protocol(1));
          await service.load(protocol(2));
          await service.load(protocol(3));
          await service.load(protocol(1));
          expect(requests, 5);
        },
      );

      testWidgets(
        'official JPG fits sidebar and opens complete original with no overflow',
        (tester) async {
          final jpg = File(
            'test/fixtures/tsunami_regions/Coastal_Forecast_Point_20240403_B2.original.jpg',
          ).readAsBytesSync();
          var requests = 0;
          final client = MockClient((_) async {
            requests++;
            return http.Response.bytes(jpg, 200);
          });
          addTearDown(client.close);
          final service = NmefcCoastalMapService(client: client);
          const boundary = ValueKey('coastal-map-preview');
          for (final size in [const Size(288, 250), const Size(160, 220)]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  backgroundColor: Colors.black,
                  body: Center(
                    child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: NmefcCoastalMapPanel(
                          message: protocol(2),
                          scale: 1,
                          service: service,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await settleImage(tester);
            expect(find.text('NMEFC 岸段预报图 · 第2报'), findsOneWidget);
            expect(
              tester.widget<Image>(find.byType(Image)).fit,
              BoxFit.contain,
            );
            expect(tester.takeException(), isNull);
            if (size.width == 288) {
              final image = await tester.runAsync(
                () => tester
                    .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
                    .toImage(pixelRatio: 2),
              );
              final png = await tester.runAsync(
                () => image!.toByteData(format: ImageByteFormat.png),
              );
              await tester.runAsync(() async {
                final output = File(
                  'tmp/nmefc_coastal_map_20261021/sidebar.png',
                );
                await output.parent.create(recursive: true);
                await output.writeAsBytes(png!.buffer.asUint8List());
              });
              image!.dispose();
              await tester.tap(find.byType(Image));
              await tester.pumpAndSettle();
              expect(find.byType(InteractiveViewer), findsOneWidget);
              expect(requests, 1);
              await tester.tap(find.byIcon(Icons.close));
              await tester.pumpAndSettle();
            }
          }
          expect(requests, 1);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    },
    skip: NativeJmaTsunami.supported
        ? false
        : 'Requires Windows station-core DLL',
  );
}
