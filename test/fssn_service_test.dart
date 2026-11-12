import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/sources/fssn_service.dart';

List<int> frame(String name) => File(
  'test/fixtures/fssn_direct_20261017/$name.original.json',
).readAsBytesSync();
Map<String, dynamic> packet(String name) =>
    jsonDecode(utf8.decode(frame(name))) as Map<String, dynamic>;

Future<void> until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('FSSN test');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('original FSSN Data reuses FAN conversion, timezone and NED tensor', () {
    final initial = packet('initial_all');
    for (final source in ['fssn', 'fssn-cmt']) {
      final raw = initial[source]['Data'] as Map<String, dynamic>;
      final before = jsonEncode(raw);
      final decoded = FanService.decodeFssnPayload(
        raw,
        cmt: source == 'fssn-cmt',
      )!;
      final fan = FanService.decodeEventPayload(raw, sourceHint: source)!;
      expect(decoded.unified.eventId, fan.eventId);
      expect(decoded.unified.source, fan.source);
      expect(decoded.unified.magnitude, fan.magnitude);
      expect(decoded.unified.maxIntensity, fan.maxIntensity);
      expect(decoded.unified.hypocenter, fan.hypocenter);
      expect(decoded.unified.apiTypeLabel, 'FSSN');
      expect(decoded.message.apiTypeLabel, 'FSSN');
      expect(decoded.unified.timeZone, 8);
      expect(decoded.message.timeZone, 8);
      expect(decoded.unified.sourcePayload, raw);
      expect(jsonEncode(raw), before);
      if (source == 'fssn-cmt') {
        expect(decoded.unified.eventId, raw['eventId']);
        expect(decoded.unified.sourcePayload!['id'], raw['id']);
        expect(decoded.unified.nodalPlane1, '225/77/83');
        expect(decoded.unified.momentTensor, isNotNull);
        expect(decoded.message.momentTensor, isNotNull);
        expect(decoded.unified.centroidDepth, 131.9);
        expect(decoded.unified.magnitude, 6.9);
      }
    }
  });

  test('direct FSSN ownership suppresses only FAN FSSN deliveries', () async {
    final fan = FanService()..setFssnDeliveryEnabled(false);
    final events = <UnifiedQuakeData>[];
    final sub = fan.onUnifiedEvent.listen(events.add);
    addTearDown(() async {
      await sub.cancel();
      fan.dispose();
    });
    final raw = packet('initial_all')['fssn']['Data'];
    final update = jsonEncode({
      'type': 'update',
      'source': 'fssn',
      'Data': raw,
    });
    fan.handleMessageForTesting(update);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    fan.setFssnDeliveryEnabled(true);
    fan.handleMessageForTesting(update);
    await until(() => events.isNotEmpty);
    expect(events.single.source, 'fssnEqlist');
  });

  test(
    'original socket snapshots, live update, dedupe, reconnect and stop',
    () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final commands = <String>[];
      final connections = <int>[];
      var sendLists = false;
      final serverSub = server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        peers.add(ws);
        connections.add(peers.length);
        ws.add(utf8.decode(frame('heartbeat')));
        ws.add(utf8.decode(frame('initial_all')));
        ws.listen((raw) {
          commands.add(raw.toString());
          if (sendLists && raw == 'fssnlist') {
            ws.add(utf8.decode(frame('fssnlist_response')));
          }
          if (sendLists && raw == 'cmtlist') {
            ws.add(utf8.decode(frame('cmtlist_response')));
          }
        });
      });
      final service = FssnService(
        uri: Uri.parse('ws://127.0.0.1:${server.port}/all'),
        retryDelay: const Duration(milliseconds: 20),
      );
      final info = <QuakeMessage>[];
      final cmt = <QuakeMessage>[];
      final events = <UnifiedQuakeData>[];
      final statuses = <SourceStatus>[];
      service.onFssnListUpdated = (rows) {
        info
          ..clear()
          ..addAll(rows);
      };
      service.onCmtListUpdated = (rows) {
        cmt
          ..clear()
          ..addAll(rows);
      };
      service.onStatusChanged = statuses.add;
      final sub = service.onUnifiedEvent.listen(events.add);
      addTearDown(() async {
        service.dispose();
        await sub.cancel();
        for (final peer in peers) {
          await peer.close();
        }
        await serverSub.cancel();
        await server.close(force: true);
      });
      service.connect();
      await until(
        () =>
            info.length == 1 &&
            cmt.length == 1 &&
            commands.contains('cmtlist') &&
            commands.contains('ping'),
      );
      expect(events, isEmpty);
      expect(info.every((e) => e.isHistory && e.timeZone == 8), isTrue);
      expect(cmt.first.momentTensor, isNotNull);
      expect(statuses, contains(SourceStatus.connected));
      // Replay an unchanged, captured Data object as a live protocol delivery.
      // No timestamps, coordinates, magnitudes or source fields are invented.
      final original = packet('fssnlist_response')['Data'][1];
      final update = jsonEncode({
        'type': 'update',
        'source': 'fssn',
        'Data': original,
      });
      peers.last.add(update);
      peers.last.add(update);
      final originalCmt = packet('cmtlist_response')['Data'][1];
      peers.last.add(
        jsonEncode({
          'type': 'update',
          'source': 'fssn-cmt',
          'Data': originalCmt,
        }),
      );
      await until(() => events.length == 2);
      expect(events.map((e) => e.source), ['fssnEqlist', 'fssnCmt']);
      expect(events.first.sourcePayload, original);
      expect(events.last.sourcePayload, originalCmt);
      peers.last.add(utf8.decode(frame('fssnlist_response')));
      peers.last.add(utf8.decode(frame('cmtlist_response')));
      await until(() => info.length == 5 && cmt.length == 10);
      expect(events, hasLength(2));
      sendLists = true;
      await peers.last.close();
      await until(
        () =>
            connections.length == 2 &&
            commands.where((e) => e == 'cmtlist').length == 2,
      );
      expect(events, hasLength(2));
      service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(connections, hasLength(2));
      expect(statuses.last, SourceStatus.disconnected);
    },
  );

  test(
    'native live upstream sends both catalogues without FAN',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      SoundEffectService().enabled = false;
      final service = FssnService();
      final manager = SourceManager()..reset();
      manager.registerSource(service);
      manager.setSourceEnabled('FAN', false);
      final provider = QuakeProvider(startCatalogServices: false);
      final receiveInfo = service.onFssnListUpdated!;
      final receiveCmt = service.onCmtListUpdated!;
      final info = Completer<List<QuakeMessage>>();
      final cmt = Completer<List<QuakeMessage>>();
      final events = <UnifiedQuakeData>[];
      service.onFssnListUpdated = (rows) {
        receiveInfo(rows);
        if (rows.length > 1 && !info.isCompleted) info.complete(rows);
      };
      service.onCmtListUpdated = (rows) {
        receiveCmt(rows);
        if (rows.length > 1 && !cmt.isCompleted) cmt.complete(rows);
      };
      final sub = service.onUnifiedEvent.listen(events.add);
      addTearDown(() async {
        provider.dispose();
        service.dispose();
        await sub.cancel();
        manager.reset();
        SoundEffectService().enabled = true;
      });
      service.connect();
      final lists = await Future.wait([
        info.future,
        cmt.future,
      ]).timeout(const Duration(seconds: 30));
      expect(lists[0], isNotEmpty);
      expect(lists[1].any((e) => e.momentTensor != null), isTrue);
      expect(events, isEmpty);
      expect(
        provider.historyBySource['fssnEqlist'],
        hasLength(lists[0].length),
      );
      expect(provider.historyBySource['fssnCmt'], hasLength(lists[1].length));
      expect(provider.unifiedEvents, isEmpty);
      provider.selectHistoryMapProducts(lists[1].first);
      expect(provider.unifiedDisplayEvents.single.source, 'fssnCmt');
      expect(provider.unifiedDisplayEvents.single.apiTypeLabel, 'FSSN');
      expect(provider.unifiedDisplayEvents.single.momentTensor, isNotNull);
      provider.selectHistoryMapProducts(lists[0].first);
      expect(provider.unifiedDisplayEvents.single.source, 'fssnEqlist');
      expect(provider.unifiedDisplayEvents.single.apiTypeLabel, 'FSSN');
      // ignore: avoid_print
      print(
        'Live FSSN: info=${lists[0].length}, cmt=${lists[1].length}; initial alerts=${events.length}',
      );
    },
    skip: Platform.environment['RQ_FSSN_LIVE'] != '1',
  );
}
