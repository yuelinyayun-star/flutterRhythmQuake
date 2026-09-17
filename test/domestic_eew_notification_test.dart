import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/notification_settings_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/notification_service.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domestic_eew_effects_test.dart' show report;

void main() {
  testWidgets(
    'independent cards and base sounds; shared threshold sounds and fill',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      SoundEffectService().enabled = false;
      final provider = QuakeProvider();
      final settings = NotificationSettingsProvider();
      final played = <String>[];
      final notifications = NotificationService(
        provider,
        settings,
        playSound: played.add,
      );
      addTearDown(() {
        SoundEffectService().enabled = true;
      });
      try {
        await tester.pumpWidget(const SizedBox());
        final now = DateTime.now().toUtc();
        final a = report('ceaEew').copyWith(timeZone: 0, originTime: now);
        final b = report('scEew').copyWith(timeZone: 0, originTime: now);
        provider.handleUnifiedEventForTest(a);
        provider.handleUnifiedEventForTest(b);
        expect(provider.unifiedEvents, hasLength(2));
        expect(played, ['issue', 'caution', 'issue']);
        expect(
          provider.unifiedEvents.where(provider.shouldDrawUnifiedIntensityFill),
          hasLength(1),
        );
        final updated = b.copyWith(
          magnitude: 6,
          maxIntensity: '7',
          className: 'orange',
          isWarn: true,
          reportNumText: '第2報',
        );
        provider.handleUnifiedEventForTest(updated);
        expect(played, ['issue', 'caution', 'issue', 'update', 'warn']);
        expect(provider.shouldDrawUnifiedIntensityFill(a), isFalse);
        expect(provider.shouldDrawUnifiedIntensityFill(updated), isTrue);
        provider.handleUnifiedEventForTest(
          a.copyWith(
            magnitude: 6,
            maxIntensity: '7',
            className: 'orange',
            isWarn: true,
            reportNumText: '第2報',
          ),
        );
        expect(played.last, 'update');
        expect(played.where((s) => s == 'warn'), hasLength(1));
        provider.handleUnifiedEventForTest(
          updated.copyWith(isFinal: true, reportNumText: '第3報'),
        );
        expect(played.last, 'final');
        provider.handleUnifiedEventForTest(
          updated.copyWith(isCanceled: true, reportNumText: '第4報'),
        );
        expect(played.last, 'cancel');
        expect(provider.unifiedEvents, hasLength(2));
        final c = report('cqEew').copyWith(
          timeZone: 0,
          originTime: now.add(const Duration(seconds: 1)),
        );
        provider.handleUnifiedEventForTest(c);
        expect(played.sublist(played.length - 2), ['issue', 'caution']);
        expect(provider.unifiedEvents, hasLength(3));
      } finally {
        notifications.dispose();
        provider.dispose();
        settings.dispose();
        await tester.pump();
      }
    },
  );
}
