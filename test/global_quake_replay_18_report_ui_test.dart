import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/services/location_service.dart';
import 'package:flutterrhythmquake/services/ntp_service.dart';
import 'package:flutterrhythmquake/widgets/ui/local_eew_sidebar_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captured 18 GlobalQuake reports update visible S-wave countdown', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await TravelTimeService().ensureLoaded();
    });
    LocationService().setCurrentLatLng(29.36, 120.17);
    final content =
        jsonDecode(
              File(
                'test/fixtures/global_quake/captured_report_only_20261018.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final reports = content['reports'] as List;
    final arrivals = content['arrivalInstantsUtc'] as List;
    expect(reports, hasLength(18));
    for (var i = 0; i < reports.length; i++) {
      final input = UnifiedQuakeData.fromMap(
        Map<String, dynamic>.from(reports[i] as Map),
      );
      final arrival = DateTime.parse(arrivals[i] as String);
      final replay = input.copyWith(
        replaySessionId: 'capture-18',
        replayClockOffset: NtpService().now.toUtc().difference(arrival),
        isHistory: false,
        isSnapshot: false,
      );
      final eligible = selectLocalEewSidebarEvent(
        [replay],
        0,
        domesticEnabled: true,
        foreignEnabled: true,
      );
      expect(eligible, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 310,
              height: 430,
              child: LocalEewSidebarPanel(event: eligible!, scale: (v) => v),
            ),
          ),
        ),
      );
      await tester.pump();
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('local-eew-countdown')))
          .data;
      expect(
        int.tryParse(text ?? ''),
        greaterThan(0),
        reason: 'report ${i + 1}: ${input.reportNumText}, rendered "$text"',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
