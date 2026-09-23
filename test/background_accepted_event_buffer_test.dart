import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/background_accepted_event_buffer.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'accepted report survives a buffer reload without changing raw data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final frames =
          jsonDecode(
                File(
                  'test/fixtures/catalog_20260917/whews_all.json',
                ).readAsStringSync(),
              )
              as List;
      final frame = frames.firstWhere((item) => item['source'] == 'jma_eew');
      final report = QuakeEventAdapter.convertWhews(
        frame['source'],
        Map<String, dynamic>.from(frame['Data']),
      )!;
      final original = jsonEncode(report.toMap());
      final preferences = await SharedPreferences.getInstance();
      final buffer = BackgroundAcceptedEventBuffer(preferences);

      buffer.add(report);
      await buffer.flush();

      final restored = BackgroundAcceptedEventBuffer(preferences).snapshot();
      expect(restored, hasLength(1));
      expect(jsonEncode(restored.single.toMap()), original);
      expect(jsonEncode(report.toMap()), original);
    },
  );

  test('buffer expires stored reports after its retention window', () async {
    SharedPreferences.setMockInitialValues({});
    final frames =
        jsonDecode(
              File(
                'test/fixtures/catalog_20260917/whews_all.json',
              ).readAsStringSync(),
            )
            as List;
    final frame = frames.firstWhere((item) => item['source'] == 'jma_eew');
    final report = QuakeEventAdapter.convertWhews(
      frame['source'],
      Map<String, dynamic>.from(frame['Data']),
    )!;
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 9, 23);
    final buffer = BackgroundAcceptedEventBuffer(preferences, now: () => now);

    buffer.add(report);
    expect(buffer.snapshot(), hasLength(1));
    now = now.add(const Duration(hours: 25));
    expect(buffer.snapshot(), isEmpty);
    await buffer.flush();
  });
}
