import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/native_camera_focus.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';

void main() {
  test(
    'native contracts use original bulletin types and release every output',
    () {
      if (!NativeCameraFocus.supported) {
        markTestSkipped('Set RQ_STATION_CORE_LIBRARY to test the real Rust DLL');
        return;
      }
      expect(
        NativeCameraFocus.supported,
        true,
        reason: 'Run with RQ_STATION_CORE_LIBRARY; this test must execute Rust',
      );
      final original = File(
        'test/fixtures/jma_camera_20261030/p2p_history.original.json',
      ).readAsStringSync(encoding: utf8);
      final raw = (jsonDecode(original) as List).cast<Map>().singleWhere(
        (r) => r['id'] == '6ae45a03e88ee598246bf44c',
      );
      expect(raw['issue']['type'], 'DetailScale');
      if (Platform.environment['RQ_WRITE_CAMERA_REPLAY'] == '1') {
        final event = QuakeEventAdapter.convert(
          'jmaEqlist',
          Map<String, dynamic>.from(raw),
          2,
        )!;
        final package = HistoryReplayPackage.fromGroup(
          EewEventGroup(
            eventId: event.eventId,
            reports: [event],
            firstArrivedAt: event.reportTime!,
          ),
        );
        expect(jsonEncode(event.sourcePayload), jsonEncode(raw));
        File(
          'tmp/jma_info_center_20261030/jma-nemuro-original.json',
        ).writeAsStringSync(
          jsonEncode(package.exportMetadata()),
          encoding: utf8,
        );
      }
      expect(
        NativeCameraFocus.prepare({
          'op': 'informationAnchor',
          'source': 'jmaEqlist',
          'origin': 2,
          'issueType': raw['issue']['type'],
          'locatable': true,
        }),
        true,
      );
      final prompts =
          jsonDecode(
                File(
                  'test/fixtures/jma_voice/p2p_scale_prompt.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      for (final raw in prompts) {
        expect(
          NativeCameraFocus.prepare({
            'op': 'informationAnchor',
            'source': 'jmaEqlist',
            'origin': 2,
            'issueType': raw['issue']['type'],
            'locatable': false,
          }),
          false,
        );
      }
      final history =
          jsonDecode(
                File(
                  'test/fixtures/jma_voice/p2p_history_20260921.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      final destinations = history.where(
        (r) => r['issue']['type'] == 'Destination',
      );
      expect(destinations, isNotEmpty);
      for (final raw in destinations) {
        expect(
          NativeCameraFocus.prepare({
            'op': 'informationAnchor',
            'source': 'jmaEqlist',
            'origin': 2,
            'issueType': raw['issue']['type'],
            'locatable': true,
          }),
          false,
        );
      }
      final calls = NativeCameraFocus.calls;
      for (var i = 0; i < 500; i++) {
        expect(
          NativeCameraFocus.prepare({'op': 'groupAnchor', 'stationFit': true}),
          true,
        );
        expect(
          () => NativeCameraFocus.prepare({'op': 'fitAnchor'}),
          throwsStateError,
        );
      }
      expect(NativeCameraFocus.calls - calls, 1000);
      expect(NativeCameraFocus.outputs, 0);
      expect(
        File(
          'test/fixtures/jma_camera_20261030/p2p_history.original.json',
        ).readAsStringSync(encoding: utf8),
        original,
      );
    },
  );

  test('Rust anchor math matches frozen previous math including rotation', () {
    if (!NativeCameraFocus.supported) {
      markTestSkipped('Set RQ_STATION_CORE_LIBRARY to test the real Rust DLL');
      return;
    }
    expect(NativeCameraFocus.supported, true);
    // Pure mathematical coordinates; these are not earthquake observations.
    for (final angle in [0.0, 0.1, -0.7, math.pi / 2, math.pi]) {
      for (final zoom in [0.0, 4.5, 7.12345, 12.0]) {
        final c = math.cos(angle), s = math.sin(angle);
        final offsets = [
          [-500.25, 3.125],
          [18.0, -97.0],
          [0.0, 0.0],
        ];
        final hw = offsets
            .map((p) => (p[0] * c + p[1] * s).abs())
            .reduce(math.max);
        final hh = offsets
            .map((p) => (-p[0] * s + p[1] * c).abs())
            .reduce(math.max);
        final scale = math.min(800 / (2 * hw), 600 / (2 * hh));
        final expected =
            (math.log(256 * math.pow(2, zoom) * scale / 256) / math.ln2).clamp(
              3.0,
              12.0,
            );
        final result =
            NativeCameraFocus.prepare({
                  'op': 'fitAnchor',
                  'offsets': offsets,
                  'width': 800,
                  'height': 600,
                  'currentScale': 256 * math.pow(2, zoom),
                  'minZoom': 3,
                  'maxZoom': 12,
                  'rotation': angle,
                  'paddingX': -90,
                  'paddingY': -20,
                })
                as Map;
        expect(result['zoom'], closeTo(expected, 1e-10));
        expect(result['offsetX'], closeTo(-90 * c + 20 * s, 1e-10));
        expect(result['offsetY'], closeTo(-90 * s - 20 * c, 1e-10));
      }
    }
    expect(NativeCameraFocus.outputs, 0);
  });
}
