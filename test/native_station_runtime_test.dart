import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';

class Harness {
  final runtime = NativeStationRuntime();
  final stream = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? latest;
  Harness(Map<String, Object?> settings) {
    runtime.onFrame = (frame) {
      latest = frame;
      stream.add(frame);
    };
    runtime.start({...settings, 'testing': true});
  }
  Future<Map<String, dynamic>> frame(int count) async {
    if (latest != null && (latest!['frames'] as int) >= count) return latest!;
    return stream.stream
        .firstWhere((f) => (f['frames'] as int) >= count)
        .timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    runtime.stop();
    await stream.close();
  }
}

void main() {
  final enabled = NativeStationRuntime.supported;
  test(
    'original KMA socket bytes match the complete Dart display/history path',
    () async {
      final h = Harness({'kind': 'kma', 'source': 'pews', 'hold': 3});
      final reference = KmaMonitorService.detached()..setIntensityHoldFrames(3);
      final signals = <int>[];
      reference.onShakeDetected = signals.add;
      reference.onShakeExpired = () => signals.add(-1);
      addTearDown(() async {
        reference.dispose();
        await h.close();
      });
      var accepted = 0;
      final nativeSignals = <int>[];
      h.runtime.onFrame = (frame) {
        h.latest = frame;
        h.stream.add(frame);
        nativeSignals.addAll((frame['signals'] as List).cast<int>());
      };
      final clock = DateTime.parse('2026-10-16T10:00:00Z');
      for (var i = 0; i < 8; i++) {
        final bytes = File(
          'test/fixtures/source_ws_followup_20261016/kma_${i.toString().padLeft(2, '0')}.original.bytes',
        ).readAsBytesSync();
        reference.handleOriginalForTesting(utf8.decode(bytes));
        h.runtime.injectOriginal(bytes, clock);
        final v = jsonDecode(utf8.decode(bytes)) as Map;
        if (v['Data'] == null) continue;
        final frame = await h.frame(++accepted);
        final actual = ForegroundStationPayload.decodeKma(frame['stations']);
        expect(actual.length, reference.stations.length);
        expect(
          DateTime.parse(frame['dataTime'] as String),
          reference.dataTimeNotifier.value!.toUtc(),
        );
        for (var j = 0; j < actual.length; j++) {
          final a = actual[j], b = reference.stations[j];
          expect(
            [
              a.id,
              a.coordinate,
              a.intensity,
              a.activityLevel,
              a.holdLevel,
              a.ascend,
              a.isActive,
            ],
            [
              b.id,
              b.coordinate,
              b.intensity,
              b.activityLevel,
              b.holdLevel,
              b.ascend,
              b.isActive,
            ],
          );
        }
        final archive = h.runtime.archive!;
        expect(
          (archive['stations'] as List).map(
            (dynamic row) => row['recentLevel'],
          ),
          reference.stations.map((s) => s.recentLevel),
        );
        expect(h.runtime.original!['data'], v);
      }
      expect(accepted, 6);
      expect(nativeSignals, signals);
      final previous = h.latest!['dataTime'];
      final old = File(
        'test/fixtures/source_ws_followup_20261016/kma_02.original.bytes',
      ).readAsBytesSync();
      h.runtime.injectOriginal(old, clock);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.latest!['dataTime'], previous);
      expect(h.latest!['frames'], 6);
    },
    skip: !enabled,
  );

  test(
    'original TREM SSE observations match legacy station merge, sort and alerts',
    () async {
      final h = Harness({'kind': 'cwa'});
      final reference = CwaStationService.detached();
      addTearDown(() async {
        reference.stop();
        await h.close();
      });
      final meta = File(
        'test/fixtures/api_ingress_20261016/trem_metadata.original.bytes',
      ).readAsBytesSync();
      reference.handleOriginalForTesting(utf8.decode(meta), metadata: true);
      final clock = DateTime.parse('2026-10-17T12:00:00Z');
      h.runtime.injectOriginal(meta, clock);
      var count = 0;
      final lines = File(
        'test/fixtures/api_ingress_20261016/trem_stream.original.bytes',
      ).readAsLinesSync();
      for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final original = line.substring(5).trim();
        Map v;
        try {
          v = jsonDecode(original) as Map;
        } on FormatException {
          continue;
        } // The capture ends mid-frame; retain raw bytes.
        if (v['station'] is! Map) continue;
        final accepted = reference.handleOriginalForTesting(original);
        h.runtime.injectOriginal(utf8.encode(original), clock);
        if (!accepted) continue;
        final frame = await h.frame(++count);
        final actual = ForegroundStationPayload.decodeCwa(frame['stations']);
        final expected = {for (final s in reference.stations) s.id: s};
        expect(actual.length, expected.length);
        expect(
          DateTime.parse(frame['dataTime'] as String),
          reference.dataTimeNotifier.value!.toUtc(),
        );
        for (final a in actual) {
          final b = expected[a.id]!;
          expect(
            [
              a.code,
              a.net,
              a.coordinate,
              a.work,
              a.pga,
              a.pgv,
              a.intensity,
              a.alertIntensity,
              a.hasAlert,
            ],
            [
              b.code,
              b.net,
              b.coordinate,
              b.work,
              b.pga,
              b.pgv,
              b.intensity,
              b.alertIntensity,
              b.hasAlert,
            ],
          );
        }
        expect(
          actual.map((s) => s.currentIntensity),
          reference.stations.map((s) => s.currentIntensity),
        );
        expect(h.runtime.original!['data'], v);
      }
      expect(count, greaterThan(3));
      final archive = h.runtime.archive!;
      expect(archive['kind'], 'cwa');
      expect((archive['stations'] as List).length, reference.stations.length);
    },
    skip: !enabled,
  );

  test(
    'source actors release on stop and cannot publish into their replacement',
    () async {
      final baseline = NativeStationRuntime.workers;
      for (var i = 0; i < 12; i++) {
        final h = Harness({'kind': i.isEven ? 'kma' : 'cwa'});
        await h.frame(0);
        await h.close();
      }
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (NativeStationRuntime.workers != baseline &&
          DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(NativeStationRuntime.workers, baseline);
    },
    skip: !enabled,
  );
}
