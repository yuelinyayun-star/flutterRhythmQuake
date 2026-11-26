import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final input = Platform.environment['RQ_SREV_FULL_INPUT'];
  test(
    'all catalogue stations participate; compare 535 frames with original restricted SREV baseline',
    () {
      final file = File(input!);
      final d = jsonDecode(file.readAsStringSync()) as Map;
      final cat = d['catalog'] as List;
      final excluded = <int>{
        for (var i = 0; i < cat.length; i++)
          if (cat[i]['slot'] == null) i,
      };
      expect(excluded.length, 15);
      List<NiedStation> create() => [
        for (final c in cat)
          NiedStation(
            id: c['id'] as int,
            code: c['code'] as String,
            name: c['name'] as String,
            coordinate: LatLng(
              (c['lat'] as num).toDouble(),
              (c['lon'] as num).toDouble(),
            ),
            network: '',
            prefecture: '',
            expireSeconds: 10,
          ),
      ];
      final report = <Map<String, Object?>>[];
      void run(Map c, {bool synthetic = false}) {
        final s = create();
        List? view;
        final owner = NativeNiedDetectionOwner(
          s,
          manualClock: true,
          useSrev: true,
          onUpdate: (r) {
            if (r[2] != null) view = r[2] as List;
          },
        );
        final reached = <int>{};
        final seen = <int>{};
        final diffs = <Map<String, Object?>>[];
        var f = 0,
            peak = 0,
            first = -1,
            oldMissing = 0,
            oldExtra = 0,
            extraNew = 0,
            projectionChecks = 0;
        final frames = c['frames'] as List;
        try {
          for (final frame in frames) {
            final time = DateTime.fromMicrosecondsSinceEpoch(
              ((frame['time'] as num) * 1000000).round() + 946684800000000,
              isUtc: true,
            );
            final levels = (frame['levels'] as List).cast<int>();
            for (var i = 0; i < s.length; i++) {
              s[i]
                ..level = levels[i]
                ..lastDataTime = time
                ..lastUpdate = time
                ..recentLevel = [levels[i]];
              if (excluded.contains(i) && levels[i] >= 0) seen.add(i);
            }
            owner.process(
              s,
              2,
              clock:
                  ((frame['time'] - (frames.first['time'] as num)) * 1000)
                          .round()
                      as int,
            );
            owner.rebind(s);
            final active = <int>{
              for (var i = 0; i < s.length; i++)
                if (s[i].isActive) i,
            };
            reached.addAll(active.intersection(excluded));
            expect(s.map((x) => x.level), levels);
            if (active.isNotEmpty && first < 0) first = f;
            if (active.length > peak) peak = active.length;
            for (final i in active) {
              expect(s[i].triggerStamp, greaterThan(0));
              expect(s[i].detectReason, 'srev-permission');
            }
            if (view != null) {
              final entries = (view![5] as List)
                  .map((v) => (v as List)[0] as int)
                  .toSet();
              expect(entries, active, reason: 'sidebar frame $f');
              final ranks = active
                  .map(
                    (i) =>
                        JpShindoScale.jmaNumberFromKanameishiLevel(levels[i]),
                  )
                  .toList();
              expect(view![1], ranks.where((v) => v == 0).length);
              expect(view![2], ranks.where((v) => v >= 1 && v < 4).length);
              expect(view![3], ranks.where((v) => v >= 4).length);
              for (final cell in view![6] as List) {
                expect(cell[3], inInclusiveRange(0, 20));
              }
              projectionChecks++;
            }
            if (!synthetic) {
              final expected = (frame['active'] as List).cast<int>().toSet();
              final old = active.difference(excluded);
              final m = expected.difference(old), e = old.difference(expected);
              oldMissing += m.length;
              oldExtra += e.length;
              extraNew += active.intersection(excluded).length;
              if (m.isNotEmpty || e.isNotEmpty)
                diffs.add({'frame': f, 'missing': m.length, 'extra': e.length});
            }
            f++;
          }
        } finally {
          owner.dispose();
        }
        report.add({
          'case': c['name'],
          'frames': f,
          'first': first,
          'peak': peak,
          'oldMissing': oldMissing,
          'oldExtra': oldExtra,
          'additionalActiveStationFrames': extraNew,
          'additionalValidCodes': [for (final i in seen) cat[i]['code']],
          'additionalDetectedCodes': [for (final i in reached) cat[i]['code']],
          'sidebarProjectionChecks': projectionChecks,
          'differences': diffs,
        });
        if (synthetic)
          expect(
            reached,
            excluded,
            reason:
                'all 15 must actually obtain permission under a coherent rising test',
          );
      }

      for (final c in d['cases'] as List) {
        run(c as Map);
      }
      run({
        'name':
            'synthetic coherent network rise (eligibility, not physical earthquake)',
        'frames': [
          for (var f = 0; f < 24; f++)
            {
              'time': 846209400 + f,
              'levels': List.filled(
                cat.length,
                f < 10 ? 2 : (f - 5).clamp(0, 20),
              ),
            },
        ],
      }, synthetic: true);
      File(
        '${file.parent.path}/full_catalog_report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      for (final r in report) {
        print({...r}..remove('differences'));
      }
    },
    skip: input == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
