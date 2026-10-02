import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

import 'support/nied_replay_fixture.dart';

class CapturedNiedTransport {
  static final first = DateTime(2026, 6, 10, 18, 1, 20);
  static const directory = 'test/fixtures/nied_recovery';
  Duration elapsed = Duration.zero;
  DateTime latest = first;
  bool metadataAvailable = true;
  bool imagesAvailable = true;
  int syncCalls = 0;
  final order = <String>[];
  final metadataReads = <Duration>[];
  final gifRequests = <String>[];
  Completer<String?>? heldMetadata;
  Completer<Uint8List?>? heldImage;
  Completer<void>? heldClock;

  late final monitor = NiedMonitorService.forTest(
    fetchText: (url) async {
      order.add('metadata');
      metadataReads.add(elapsed);
      if (heldMetadata != null) return heldMetadata!.future;
      if (!metadataAvailable) return null;
      // Transport timing fixture; earthquake pixels remain the original files.
      return jsonEncode({
        'latest_time':
            '${latest.year}/${latest.month.toString().padLeft(2, '0')}/${latest.day.toString().padLeft(2, '0')} ${latest.hour.toString().padLeft(2, '0')}:${latest.minute.toString().padLeft(2, '0')}:${latest.second.toString().padLeft(2, '0')}',
      });
    },
    fetchBytes: (url) async {
      order.add('gif');
      gifRequests.add(url);
      if (heldImage != null) return heldImage!.future;
      if (!imagesAvailable) return null;
      final key = RegExp(r'/(\d{14})\.jma_s\.gif').firstMatch(url)!.group(1)!;
      final file = File('$directory/$key.lmoni.jma_s.gif');
      return file.existsSync() ? file.readAsBytes() : null;
    },
    syncClock: () async {
      order.add('clock');
      syncCalls++;
      if (heldClock != null) await heldClock!.future;
    },
    elapsed: () => elapsed,
  );

  Future<void> start() async {
    final received = Completer<void>();
    void listen() {
      if (monitor.dataFrameTime.value == first && !received.isCompleted) {
        received.complete();
      }
    }

    monitor.dataFrameTime.addListener(listen);
    try {
      monitor.start();
      await received.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
    } finally {
      monitor.dataFrameTime.removeListener(listen);
    }
  }

