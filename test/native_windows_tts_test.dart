import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/native_windows_tts.dart';

void main() {
  test(
    'actual Rust voice probe is asynchronous and releases every result',
    () async {
      expect(NativeWindowsTts.outputs, 0);
      final timerTick = Completer<void>();
      final pending = NativeWindowsTts.probe();
      Timer.run(timerTick.complete);
      await timerTick.future;
      final result = await pending;
      // This host's original System.Speech response contains two usable voices.
      expect(result['state'], 'available');
      expect(
        (result['voices'] as List).where((v) => v['enabled'] == true),
        isNotEmpty,
      );
      expect(NativeWindowsTts.outputs, 0);
      for (var i = 0; i < 2; i++) {
        expect((await NativeWindowsTts.probe())['state'], 'available');
        expect(NativeWindowsTts.outputs, 0);
      }
    },
    skip: !Platform.isWindows || !NativeWindowsTts.supported,
  );
}
