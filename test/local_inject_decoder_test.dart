import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jian_sources.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/mock_input_service.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/sources/nowquake_cenc_intensity_service.dart';

Object? fixture(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'complete WHEWS snapshot routes weather and tsunami away from earthquake events',
    () {
      final frames = fixture('catalog_20260917/whews_all.json') as List;
      final before = jsonEncode(frames);
      final batch = LocalInjectDecoder.decode(frames, format: 'whews');
      expect(batch.count, frames.length);
      expect(batch.weatherAlarms.length, 1);
      expect(batch.weatherAlarms.single.apiTypeLabel, localInjectApiName);
      expect(batch.tsunamis.length, 4);
      expect(
        batch.events.every((event) => event.source != 'whews_weatheralarm'),
        isTrue,
      );
      expect(batch.events.any((event) => event.isVolcanoEvent), isTrue);
      expect(jsonEncode(frames), before);
    },
  );

  test(
    'existing tool examples use the same local entry, without rewriting',
    () {
      // Existing simulation fixtures, not new observations or production data.
      for (final name in [
        'sample_cea_eew',
        'sample_cenc_eew',
        'sample_jma_eew',
        'sample_usgs_chile_info',
        'nearby_camera_simulation',
        'tohoku_20110311_info',
        'tohoku_20110311_tsunami',
      ]) {
        final file = File('tools/fixtures/$name.json');
        final text = file.readAsStringSync();
        final raw = jsonDecode(text);
        final batch = LocalInjectDecoder.decode(raw);
        expect(batch.count, greaterThan(0), reason: name);
        expect(file.readAsStringSync(), text);
        expect(
          batch.events.every((e) => e.apiTypeLabel == localInjectApiName),
          isTrue,
        );
      }
    },
  );

  test(
    'FAN live conversion and local envelope produce matching fields',
    () async {
      final frames = fixture('catalog_20260917/whews_all.json') as List;
      final original = frames.firstWhere((f) => f['source'] == 'cenc');
      final frame = <String, dynamic>{'type': 'update', ...original};
      final service = FanService();
      final future = service.onUnifiedEvent.first;
      service.handleMessageForTesting(jsonEncode(frame));
      final live = await future;
      final local = LocalInjectDecoder.decode(frame).events.single;
      expect(local.eventId, live.eventId);
      expect(local.originTime, live.originTime);
      expect(local.reportNumText, live.reportNumText);
      expect(local.magnitude, live.magnitude);
      expect(local.sourcePayload, frame);
      expect(local.apiTypeLabel, localInjectApiName);
      final snapshot = LocalInjectDecoder.decode({
        'type': 'initial',
        ...original,
      }).events.single;
      expect(snapshot.isHistory, isTrue);
      expect(snapshot.isSnapshot, isTrue);
      service.dispose();
    },
  );

  test(
    'original P2P history keeps all event bodies, timestamps and regions',
    () {
      final raw = fixture('jma_voice/p2p_history_20260921.json') as List;
      final before = jsonEncode(raw);
      final batch = LocalInjectDecoder.decode(raw);
      expect(batch.events.length, raw.length);
      for (var i = 0; i < raw.length; i++) {
        final live = QuakeEventAdapter.convert('jmaEqlist', raw[i], 2)!;
        final local = batch.events[i];
        expect(local.apiTypeLabel, localInjectApiName);
        expect(local.source, live.source);
        expect(local.origin, live.origin);
        expect(local.originTime, live.originTime);
        expect(local.warnArea, live.warnArea);
        expect(local.sourcePayload, raw[i]);
        expect(
          UnifiedQuakeData.fromMap(local.toMap()).apiTypeLabel,
          localInjectApiName,
        );
      }
      expect(jsonEncode(raw), before);
    },
  );

  test('Jian full-width aggregate and historical list reuse Jian adapter', () {
    final raw = fixture('jian/all.json') as Map<String, dynamic>;
    final before = jsonEncode(raw);
    final events = LocalInjectDecoder.decode(raw).events;
    final expected = raw.keys
        .where(
          (key) =>
              key.startsWith('source：') &&
              jianEarthquakeSources.containsKey(key.substring(7)),
        )
        .length;
    expect(events.length, expected);
    expect(events, isNotEmpty);
    expect(
      events.every((event) => event.apiTypeLabel == localInjectApiName),
      isTrue,
    );
    expect(events.every((event) => event.isSnapshot), isTrue);
    expect(jsonEncode(raw), before);
    final history = LocalInjectDecoder.decode(
      fixture('jian/jmalist_response.json'),
      format: 'jian',
    );
    expect(history.events.length, 50);
    expect(history.events.every((event) => event.isHistory), isTrue);
  });

  test('original WHEWS earthquake frames and WAuth use the same adapter', () {
    final frames = fixture('catalog_20260917/whews_all.json') as List;
    var count = 0;
    for (final frame in frames.whereType<Map<String, dynamic>>()) {
      if (frame['Data'] is! Map<String, dynamic> ||
          !const [
            'jma',
            'cenc',
            'usgs',
            'emsc',
            'kma',
            'cwa',
          ].contains(frame['source'])) {
        continue;
      }
      final live = QuakeEventAdapter.convertWhews(
        frame['source'],
        frame['Data'],
      )!;
      for (final format in ['auto', 'whews', 'wauth']) {
        final event = LocalInjectDecoder.decode(
          frame,
          format: format,
        ).events.single;
        expect(event.eventId, live.eventId);
        expect(event.hypocenter, live.hypocenter);
        expect(event.apiTypeLabel, localInjectApiName);
        expect(event.sourcePayload, frame);
      }
      count++;
    }
    expect(count, greaterThan(0));
  });

  test('NowQuake original station frame retains complete station data', () {
    final raw =
        fixture('cenc_ir_mojiang_20260914170727.json') as Map<String, dynamic>;
    final event = LocalInjectDecoder.decode(raw).events.single;
    final live = NowQuakeCencIntensityService.unifiedInfoFromJson(raw)!;
    expect(event.source, 'nowQuakeCencIr');
    expect(event.eventId, live.eventId);
    expect(event.originTime, live.originTime);
    expect(event.sourcePayload, raw);
  });

  test(
    'manual injection emits only unified events, not a duplicate legacy event',
    () async {
      final raw =
          (fixture('jma_voice/p2p_history_20260921.json') as List).first;
      final service = MockInputService();
      final events = <UnifiedQuakeData>[];
      var legacy = 0;
      final unified = service.onUnifiedEvent.listen(events.add);
      final old = service.onEvent.listen((_) => legacy++);
      expect(service.injectFromJs(jsonEncode(raw)), 1);
      await Future<void>.delayed(Duration.zero);
      expect(events.single.apiTypeLabel, localInjectApiName);
      expect(legacy, 0);
      expect(service.name, localInjectApiName);
      await unified.cancel();
      await old.cancel();
      service.dispose();
    },
  );

  test('invalid batch never publishes a partial first event', () async {
    final raw = (fixture('jma_voice/p2p_history_20260921.json') as List).first;
    final service = MockInputService();
    var emitted = 0;
    final sub = service.onUnifiedEvent.listen((_) => emitted++);
    expect(
      () => service.injectFromJs(jsonEncode([raw, {}])),
      throwsFormatException,
    );
    await Future<void>.delayed(Duration.zero);
    expect(emitted, 0);
    await sub.cancel();
    service.dispose();
  });

  test(
    'explicit unified envelope preserves lifecycle fields and provenance',
    () {
      final raw =
          (fixture('jma_voice/p2p_history_20260921.json') as List).first;
      final original = QuakeEventAdapter.convert(
        'jmaEqlist',
        raw,
        2,
      )!.copyWith(isHistory: true, isSnapshot: true);
      final event = LocalInjectDecoder.decode({
        'format': 'unified',
        'payload': original.toMap(),
      }).events.single;
      expect(event.isHistory, isTrue);
      expect(event.isSnapshot, isTrue);
      expect(event.apiTypeLabel, localInjectApiName);
    },
  );
}
