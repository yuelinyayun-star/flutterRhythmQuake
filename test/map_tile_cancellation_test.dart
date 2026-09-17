import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutterrhythmquake/widgets/map/shared_cancellable_tile_provider.dart';

class _DelayedAbortClient extends http.BaseClient {
  final started = Completer<void>();
  final releaseAbort = Completer<void>();
  final firstResponse = Completer<http.StreamedResponse>();
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (requests == 1) {
      started.complete();
      return Future.any([
        firstResponse.future,
        () async {
          await (request as http.Abortable).abortTrigger;
          await releaseAbort.future;
          throw http.RequestAbortedException(request.url);
        }(),
      ]);
    }
    return http.StreamedResponse(
      Stream.value(File('assets/images/volcano/vol.png').readAsBytesSync()),
      200,
    );
  }
}

http.StreamedResponse _tileResponse() => http.StreamedResponse(
  Stream.value(File('assets/images/volcano/vol.png').readAsBytesSync()),
  200,
);

Future<ImageInfo> _loadedImage(ImageStream stream) {
  final result = Completer<ImageInfo>();
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      stream.removeListener(listener);
      result.complete(image);
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      result.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return result.future;
}

void main() {
  testWidgets(
    'returning to a cancelled tile loads a real image without a gesture',
    (tester) async {
      await tester.runAsync(() async {
        final client = _DelayedAbortClient();
        final provider = SharedCancellableTileProvider(
          httpClient: client,
          cachingProvider: const DisabledMapCachingProvider(),
        );
        final options = TileLayer(
          urlTemplate: 'https://tiles.test/{z}/{x}/{y}',
        );
        final oldCancel = Completer<void>();
        final newCancel = Completer<void>();
        const coords = TileCoordinates(26, 13, 5);
        final oldImage = provider.getImageWithCancelLoadingSupport(
          coords,
          options,
          oldCancel.future,
        );
        final oldResult = _loadedImage(
          oldImage.resolve(ImageConfiguration.empty),
        );
        await client.started.future;
        oldCancel.complete();
        await Future<void>.delayed(Duration.zero);
        final newImage = provider.getImageWithCancelLoadingSupport(
          coords,
          options,
          newCancel.future,
        );
        final newResult = _loadedImage(
          newImage.resolve(ImageConfiguration.empty),
        );
        client.releaseAbort.complete();
        final result = await newResult.timeout(const Duration(seconds: 5));
        final old = await oldResult.timeout(const Duration(seconds: 5));
        final width = result.image.width;
        result.dispose();
        old.dispose();
        newCancel.complete();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await provider.dispose();
        client.close();
        expect(width, greaterThan(1));
        expect(client.requests, 2);
      });
    },
  );

  testWidgets('one consumer cannot cancel a tile still used by another', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final client = _DelayedAbortClient();
      final provider = SharedCancellableTileProvider(
        httpClient: client,
        cachingProvider: const DisabledMapCachingProvider(),
      );
      final options = TileLayer(
        urlTemplate: 'https://tiles.test/shared/{z}/{x}/{y}',
      );
      const coords = TileCoordinates(26, 13, 5);
      final firstCancel = Completer<void>();
      final secondCancel = Completer<void>();
      final first = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        firstCancel.future,
      );
      final firstResult = _loadedImage(first.resolve(ImageConfiguration.empty));
      await client.started.future;
      final second = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        secondCancel.future,
      );
      final secondResult = _loadedImage(
        second.resolve(ImageConfiguration.empty),
      );
      firstCancel.complete();
      client.releaseAbort.complete();
      await Future<void>.delayed(Duration.zero);
      client.firstResponse.complete(_tileResponse());
      final result = await secondResult.timeout(const Duration(seconds: 5));
      final firstImage = await firstResult;
      expect(result.image.width, greaterThan(1));
      expect(client.requests, 1);
      result.dispose();
      firstImage.dispose();
      secondCancel.complete();
      await Future<void>.delayed(Duration.zero);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await provider.dispose();
      client.close();
    });
  });

  testWidgets('completed tiles stay cached after leaving and returning', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final client = _DelayedAbortClient();
      client.firstResponse.complete(_tileResponse());
      final provider = SharedCancellableTileProvider(
        httpClient: client,
        cachingProvider: const DisabledMapCachingProvider(),
      );
      final options = TileLayer(
        urlTemplate: 'https://tiles.test/cache/{z}/{x}/{y}',
      );
      const coords = TileCoordinates(26, 13, 5);
      final firstCancel = Completer<void>();
      final first = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        firstCancel.future,
      );
      final firstResult = await _loadedImage(
        first.resolve(ImageConfiguration.empty),
      );
      firstResult.dispose();
      firstCancel.complete();
      await Future<void>.delayed(Duration.zero);
      final secondCancel = Completer<void>();
      final second = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        secondCancel.future,
      );
      final result = await _loadedImage(
        second.resolve(ImageConfiguration.empty),
      );
      expect(result.image.width, greaterThan(1));
      expect(client.requests, 1, reason: 'Return must reuse the decoded cache');
      result.dispose();
      secondCancel.complete();
      client.releaseAbort.complete();
      await Future<void>.delayed(Duration.zero);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await provider.dispose();
      client.close();
    });
  });
}
