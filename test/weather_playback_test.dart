import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/native_weather_playback_catalog.dart';
import 'package:flutterrhythmquake/services/native_weather_playback_catalog_portable.dart'
    as portable;
import 'package:flutterrhythmquake/services/weather_playback_controller.dart';
import 'package:flutterrhythmquake/services/sources/fan_radar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const root = 'test/fixtures/weather_playback_20261105';
  test(
    'all original catalogs have native/portable parity without changing raw bytes',
    () {
      final files = [
        'radar',
        'precipitation',
        'jma_radar',
        'jma_cloud',
        'nsmc',
      ];
      for (var i = 0; i < files.length; i++) {
        final bytes = File('$root/${files[i]}.json').readAsBytesSync(),
            before = bytes.toList();
        final native = NativeWeatherPlaybackCatalog.parse(i, bytes);
        expect(
          native,
          portable.NativeWeatherPlaybackCatalog.parse(i, bytes),
          reason: files[i],
        );
        expect(native.length, inInclusiveRange(2, 24));
        expect(bytes, before);
      }
    },
  );
  test(
    'real radar frames: play, pause, seek, three-image budget, live and exit release',
    () async {
      final client = MockClient((request) async {
        final path = request.url.path;
        return http.Response.bytes(
          File(
            path.endsWith('radar_list.json')
                ? '$root/radar.json'
                : '$root/${request.url.pathSegments.last}',
          ).readAsBytesSync(),
          200,
        );
      });
      final c = WeatherPlaybackController(
        client: client,
        autoPrepare: false,
        interval: const Duration(days: 1),
      );
      c.selectSource('radarChinaLayer');
      await c.load();
      expect(c.entries.length, 24);
      expect(c.frame.value, isNull);
      await c.toggle();
      expect(c.playing, isTrue);
      expect(c.index, 0);
      expect(c.frame.value!.time, c.timeAt(0));
      final first = (c.frame.value!.data as FanRadarFrame).imageBytes;
      expect(
        first,
        File('$root/ACHN_QREF_20261105_140000.png').readAsBytesSync(),
      );
      c.pause();
      expect(c.playing, isFalse);
      for (var i = 1; i < 4; i++) {
        await c.seek(i);
        expect(c.index, i);
      }
      expect(c.cachedBytes, lessThanOrEqualTo(16 * 1024 * 1024));
      expect(
        c.cachedBytes,
        [1, 2, 3].fold<int>(
          0,
          (sum, i) =>
              sum +
              File(
                '$root/ACHN_QREF_20261105_14${(i * 6).toString().padLeft(2, '0')}00.png',
              ).lengthSync(),
        ),
      );
      c.live();
      expect(c.frame.value, isNull);
      expect(c.playing, isFalse);
      c.selectSource(null);
      expect(c.cachedBytes, 0);
      expect(c.entries, isEmpty);
      c.dispose();
      expect(c.isDisposed, isTrue);
    },
  );
  test(
    'pause during a slow image request stays paused when the image arrives',
    () async {
      final pending = Completer<http.Response>();
      final c = WeatherPlaybackController(
        autoPrepare: false,
        interval: const Duration(days: 1),
        client: MockClient((r) async {
          final file = r.url.pathSegments.last;
          if (file == 'ACHN_QREF_20261105_141800.png') return pending.future;
          return http.Response.bytes(
            File(
              r.url.path.endsWith('radar_list.json')
                  ? '$root/radar.json'
                  : '$root/$file',
            ).readAsBytesSync(),
            200,
          );
        }),
      );
      c.selectSource('radarChinaLayer');
      await c.load();
      await c.toggle();
      final before = c.frame.value;
      final advancing = c.show(3);
      expect(c.loading, isTrue);
      c.pause();
      expect(c.playing, isFalse);
      expect(c.loading, isFalse);
      pending.complete(
        http.Response.bytes(
          File('$root/ACHN_QREF_20261105_141800.png').readAsBytesSync(),
          200,
        ),
      );
      await advancing;
      expect(c.frame.value, same(before));
      c.dispose();
    },
  );

  test('late image cannot reappear after source changes or disposal', () async {
    final pending = Completer<http.Response>();
    final c = WeatherPlaybackController(
      autoPrepare: false,
      client: MockClient(
        (r) async => r.url.path.endsWith('radar_list.json')
            ? http.Response.bytes(
                File('$root/radar.json').readAsBytesSync(),
                200,
              )
            : pending.future,
      ),
    );
    c.selectSource('radarChinaLayer');
    await c.load(preload: false);
    final showing = c.show(0);
    c.selectSource('jmaRadarLayer');
    c.dispose();
    pending.complete(
      http.Response.bytes(
        File('$root/ACHN_QREF_20261105_140000.png').readAsBytesSync(),
        200,
      ),
    );
    await showing;
    expect(c.cachedBytes, 0);
  });

  test(
    'selecting radar proactively loads its catalog and initial real images before play',
    () async {
      final requested = <String>[];
      final c = WeatherPlaybackController(
        client: MockClient((r) async {
          requested.add(r.url.pathSegments.last);
          return http.Response.bytes(
            File(
              r.url.path.endsWith('radar_list.json')
                  ? '$root/radar.json'
                  : '$root/${r.url.pathSegments.last}',
            ).readAsBytesSync(),
            200,
          );
        }),
      );
      final ready = Completer<void>();
      c.addListener(() {
        if (!c.loading && c.entries.isNotEmpty && !ready.isCompleted)
          ready.complete();
      });
      c.selectSource('radarChinaLayer');
      await ready.future.timeout(const Duration(seconds: 5));
      expect(requested, [
        'radar_list.json',
        'ACHN_QREF_20261105_140000.png',
        'ACHN_QREF_20261105_140600.png',
      ]);
      expect(
        c.frame.value,
        isNull,
        reason: 'preloading must not overwrite the live map',
      );
      expect(c.cachedBytes, greaterThan(0));
      await c.toggle();
      c.pause();
      expect(
        requested.length,
        3,
        reason: 'first play uses already preloaded original pixels',
      );
      expect(c.frame.value!.time, c.timeAt(0));
      c.dispose();
    },
  );
}
