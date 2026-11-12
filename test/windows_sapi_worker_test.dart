import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/native_windows_tts.dart';
import 'package:flutterrhythmquake/services/windows_sapi_worker.dart';

void main() {
  test(
    'SAPI stays alive between synthesis requests and recovers after abort',
    () async {
      final worker = WindowsSapiWorker();
      final dir = await Directory.systemTemp.createTemp('rq_sapi_test_');
      addTearDown(() async {
        worker.close();
        await dir.delete(recursive: true);
      });
      final elapsed = <int>[];
      for (var i = 0; i < 3; i++) {
        final path = '${dir.path}\\sample_$i.wav';
        final watch = Stopwatch()..start();
        await worker.synthesize(
          text: '地震预警测试，震级五点零',
          file: path,
          rate: 1,
          volume: 50,
          voice: '',
        );
        watch.stop();
        elapsed.add(watch.elapsedMilliseconds);
        final file = File(path);
        expect(await file.exists(), true);
        expect(await file.length(), greaterThan(44));
      }
      // ignore: avoid_print
      print('SAPI_WARM_TIMES_MS=$elapsed');
      expect(elapsed[1], lessThan(elapsed[0]));
      worker.abort();
      final next = '${dir.path}\\recovered.wav';
      await worker.synthesize(
        text: '重启以后恢复合成',
        file: next,
        rate: 1,
        volume: 50,
        voice: '',
      );
      expect(await File(next).length(), greaterThan(44));
    },
    skip: !Platform.isWindows || !NativeWindowsTts.supported,
  );
}
