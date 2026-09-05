import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_alert_map_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'identical response retains snapshot and does not notify twice',
    () async {
      final service = ChinaWeatherAlertMapService();
      var notifications = 0;
      void listener() => notifications++;
      final notifier = ChinaWeatherAlertMapService.alertItemsNotifier;
      notifier.addListener(listener);
      addTearDown(() => notifier.removeListener(listener));
      await http.runWithClient(
        () async {
          await service.fetchNow(force: true);
          final snapshot = notifier.value;
          await service.fetchNow(force: true);
          expect(identical(snapshot, notifier.value), isTrue);
          expect(notifications, 1);
        },
        () => MockClient(
          (_) async => http.Response('{"result":{"data":[]}}', 200),
        ),
      );
    },
  );

  test('stop prevents an in-flight map response from publishing', () async {
    final service = ChinaWeatherAlertMapService();
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final snapshot = ChinaWeatherAlertMapService.alertItemsNotifier.value;
    await http.runWithClient(
      () async {
        service.start();
        final request = service.fetchNow(force: true);
        await started.future;
        service.stop();
        response.complete(
          http.Response('{"result":{"data":[]},"revision":2}', 200),
        );
        await request;
        expect(service.isRunning, isFalse);
        expect(
          identical(
            snapshot,
            ChinaWeatherAlertMapService.alertItemsNotifier.value,
          ),
          isTrue,
        );
        expect(ChinaWeatherAlertMapService.isLoadingNotifier.value, isFalse);
      },
      () => MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
  });

  test(
    'detail requests coalesce, reuse cache and evict oldest entries',
    () async {
      final service = ChinaWeatherAlertMapService();
      var requests = 0;
      await http.runWithClient(
        () async {
          final first = service.fetchAlertDetail('cache-contract');
          final second = service.fetchAlertDetail('cache-contract.html');
          final results = await Future.wait([first, second]);
          expect(requests, 1);
          expect(identical(results[0], results[1]), isTrue);
          await service.fetchAlertDetail('cache-contract');
          expect(requests, 1);
          for (
            var i = 0;
            i < ChinaWeatherAlertMapService.detailCacheLimit;
            i++
          ) {
            await service.fetchAlertDetail('cache-contract-$i');
          }
          await service.fetchAlertDetail('cache-contract');
          expect(requests, ChinaWeatherAlertMapService.detailCacheLimit + 2);
        },
        () => MockClient((_) async {
          requests++;
          return http.Response('var alarminfo={"head":"cache contract"};', 200);
        }),
      );
    },
  );

  test('failed detail request may retry', () async {
    var requests = 0;
    await http.runWithClient(
      () async {
        final service = ChinaWeatherAlertMapService();
        expect(await service.fetchAlertDetail('retry-contract'), isNull);
        expect(await service.fetchAlertDetail('retry-contract'), isNotNull);
        expect(requests, 2);
      },
      () => MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('', 503)
            : http.Response('var alarminfo={"head":"retry contract"};', 200);
      }),
    );
  });
}
