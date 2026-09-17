import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'preloaded alerts reuse players, preserve overlap and cooldown',
    () async {
      final messenger = binding.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      final playing = <String>{};
      final prepared = <String, String>{};
      var failNextSource = false;
      Completer<void>? sourceReached;
      Completer<void>? sourceGate;
      Future<void> emit(String id, String event, [Object? value]) async {
        await messenger.handlePlatformMessage(
          'xyz.luan/audioplayers/events/$id',
          const StandardMethodCodec().encodeSuccessEnvelope({
            'event': event,
            'value': value,
          }),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global/events'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (call) async {
          calls.add(call);
          final args = call.arguments as Map;
          final id = args['playerId'] as String;
          switch (call.method) {
            case 'create':
              messenger.setMockMethodCallHandler(
                MethodChannel('xyz.luan/audioplayers/events/$id'),
                (_) async => null,
              );
            case 'setSourceUrl':
              if (failNextSource) {
                failNextSource = false;
                await messenger.handlePlatformMessage(
                  'xyz.luan/audioplayers/events/$id',
                  const StandardMethodCodec().encodeErrorEnvelope(
                    code: 'test-prepare-failure',
                  ),
                  (_) {},
                );
                throw PlatformException(code: 'test-prepare-failure');
              }
              sourceReached?.complete();
              await sourceGate?.future;
              prepared[id] = args['url'] as String;
              await emit(id, 'audio.onPrepared', true);
            case 'resume':
              playing.add(id);
            case 'stop':
            case 'dispose':
              playing.remove(id);
            case 'getCurrentPosition':
            case 'getDuration':
              return 0;
          }
          return null;
        },
      );

      final sounds = SoundEffectService();
      await sounds.warmUp();
      expect(calls.where((c) => c.method == 'create'), hasLength(17));
      expect(playing, isEmpty, reason: 'Preloading must never play a sound.');
      expect(calls.where((c) => c.method == 'resume'), isEmpty);
      calls.clear();

      await sounds.play('issue');
      expect(playing, hasLength(1));
      final firstPlayer = playing.single;
      expect(calls.where((c) => c.method == 'setSourceUrl'), isEmpty);
      expect(calls.where((c) => c.method == 'create'), isEmpty);
      await emit(firstPlayer, 'audio.onComplete');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sounds.play('issue');
      expect(playing.single, firstPlayer);
      expect(calls.where((c) => c.method == 'create'), isEmpty);

      await sounds.play('issue');
      await sounds.play('caution');
      expect(
        playing,
        hasLength(3),
        reason: 'Independent alerts must not queue.',
      );
      for (final id in playing.toList()) {
        await emit(id, 'audio.onComplete');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        calls.where((c) => c.method == 'dispose'),
        hasLength(1),
        reason: 'Overflow players must be disposed rather than retained.',
      );
      calls.clear();
      await sounds.playShindo(2);
      await sounds.playShindo(2);
      expect(calls.where((c) => c.method == 'resume'), hasLength(1));
      expect(prepared[playing.single], endsWith('shindo2.mp3'));
      for (final id in playing.toList()) {
        await emit(id, 'audio.onComplete');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sounds.enabled = false;
      calls.clear();
      await sounds.play('warn');
      expect(calls, isEmpty);
      sounds.enabled = true;
      calls.clear();
      failNextSource = true;
      await sounds.play('prompt');
      expect(calls.where((c) => c.method == 'resume'), isEmpty);
      expect(calls.where((c) => c.method == 'dispose'), hasLength(1));
      await sounds.play('prompt');
      expect(
        calls.where((c) => c.method == 'resume'),
        hasLength(1),
        reason: 'Failed preparation must be retryable.',
      );
      await emit(playing.single, 'audio.onComplete');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      calls.clear();
      sourceReached = Completer<void>();
      sourceGate = Completer<void>();
      final pending = sounds.play('ews');
      await sourceReached.future;
      sounds.enabled = false;
      sourceGate.complete();
      await pending;
      expect(
        calls.where((c) => c.method == 'resume'),
        isEmpty,
        reason: 'Disabling during preparation must prevent delayed playback.',
      );
      sounds.enabled = true;
      for (final uri in AudioCache.instance.loadedFiles.values) {
        await File.fromUri(uri).delete();
      }
      AudioCache.instance.loadedFiles.clear();
    },
  );
}
