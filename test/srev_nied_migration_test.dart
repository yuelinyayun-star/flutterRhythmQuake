// Explicit local integration replay, using the saved independent SREV output.
// Set RQ_SREV_COMPARISON_INPUT to comparison_input.json from the migration audit.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart';

final _input = Platform.environment['RQ_SREV_COMPARISON_INPUT'];
final _skip = _input == null
    ? 'Local SREV reference replay not configured'
    : false;
Map<String, dynamic> load() =>
    jsonDecode(File(_input!).readAsStringSync()) as Map<String, dynamic>;
Directory get out => File(_input!).parent;
List<NiedStation> stations(Map<String, dynamic> data) => [
  for (final r in data['catalog'] as List)
    NiedStation(
      id: r['id'] as int,
      code: r['code'] as String,
      name: r['name'] as String,
      coordinate: LatLng(
        (r['lat'] as num).toDouble(),
        (r['lon'] as num).toDouble(),
      ),
      network: '',
      prefecture: '',
      expireSeconds: 10,
    ),
];
void loadFrame(List<NiedStation> s, Map f) {
  final t = DateTime.fromMicrosecondsSinceEpoch(
    ((f['time'] as num) * 1000000).round() + 946684800000000,
    isUtc: true,
  );
  final levels = f['levels'] as List;
  for (var i = 0; i < s.length; i++) {
    s[i]
      ..level = levels[i] as int
      ..lastDataTime = t
      ..lastUpdate = t;
    s[i].recentLevel = [levels[i] as int];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Native NIED owner equals independently saved SREV permission sets on 535 frames',
    () {
      expect(NativeNiedDetectionOwner.supported, isTrue);
      final d = load(), results = <Map<String, Object?>>[];
      final before = NativeNiedDetectionOwner.diagnostics['sessions'];
      for (final c in d['cases'] as List) {
        final s = stations(d);
        final changes = <dynamic>[];
        final owner = NativeNiedDetectionOwner(
          s,
          manualClock: true,
          useSrev: true,
          onUpdate: changes.add,
        );
        var f = 0,
            missing = 0,
            extra = 0,
            peak = 0,
            first = -1,
            changedLevels = 0,
            activeWithoutTime = 0;
        final differences = <Map<String, Object?>>[];
        final watch = Stopwatch();
        try {
          for (final frame in c['frames'] as List) {
            loadFrame(s, frame as Map);
            final original = s.map((v) => v.level).toList();
            watch.start();
            owner.process(
              s,
              2,
              clock:
                  ((frame['time'] - (c['frames'][0]['time'] as num)) * 1000)
                          .round()
                      as int,
            );
            owner.rebind(s);
            watch.stop();
            final got = <int>{
              for (var i = 0; i < s.length; i++)
                if (s[i].isActive) i,
            };
            final expected = (frame['active'] as List).cast<int>().toSet();
            final m = expected.difference(got), e = got.difference(expected);
            missing += m.length;
            extra += e.length;
            if (m.isNotEmpty || e.isNotEmpty)
              differences.add({
                'frame': f,
                'missing': m.toList(),
                'extra': e.toList(),
              });
            if (got.isNotEmpty && first < 0) first = f;
            if (got.length > peak) peak = got.length;
            for (var i = 0; i < s.length; i++) {
              if (s[i].level != original[i]) changedLevels++;
              if (s[i].isActive && s[i].triggerStamp <= 0) activeWithoutTime++;
            }
            f++;
          }
        } finally {
          owner.dispose();
        }
        results.add({
          'case': c['name'],
          'frames': f,
          'first': first,
          'peak': peak,
          'missing': missing,
          'extra': extra,
          'changedDisplayLevels': changedLevels,
          'activeWithoutTime': activeWithoutTime,
          'meanOwnerMs': watch.elapsedMicroseconds / 1000 / f,
          'differences': differences,
        });
      }
      File(
        '${out.path}/native_owner_comparison.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
      expect(NativeNiedDetectionOwner.diagnostics['sessions'], before);
      for (final r in results) {
        print(r..remove('differences'));
        expect(r['missing'], 0, reason: '${r['case']} missing');
        expect(r['extra'], 0, reason: '${r['case']} extra');
        expect(r['changedDisplayLevels'], 0);
      }
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 4)),
  );
  testWidgets(
    'Render actual NIED map before/after native SREV for all display modes',
    (tester) async {
      final d = load();
      final s = stations(d);
      final c = (d['cases'] as List).first;
      final owner = NativeNiedDetectionOwner(
        s,
        manualClock: true,
        useSrev: true,
        onUpdate: (_) {},
      );
      late List<NiedStation> before, after;
      try {
        for (var f = 0; f <= 80; f++) {
          final frame = c['frames'][f] as Map;
          loadFrame(s, frame);
          if (f == 80) before = s.map(NiedStation.detachedSnapshot).toList();
          owner.process(
            s,
            2,
            clock:
                ((frame['time'] - (c['frames'][0]['time'] as num)) * 1000)
                        .round()
                    as int,
          );
          owner.rebind(s);
        }
        after = s.map(NiedStation.detachedSnapshot).toList();
      } finally {
        owner.dispose();
      }
      // Include an explicit missing observation and all legacy display level bands
      // at fixed screen-visible positions, in addition to the real network frame.
      for (var i = -1; i <= 20; i++) {
        final v = NiedStation(
          id: 2000 + i,
          code: 'band$i',
          name: 'band$i',
          coordinate: LatLng(
            34.0 + (i + 1) ~/ 6 * .4,
            135.0 + (i + 1) % 6 * .5,
          ),
          network: '',
          prefecture: '',
          expireSeconds: 10,
          level: i,
        );
        before.add(v);
        after.add(NiedStation.detachedSnapshot(v));
      }
      final missing = NiedStation(
        id: 3000,
        code: 'missing',
        name: 'missing',
        coordinate: const LatLng(34, 139),
        network: '',
        prefecture: '',
        expireSeconds: 10,
        level: 10,
      )..clearGifObservation(NiedGifLayer.realtimeShindo, qualityFlag: 'test');
      before.add(missing);
      after.add(NiedStation.detachedSnapshot(missing));
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final report = <Map<String, Object?>>[];
      for (final mode in [
        (3.9, false, false),
        (4.0, false, false),
        (6.0, true, false),
        (6.0, false, true),
      ]) {
        Future<({List<int> bytes, int icons})> render(
          List<NiedStation> list,
          String tag,
        ) async {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: RepaintBoundary(
                key: key,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: const LatLng(35, 138),
                    initialZoom: mode.$1,
                    backgroundColor: const Color(0xff202124),
                  ),
                  children: [
                    NiedIntensityLayer(
                      stations: list,
                      hideGrid: true,
                      displayShindo0: mode.$2,
                      informationFocusDotsOnly: mode.$3,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final icons = tester
              .widgetList<NiedIntensityNumberMarker>(
                find.byType(NiedIntensityNumberMarker),
              )
              .length;
          return (await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final raw = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File(
              '${out.path}/map_${mode.$1}_${mode.$2}_${mode.$3}_$tag.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
            return (bytes: raw!.buffer.asUint8List(), icons: icons);
          }))!;
        }

        final a = await render(before, 'before'),
            b = await render(after, 'after');
        var pixels = 0;
        for (var i = 0; i < a.bytes.length; i += 4) {
          if (a.bytes[i] != b.bytes[i] ||
              a.bytes[i + 1] != b.bytes[i + 1] ||
              a.bytes[i + 2] != b.bytes[i + 2] ||
              a.bytes[i + 3] != b.bytes[i + 3])
            pixels++;
        }
        report.add({
          'zoom': mode.$1,
          'displayShindo0': mode.$2,
          'focusDots': mode.$3,
          'beforeIcons': a.icons,
          'afterIcons': b.icons,
          'differentPixels': pixels,
          'totalPixels': a.bytes.length ~/ 4,
        });
        expect(pixels, 0);
        expect(a.icons, b.icons);
      }
      File(
        '${out.path}/map_comparison.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    },
    skip: _skip != false,
  );
}
