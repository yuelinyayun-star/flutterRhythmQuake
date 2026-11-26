import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart';
import 'package:flutterrhythmquake/models/snet_station.dart';
import 'package:flutterrhythmquake/widgets/map/cwa_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/snet_layer.dart';
import 'package:flutterrhythmquake/widgets/map/seisjs_layer.dart';

import 'native_palert_runtime_test.dart' as archive;
import 'package:flutterrhythmquake/core/source_estimation/palert_source_profile.dart';

void main() {
  final stamp = DateTime.utc(2026, 11, 25);
  test(
    'P-Alert original archive: equivalent bands, PGV and noise gate coverage',
    () {
      final frames = archive.earthquakeFrames();
      final levels = <int, int>{}, codes = <int, int>{};
      final seenTimes = <String>{};
      var valid = 0, missing = 0, noise = 0, high = 0, highMissingPgv = 0;
      for (final f in frames) {
        final raw = f.originalJson!['data'] as Map;
        final a = raw['data']['pga'] as Map, b = raw['data']['pgv'] as Map;
        if (!seenTimes.add(a['timestamp'].toString())) continue;
        final pgvs = a['timestamp'] == b['timestamp']
            ? b['dataVals'] as Map
            : const {};
        for (final e in (a['dataVals'] as Map).entries) {
          final pga = (e.value as num?)?.toDouble(),
              pgv = (pgvs[e.key] as num?)?.toDouble();
          final k = PAlertSourceProfile.level(pga, pgv);
          final c = JpShindoScale.srevCodeFromKanameishiLevel(k);
          if (k < 0) {
            missing++;
            expect(c, 0);
            continue;
          }
          valid++;
          if (pga! < 0.8) noise++;
          if (pga >= 80) {
            high++;
            if (pgv == null) highMissingPgv++;
          }
          levels.update(k, (v) => v + 1, ifAbsent: () => 1);
          codes.update(c, (v) => v + 1, ifAbsent: () => 1);
          expect(c, inInclusiveRange(1, 30));
        }
      }
      final report = {
        'archiveFrames': frames.length,
        'uniquePgaFrames': seenTimes.length,
        'validSamples': valid,
        'missingSamples': missing,
        'belowNoiseGate': noise,
        'highPgaSamples': high,
        'highWithoutMatchingPgv': highMissingPgv,
        'kaBands': levels.map((k, v) => MapEntry('$k', v)),
        'srevCodes': codes.map((k, v) => MapEntry('$k', v)),
      };
      Directory('tmp/srev_nied_migration_20261125').createSync(recursive: true);
      File(
        'tmp/srev_nied_migration_20261125/palert_srev_scale_audit.json',
      ).writeAsStringSync(jsonEncode(report));
      print(jsonEncode(report));
      expect(valid, greaterThan(0));
      expect(noise, greaterThan(0));
    },
  );

  test('all 99 original observation values and KA midpoint bands', () {
    const ends = [
      4,
      9,
      14,
      18,
      21,
      24,
      28,
      31,
      34,
      38,
      41,
      44,
      48,
      51,
      54,
      58,
      61,
      64,
      68,
      71,
      74,
      77,
      79,
      82,
      84,
      87,
      89,
      92,
      94,
      98,
    ];
    for (var q = 0; q < 99; q++) {
      final shindo = (q - 30) / 10;
      expect(
        JpShindoScale.srevCodeFromShindo(shindo),
        ends.indexWhere((v) => q <= v) + 1,
      );
    }
    const midpoint = [
      1,
      1,
      2,
      3,
      4,
      6,
      7,
      9,
      10,
      12,
      13,
      15,
      16,
      18,
      19,
      21,
      22,
      24,
      26,
      28,
      30,
    ];
    for (var k = 0; k <= 20; k++)
      expect(JpShindoScale.srevCodeFromKanameishiLevel(k), midpoint[k]);
    for (final v in <double?>[
      null,
      -3.01,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(JpShindoScale.srevCodeFromShindo(v), 0);
    }
    expect(CwaStationService.gridLevelFromInstShindo(double.nan), -1);
    expect(CwaStationService.gridLevelFromInstShindo(double.infinity), -1);
    expect(JpShindoScale.srevCodeFromShindo(7.0), 30);
  });
  test('source-specific current, held and missing semantics', () {
    final c = CwaStation(
      id: 'c',
      code: 1,
      net: 'TREM',
      coordinate: const LatLng(24, 121),
      work: true,
      intensity: 0.3,
      alertIntensity: 2.5,
      hasAlert: true,
      lastUpdate: stamp,
    );
    expect(c.srevObservationCode, 9);
    expect(c.srevDisplayCode, 16);
    expect(CwaStationService.gridLevelFromInstShindo(c.currentIntensity), 12);
    final p = PAlertStation(
      id: 'p',
      network: 'P-Alert',
      name: 'p',
      area: '',
      coordinate: const LatLng(24, 121),
      pgaGal: 80,
      pgvCms: 80,
      heldLevel: 20,
      dataTime: stamp,
      receivedAt: stamp,
    );
    expect(p.currentGridLevel, 19);
    expect(p.srevObservationCode, 28);
    expect(p.srevDisplayCode, 30);
    expect(p.shindoLabel, '7');
    final s = SnetStation(
      code: 's',
      name: 's',
      coordinate: const LatLng(35, 141),
      depth: 1000,
      network: '0120A',
      type: 'acceleration',
      shindo: 0.49,
      level: JpShindoScale.levelFromShindo(0.49),
      isActive: true,
      lastUpdate: stamp,
    );
    expect(s.srevObservationCode, 10);
    expect(JpShindoScale.jmaIndexFromShindo(s.shindo), 0);
    s.isActive = false;
    expect(s.srevObservationCode, 0);
    final m = SeisJsStation(
      id: 'm',
      region: '',
      coordinate: const LatLng(35, 140),
      calcShindo: 1.5,
      intensity: 9,
      lastUpdate: stamp,
    );
    expect(m.srevCalculatedCode, 13);
    expect(seisJsMapIntensityLevel(m.intensity), 9);
    m.calcShindo = -3;
    expect(m.srevCalculatedCode, 0);
  });
  testWidgets(
    'CWA old prepared display and physical projection have identical actual marker labels',
    (tester) async {
      final input = [
        -3.1,
        -3.0,
        -0.51,
        -0.5,
        0.45,
        0.49,
        0.5,
        1.49,
        1.5,
        2.5,
        3.5,
        4.45,
        4.5,
        5.0,
        5.5,
        6.0,
        6.5,
        7.0,
      ];
      Future<(List<String>, List<int>)> render(
        bool legacy,
        double zoom,
        bool zero,
      ) async {
        final key = GlobalKey();
        final stations = [
          for (var i = 0; i < input.length; i++)
            CwaStation(
                id: 'c$i',
                code: i,
                net: 'TREM',
                coordinate: LatLng(
                  24 + (i ~/ 6) * 0.25,
                  120.0 + (i % 6) * 0.25,
                ),
                work: true,
                intensity: input[i],
                alertIntensity: input[i],
                hasAlert: true,
                lastUpdate: stamp,
              )
              ..preparedGridLevel = legacy
                  ? (input[i] < -3
                        ? -1
                        : input[i] == -3
                        ? 0
                        : input[i] >= 6.5
                        ? 20
                        : (input[i] * 2 + 7).floor())
                  : null,
        ];
        for (final s in stations) {
          s.srevObservationCode;
          s.srevDisplayCode;
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: const LatLng(24.3, 120.6),
                  initialZoom: zoom,
                ),
                children: [
                  CwaStationLayer(
                    stations: stations,
                    hideGrid: true,
                    displayShindo0: zero,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final labels = tester
            .widgetList<Text>(find.byType(Text))
            .map((v) => v.data ?? '')
            .toList();
        final bytes = await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final rgba = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final png = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          final dir = Directory(
            'tmp/srev_nied_migration_20261125/other_source_render',
          )..createSync(recursive: true);
          File(
            '${dir.path}/cwa_${zoom}_${zero}_${legacy ? "before" : "after"}.png',
          ).writeAsBytesSync(png);
          image.dispose();
          return rgba;
        });
        return (labels, bytes!);
      }

      for (final mode in [(3.9, false), (4.0, false), (6.0, true)]) {
        final before = await render(true, mode.$1, mode.$2);
        final after = await render(false, mode.$1, mode.$2);
        expect(after.$1, before.$1);
        expect(after.$2, before.$2);
        print("CWA pixel comparison ${after.$2.length ~/ 4} pixels identical");
        if (mode.$1 >= 4) {
          expect(after.$1, containsAll(['5-', '5+', '6-', '6+', '7']));
        } else {
          expect(after.$1, isEmpty);
        }
        print(
          'CWA zoom ${mode.$1} show0=${mode.$2} markers=${after.$1.length} ${after.$1.join(',')}',
        );
      }
    },
  );
  testWidgets(
    'S-net and SeisJS retain source-specific symbols after conversion',
    (tester) async {
      final input = [-3.0, -0.6, -0.5, 0.49, 0.5, 4.5, 5.0, 5.5, 6.0, 6.5];
      final s = [
        for (var i = 0; i < input.length; i++)
          SnetStation(
            code: 'S$i',
            name: 'S$i',
            coordinate: LatLng(35 + i * 0.1, 140),
            depth: 1000,
            network: '0120A',
            type: 'acceleration',
            shindo: input[i],
            level: JpShindoScale.levelFromShindo(input[i]),
            isActive: true,
            lastUpdate: stamp,
          ),
      ];
      final mobile = SeisJsStation(
        id: 'M',
        region: '',
        coordinate: const LatLng(35, 140.6),
        intensity: 12,
        calcShindo: 1.5,
        lastUpdate: stamp,
      );
      for (final v in s) {
        expect(v.srevObservationCode, greaterThan(0));
      }
      expect(mobile.srevCalculatedCode, 13);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(35.5, 140.2),
              initialZoom: 6,
            ),
            children: [
              SnetLayer(stations: s),
              SeisJsLayer(stations: [mobile]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsNWidgets(2));
      for (final v in ['1', '5-', '5+', '6-', '6+', '7', '12'])
        expect(find.text(v), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
