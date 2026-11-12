import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/native_station_summary.dart';
import 'package:flutterrhythmquake/services/sources/native_station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/whews_nied_station_metadata.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/models/snet_station.dart';
import 'package:flutterrhythmquake/widgets/map/station_summary_projection.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';

// Frozen region-assignment semantics from the pre-migration map method. This
// reference is only used for equivalence tests, never by the Windows runtime.
List<(String, int)> referenceAreas(
  List<NiedStation> stations,
  Map<String, NiedDetectionGridCell> cells,
) {
  final prefMax = <String, int>{};
  final buckets = <(int, int), List<NiedStation>>{};
  for (final s in stations.where((s) => s.isActive && s.level >= 0)) {
    (buckets[(
              s.coordinate.latitude.floor(),
              s.coordinate.longitude.floor(),
            )] ??=
            <NiedStation>[])
        .add(s);
  }
  for (final cell in cells.values) {
    final lat = cell.center.latitude.floor(),
        lng = cell.center.longitude.floor();
    final nearby = <NiedStation>[
      for (var y = lat - 1; y <= lat + 1; y++)
        for (var x = lng - 1; x <= lng + 1; x++)
          ...buckets[(y, x)] ?? const <NiedStation>[],
    ];
    final prefs = <String>{};
    for (final s in nearby) {
      if ((s.coordinate.latitude - cell.center.latitude).abs() <= .500001 &&
          (s.coordinate.longitude - cell.center.longitude).abs() <= .500001) {
        prefs.add(s.prefecture.trim().isNotEmpty ? s.prefecture : s.code);
      }
    }
    if (prefs.isEmpty) {
      NiedStation? nearest;
      var distance = double.infinity;
      for (final s in nearby) {
        final a = math.sin(
          (s.coordinate.latitude - cell.center.latitude) * math.pi / 180 / 2,
        );
        final b = math.sin(
          (s.coordinate.longitude - cell.center.longitude) * math.pi / 180 / 2,
        );
        final h =
            a * a +
            math.cos(cell.center.latitude * math.pi / 180) *
                math.cos(s.coordinate.latitude * math.pi / 180) *
                b *
                b;
        final d = 2 * 6371 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
        if (d < distance) {
          distance = d;
          nearest = s;
        }
      }
      if (nearest != null) {
        prefs.add(
          nearest.prefecture.trim().isNotEmpty
              ? nearest.prefecture
              : nearest.code,
        );
      }
    }
    final rank = JpShindoScale.jmaNumberFromKanameishiLevel(cell.level);
    for (final pref in prefs) {
      final name = pref.trim();
      if (name.isNotEmpty && rank > (prefMax[name] ?? -1)) prefMax[name] = rank;
    }
  }
  final result = [for (final e in prefMax.entries) (e.key, e.value)]
    ..sort((a, b) {
      final order = b.$2.compareTo(a.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = !NativeStationSummary.supported;
  final clock = DateTime.utc(2026, 10, 16);
  test(
    'startup empty frames followed by growing station batches survive JIT and GC',
    () {
      final baseline =
          NativeStationImageDecoder.memoryStats['rustCurrentBytes'];
      final owner = NativeStationSummary();
      try {
        for (var i = 0; i < 60; i++) {
          for (var kind = 0; kind < 6; kind++) {
            owner.update(kind, 0, (rows) => expect(rows, isEmpty));
          }
          owner.cells(0, (rows) => expect(rows, isEmpty));
          owner.niedLevels(0, (rows) => expect(rows, isEmpty));
        }
        // Controlled transport lifecycle, not altered earthquake observations.
        // The pre-fix Windows Debug crashed near 2000 updates in the standalone
        // JIT reproduction; normal value-only tests never reached this transition.
        for (var i = 0; i < 20000; i++) {
          if (i % 3 == 0) owner.update(0, 0, (rows) {});
          final count = i % 32 + 1;
          owner.update(0, count, (rows) {
            for (var j = 0; j < count; j++) {
              rows[j * 5] = j.toDouble();
            }
          }, regions: List.filled(count, '原站'));
          expect(owner.readIndices((indices) => indices[1]), count - 1);
        }
      } finally {
        owner.dispose();
      }
      expect(
        NativeStationImageDecoder.memoryStats['rustCurrentBytes'],
        baseline,
      );
    },
    skip: skip,
  );
  StationSummaryData project(
    StationSummaryProjection p, {
    List<NiedStation> nied = const [],
    List<SeisJsStation> seisjs = const [],
    List<SnetStation> snet = const [],
    List<CwaStation> cwa = const [],
    List<PAlertStation> palert = const [],
    ShakeDetectionSnapshot detection = ShakeDetectionService.idleSnapshot,
    Set<String>? changed,
  }) => p.project(
    nied: nied,
    kma: const [],
    cwa: cwa,
    palert: palert,
    seisjs: seisjs,
    snet: snet,
    detection: detection,
    lpgm: null,
    windowEnd: clock,
    changed: changed,
  );

  test(
    'original 1560-station capture and original SeisJS frames preserve selected values',
    () async {
      final metadata = File(
        'test/fixtures/whews_nied/stations.json',
      ).readAsBytesSync();
      final body = File(
        'test/fixtures/whews_nied/observations.json',
      ).readAsBytesSync();
      final raw = jsonDecode(utf8.decode(body)) as Map;
      final directory = jsonDecode(utf8.decode(metadata)) as Map;
      final coordinates = [
        for (final s in directory['stations'] as List)
          LatLng(
            (s['latitude'] as num).toDouble(),
            (s['longitude'] as num).toDouble(),
          ),
      ];
      final stations = buildWhewsNiedStations(coordinates);
      for (var i = 0; i < stations.length; i++) {
        final value = (raw['Data']['shindo'][i] as num).toDouble();
        stations[i].updateFromContinuousShindo(
          value > -3 && value <= 7 ? value : null,
          render: false,
        );
      }
      final js = <SeisJsStation>[];
      for (var i = 1; i <= 7; i++) {
        final data =
            jsonDecode(
                  File(
                    'test/fixtures/source_ws_followup_20261016/seisjs_0$i.original.bytes',
                  ).readAsStringSync(encoding: utf8),
                )
                as Map;
        js.add(
          SeisJsStation(
            id: data['type'],
            region: data['region'],
            coordinate: LatLng(
              (data['latitude'] as num).toDouble(),
              (data['longitude'] as num).toDouble(),
            ),
            intensity: (data['Intensity'] as num).toDouble(),
          ),
        );
      }
      final beforeLevels = [for (final s in stations) s.level];
      final before = NativeStationSummary.diagnostics;
      final p = StationSummaryProjection();
      try {
        var expected = -1;
        NiedStation? max;
        for (final s in stations) {
          if (s.level >= 0 && s.level > expected) {
            expected = s.level;
            max = s;
          }
        }
        final actual = project(p, nied: stations, seisjs: js);
        expect(actual.niedMaxStation, same(max));
        expect(
          actual.seisJsMaxStation,
          same(selectSeisJsCurrentMaxStation(js)),
        );
        final after = NativeStationSummary.diagnostics;
        final next = project(
          p,
          nied: stations,
          seisjs: js,
          changed: const {'seisjs'},
        );
        expect(next.niedMaxStation, same(max));
        expect(NativeStationSummary.diagnostics['calls']! - after['calls']!, 1);
        expect(
          NativeStationSummary.diagnostics['rows']! - after['rows']!,
          js.length,
        );
        expect(stations.map((s) => s.level), beforeLevels);
        expect(
          File('test/fixtures/whews_nied/stations.json').readAsBytesSync(),
          metadata,
        );
        expect(
          File('test/fixtures/whews_nied/observations.json').readAsBytesSync(),
          body,
        );
      } finally {
        p.dispose();
      }
      expect(NativeStationSummary.diagnostics['sessions'], before['sessions']);
    },
    skip: skip,
  );

  // Model-level boundary cases; these are not modified upstream captures.
  test(
    'all S-net boundaries retain original ranking, ties, signed zero and visibility',
    () {
      SnetStation s(
        String code,
        double value, {
        bool active = true,
        int level = 0,
      }) => SnetStation(
        code: code,
        name: code,
        coordinate: const LatLng(0, 0),
        depth: 0,
        network: 'test',
        type: 'test',
        shindo: value,
        level: level,
        isActive: active,
      );
      final input = [
        s('trigger', .5),
        s('zero', 0),
        s('negative-zero', -0.0),
        s('nan', double.nan),
        s('infinity', double.infinity),
        s('invalid', 7, level: -1),
        s('inactive', 7, active: false),
        s('B', .5),
        s('A', .5),
        s('negative', -3),
        s('😀', .5),
        s('\uE000', .5),
      ];
      final p = StationSummaryProjection();
      addTearDown(p.dispose);
      for (var start = 0; start < input.length; start++) {
        final ordered = [...input.skip(start), ...input.take(start)];
        final actual = project(p, snet: ordered).snetTopStations;
        final expected = selectSnetSidebarTopStations(ordered);
        expect(
          actual.map((s) => (s.code, s.jmaIndex)),
          expected.map((s) => (s.code, s.jmaIndex)),
        );
        for (var i = 0; i < actual.length; i++) {
          expect(actual[i].shindo.compareTo(expected[i].shindo), 0);
        }
      }
      expect(project(p, snet: [s('A', .49)]).snetTopStations, isEmpty);
      expect(project(p).snetTopStations, isEmpty);
    },
    skip: skip,
  );

  test(
    'NIED regions match original cell and nearest rules, then clear on empty data',
    () {
      NiedStation s(
        String code,
        String pref,
        double lat,
        double lng,
        int level,
      ) => NiedStation(
        id: code.hashCode,
        code: code,
        name: code,
        coordinate: LatLng(lat, lng),
        network: 'boundary',
        prefecture: pref,
        expireSeconds: 10,
        level: level,
      )..isActive = true;
      final stations = [
        s('A', '\uFEFF岩手県 ', 35, 140, 16),
        s('B', '宮城県', 35.3, 140.2, 18),
        s('C', '', 36.6, 140, 17),
        s('😀', '😀', 35.1, 140.1, 15),
        s('D', '\uE000', 35.2, 140, 14),
      ];
      final cells = {
        'first': const NiedDetectionGridCell(
          center: LatLng(35, 140),
          level: 16,
          shindo: 4.6,
        ),
        'nearest': const NiedDetectionGridCell(
          center: LatLng(36, 140),
          level: 18,
          shindo: 5.8,
        ),
        'far': const NiedDetectionGridCell(
          center: LatLng(0, 0),
          level: 20,
          shindo: 7,
        ),
      };
      final detection = ShakeDetectionSnapshot(
        stage: ShakeDetectStage.strong,
        weakCount: 1,
        detectedCount: 2,
        strongCount: 3,
        maxShindo: 6,
        gridCells: cells,
      );
      final p = StationSummaryProjection();
      addTearDown(p.dispose);
      final actual = project(p, nied: stations, detection: detection);
      expect(
        actual.niedDetect!.visualAreas.map((a) => (a.name, a.jmaShindo)),
        referenceAreas(stations, cells),
      );
      expect(actual.niedDetect!.visualGridCount, 3);
      stations.first.isActive = false;
      final changed = project(
        p,
        nied: stations,
        detection: detection,
        changed: const {'detection'},
      );
      expect(
        changed.niedDetect!.visualAreas.map((a) => (a.name, a.jmaShindo)),
        referenceAreas(stations, cells),
      );
      expect(project(p).niedMaxStation, isNull);
      expect(project(p).niedDetect!.visualAreas, isEmpty);
    },
    skip: skip,
  );

  test(
    'CWA active alert and P-Alert held sampled and raw levels use native selection',
    () {
      final cwa = [
        CwaStation(
          id: 'a',
          code: 1,
          net: 'test',
          coordinate: const LatLng(0, 0),
          work: true,
          intensity: 9,
          hasAlert: true,
          alertIntensity: 2,
        ),
        CwaStation(
          id: 'b',
          code: 2,
          net: 'test',
          coordinate: const LatLng(0, 0),
          work: true,
          intensity: 3,
        ),
      ];
      PAlertStation pa(
        String id, {
        int? held,
        int? sampled,
        double? pga,
        double? pgv,
      }) => PAlertStation(
        id: id,
        network: 'boundary',
        name: id,
        area: '',
        coordinate: const LatLng(0, 0),
        heldLevel: held,
        sampledLevel: sampled,
        pgaGal: pga,
        pgvCms: pgv,
      );
      final palert = [
        pa('held', held: 3, pga: 999),
        pa('sampled', sampled: 5, pga: 999),
        pa('raw', pga: 100, pgv: 30),
        pa('missing'),
      ];
      final p = StationSummaryProjection();
      addTearDown(p.dispose);
      final actual = project(p, cwa: cwa, palert: palert);
      expect(actual.treaMaxStation, same(cwa[1]));
      final expected = palert.reduce(
        (a, b) => a.gridLevel >= b.gridLevel ? a : b,
      );
      expect(actual.pAlertMaxStation, same(expected));
      final independent = StationSummaryProjection();
      try {
        expect(project(independent).pAlertMaxStation, isNull);
      } finally {
        independent.dispose();
      }
      expect(
        project(
          p,
          cwa: cwa,
          palert: palert,
          changed: const {'cwa'},
        ).pAlertMaxStation,
        same(expected),
      );
    },
    skip: skip,
  );

  test(
    'native buffers survive reuse and reject bad revisions without replacing state',
    () {
      final baseline = NativeStationSummary.diagnostics['sessions'];
      final baselineBytes =
          NativeStationImageDecoder.memoryStats['rustCurrentBytes'];
      for (var cycle = 0; cycle < 20; cycle++) {
        final owner = NativeStationSummary();
        owner.update(
          1,
          2,
          (rows) {
            rows.setAll(0, [2, 2, 1, 35, 140, 3, 3, 1, 35.1, 140.1]);
          },
          codes: const ['A', 'B'],
          regions: const ['岩手県', '宮城県'],
        );
        owner.cells(1, (rows) => rows.setAll(0, [35, 140, 16]));
        final first = owner.indices;
        final firstAreas = owner.areas;
        owner.niedLevels(2, (rows) => rows.setAll(0, [4, 1, 1, 0]));
        expect(owner.indices[2], 0);
        expect(first[2], 1);
        expect(firstAreas.map((a) => a.$1), ['宮城県', '岩手県']);
        expect(() => owner.niedLevels(1, (_) {}), throwsStateError);
        expect(owner.indices[2], 0);
        expect(
          () => owner.cells(1, (rows) => rows.setAll(0, [double.nan, 140, 16])),
          throwsStateError,
        );
        expect(owner.areas.map((a) => a.$1), ['岩手県']);
        owner.dispose();
        owner.dispose();
        expect(first[2], 1);
        expect(() => owner.indices, throwsStateError);
      }
      expect(NativeStationSummary.diagnostics['sessions'], baseline);
      expect(
        NativeStationImageDecoder.memoryStats['rustCurrentBytes'],
        baselineBytes,
      );
    },
    skip: skip,
  );

  test(
    'same-length catalogue coordinate and region revisions reach native owner',
    () {
      NiedStation view(double lat, String prefecture) => NiedStation(
        id: 1,
        code: 'A',
        name: 'A',
        coordinate: LatLng(lat, 140),
        network: 'boundary',
        prefecture: prefecture,
        expireSeconds: 10,
        level: 16,
      )..isActive = true;
      final detection = ShakeDetectionSnapshot(
        stage: ShakeDetectStage.strong,
        weakCount: 1,
        detectedCount: 1,
        strongCount: 1,
        maxShindo: 5,
        gridCells: const {
          'cell': NiedDetectionGridCell(
            center: LatLng(35, 140),
            level: 16,
            shindo: 4.6,
          ),
        },
      );
      final p = StationSummaryProjection();
      addTearDown(p.dispose);
      expect(
        project(
          p,
          nied: [view(35, '岩手県')],
          detection: detection,
        ).niedDetect!.visualAreas.single.name,
        '岩手県',
      );
      expect(
        project(
          p,
          nied: [view(35, '宮城県')],
          detection: detection,
          changed: const {'nied'},
        ).niedDetect!.visualAreas.single.name,
        '宮城県',
      );
      expect(
        project(
          p,
          nied: [view(40, '宮城県')],
          detection: detection,
          changed: const {'nied'},
        ).niedDetect!.visualAreas,
        isEmpty,
      );
    },
    skip: skip,
  );
}
