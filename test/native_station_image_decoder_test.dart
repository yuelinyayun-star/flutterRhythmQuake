import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/native_station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

void main() {
  final native = NativeStationImageDecoder.supported;
  test('Rust samples retain exact original GIF and PNG channel values', () {
    final files = [
      ...Directory(
        'test/fixtures/nied_recovery',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.gif')),
      ...Directory(
        'test/fixtures/station_image_decoder',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.png')),
    ];
    expect(files.length, 20);
    for (final file in files) {
      final bytes = file.readAsBytesSync(), hash = sha256.convert(bytes);
      final reference = image.decodeImage(bytes)!;
      final coordinates = <int>[
        for (var y = 0; y < reference.height; y++)
          for (var x = 0; x < reference.width; x++) ...[x, y],
        -1,
        0,
        reference.width,
        0,
        0,
        reference.height,
        1 << 32,
        0,
        -(1 << 32),
        0,
      ];
      final decoder = NativeStationImageDecoder(coordinates);
      try {
        final frame = decoder.decode(bytes);
        expect(
          [frame.width, frame.height],
          [reference.width, reference.height],
        );
        for (var y = 0; y < reference.height; y++) {
          for (var x = 0; x < reference.width; x++) {
            final pixel = reference.getPixel(x, y);
            final expected =
                0x100000000 |
                (pixel.a.toInt() << 24) |
                (pixel.r.toInt() << 16) |
                (pixel.g.toInt() << 8) |
                pixel.b.toInt();
            if (frame.pixels[y * frame.width + x] != expected) {
              fail(
                '${file.path} ($x,$y): ${frame.pixels[y * frame.width + x].toRadixString(16)} != ${expected.toRadixString(16)}',
              );
            }
          }
        }
        expect(frame.pixels.skip(reference.width * reference.height), [
          0,
          0,
          0,
          0,
          0,
        ]);
      } finally {
        decoder.dispose();
      }
      expect(sha256.convert(file.readAsBytesSync()), hash);
    }
  }, skip: !native);

  test(
    'original S-net BMP recording is decoded without header repairs',
    () {
      final file = File(
        'tmp/equake_replays/20261003214550_wakayama_eq/snet.dat',
      );
      if (!file.existsSync()) {
        return; // Additional local raw capture, not a CI fixture.
      }
      final bytes = file.readAsBytesSync(), hash = sha256.convert(bytes);
      final headers = RegExp(
        r'[0-9]{14}\*#!\)#\(#',
      ).allMatches(latin1.decode(bytes)).toList();
      expect(headers.length, 3);
      for (var i = 0; i < headers.length; i++) {
        final end = i + 1 < headers.length
            ? headers[i + 1].start
            : bytes.length;
        final bmp = Uint8List.sublistView(bytes, headers[i].end, end - 6);
        final reference = image.decodeBmp(bmp)!;
        final decoder = NativeStationImageDecoder([
          for (var y = 0; y < reference.height; y++)
            for (var x = 0; x < reference.width; x++) ...[x, y],
        ]);
        try {
          final result = decoder.decode(bmp);
          for (var y = 0; y < reference.height; y++) {
            for (var x = 0; x < reference.width; x++) {
              final p = reference.getPixel(x, y),
                  actual = result.pixels[y * reference.width + x];
              final expected =
                  0x100000000 |
                  (p.a.toInt() << 24) |
                  (p.r.toInt() << 16) |
                  (p.g.toInt() << 8) |
                  p.b.toInt();
              if (actual != expected) {
                fail('Original BMP $i ($x,$y) channel mismatch');
              }
            }
          }
        } finally {
          decoder.dispose();
        }
      }
      expect(sha256.convert(file.readAsBytesSync()), hash);
    },
    skip: !native,
  );

  test(
    'worker uses Rust and keeps original 1634-station values and order',
    () async {
      final coords = [
        for (final station in NiedStationDb.stations)
          if (NiedScanPositions.positions[station['code']] case final p?)
            NiedScanConfig(pixelX: p[0], pixelY: p[1]),
      ];
      expect(coords.length, 1634);
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      final files = directory.existsSync()
          ? directory
                .listSync()
                .whereType<File>()
                .where(
                  (f) =>
                      f.path.endsWith('.lmoni.jma_s.gif') &&
                      f.uri.pathSegments.last.compareTo(
                            '20260610180120.lmoni.jma_s.gif',
                          ) >=
                          0 &&
                      f.uri.pathSegments.last.compareTo(
                            '20260610180210.lmoni.jma_s.gif',
                          ) <=
                          0,
                )
                .toList()
          : Directory('test/fixtures/nied_recovery')
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.gif'))
                .toList();
      if (directory.existsSync()) expect(files.length, 51);
      addTearDown(NiedBackgroundWorker.instance.stop);
      for (final file in files) {
        final bytes = file.readAsBytesSync(), original = sha256.convert(bytes);
        final reference = image.decodeImage(bytes)!;
        final frame = await NiedBackgroundWorker.instance.scanFrame(
          surfaceBytes: bytes,
          configs: coords,
          configSignature: 'native-original-1634',
        );
        expect(frame, isNotNull, reason: file.path);
        expect(frame!.backend, 'rust-abi-1');
        for (var i = 0; i < coords.length; i++) {
          final p = reference.getPixel(coords[i].pixelX, coords[i].pixelY);
          final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
          final expected = ShindoColorUtil.rgbaToShindo(r, g, b) == null
              ? null
              : ShindoColorUtil.rgbaToPosition(r, g, b);
          expect(
            frame.samples[i].surfacePosition,
            expected,
            reason: '${file.path} station $i',
          );
        }
        expect(sha256.convert(file.readAsBytesSync()), original);
      }
    },
    skip: !native,
  );

  test('native worker restarts and replaces its station buffers', () async {
    final worker = NiedBackgroundWorker.instance;
    addTearDown(worker.stop);
    final bytes = Directory('test/fixtures/nied_recovery')
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.gif'))
        .readAsBytesSync();
    const config = NiedScanConfig(pixelX: 10, pixelY: 20);
    for (var restart = 0; restart < 3; restart++) {
      final first = await worker.scanFrame(
        surfaceBytes: bytes,
        configs: const [config],
        configSignature: 'one',
      );
      expect(first!.backend, 'rust-abi-1');
      final second = await worker.scanFrame(
        surfaceBytes: bytes,
        configs: const [config, config],
        configSignature: 'two',
      );
      expect(second!.samples.length, 2);
      expect(
        second.samples[0].surfacePosition,
        first.samples[0].surfacePosition,
      );
      expect(
        second.samples[1].surfacePosition,
        first.samples[0].surfacePosition,
      );
      final stats = await worker.imageDecoderDiagnostics();
      expect(stats['rustCurrentBytes'], 0);
      worker.stop();
      expect(await worker.imageDecoderDiagnostics(), {
        'backend': 'not-started',
      });
    }
  }, skip: !native);

  test(
    'owned results survive buffer reuse; bad frames and disposal release resources',
    () {
      final files = Directory('test/fixtures/nied_recovery')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gif'))
          .toList();
      final decoder = NativeStationImageDecoder([10, 20]);
      final a = decoder.decode(files.first.readAsBytesSync());
      final saved = Uint64List.fromList(a.pixels);
      final before = NativeStationImageDecoder.memoryStats['rustCurrentBytes'];
      for (var i = 0; i < 100; i++) {
        decoder.decode(files[i % files.length].readAsBytesSync());
      }
      expect(a.pixels, saved);
      expect(NativeStationImageDecoder.memoryStats['rustCurrentBytes'], before);
      expect(() => decoder.decode(Uint8List(0)), throwsFormatException);
      expect(
        () => decoder.decode(Uint8List(8 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
      expect(
        () => decoder.decode(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      decoder.dispose();
      decoder.dispose();
      expect(decoder.bufferCapacityBytes, 0);
      expect(
        () => decoder.decode(files.first.readAsBytesSync()),
        throwsStateError,
      );
    },
    skip: !native,
  );
}
