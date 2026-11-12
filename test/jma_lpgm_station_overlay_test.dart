import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/widgets/map/jma_lpgm_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart'
    show NiedIntensityNumberMarker;
import 'package:flutterrhythmquake/widgets/ui/jma_lpgm_sidebar_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final xml = File(
    'test/fixtures/jma_lpgm_20261108/20261107161354_0_VXSE62_010000.xml',
  ).readAsStringSync();
  late JmaLpgmBulletin bulletin;
  setUpAll(() {
    final parser = JmaLpgmService();
    bulletin = parser.parseDetailForTesting(xml)!;
    parser.dispose();
  });

  test(
    'four real VXSE62 stations resolve through JMA and non-JMA locations',
    () async {
      final locations = await JmaLpgmStationLocations.load();
      expect(locations.stations, hasLength(703));
      expect(locations.byCode, hasLength(703));
      expect(locations.byName.length, greaterThanOrEqualTo(703));
      expect(locations.byName['防府市寿']?.code, '3520601');
      expect(
        locations.stations.where((e) => e.network == 'NIED K-NET'),
        hasLength(31),
      );
      expect(bulletin.stations, hasLength(4));
      final located = JmaLpgmStationLocations.located(bulletin, locations);
      expect(located.length, 4);
      expect(located.map((e) => e.station.name), contains('飯田市高羽町'));
      expect(located.map((e) => e.station.name), contains('豊橋市向山'));
      expect(located.map((e) => e.station.name), contains('名古屋千種区日和町'));
      expect(located.map((e) => e.station.code), contains('2321120'));
      final toyota = located.singleWhere(
        (entry) => entry.station.code == '2321120',
      );
      expect(toyota.position.latitude, closeTo(35.0813, 0.00001));
      expect(toyota.position.longitude, closeTo(137.1466, 0.00001));
      expect(toyota.station.name, '豊田市小坂町＊');
    },
  );

  test(
    'all 703 JMA official long-period station codes resolve with unique coordinates',
    () async {
      final locations = await JmaLpgmStationLocations.load();
      final realStations = locations.stations
          .map(
            (item) => JmaLpgmStation(
              name: item.name,
              code: item.code,
              intensity: '',
              lgInt: 1,
              sva: null,
            ),
          )
          .toList();
      final artificialBulletin = JmaLpgmBulletin.fromMap({
        ...bulletin.toMap(),
        'stations': realStations.map((station) => station.toMap()).toList(),
      });
      final markers = JmaLpgmStationLocations.located(
        artificialBulletin,
        locations,
      );
      expect(markers, hasLength(703));
      final codePositions = <String>{};
      for (final marker in markers) {
        final code = marker.station.code;
        expect(locations.byCode.containsKey(code), isTrue);
        expect(codePositions.add(code), isTrue, reason: 'Repeated code: $code');
        expect(marker.position.latitude, inInclusiveRange(20, 50));
        expect(marker.position.longitude, inInclusiveRange(120, 155));
      }
      expect(locations.byCode['2321120']?.niedSiteCode, 'AIC009');
      expect(
        locations.byCode['1410199']?.position.latitude,
        closeTo(35.4608, 0.00001),
      );
      expect(locations.byCode['1336172']?.name, '伊豆大島町岡田');
    },
  );

  test(
    'real JMA level.csv has 179 actual stations and no missing station location',
    () async {
      final locations = await JmaLpgmStationLocations.load();
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/jma_lpgm_20261108/official_level_station_positions.json',
                ).readAsStringSync(),
              )
              as List;
      expect(raw, hasLength(179));
      for (final element in raw) {
        final station = element as Map;
        final name = station['name'] as String;
        final code = station['code'] as String;
        final byName =
            locations.byName[JmaLpgmStationLocations.normalizeName(name)];
        expect(byName, isNotNull, reason: '$code $name not in catalog');
        final lat = (station['lat'] as num).toDouble();
        final lng = (station['lng'] as num).toDouble();
        expect(
          byName!.position.latitude,
          closeTo(lat, 0.005),
          reason: '$code $name latitude mismatch',
        );
        expect(
          byName.position.longitude,
          closeTo(lng, 0.005),
          reason: '$code $name longitude mismatch',
        );
      }
    },
  );

  testWidgets(
    'station overlay renders observed markers without regional fill',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(35.1, 137.2),
                  initialZoom: 6,
                ),
                children: [JmaLpgmStationLayer(bulletin: bulletin)],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => JmaLpgmStationLocations.load());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MarkerLayer), findsOneWidget);
      final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(markerLayer.markers, hasLength(4));
      for (final marker in markerLayer.markers) {
        expect(marker.width, NiedIntensityNumberMarker.markerSize);
        expect(marker.height, NiedIntensityNumberMarker.markerSize);
      }
      expect(find.byType(PolygonLayer), findsNothing);
      // Station symbols must not open unrequested station info tips.
      expect(find.byType(Tooltip), findsNothing);
      expect(find.textContaining('SVA'), findsNothing);
      expect(
        find.byKey(const ValueKey('jma_lpgm_station_2020502')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('jma_lpgm_station_2321120')),
        findsOneWidget,
      );
    },
  );

  test(
    'long-period symbol uses exactly the NIED measured value marker size',
    () {
      expect(
        JmaLpgmMarkerStyle.markerSize,
        NiedIntensityNumberMarker.markerSize,
      );
      expect(JmaLpgmMarkerStyle.markerSize, 14.0);
      for (var level = 1; level <= 4; level++) {
        expect(
          JmaLpgmMarkerStyle.colorForClass(level),
          jmaLpgmClassColor(level),
        );
      }
      expect(JmaLpgmMarkerStyle.foregroundForClass(1), Colors.black);
      expect(JmaLpgmMarkerStyle.foregroundForClass(3), Colors.white);
      expect(JmaLpgmMarkerStyle.foregroundForClass(4), Colors.white);
    },
  );

  testWidgets('far zoom still shows four NIED numeric icons (no tiny dots)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(35.1, 137.2),
                initialZoom: 3.0,
              ),
              children: [JmaLpgmStationLayer(bulletin: bulletin)],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => JmaLpgmStationLocations.load());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(markers, hasLength(4));
    expect(find.byType(NiedIntensityNumberMarker), findsNWidgets(4));
    for (final marker in markers) {
      expect(marker.width, 14.0);
      expect(marker.height, 14.0);
    }
    expect(find.byType(PolygonLayer), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('long-period 1-4 render through the actual NIED value glyph', (
    tester,
  ) async {
    final sample = JmaLpgmBulletin.fromMap({
      ...bulletin.toMap(),
      'stations': [
        for (var i = 0; i < bulletin.stations.length; i++)
          {...bulletin.stations[i].toMap(), 'lgInt': i + 1},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(35.1, 137.2),
                initialZoom: 9.2,
              ),
              children: [JmaLpgmStationLayer(bulletin: sample)],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => JmaLpgmStationLocations.load());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(markers, hasLength(4));
    for (var i = 0; i < markers.length; i++) {
      expect(markers[i].width, NiedIntensityNumberMarker.markerSize);
      expect(markers[i].height, NiedIntensityNumberMarker.markerSize);
      final key = ValueKey('jma_lpgm_station_${sample.stations[i].code}');
      final item = tester.widget<NiedIntensityNumberMarker>(find.byKey(key));
      expect(item.color, jmaLpgmClassColor(i + 1));
      expect(item.label, (i + 1).toString());
      expect(item.highIntensity, isFalse);
      expect(
        item.foregroundColor,
        JmaLpgmMarkerStyle.foregroundForClass(i + 1),
      );
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.text((i + 1).toString()),
        ),
        findsOneWidget,
      );
    }
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('sidebar preserves all stations and every available period band', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 450,
            height: 620,
            child: JmaLpgmSidebarPanel(bulletin: bulletin, scale: (n) => n),
          ),
        ),
      ),
    );
    await tester.pump();
    // All four stations are built in the scrolling column (not top-six subset).
    final stationNames = bulletin.stations.map((s) => s.name);
    for (final name in stationNames) {
      expect(find.textContaining(name, findRichText: true), findsWidgets);
    }
    expect(find.textContaining('各周期阶级'), findsWidgets);
    expect(find.textContaining('各周期 SVA'), findsWidgets);
  });
}
