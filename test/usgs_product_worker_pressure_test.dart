import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/database_helper.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'usgs_dyfi_test.dart' show dyfiEvent, originalDetail;

class _Dyfi extends UsgsDyfiService {
  _Dyfi(http.Client client) : super(client: client);

  void Function()? onPublish, onExpiry;

  @override
  UsgsDyfiFrame? get automaticFrame {
    final frame = super.automaticFrame;
    final callback = frame == null ? onExpiry : onPublish;
    if (frame == null) {
      onExpiry = null;
    } else {
      onPublish = null;
    }
    callback?.call();
    return frame;
  }
}

class _ShakeMap extends UsgsShakeMapService {
  _ShakeMap(http.Client client) : super(client: client);

  void Function()? onPublish, onExpiry;

  @override
  UsgsShakeMapFrame? get automaticFrame {
    final frame = super.automaticFrame;
    final callback = frame == null ? onExpiry : onPublish;
    if (frame == null) {
      onExpiry = null;
    } else {
      onPublish = null;
    }
    callback?.call();
    return frame;
  }
}

Map<String, dynamic> get _worker =>
    NativeUnifiedEventOwner.runtimeDiagnostics.single;

Future<void> _drain() async {
  for (var attempt = 0; attempt < 500; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final stats = _worker['native'] as Map;
    if (stats['queued'] == 0 && stats['outstanding'] == 0) return;
  }
  fail('Worker did not drain: $_worker');
}

void _saturate(QuakeProvider provider) {
  var rejected = 0;
  for (var i = 0; i < 800; i++) {
    try {
      provider.setMagFilter(0);
    } on StateError catch (error) {
      if (!error.toString().contains('rejected (3)')) rethrow;
      rejected++;
    }
  }
  expect(rejected, greaterThan(0));
  expect(_worker['native'], containsPair('queued', 256));
  expect(_worker['native'], containsPair('outstanding', 128));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // On Windows run with FLUTTER_TEST=false and RQ_STATION_CORE_LIBRARY set
  // to the test DLL. The usual manual clock bypasses worker backpressure.
  test(
    'live Rust worker keeps original USGS products consistent at capacity',
    () async {
      final dyfiDetail = File(
        'test/fixtures/usgs_dyfi/us6000ubxg.original.geojson',
      ).readAsBytesSync();
      final grid = File(
        'test/fixtures/usgs_dyfi/us6000ubxg.1795059223143.grid.original.geojson',
      ).readAsBytesSync();
      final shakeDetail = File(
        'test/fixtures/usgs_shakemap/us6000u0xi.detail.original.geojson',
      ).readAsBytesSync();
      final contours = File(
        'test/fixtures/usgs_shakemap/us6000u0xi.cont_mmi.original.json',
      ).readAsBytesSync();
      final dyfiEventData = dyfiEvent(
        jsonDecode(utf8.decode(dyfiDetail)) as Map<String, dynamic>,
      );
      final shakeEventData = dyfiEvent(
        jsonDecode(utf8.decode(shakeDetail)) as Map<String, dynamic>,
      );
      final baseline = dyfiEvent(originalDetail('ci41345415'));
      final release = Completer<void>();
      final dyfi = _Dyfi(
        MockClient((request) async {
          if (request.url.path.endsWith('dyfi_geo_10km.geojson')) {
            return http.Response.bytes(grid, 200);
          }
          if (request.url.queryParameters['eventid'] == dyfiEventData.eventId) {
            await release.future;
            return http.Response.bytes(dyfiDetail, 200);
          }
          return http.Response('', 404);
        }),
      );
      final shake = _ShakeMap(
        MockClient((request) async {
          if (request.url.path.endsWith('/cont_mmi.json')) {
            return http.Response.bytes(contours, 200);
          }
          if (request.url.queryParameters['eventid'] ==
              shakeEventData.eventId) {
            return http.Response.bytes(shakeDetail, 200);
          }
          return http.Response('', 404);
        }),
      );
      final dbDir = Directory.systemTemp.createTempSync('rq_product_worker_');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      await databaseFactory.setDatabasesPath(dbDir.path);
      SharedPreferences.setMockInitialValues({});
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
        dyfiService: dyfi,
        shakeMapService: shake,
      );
      addTearDown(() async {
        provider.dispose();
        await (await DatabaseHelper().database).close();
        await dbDir.delete(recursive: true);
      });
      List<String> ids() =>
          provider.unifiedDisplayEvents.map((e) => e.eventId).toList();
      var dyfiExpired = false, shakeExpired = false;
      final expired = Completer<void>();
      provider.addListener(() {
        final visible = ids();
        expect(visible, hasLength(visible.toSet().length));
        if (dyfiExpired)
          expect(visible, isNot(contains(dyfiEventData.eventId)));
        if (shakeExpired) {
          expect(visible, isNot(contains(shakeEventData.eventId)));
        }
        if (dyfiExpired && shakeExpired && !expired.isCompleted)
          expired.complete();
      });
      await _drain();
      expect(NativeUnifiedEventOwner.diagnostics['workers'], 1);
      await dyfi.observe([baseline]);
      await shake.observe([baseline]);
      expect(ids(), isEmpty);

      dyfi.onPublish = () => _saturate(provider);
      final reads = List.generate(32, (_) => dyfi.observe([dyfiEventData]));
      release.complete();
      await Future.wait(reads);
      expect(ids(), [dyfiEventData.eventId]);
      expect(provider.dyfiMapFrame?.cells, hasLength(1));
      await _drain();
      expect(ids(), [dyfiEventData.eventId]);
      expect(_worker, containsPair('pendingViews', 0));
      expect(_worker, containsPair('retainedViews', 1));

      shake.onPublish = () => _saturate(provider);
      await shake.observe([shakeEventData]);
      expect(
        ids(),
        unorderedEquals([dyfiEventData.eventId, shakeEventData.eventId]),
      );
      expect(provider.shakeMapFrame?.contours, hasLength(7));
      final realShakeMap = provider.shakeMapFrame!;
      await _drain();
      expect(
        ids(),
        unorderedEquals([dyfiEventData.eventId, shakeEventData.eventId]),
      );
      expect(_worker, containsPair('retainedViews', 2));

      dyfi.onExpiry = () {
        _saturate(provider);
        dyfiExpired = true;
      };
      shake.onExpiry = () {
        _saturate(provider);
        shakeExpired = true;
      };
      await expired.future;
      await _drain();
      expect(ids(), isEmpty);
      expect(provider.dyfiMapFrame, isNull);
      expect(provider.shakeMapFrame, isNull);
      expect(_worker, containsPair('pendingViews', 0));
      expect(_worker, containsPair('retainedViews', 0));

      // Release a product seen in an earlier snapshot without another
      // worker message to acknowledge the synchronous removal.
      final seen = Completer<void>();
      final idleOwner = NativeUnifiedEventOwner(
        onBatch: (_, _) => seen.complete(),
        manualClock: false,
      );
      try {
        final product = QuakeEventAdapter.shakeMapInfo(realShakeMap);
        idleOwner.replaceProductSlot(product.source, product);
        idleOwner.send({'op': 'ready'});
        await seen.future;
        expect(idleOwner.retainsView(product), isTrue);
        idleOwner.replaceProductSlot(product.source, null);
        expect(idleOwner.retainsView(product), isFalse);
      } finally {
        idleOwner.dispose();
      }
    },
    skip:
        Platform.environment['FLUTTER_TEST'] != 'false' ||
        !Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
