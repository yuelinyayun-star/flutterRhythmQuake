import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/jma_eqlist_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/cwa_eqlist_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'JMA HTTP rows preserve original intensity areas across serialization',
    () async {
      final file = File('test/fixtures/jma_voice/p2p_history_20260921.json');
      final bytes = file.readAsBytesSync();
      final originals = (jsonDecode(utf8.decode(bytes)) as List)
          .cast<Map<String, dynamic>>();
      final service = JmaEqlistService.forTesting(
        MockClient(
          (_) async => http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      List<QuakeMessage>? rows;
      service.onListUpdated = (value) => rows = value;
      await service.fetch();
      expect(rows, isNotEmpty);
      var observed = 0;
      for (final row in rows!) {
        final raw = originals.firstWhere(
          (e) =>
              e['earthquake']['time'].toString().replaceAll('/', '-') ==
                  row.eventId &&
              DateTime.parse(
                    e['issue']['time'].toString().replaceAll('/', '-'),
                  ) ==
                  row.reportTime,
        );
        final event = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
        expect(row.informationMap!.warnArea, event.warnArea);
        expect(row.informationMap!.titleText, event.titleText);
        final restored = QuakeMessage.fromMap(
          jsonDecode(jsonEncode(row.toMap())) as Map<String, dynamic>,
        );
        expect(restored.informationMap!.toMap(), row.informationMap!.toMap());
        if (event.warnArea.isNotEmpty) observed++;
      }
      expect(observed, greaterThan(5));
      expect(file.readAsBytesSync(), bytes);
    },
  );
  test(
    'Wolfx JMA summaries preserve regions observed through P2P HTTP',
    () async {
      final bytes = File(
        'test/fixtures/jma_camera_20261030/p2p_history.original.json',
      ).readAsBytesSync();
      final service = JmaEqlistService.forTesting(
        MockClient(
          (_) async => http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      var p2pRows = <QuakeMessage>[];
      service.onListUpdated = (rows) => p2pRows = rows;
      await service.fetch();
      final detail = p2pRows.firstWhere(
        (row) =>
            row.eventId == '2026-10-30 17:45:00' &&
            row.informationMap!.warnArea.isNotEmpty,
      );
      final original = File(
        'test/fixtures/event_render_20261104/wolfx-jma.original.json',
      ).readAsStringSync(encoding: utf8);
      final summaries = QuakeEventAdapter.convertWolfxJmaEqlist(
        jsonDecode(original) as Map<String, dynamic>,
      );
      final summary = summaries.singleWhere(
        (row) => row.eventId == '20261030174600',
      );
      expect(summary.informationMap, isNull);
      expect(detail.location, summary.location);
      final manager = EqlistManager();
      final owner = NativeUnifiedEventOwner.supported
          ? NativeUnifiedEventOwner(onBatch: (_, _) {})
          : null;
      addTearDown(() {
        manager.onJmaObservedMapBindings = null;
        manager.updateJmaList(const []);
        owner?.dispose();
      });
      for (final binding in [
        null,
        if (owner != null) owner.jmaObservedMapBindings,
      ]) {
        manager.onJmaObservedMapBindings = binding;
        manager.updateJmaList([detail]);
        manager.updateJmaList(summaries);
        final retained = manager.jmaList.singleWhere(
          (row) => row.eventId == summary.eventId,
        );
        expect(retained.informationMap, same(detail.informationMap));
        expect(retained.toMap()..remove('informationMap'), summary.toMap());
      }
    },
  );
  test(
    'CWA HTTP rows retain original fill parameters and existing field values',
    () async {
      final list = File(
        'test/fixtures/cwa_catalog_20261028/trem_list.original.json',
      ).readAsBytesSync();
      final detail = File(
        'test/fixtures/cwa_catalog_20261028/trem_detail.original.json',
      ).readAsBytesSync();
      final original = jsonDecode(utf8.decode(list)) as List;
      final service = CwaEqlistService.forTesting(
        MockClient(
          (request) async =>
              http.Response.bytes(request.url.hasQuery ? list : detail, 200),
        ),
      );
      await service.fetchForTesting();
      expect(service.latestList.length, original.length);
      for (final row in service.latestList) {
        final raw = original.firstWhere((e) => e['id'] == row.eventId);
        expect(row.informationMap!.cwaSourcePayload, raw);
        final event = QuakeEventAdapter.convert(
          'cwaEqlist',
          Map<String, dynamic>.from(raw as Map),
          0,
        )!;
        expect(row.informationMap!.warnArea, event.warnArea);
        expect(row.latitude, event.lat);
        expect(row.longitude, event.lng);
      }
      service.stop();
    },
  );
}
