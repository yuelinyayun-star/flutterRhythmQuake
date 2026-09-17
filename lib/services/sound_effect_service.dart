import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundEffectService {
  static final SoundEffectService _instance = SoundEffectService._internal();
  factory SoundEffectService() => _instance;
  SoundEffectService._internal();

  static const Map<String, String> _srev = {
    'issue': 'sounds/srev/issue.mp3',
    'caution': 'sounds/srev/caution.mp3',
    'warn': 'sounds/srev/warn.mp3',
    'update': 'sounds/srev/update.mp3',
    'final': 'sounds/srev/final.mp3',
    'cancel': 'sounds/srev/cancel.mp3',
    'prompt': 'sounds/srev/prompt.mp3',
    'hypocenter': 'sounds/srev/hypocenter.mp3',
    'detail': 'sounds/srev/detail.mp3',
    'shindo0': 'sounds/srev/shindo0.mp3',
    'shindo1': 'sounds/srev/shindo1.mp3',
    'shindo2': 'sounds/srev/shindo2.mp3',
    'shindo3': 'sounds/srev/shindo3.mp3',
    'shindo4': 'sounds/srev/shindo4.mp3',
    'shindo5': 'sounds/srev/shindo5.mp3',
    'shindo6': 'sounds/srev/shindo6.mp3',
    'shindo7': 'sounds/srev/shindo6.mp3',
    'tsunami1issue': 'sounds/srev/tsunami1issue.mp3',
    'tsunami1update': 'sounds/srev/tsunami1update.mp3',
    'tsunami1switch': 'sounds/srev/tsunami1switch.mp3',
    'tsunami1cancel': 'sounds/srev/tsunami1cancel.mp3',
    'tsunami2issue': 'sounds/srev/tsunami2issue.mp3',
    'tsunami2update': 'sounds/srev/tsunami2update.mp3',
    'tsunami2switch': 'sounds/srev/tsunami2switch.mp3',
    'tsunami2cancel': 'sounds/srev/tsunami2cancel.mp3',
    'tsunami3issue': 'sounds/srev/tsunami3issue.mp3',
    'tsunami3update': 'sounds/srev/tsunami3update.mp3',
    'tsunami3cancel': 'sounds/srev/tsunami3cancel.mp3',
  };

  static const Map<String, String> _general = {
    'countdown': 'sounds/general/countdown.wav',
    'intense': 'sounds/general/intense.wav',
    'ews': 'sounds/general/ews.mp3',
    'typhoonUpdate': 'sounds/general/typhoon_update.wav',
    '0s': 'sounds/general/0s.mp3',
    '1s': 'sounds/general/1s.mp3',
    '2s': 'sounds/general/2s.mp3',
    '3s': 'sounds/general/3s.mp3',
    '4s': 'sounds/general/4s.mp3',
    '5s': 'sounds/general/5s.mp3',
    '6s': 'sounds/general/6s.mp3',
    '7s': 'sounds/general/7s.mp3',
    '8s': 'sounds/general/8s.mp3',
    '9s': 'sounds/general/9s.mp3',
    '10s': 'sounds/general/10s.mp3',
    '20s': 'sounds/general/20s.mp3',
    '30s': 'sounds/general/30s.mp3',
    '40s': 'sounds/general/40s.mp3',
    '50s': 'sounds/general/50s.mp3',
    '60s': 'sounds/general/60s.mp3',
  };

  final Map<String, DateTime> _lastPlayedAt = {};
  final Map<String, Future<_PreparedSound>> _pools = {};

  Future<_PreparedSound> _poolFor(String asset) =>
      _pools.putIfAbsent(asset, () async {
        try {
          return await _PreparedSound.create(asset);
        } catch (_) {
          _pools.remove(asset);
          rethrow;
        }
      });

  /// Prepare common alerts without delaying startup or taking audio focus.
  Future<void> warmUp() async {
    for (final key in [
      'issue',
      'warn',
      'caution',
      'update',
      'final',
      'cancel',
      'hypocenter',
      'detail',
      for (var i = 0; i <= 6; i++) 'shindo$i',
      'countdown',
      'intense',
    ]) {
      if (!enabled) return;
      final asset = _srev[key] ?? _general[key]!;
      try {
        await _poolFor(asset);
      } catch (error) {
        debugPrint('SoundEffect preload failed ($key): $error');
      }
    }
  }

  bool enabled = true;
  double volume = 1.0;

  Future<void> play(String key, {Duration cooldown = Duration.zero}) async {
    if (!enabled) return;
    final asset = _srev[key] ?? _general[key];
    if (asset == null) return;
    if (cooldown > Duration.zero) {
      final last = _lastPlayedAt[key];
      final now = DateTime.now();
      if (last != null && now.difference(last) < cooldown) return;
      _lastPlayedAt[key] = now;
    }

    try {
      final pool = await _poolFor(asset);
      if (!enabled) return;
      await pool.start(volume: volume.clamp(0.0, 1.0));
    } catch (error) {
      debugPrint('SoundEffect playback failed ($key): $error');
    }
  }

  Future<void> playShindo(int shindo) {
    final clamped = shindo.clamp(0, 7);
    return play('shindo$clamped', cooldown: const Duration(seconds: 2));
  }
}

/// Keep one prepared player per asset. Concurrent alerts get temporary players
/// which are disposed after completion, without queuing behind an earlier sound.
class _PreparedSound {
  _PreparedSound(this.asset);
  final String asset;
  AudioPlayer? _idle;

  static Future<_PreparedSound> create(String asset) async {
    final sound = _PreparedSound(asset);
    sound._idle = await sound._createPlayer();
    return sound;
  }

  Future<AudioPlayer> _createPlayer() async {
    final player = AudioPlayer()..positionUpdater = null;
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource(asset));
      return player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  Future<void> start({required double volume}) async {
    final reserved = _idle;
    _idle = null;
    final player = reserved ?? await _createPlayer();
    StreamSubscription<void>? completion;
    var returned = false;
    Future<void> recycle() async {
      if (returned) return;
      returned = true;
      await completion?.cancel();
      try {
        await player.stop();
        if (_idle == null) {
          _idle = player;
          return;
        }
      } catch (error) {
        debugPrint('SoundEffect reset failed: $error');
      }
      await player.dispose();
    }

    completion = player.onPlayerComplete.listen((_) => unawaited(recycle()));
    try {
      await player.setVolume(volume);
      await player.resume();
    } catch (_) {
      returned = true;
      await completion.cancel();
      await player.dispose();
      rethrow;
    }
  }
}
