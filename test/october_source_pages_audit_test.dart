// Repeat the existing UI-only pagination boundary case, observing stable card
// identities as well as the old coordinate-text assertion. No source injection.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_state.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'map_card_viewport_sync_test.dart' show mount, item;

void main() {
  testWidgets(
    'AUDIT original six-source pagination survives updates; coordinate-text assertion is obsolete',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = 4;
      SoundEffectService().enabled = false;
      StationEventTracker.instance.currentNiedEvent.value = null;
      PAlertSourceState.events.value = const [];
      addTearDown(() {
        SoundEffectService().enabled = true;
        PAlertSourceState.events.value = const [];
      });
      final provider = await mount(tester);
      for (var i = 0; i < 5; i++) {
        provider.handleUnifiedEventForTest(item(i, eew: false));
      }
      final now = DateTime.now().toUtc();
      final sources = [
        for (var i = 0; i < 6; i++)
          SeismicActiveEvent(
            eventId: 'AUDIT-PA-$i',
            sourceId: 'palert',
            startedAt: now,
            updatedAt: now,
            stageName: 'confirmed',
            maxShindo: 3,
            estimate: SourceEstimate(
              latitude: 23.3 + i * .01,
              longitude: 121.1,
              depthKm: 20,
              magnitude: 4.2,
              originTime: now,
              confidence: .5,
              method: 'audit',
              supportingStationCount: 6,
            ),
          ),
      ];
      PAlertSourceState.events.value = sources;
      provider.setCameraSourceFocus([
        for (final event in sources)
          'palert_source_estimation:${event.eventId}',
      ]);
      final seen = <int>{};
      final oldTextSeen = <int>{};
      for (var tick = 0; tick < 12; tick++) {
        for (final event in sources) {
          event.updatedAt = now.add(Duration(seconds: tick));
        }
        PAlertSourceState.events.value = List.of(sources);
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          if (find
              .byKey(
                ValueKey(
                  'unified_card_palert_source_estimation_AUDIT-PA-${i}_',
                ),
              )
              .evaluate()
              .isNotEmpty) {
            seen.add(i);
          }
          if (find
              .text('${(23.3 + i * .01).toStringAsFixed(3)}°N, 121.100°E')
              .evaluate()
              .isNotEmpty) {
            oldTextSeen.add(i);
          }
        }
        await tester.pump(const Duration(seconds: 1));
      }
      expect(seen, hasLength(6));
      expect(oldTextSeen, isEmpty);
      expect(tester.takeException(), isNull);
      debugPrint(
        'AUDIT_CONFIRMED sourcePages identities=${seen.length}/6 oldCoordinateText=${oldTextSeen.length}/6',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
