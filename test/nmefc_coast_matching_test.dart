import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/native_tsunami_regions.dart';
import 'package:flutterrhythmquake/services/tsunami_region_service.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_region_layer.dart';
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

// Protocol matching cases using the names in the unchanged official 2024-04-03
// bulletin. This is not a captured WHEWS warning or a live injected report.
Map<String, dynamic> protocol({bool fullNames = false}) => {
  'code': 'protocol-coast-match',
  'warningInfo': {'level': '橙色'},
  'timeInfo': {'alarmDate': '2024-04-03 08:52:00'},
  'details': {'batch': '2'},
  'forecasts': [
    {
      'province': '台湾',
      'forecastArea': fullNames ? '花莲县' : '花莲',
      'forecastPoint': '花莲',
      'maxWaveHeight': '100-300',
      'warningLevel': '橙色',
    },
    {
      'province': '台湾',
      'forecastArea': fullNames ? '宜兰县' : '宜兰',
      'forecastPoint': '宜兰县',
      'maxWaveHeight': '30-100',
      'warningLevel': '黄色',
    },
    {
      'province': '台湾',
      'forecastArea': '台东北',
      'forecastPoint': '富冈',
      'maxWaveHeight': '30-100',
      'warningLevel': '黄色',
    },
  ],
};

// Explicit mainland format cases, not fabricated live NMEFC bulletins.
Map<String, dynamic> mainlandProtocol() => {
  ...protocol(),
  'forecasts': [
    {'province': '浙江', 'forecastArea': '温州', 'warningLevel': '橙色'},
    {'province': '福建省', 'forecastArea': '福州', 'warningLevel': '黄色'},
    {'province': '广东', 'forecastArea': '深圳', 'warningLevel': '红色'},
    {'province': '广西', 'forecastArea': '防城港', 'warningLevel': '蓝色'},
    {'province': '海南', 'forecastArea': '海口', 'warningLevel': '黄色'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'NMEFC named coasts actual native path',
    () {
      test(
        'source format matches county shores locally and keeps raw data unchanged',
        () async {
          final raw = protocol(fullNames: true);
          final original = jsonDecode(jsonEncode(raw));
          final message = await TsunamiMessage.parseNmefcTsunamiAsync(raw);
          final client = MockClient(
            (_) async => throw StateError('Named coasts must not issue HTTP'),
          );
          addTearDown(client.close);
          final lines = await TsunamiRegionService(
            client: client,
          ).load(message);
          expect(raw, original);
          expect(message.sourcePayload, original);
          expect(lines.map((v) => v['name']), ['花莲县', '宜兰县']);
          expect(lines.map((v) => v['coastName']), ['台湾省花莲县', '台湾省宜兰县']);
          expect(lines.map((v) => v['className']), ['orange', 'yellow']);
          expect(lines.map((v) => v['strokeArgb']), [0xffffa500, 0xffffff00]);
          expect(
            lines.every(
              (v) => v['matchKind'] == 'namedAdministrativeCoastline',
            ),
            isTrue,
          );
          final base =
              jsonDecode(
                    File(
                      'assets/maps/nmefc.named-coasts.geo.json',
                    ).readAsStringSync(),
                  )
                  as Map;
          final flower = (base['features'] as List).singleWhere(
            (f) => f['properties']['name'] == '台湾省花莲县',
          );
          expect(lines.first['lines'], flower['geometry']['coordinates']);
        },
      );
      test(
        'station/forecast-point names cannot replace an unmatched forecast region',
        () async {
          final raw = protocol();
          raw['forecasts'] = [
            {
              'province': '台湾',
              'forecastArea': '未定义岸段',
              'forecastPoint': '花莲',
              'warningLevel': '红色',
            },
            {'province': '福建', 'forecastArea': '宜兰', 'warningLevel': '黄色'},
          ];
          final message = await TsunamiMessage.parseNmefcTsunamiAsync(raw);
          expect(await TsunamiRegionService().load(message), isEmpty);
        },
      );
      test(
        'historical abbreviations select county coasts by the configured display policy',
        () async {
          final raw = protocol();
          final original = jsonDecode(jsonEncode(raw));
          final message = await TsunamiMessage.parseNmefcTsunamiAsync(raw);
          final lines = await TsunamiRegionService().load(message);
          expect(raw, original);
          expect(message.sourcePayload, original);
          expect(lines.map((v) => v['name']), ['花莲', '宜兰']);
          expect(lines.map((v) => v['coastName']), ['台湾省花莲县', '台湾省宜兰县']);
          expect(lines.map((v) => v['strokeArgb']), [0xffffa500, 0xffffff00]);
          expect(lines.any((v) => v['name'] == '台东北'), isFalse);
        },
      );
      test('cancellation does not restore named shore geometry', () async {
        final raw = protocol();
        raw['warningInfo'] = {'level': '解除'};
        final message = await TsunamiMessage.parseNmefcTsunamiAsync(raw);
        expect(await TsunamiRegionService().load(message), isEmpty);
      });
      test(
        'mainland original province and city fields reach the native coastline path',
        () async {
          final raw = mainlandProtocol();
          final original = jsonDecode(jsonEncode(raw));
          final message = await TsunamiMessage.parseNmefcTsunamiAsync(raw);
          final client = MockClient(
            (_) async =>
                throw StateError('Mainland coasts must not issue HTTP'),
          );
          addTearDown(client.close);
          final lines = await TsunamiRegionService(
            client: client,
          ).load(message);
          expect(raw, original);
          expect(message.sourcePayload, original);
          expect(lines.map((v) => v['coastName']), [
            '浙江省温州市',
            '福建省福州市',
            '广东省深圳市',
            '广西壮族自治区防城港市',
            '海南省海口市',
          ]);
          expect(lines.map((v) => v['strokeArgb']), [
            0xffffa500,
            0xffffff00,
            0xffff0000,
            0xff0000ff,
            0xffffff00,
          ]);
        },
      );
      testWidgets(
        'prepared mainland coasts reach the existing outline layer with source colours',
        (tester) async {
          final message = await tester.runAsync(
            () => TsunamiMessage.parseNmefcTsunamiAsync(mainlandProtocol()),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(24, 121.6),
                  initialZoom: 7,
                ),
                children: [TsunamiRegionLayer(tsunami: message!)],
              ),
            ),
          );
          for (
            var i = 0;
            i < 150 && find.byType(PolylineLayer).evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(find.byType(PolylineLayer), findsOneWidget);
          final layer = tester.widget<PolylineLayer>(
            find.byType(PolylineLayer),
          );
          expect(layer.polylines.map((line) => line.color).toSet(), {
            const Color(0xffffa500),
            const Color(0xffffff00),
            const Color(0xffff0000),
            const Color(0xff0000ff),
          });
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    },
    skip: NativeTsunamiRegions.supported
        ? false
        : 'Requires Windows station-core DLL',
  );
}
