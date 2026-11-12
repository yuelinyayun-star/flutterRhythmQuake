import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/native_nsmc_image.dart';
import 'package:flutterrhythmquake/services/native_nsmc_image_portable.dart'
    as portable;
import 'package:flutterrhythmquake/services/sources/nsmc_satellite_cloud_service.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/weather_playback_controller.dart';
import 'package:flutterrhythmquake/widgets/map/nsmc_cloud_tile_provider.dart';
import 'package:flutterrhythmquake/widgets/map/nsmc_satellite_cloud_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = File(
    'test/fixtures/nsmc_viewport_20261105/tile-z3-x6-y3.png',
  ).readAsBytesSync();
  final time = DateTime.utc(2026, 11, 5, 4);
  test('native tile bounds and original pixels match portable backend', () {
    for (var z = 0; z < 7; z++) {
      final n = 1 << z;
      for (final x in [-1, 0, n - 1, n]) {
        for (final y in [0, n ~/ 2, n - 1]) {
          final actual = NativeNsmcImage.bounds(z, x, y),
              expected = portable.NativeNsmcImage.bounds(z, x, y);
          for (var i = 0; i < 4; i++) {
            expect(actual[i], closeTo(expected[i], 1e-10));
          }
        }
      }
    }
    final native = img.decodePng(
          NativeNsmcImage.project(original, z: 3, y: 3),
        )!,
        other = img.decodePng(
          portable.NativeNsmcImage.project(original, z: 3, y: 3),
        )!;
    expect(
      native.getBytes(order: img.ChannelOrder.rgba),
      other.getBytes(order: img.ChannelOrder.rgba),
    );
  });
  test(
    'live service requests only original time catalog; Android metadata and legacy bytes both round-trip',
    () async {
      final requested = <Uri>[];
      final service = NsmcSatelliteCloudService.forTest(
        client: MockClient((r) async {
          requested.add(r.url);
          return http.Response.bytes(
            File(
              'test/fixtures/weather_playback_20261105/nsmc.json',
            ).readAsBytesSync(),
            200,
          );
        }),
      );
      final first = service.frameStream.first;
      service.start();
      final frame = await first.timeout(const Duration(seconds: 3));
      expect(requested.length, 1);
      expect(
        requested.single.toString(),
        NsmcSatelliteCloudService.targetTimesUrl,
      );
      expect(frame!.isTiled, isTrue);
      expect(frame.imageBytes, isEmpty);
      expect(
        ForegroundStationPayload.decodeNsmcSatelliteCloud(
          ForegroundStationPayload.nsmcSatelliteCloud(frame),
        )!.isTiled,
        isTrue,
      );
      final legacy = NsmcSatelliteCloudFrame(time: time, imageBytes: original);
      expect(
        ForegroundStationPayload.decodeNsmcSatelliteCloud(
          ForegroundStationPayload.nsmcSatelliteCloud(legacy),
        )!.imageBytes,
        original,
      );
      service.stop(clear: true);
    },
  );
  test(
    'NSMC playback changes only the selected time and never downloads a global image',
    () async {
      var requests = 0;
      final controller = WeatherPlaybackController(
        autoPrepare: false,
        client: MockClient((r) async {
          requests++;
          expect(r.url.toString(), NsmcSatelliteCloudService.targetTimesUrl);
          return http.Response.bytes(
            File(
              'test/fixtures/weather_playback_20261105/nsmc.json',
            ).readAsBytesSync(),
            200,
          );
        }),
      );
      controller.selectSource('nsmcSatelliteCloudLayer');
      await controller.load();
      final playing=controller.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(controller.loading,isTrue);
      (controller.frame.value!.data as NsmcSatelliteCloudFrame).onVisibleReady!();
      await playing;
      controller.pause();
      expect(controller.error,isNull);
      expect(
        (controller.frame.value!.data as NsmcSatelliteCloudFrame).isTiled,
        isTrue,
      );
      expect(controller.cachedBytes, 0);
      expect(requests, 1);
      controller.dispose();
    },
  );

  testWidgets(
    'visible tile starts before margin, aborted queued tiles never download',
    (tester) async {
      final requests = <Uri>[];
      final pending = Completer<http.Response>();
      final provider = NsmcCloudTileProvider(
        concurrency: 1,
        client: MockClient((r) {
          requests.add(r.url);
          return pending.future;
        }),
      );
      final bounds = NativeNsmcImage.bounds(3, 6, 3);
      provider.setView(
        MapCamera(
          crs: const Epsg3857(),
          center: LatLng((bounds[1] + bounds[3]) / 2, 112.5),
          zoom: 3,
          rotation: 0,
          nonRotatedSize: const Size(80, 80),
        ),
      );
      final options = TileLayer(
        urlTemplate: 'nsmc://${time.millisecondsSinceEpoch}/{z}/{x}/{y}',
        tileProvider: provider,
      );
      final cancels = [Completer<void>(), Completer<void>()];
      final ring = provider.getImageWithCancelLoadingSupport(
        const TileCoordinates(5, 3, 3),
        options,
        cancels[0].future,
      );
      final visible = provider.getImageWithCancelLoadingSupport(
        const TileCoordinates(6, 3, 3),
        options,
        cancels[1].future,
      );
      final streams = [
        ring.resolve(ImageConfiguration.empty),
        visible.resolve(ImageConfiguration.empty),
      ];
      final listener = ImageStreamListener(
        (_, __) {},
        onError: (Object e, StackTrace? s) {},
      );
      for (final s in streams) {
        s.addListener(listener);
      }
      await tester.pump();
      expect(requests.length, 1);
      expect(requests.single.queryParameters['bbox'], bounds.join(','));
      expect(provider.activeRequests, 1);
      expect(provider.queuedRequests, 1);
      cancels[0].complete();
      await tester.pump();
      expect(provider.queuedRequests, 0);
      pending.complete(http.Response.bytes(original, 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump();
      expect(requests.length, 1);
      for (final s in streams) {
        s.removeListener(listener);
      }
      cancels[1].complete();
      provider.dispose();
      await tester.pump();
      expect(provider.cachedTiles, 0);
      expect(provider.queuedRequests, 0);
    },
  );
  testWidgets('new frame stays hidden until every visible tile is decoded', (tester)async {
    tester.view.physicalSize=const Size(80,80);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final pending=Completer<http.Response>();
    var ready=0;
    final central=NativeNsmcImage.bounds(3,6,3).join(',');
    final originals=<String,String>{for(var x=5;x<=7;x++)for(var y=2;y<=4;y++)NativeNsmcImage.bounds(3,x,y).join(','):'tile-z3-x$x-y$y.png'};
    final provider=NsmcCloudTileProvider(client:MockClient((r)async {
      final bbox=r.url.queryParameters['bbox']!,stamp=r.url.queryParameters['datetime'];
      final isNew=stamp=='202611050300';
      if(isNew&&bbox==central)return pending.future;
      return http.Response.bytes(File('test/fixtures/nsmc_viewport_20261105/${isNew?'frame-202611050300/':''}${originals[bbox]}').readAsBytesSync(),200);
    }));
    final frame=ValueNotifier(NsmcSatelliteCloudFrame.tiles(time:time));
    await tester.pumpWidget(MaterialApp(home:FlutterMap(options:const MapOptions(initialCenter:LatLng(21.943045533438177,112.5),initialZoom:3),children:[ValueListenableBuilder<NsmcSatelliteCloudFrame>(valueListenable:frame,builder:(_,v,child)=>NsmcSatelliteCloudLayer(frame:v,tileProvider:provider))])));
    for(var i=0;i<40;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:35)));await tester.pump();if(provider.activeRequests==0&&provider.cachedTiles==9)break;}
    await tester.pumpAndSettle();expect(find.byType(TileLayer),findsOneWidget);
    final next=time.subtract(const Duration(hours:1));
    frame.value=NsmcSatelliteCloudFrame.tiles(time:next,onVisibleReady:()=>ready++);
    await tester.pump();
    for(var i=0;i<10;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:35)));await tester.pump();}
    expect(ready,0);
    final layers=tester.widgetList<TileLayer>(find.byType(TileLayer)).toList();
    expect(layers.length,2);expect(layers.first.urlTemplate,contains('${time.millisecondsSinceEpoch}'));
    final staged=find.ancestor(of:find.byWidget(layers.last),matching:find.byType(Opacity)).first;
    expect(tester.widget<Opacity>(staged).opacity,0);
    pending.complete(http.Response.bytes(File('test/fixtures/nsmc_viewport_20261105/frame-202611050300/tile-z3-x6-y3.png').readAsBytesSync(),200));
    for(var i=0;i<30&&ready==0;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:35)));await tester.pump();}
    await tester.pumpAndSettle();expect(ready,greaterThan(0));
    expect(find.byType(TileLayer),findsOneWidget);expect(tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,contains('${next.millisecondsSinceEpoch}'));
    expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());frame.dispose();expect(provider.cachedTiles,0);
  });

  testWidgets(
    'production layer loads visible tile and exactly one outer ring',
    (tester) async {
      tester.view.physicalSize = const Size(80, 80);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requested = <String>{};
      final originals = <String, Uint8List>{
        for (var x = 5; x <= 7; x++)
          for (var y = 2; y <= 4; y++)
            NativeNsmcImage.bounds(3, x, y).join(','): File(
              'test/fixtures/nsmc_viewport_20261105/tile-z3-x$x-y$y.png',
            ).readAsBytesSync(),
      };
      final provider = NsmcCloudTileProvider(
        client: MockClient((r) async {
          final bbox = r.url.queryParameters['bbox']!;
          requested.add(bbox);
          expect(r.url.queryParameters['width'], '256');
          expect(r.url.queryParameters['height'], '256');
          expect(
            originals.containsKey(bbox),
            isTrue,
            reason: 'must not load beyond one ring',
          );
          return http.Response.bytes(originals[bbox]!, 200);
        }),
      );
      final enabled = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(21.943045533438177, 112.5),
              initialZoom: 3,
            ),
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: enabled,
                builder: (_, on, child) => TickerMode(
                  enabled: on,
                  child: NsmcSatelliteCloudLayer(
                    frame: NsmcSatelliteCloudFrame.tiles(time: time),
                    tileProvider: provider,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final tile = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tile.panBuffer, 1);
      expect(tile.keepBuffer, 1);
      for (
        var i = 0;
        i < 100 && (requested.length < 9 || provider.activeRequests > 0);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(requested, originals.keys.toSet());
      expect(provider.cachedTiles, 9);
      expect(provider.activeRequests, 0);
      expect(tester.takeException(), isNull);
      enabled.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(TileLayer), findsNothing);
      expect(provider.isDisposed, isTrue);
      expect(provider.cachedTiles, 0);
      await tester.pumpWidget(const SizedBox());
      enabled.dispose();
    },
  );
}