  void stop() => monitor.stop();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    LmoniImageService()
      ..stop()
      ..start();
  });
  tearDown(() {
    LmoniImageService().stop();
    NiedBackgroundWorker.instance.stop();
  });

  test('startup requests source time before original GIF data', () async {
    final transport = CapturedNiedTransport();
    addTearDown(transport.stop);
    await transport.start();
    expect(transport.order.take(3), ['clock', 'metadata', 'gif']);
    expect(
      transport.gifRequests.single,
      contains('${formatNiedTimeKey(CapturedNiedTransport.first)}.jma_s.gif'),
    );
    expect(transport.monitor.dataFrameTime.value, CapturedNiedTransport.first);
  });

  test(
    'stalled recovery waits for metadata and resumes at the original latest frame',
    () async {
      final transport = CapturedNiedTransport();
      addTearDown(transport.stop);
      await transport.start();
      transport.metadataAvailable = false;
      transport.elapsed = const Duration(seconds: 3);
      transport.gifRequests.clear();
      await transport.monitor.tickForTest();
      expect(transport.gifRequests, isEmpty);
      expect(
        transport.monitor.dataFrameTime.value,
        CapturedNiedTransport.first,
      );
      transport.elapsed = const Duration(seconds: 4);
      final reads = transport.metadataReads.length;
      await transport.monitor.tickForTest();
      expect(transport.metadataReads.length, reads);
      transport.metadataAvailable = true;
      transport.latest = CapturedNiedTransport.first.add(
        const Duration(seconds: 30),
      );
      transport.elapsed = const Duration(seconds: 6);
      await transport.monitor.tickForTest();
      expect(transport.gifRequests, hasLength(1));
      expect(
        transport.gifRequests.single,
        contains('${formatNiedTimeKey(transport.latest)}.jma_s.gif'),
      );
      expect(transport.monitor.dataFrameTime.value, transport.latest);
      expect(
        transport.gifRequests.single,
        isNot(
          contains(
            '${formatNiedTimeKey(CapturedNiedTransport.first.add(const Duration(seconds: 1)))}.jma_s.gif',
          ),
        ),
      );
    },
  );

  test(
    'healthy source refreshes every 15 seconds without waiting for a slow NTP task',
    () async {
      final transport = CapturedNiedTransport()..heldClock = Completer<void>();
      addTearDown(() {
        transport.stop();
        if (!transport.heldClock!.isCompleted) transport.heldClock!.complete();
      });
      await transport.start();
      for (var second = 1; second <= 15; second++) {
        transport.elapsed = Duration(seconds: second);
        transport.latest = CapturedNiedTransport.first.add(transport.elapsed);
        await transport.monitor.tickForTest();
      }
      expect(transport.metadataReads, [
        Duration.zero,
        const Duration(seconds: 15),
      ]);
      expect(transport.syncCalls, 1);
      expect(transport.monitor.dataFrameTime.value, transport.latest);
      transport.heldClock!.complete();
    },
  );

  test(
    'late periodic metadata cannot overwrite the recovery time anchor',
    () async {
      final transport = CapturedNiedTransport();
      addTearDown(transport.stop);
      await transport.start();
      for (var second = 1; second < 15; second++) {
        transport.elapsed = Duration(seconds: second);
        await transport.monitor.tickForTest();
      }
      final oldMetadata = transport.heldMetadata = Completer<String?>();
      transport.elapsed = const Duration(seconds: 15);
      await transport.monitor.tickForTest();
      transport.heldMetadata = null;
      transport.elapsed = const Duration(seconds: 18);
      transport.latest = CapturedNiedTransport.first.add(
        const Duration(seconds: 30),
      );
      await transport.monitor.tickForTest();
      expect(transport.monitor.dataFrameTime.value, transport.latest);
      oldMetadata.complete(jsonEncode({'latest_time': '2026/06/10 18:01:35'}));
      await Future<void>.delayed(Duration.zero);
      transport.gifRequests.clear();
      transport.elapsed = const Duration(seconds: 19);
      await transport.monitor.tickForTest();
      expect(
        transport.gifRequests.single,
        contains('20260610180151.jma_s.gif'),
      );
      expect(
        transport.monitor.dataFrameTime.value,
        CapturedNiedTransport.first.add(const Duration(seconds: 31)),
      );
    },
  );

  test(
    'source time recovery is awaited before issuing any GIF request',
    () async {
      final transport = CapturedNiedTransport();
      addTearDown(transport.stop);
      await transport.start();
      transport.elapsed = const Duration(seconds: 3);
      transport.heldMetadata = Completer<String?>();
      transport.gifRequests.clear();
      final tick = transport.monitor.tickForTest();
      await Future<void>.delayed(Duration.zero);
      expect(transport.gifRequests, isEmpty);
      transport.monitor.stop();
      transport.heldMetadata!.complete(
        jsonEncode({'latest_time': '2026/06/10 18:01:50'}),
      );
      await tick;
      expect(transport.gifRequests, isEmpty);
      expect(transport.monitor.dataFrameTime.value, isNull);
    },
  );

  test(
    'late pre-stop GIF cannot publish into a restarted connection',
    () async {
      final transport = CapturedNiedTransport();
      addTearDown(transport.stop);
      await transport.start();
      transport.elapsed = const Duration(seconds: 1);
      final held = transport.heldImage = Completer<Uint8List?>();
      final tick = transport.monitor.tickForTest();
      await Future<void>.delayed(Duration.zero);
      transport.monitor.stop();
      transport.heldImage = null;
      transport.latest = CapturedNiedTransport.first;
      await transport.start();
      final oldBytes = await File(
        '${CapturedNiedTransport.directory}/20260610180121.lmoni.jma_s.gif',
      ).readAsBytes();
      held.complete(oldBytes);
      await tick;
      expect(
        transport.monitor.dataFrameTime.value,
        CapturedNiedTransport.first,
      );
    },
  );
}
