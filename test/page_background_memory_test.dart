import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/page_background_provider_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disabled saved background stays on disk and loads only when enabled',
    () async {
      final original = File(
        'test/fixtures/cma_radar/ACHN_QREF_20260921_221200.png',
      );
      final bytes = await original.readAsBytes();
      SharedPreferences.setMockInitialValues({
        'page_background_use_custom': false,
        'page_background_custom_path': original.absolute.path,
        'page_background_custom_name': original.uri.pathSegments.last,
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = PageBackgroundProvider();
      addTearDown(provider.dispose);
      await provider.load(prefs);
      expect(provider.hasCustomImage, isTrue);
      expect(provider.customBytes, isNull);
      expect(provider.useCustom, isFalse);
      await provider.enableSavedCustom();
      expect(provider.useCustom, isTrue);
      expect(provider.customBytes, bytes);
      final key = MemoryImage(provider.customBytes!);
      final stream = key.resolve(ImageConfiguration.empty);
      final ready = Completer<void>();
      final listener = ImageStreamListener((image, _) {
        image.dispose();
        ready.complete();
      }, onError: ready.completeError);
      stream.addListener(listener);
      await ready.future;
      stream.removeListener(listener);
      expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
      await provider.restoreDefault();
      expect(provider.customBytes, isNull);
      expect(provider.hasCustomImage, isTrue);
      expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
      expect(
        prefs.getString('page_background_custom_path'),
        original.absolute.path,
      );
      await provider.enableSavedCustom();
      expect(provider.customBytes, bytes);
      expect(await original.readAsBytes(), bytes);
      await provider.restoreDefault();
    },
  );
}
