import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/models/history_map_product.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/history_product_camera_gate.dart';
import 'package:latlong2/latlong.dart';

import 'usgs_dyfi_test.dart'
    show dyfiDetail, dyfiEvent, dyfiGridResponse, originalDetail;

class _ProductPublication extends UsgsDyfiService {
  _ProductPublication()
    : super(client: MockClient((_) async => http.Response('', 404)));
  UsgsDyfiFrame? _published;
  @override
  UsgsDyfiFrame? get automaticFrame => _published;
  void publish(int responses) {
    final detail = dyfiDetail(responses);
    // Original product metadata; this state-machine test does not load grids.
    _published = UsgsDyfiFrame(
      event: dyfiEvent(detail),
      product: UsgsDyfiProduct.fromDetail(detail)!,
      cells: null,
    );
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'actual DYFI revisions do not steal another information turn or reset five seconds',
    () {
      fakeAsync((clock) {
        final service = _ProductPublication();
        final provider = QuakeProvider(
          startCatalogServices: false,
          dyfiService: service,
          shakeMapService: UsgsShakeMapService(
            client: MockClient((_) async => http.Response('', 404)),
          ),
        );
        clock.flushMicrotasks();
        service.publish(191);
        const other = UnifiedQuakeData(
          source: 'testInformation',
          origin: -2,
          eventId: 'carousel-information',
          isEew: false,
          timeZone: 0,
          titleText: 'information',
          reportNumText: '',
          useShindo: false,
          maxIntensity: '-',
          className: 'gray',
          hypocenter: '',
          magnitude: 0,
          depth: 0,
          depthText: '',
        );
        provider.handleUnifiedEventForTest(other, suppressEffects: true);
        clock.elapse(const Duration(seconds: 4));
        service.publish(210);
        expect(provider.currentUnifiedEvent?.source, 'testInformation');
        clock.elapse(const Duration(seconds: 1));
        expect(provider.currentUnifiedEvent?.source, 'usgsDyfi');
        clock.elapse(const Duration(seconds: 4));
        service.publish(223);
        expect(provider.currentUnifiedEvent?.source, 'usgsDyfi');
        clock.elapse(const Duration(seconds: 1));
        expect(provider.currentUnifiedEvent?.source, 'testInformation');
        expect(provider.unifiedEvents, hasLength(2));
        provider.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'native DYFI publication joins carousel; cache changes do not restart it',
    () {
      fakeAsync((clock) {
        var detail = dyfiDetail();
        final service = UsgsDyfiService(
          client: MockClient(
            (r) async => r.url.path.endsWith('.geojson')
                ? dyfiGridResponse(r.url)
                : http.Response(jsonEncode(detail), 200),
          ),
        );
        final provider = QuakeProvider(
          startCatalogServices: false,
          dyfiService: service,
          shakeMapService: UsgsShakeMapService(
            client: MockClient((_) async => http.Response('', 404)),
          ),
        );
        var alerts = 0;
        provider.onUnifiedEventNotified = (_, _) => alerts++;
        clock.flushMicrotasks();
        unawaited(service.observe([dyfiEvent(detail)]));
        clock.flushMicrotasks();
        detail = dyfiDetail(210); // Actual archived native product revision.
        unawaited(service.observe([dyfiEvent(detail)]));
        clock.flushMicrotasks();
        expect(provider.unifiedEvents.single.source, 'usgsDyfi');
        expect(provider.unifiedDisplayEvents, hasLength(1));
        expect(provider.currentUnifiedEvent?.source, 'usgsDyfi');
        final product = provider.currentUnifiedEvent!;
        expect(provider.unifiedSourceTypeForTest(product).name, 'usgs');
        expect(alerts, 0);

        // Controlled information identity only; no modified earthquake payload.
        const other = UnifiedQuakeData(
          source: 'testInformation',
          origin: -2,
          eventId: 'carousel-information',
          isEew: false,
          timeZone: 0,
          titleText: 'information',
          reportNumText: '',
          useShindo: false,
          maxIntensity: '-',
          className: 'gray',
          hypocenter: '',
          magnitude: 0,
          depth: 0,
          depthText: '',
        );
        provider.handleUnifiedEventForTest(other, suppressEffects: true);
        expect(provider.currentUnifiedEvent?.source, 'testInformation');
        expect(provider.unifiedDisplayEvents, hasLength(2));
        clock.elapse(const Duration(seconds: 4));
        unawaited(service.select(null)); // Cache/selection notification only.
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(provider.currentUnifiedEvent?.source, 'usgsDyfi');
        clock.elapse(const Duration(seconds: 5));
        expect(provider.currentUnifiedEvent?.source, 'testInformation');
        provider.setCurrentUnifiedIndex(
          provider.unifiedEvents.indexWhere(
            (event) => event.source == 'usgsDyfi',
          ),
        );
        expect(provider.dyfiMapFrame, same(service.automaticFrame));
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(
          provider.unifiedEvents.any((e) => e.source == 'usgsDyfi'),
          isFalse,
        );
        expect(provider.dyfiInfoDisplayEvent, isNull);
        expect(alerts, 0);
        provider.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'automatic camera uses its own grid while a different manual DYFI stays selected',
    () {
      fakeAsync((clock) {
        var current = dyfiDetail();
        final oldDetail = originalDetail('us6000u0xi');
        final old = dyfiEvent(oldDetail);
        final service = UsgsDyfiService(
          client: MockClient(
            (r) async => r.url.path.endsWith('.geojson')
                ? dyfiGridResponse(r.url)
                : http.Response(
                    jsonEncode(
                      r.url.queryParameters['eventid'] == old.eventId
                          ? oldDetail
                          : current,
                    ),
                    200,
                  ),
          ),
        );
        final provider = QuakeProvider(
          startCatalogServices: false,
          dyfiService: service,
          shakeMapService: UsgsShakeMapService(
            client: MockClient((_) async => http.Response('', 404)),
          ),
        );
        clock.flushMicrotasks();
        unawaited(service.observe([old, dyfiEvent(current)]));
        clock.flushMicrotasks();
        provider.selectHistoryMapProducts(old, product: HistoryMapProduct.dyfi);
        clock.flushMicrotasks();
        expect(provider.dyfiMapFrame?.event.eventId, old.eventId);
        current = dyfiDetail(210);
        unawaited(service.observe([old, dyfiEvent(current)]));
        clock.flushMicrotasks();
        expect(provider.currentUnifiedEvent?.source, 'usgsDyfi');
        expect(provider.dyfiMapFrame, same(service.automaticFrame));
        expect(
          provider.dyfiMapFrame?.event.eventId,
          dyfiEvent(current).eventId,
        );
        expect(service.manualFrame?.event.eventId, old.eventId);
        expect(provider.historyInfoDisplayEvent?.eventId, old.eventId);
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(provider.unifiedEvents, isEmpty);
        expect(provider.dyfiMapFrame?.event.eventId, old.eventId);
        expect(provider.historyInfoDisplayEvent?.eventId, old.eventId);
        provider.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'DYFI releases camera to information even when both centers are visible',
    () {
      final focus = DesktopEventCameraFocus();
      const product = DesktopCameraCandidate(
        key: 'usgsDyfi:event',
        index: 0,
        location: LatLng(-38, 178),
        isMapProduct: true,
      );
      const info = DesktopCameraCandidate(
        key: 'usgsEqlist:event',
        index: 1,
        location: LatLng(-38, 178),
      );
      for (final index in [0, 1, 0, 1]) {
        expect(
          focus.select(
            candidates: [product, info],
            requestedIndex: index,
            isVisible: (_) => true,
          ),
          same(index == 0 ? product : info),
        );
      }
    },
  );

  test(
    'selected overlay retains selection but cannot recapture camera after new info',
    () {
      final gate = HistoryProductCameraGate();
      gate.select('old-info');
      expect(gate.canFollow('old-info'), isTrue);
      expect(gate.canFollow('new-info'), isFalse);
      expect(gate.canFollow('old-info'), isFalse);
      gate.select('new-info'); // An explicit list click grants a new focus.
      expect(gate.canFollow('new-info'), isTrue);
    },
  );
}
