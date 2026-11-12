import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart' hide Size;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/event_render_clipboard.dart';
import 'package:flutterrhythmquake/widgets/ui/event_render_export.dart';

final _user = DynamicLibrary.open('user32.dll');
final _kernel = DynamicLibrary.open('kernel32.dll');
final _open = _user
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'OpenClipboard',
    );
final _close = _user.lookupFunction<Int32 Function(), int Function()>(
  'CloseClipboard',
);
final _get = _user
    .lookupFunction<
      Pointer<Void> Function(Uint32),
      Pointer<Void> Function(int)
    >('GetClipboardData');
final _register = _user
    .lookupFunction<
      Uint32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)
    >('RegisterClipboardFormatW');
final _lock = _kernel
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)
    >('GlobalLock');
final _unlock = _kernel
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'GlobalUnlock',
    );
final _size = _kernel
    .lookupFunction<
      UintPtr Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('GlobalSize');

Uint8List clipboardBytes(int format) {
  expect(_open(nullptr), isNonZero);
  try {
    final handle = _get(format);
    expect(handle, isNot(nullptr));
    final pointer = _lock(handle);
    expect(pointer, isNot(nullptr));
    try {
      return Uint8List.fromList(pointer.asTypedList(_size(handle)));
    } finally {
      _unlock(handle);
    }
  } finally {
    _close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final height in [900, 1200]) {
    testWidgets('image clipboard round trip keeps full 1600x$height canvas', (
      tester,
    ) async {
      tester.view.physicalSize = ui.Size(1600, height.toDouble());
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const ValueKey('poster'),
            child: const ColoredBox(
              color: Color(0xff102030),
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 160,
                  child: ColoredBox(color: Color(0xffcc8844)),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('poster')),
      );
      final expected = await tester.runAsync(
        () => captureEventRenderPng(boundary),
      );
      await tester.runAsync(() => copyEventRenderPng(boundary));
      final format = using(
        (arena) => _register('PNG'.toNativeUtf16(allocator: arena)),
      );
      final png = clipboardBytes(format);
      expect(png, orderedEquals(expected!));
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1600);
        expect(frame.image.height, height);
        frame.image.dispose();
        codec.dispose();
      });
      final dib = ByteData.sublistView(clipboardBytes(17));
      expect(dib.getUint32(0, Endian.little), 124);
      expect(dib.getInt32(4, Endian.little), 1600);
      expect(dib.getInt32(8, Endian.little), -height);
      // A malformed image must not erase the previously copied poster.
      await tester.runAsync(() async {
        await expectLater(
          EventRenderClipboard.writePng(Uint8List.fromList([1, 2, 3])),
          throwsStateError,
        );
      });
      expect(clipboardBytes(format), orderedEquals(png));
      expect(tester.takeException(), isNull);
    });
  }
}
