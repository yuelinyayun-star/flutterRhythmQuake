import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/replay_source_estimation.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_driver.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_worker.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_state.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'support/unified_ui_fonts.dart';

const fixture = 'test/fixtures/palert_cwa_1150077_20261017';
List<StationHistoryFrame> originalFrames() {
  final manifest =
      jsonDecode(
            File('$fixture/manifest.json').readAsStringSync(encoding: utf8),
          )
          as List;
  final frames = <StationHistoryFrame>[];
  for (final entry in manifest) {
    final stored = jsonDecode(
      File('$fixture/${entry['file']}').readAsStringSync(encoding: utf8),
    );
    frames.addAll(
      StationJsonArchive.decode(StationArchiveStorage.decode(stored['value'])),
    );
  }
  return frames..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recorded snapshot worker matches the original typed-frame inference',
    () async {
      final frames = originalFrames();
      final replay = ReplaySourceEstimation();
      final reference = PAlertSourceWorker.dartReferenceForTesting();
      final live = PAlertSourceState.events.value;
      var clock = frames.first.receivedAt;
      replay.start('palert-original-worker', () => clock);
      var estimates = 0;
      try {
        for (final frame in frames) {
          clock = frame.receivedAt;
          final expected = await reference.process(
            ForegroundStationPayload.decodePAlert(frame.snapshot['stations']),
            ForegroundStationPayload.decodePAlertDetectedStationIds(
              frame.snapshot,
              now: clock,
            ),
            now: clock,
          );
          await replay.process(frame);
          expect(replay.error, isNull);
          expect(
            replay.palert.map(
              (e) => [
                e.estimate?.latitude,
                e.estimate?.longitude,
                e.estimate?.depthKm,
                e.estimate?.magnitude,
                e.estimate?.originTime,
                e.estimate?.confidence,
                e.metadata['palert_max_cwa_intensity_index'],
              ],
            ),
            expected!.map(
              (e) => [
                e.estimate?.latitude,
                e.estimate?.longitude,
                e.estimate?.depthKm,
                e.estimate?.magnitude,
                e.estimate?.originTime,
                e.estimate?.confidence,
                e.metadata['palert_max_cwa_intensity_index'],
              ],
            ),
          );
          if (replay.palert.isNotEmpty) estimates++;
        }
        expect(estimates, 15);
        expect(PAlertSourceState.events.value, same(live));
      } finally {
        reference.dispose();
        replay.dispose();
      }
    },
  );

  test(
    'display expiry preserves raw pre-trigger observations in this real event',
    () async {
      final frames = originalFrames();
      var clock = frames.first.receivedAt;
      final driver = PAlertSourceDriver(clock: () => clock);
      addTearDown(driver.dispose);
      var outputs = 0;
      for (var i = 0; i < frames.length; i++) {
        final frame = frames[i];
        clock = frame.receivedAt;
        final stations = ForegroundStationPayload.decodePAlert(
          frame.snapshot['stations'],
        );
        final ids = ForegroundStationPayload.decodePAlertDetectedStationIds(
          frame.snapshot,
          now: clock,
        );
        await driver.process(stations, ids);
        expect(driver.lastError, isNull);
        if (driver.events.value.isNotEmpty) outputs++;
        // Ending a weak detection used to destroy these seven original samples.
        if (i == 6) driver.clear();
      }
      expect(outputs, 15);
      expect(driver.events.value, isEmpty);
      expect(driver.processedFrames, frames.length);
    },
  );

  testWidgets('original P-Alert inference renders beside its real CWA EEW', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    final previousHide = UiRuntimeFlags.hideGridOnEewNotifier.value;
    UiRuntimeFlags.hideGridOnEewNotifier.value = false;
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final frames = originalFrames();
    var clock = frames.first.receivedAt;
    final driver = PAlertSourceDriver(clock: () => clock);
    final provider = QuakeProvider(
      startCatalogServices: false,
      eewClock: () => clock,
    );
    final mapState = MapStateProvider()..setShowEstimatedEpicenter(true);
    await tester.runAsync(() async {
      for (final frame in frames.take(11)) {
        clock = frame.receivedAt;
        await driver.process(
          ForegroundStationPayload.decodePAlert(frame.snapshot['stations']),
          ForegroundStationPayload.decodePAlertDetectedStationIds(
            frame.snapshot,
            now: clock,
          ),
        );
      }
      final stored = jsonDecode(
        File(
          '$fixture/cwa_1150077.original.json',
        ).readAsStringSync(encoding: utf8),
      );
      final event = jsonDecode(stored['value']);
      final report = UnifiedQuakeData.fromMap(
        Map<String, dynamic>.from(event['reports'][0]),
      );
      provider.handleUnifiedEventForTest(report, suppressEffects: true);
      await loadUnifiedUiFonts();
    });
    expect(driver.lastError, isNull);
    expect(
      PAlertSourceState.events.value.single.estimate!.magnitude,
      isNotNull,
    );
    expect(provider.unifiedEvents.single.source, 'cwaEew');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
        ],
        child: MaterialApp(
          theme: unifiedUiTestTheme(),
          home: const Scaffold(body: AlertModule()),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('PGA 初估'), findsOneWidget);
    expect(find.text('预估震度'), findsOneWidget);
    expect(find.textContaining('中央氣象署'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    driver.dispose();
    provider.dispose();
    mapState.dispose();
    UiRuntimeFlags.hideGridOnEewNotifier.value = previousHide;
    SoundEffectService().enabled = true;
  });
}
