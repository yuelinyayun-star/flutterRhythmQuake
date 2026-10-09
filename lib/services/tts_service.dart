import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsVoiceOption {
  final String id;
  final String label;
  final String name;
  final String? locale;

  const TtsVoiceOption({
    required this.id,
    required this.label,
    required this.name,
    this.locale,
  });

  static const systemDefault = TtsVoiceOption(
    id: '',
    label: '\u7cfb\u7edf\u9ed8\u8ba4',
    name: '',
  );
}

enum EewSpeechKind { first, update, caution, warn, finalReport, cancel }

class _TtsJob {
  String text;
  final Duration delay;
  final bool interrupt;
  final String? eewEventKey;
  final String? eventKey;
  final bool Function()? isCurrent;
  final EewSpeechKind? eewKind;
  final DateTime? expiresAt;
  bool obsolete = false;
  bool playbackStarted = false;

  _TtsJob({
    required this.text,
    this.delay = Duration.zero,
    this.interrupt = false,
    this.eewEventKey,
    this.eventKey,
    this.isCurrent,
    this.eewKind,
    this.expiresAt,
  });

  bool get isCriticalEew => eewKind != null && eewKind != EewSpeechKind.update;

  int get priority => switch (eewKind) {
    EewSpeechKind.cancel => 0,
    EewSpeechKind.warn => 1,
    EewSpeechKind.first ||
    EewSpeechKind.caution ||
    EewSpeechKind.finalReport => 2,
    EewSpeechKind.update => 3,
    null => 4,
  };
}

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  static const enabledKey = 'tts_enabled';
  static const eventEnabledKey = 'tts_event_enabled';
  static const countdownEnabledKey = 'tts_countdown_enabled';
  static const updateEnabledKey = 'tts_update_enabled';
  static const voiceIdKey = 'tts_voice_id';
  static const speechRateKey = 'tts_speech_rate';
  static const pitchKey = 'tts_pitch';
  static const volumeKey = 'tts_volume';
  static const gptSovitsEnabledKey = 'tts_gpt_sovits_enabled';
  static const gptSovitsUrlKey = 'tts_gpt_sovits_url';
  static const gptSovitsRefAudioKey = 'tts_gpt_sovits_ref_audio';
  static const gptSovitsPromptTextKey = 'tts_gpt_sovits_prompt_text';
  static const _dedupeEntryTtl = Duration(hours: 1);
  static const _dedupeEntryLimit = 256;

  final FlutterTts _flutterTts = FlutterTts();
  final Queue<_TtsJob> _queue = Queue<_TtsJob>();
  final Map<String, DateTime> _lastSpokenAt = {};

  bool _initialized = false;
  bool _engineReady = false;
  bool _processing = false;
  int _generation = 0;
  int _gptSovitsGeneration = 0;
  int _windowsGeneration = 0;
  _TtsJob? _activeJob;
  Completer<void>? _activeDelayCanceled;
  Completer<void>? _gptSovitsPlaybackCanceled;
  Completer<void>? _windowsPlaybackCanceled;
  Future<void>? _playbackStopFuture;
  Process? _windowsSynthesisProcess;
  AudioPlayer? _gptSovitsPlayer;
  AudioPlayer? _windowsTtsPlayer;
  @visibleForTesting
  Future<void> Function(String text)? windowsSpeechOverrideForTest;
  List<TtsVoiceOption> _voices = const [TtsVoiceOption.systemDefault];

  bool enabled = false;
  bool eventEnabled = false;
  bool countdownEnabled = false;
  bool updateEnabled = false;
  String voiceId = '';
  double speechRate = 0.58;
  double pitch = 1.0;
  double volume = 1.0;
  bool gptSovitsEnabled = false;
  String gptSovitsUrl = 'http://localhost:9880';
  String gptSovitsRefAudioPath = '';
  String gptSovitsPromptText = '';
  String _lastGptSovitsEndpoint = 'tts';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(enabledKey) ?? false;
    eventEnabled = prefs.getBool(eventEnabledKey) ?? false;
    countdownEnabled = prefs.getBool(countdownEnabledKey) ?? false;
    updateEnabled = prefs.getBool(updateEnabledKey) ?? false;
    voiceId = prefs.getString(voiceIdKey) ?? '';
    speechRate = prefs.getDouble(speechRateKey) ?? 0.58;
    pitch = prefs.getDouble(pitchKey) ?? 1.0;
    volume = prefs.getDouble(volumeKey) ?? 1.0;
    gptSovitsEnabled = prefs.getBool(gptSovitsEnabledKey) ?? false;
    gptSovitsUrl = prefs.getString(gptSovitsUrlKey) ?? 'http://localhost:9880';
    gptSovitsRefAudioPath = prefs.getString(gptSovitsRefAudioKey) ?? '';
    gptSovitsPromptText = prefs.getString(gptSovitsPromptTextKey) ?? '';
  }

  Future<List<TtsVoiceOption>> loadVoices() async {
    await _ensureInitialized();
    if (!kIsWeb && Platform.isWindows) {
      return _loadWindowsVoices();
    }
    try {
      await _ensureEngineReady();
      if (!_engineReady) return _voices;
      final raw = await _flutterTts.getVoices;
      final parsed = <TtsVoiceOption>[TtsVoiceOption.systemDefault];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final name = item['name']?.toString() ?? '';
          final locale =
              item['locale']?.toString() ?? item['language']?.toString();
          if (name.isEmpty) continue;
          final id = _voiceId(name, locale);
          final label = locale == null || locale.isEmpty
              ? name
              : '$name ($locale)';
          if (parsed.every((voice) => voice.id != id)) {
            parsed.add(
              TtsVoiceOption(id: id, label: label, name: name, locale: locale),
            );
          }
        }
      }
      parsed.sort(_sortVoice);
      _voices = parsed;
    } catch (e) {
      debugPrint('[TTS] load voices error: $e');
      _voices = const [TtsVoiceOption.systemDefault];
    }
    return _voices;
  }

  List<TtsVoiceOption> get voices => List.unmodifiable(_voices);

  Future<void> configure({
    bool? enabled,
    bool? eventEnabled,
    bool? countdownEnabled,
    bool? updateEnabled,
    String? voiceId,
    double? speechRate,
    double? pitch,
    double? volume,
    bool? gptSovitsEnabled,
    String? gptSovitsUrl,
    String? gptSovitsRefAudioPath,
    String? gptSovitsPromptText,
    bool persist = true,
  }) async {
    await _ensureInitialized();
    if (enabled != null) this.enabled = enabled;
    if (eventEnabled != null) this.eventEnabled = eventEnabled;
    if (countdownEnabled != null) this.countdownEnabled = countdownEnabled;
    if (updateEnabled != null) this.updateEnabled = updateEnabled;
    if (voiceId != null) this.voiceId = voiceId;
    if (speechRate != null) this.speechRate = speechRate;
    if (pitch != null) this.pitch = pitch;
    if (volume != null) this.volume = volume;
    if (gptSovitsEnabled != null) this.gptSovitsEnabled = gptSovitsEnabled;
    if (gptSovitsUrl != null) this.gptSovitsUrl = gptSovitsUrl;
    if (gptSovitsRefAudioPath != null) {
      this.gptSovitsRefAudioPath = gptSovitsRefAudioPath;
    }
    if (gptSovitsPromptText != null) {
      this.gptSovitsPromptText = gptSovitsPromptText;
    }

    if (!this.gptSovitsEnabled &&
        _engineReady &&
        (kIsWeb || !Platform.isWindows)) {
      await _applyEngineConfig();
    }

    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, this.enabled);
    await prefs.setBool(eventEnabledKey, this.eventEnabled);
    await prefs.setBool(countdownEnabledKey, this.countdownEnabled);
    await prefs.setBool(updateEnabledKey, this.updateEnabled);
    await prefs.setString(voiceIdKey, this.voiceId);
    await prefs.setDouble(speechRateKey, this.speechRate);
    await prefs.setDouble(pitchKey, this.pitch);
    await prefs.setDouble(volumeKey, this.volume);
    await prefs.setBool(gptSovitsEnabledKey, this.gptSovitsEnabled);
    await prefs.setString(gptSovitsUrlKey, this.gptSovitsUrl);
    await prefs.setString(gptSovitsRefAudioKey, this.gptSovitsRefAudioPath);
    await prefs.setString(gptSovitsPromptTextKey, this.gptSovitsPromptText);
  }

  Future<bool> testGptSovitsConnection({
    String? url,
    String? refAudioPath,
    String? promptText,
  }) async {
    await _ensureInitialized();
    final targetUrl = (url ?? gptSovitsUrl).trim();
    final targetRefAudio = (refAudioPath ?? gptSovitsRefAudioPath).trim();
    final targetPromptText = (promptText ?? gptSovitsPromptText).trim();
    if (targetRefAudio.isEmpty || targetPromptText.isEmpty) return false;

    try {
      final resp = await _requestGptSovitsAudio(
        url: targetUrl,
        text: 'test',
        refAudioPath: targetRefAudio,
        promptText: targetPromptText,
        timeout: const Duration(seconds: 8),
      );
      if (resp == null) {
        return false;
      }
      return resp.bodyBytes.isNotEmpty && _looksLikeAudio(resp);
    } catch (e) {
      debugPrint('[GPT-SoVITS] test error: $e');
      return false;
    }
  }

  Future<void> speakEvent(
    String text, {
    required String dedupeKey,
    String? eventKey,
    bool Function()? isCurrent,
    bool isUpdate = false,
    Duration delay = const Duration(milliseconds: 1150),
  }) {
    if (!eventEnabled) return Future.value();
    if (isUpdate && !updateEnabled) return Future.value();
    return speak(
      text,
      dedupeKey: 'event:$dedupeKey',
      eventKey: eventKey,
      isCurrent: isCurrent,
      dedupeWindow: const Duration(seconds: 4),
      delay: delay,
      interrupt: false,
    );
  }

  Future<void> speakEew(
    String text, {
    required String eventKey,
    required String dedupeKey,
    required EewSpeechKind kind,
    Duration delay = const Duration(milliseconds: 1250),
  }) {
    if (!eventEnabled) return Future.value();
    if (kind == EewSpeechKind.update &&
        !updateEnabled &&
        !_queue.any(
          (job) => job.eewEventKey == eventKey && job.isCriticalEew,
        ) &&
        !(_activeJob?.eewEventKey == eventKey &&
            _activeJob?.isCriticalEew == true &&
            _activeJob?.playbackStarted == false)) {
      return Future.value();
    }
    return speak(
      text,
      dedupeKey: 'event:$dedupeKey',
      dedupeWindow: const Duration(seconds: 4),
      delay: delay,
      eewEventKey: eventKey,
      eewKind: kind,
    );
  }

  Future<void> speakCountdown(String eventId, int seconds) {
    if (!countdownEnabled) return Future.value();
    if (_hasCriticalEewSpeech) return Future.value();
    return speak(
      '$seconds',
      dedupeKey: 'countdown:$eventId:$seconds',
      dedupeWindow: const Duration(seconds: 30),
      interrupt: true,
      preserveCriticalEew: true,
    );
  }

  Future<void> speakArrival(String eventId) {
    if (!countdownEnabled) return Future.value();
    if (_hasCriticalEewSpeech) return Future.value();
    return speak(
      '\u5730\u9707\u6ce2\u5230\u8fbe\u3002',
      dedupeKey: 'arrival:$eventId',
      dedupeWindow: const Duration(minutes: 3),
      interrupt: true,
      preserveCriticalEew: true,
    );
  }

  Future<void> speak(
    String text, {
    String? dedupeKey,
    Duration dedupeWindow = Duration.zero,
    Duration delay = Duration.zero,
    bool interrupt = false,
    String? eewEventKey,
    String? eventKey,
    bool Function()? isCurrent,
    EewSpeechKind? eewKind,
    bool preserveCriticalEew = false,
  }) async {
    await _ensureInitialized();
    final cleaned = _cleanText(text);
    if (!enabled || cleaned.isEmpty || isCurrent?.call() == false) return;

    if (dedupeKey != null && dedupeWindow > Duration.zero) {
      final now = DateTime.now();
      _pruneDedupeKeys(now);
      final last = _lastSpokenAt[dedupeKey];
      if (last != null && now.difference(last) < dedupeWindow) return;
      _lastSpokenAt[dedupeKey] = now;
    }

    if (interrupt) {
      if (preserveCriticalEew) {
        _queue.removeWhere((job) => !job.isCriticalEew);
      } else {
        _queue.clear();
      }
      _generation++;
      _activeJob?.obsolete = true;
      _cancelActiveDelay();
    }

    final job = _TtsJob(
      text: cleaned,
      delay: delay,
      interrupt: interrupt,
      eewEventKey: eewEventKey,
      eventKey: eventKey,
      isCurrent: isCurrent,
      eewKind: eewKind,
      expiresAt: eewKind == null
          ? null
          : DateTime.now().add(
              eewKind == EewSpeechKind.update
                  ? const Duration(seconds: 12)
                  : const Duration(seconds: 30),
            ),
    );
    if (eewKind != null && eewEventKey != null) {
      _queueEewJob(job);
    } else if (interrupt) {
      _queue.addFirst(job);
    } else {
      _queue.add(job);
    }
    if (interrupt ||
        (eewKind != null &&
            eewKind != EewSpeechKind.update &&
            _activeJob?.obsolete == true)) {
      await _stopActivePlayback();
    }
    unawaited(_processQueue());
  }

  void _pruneDedupeKeys(DateTime now) {
    _lastSpokenAt.removeWhere(
      (_, timestamp) => now.difference(timestamp) >= _dedupeEntryTtl,
    );
    if (_lastSpokenAt.length <= _dedupeEntryLimit) return;
    final oldest = _lastSpokenAt.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final removeCount = _lastSpokenAt.length - _dedupeEntryLimit;
    for (var i = 0; i < removeCount; i++) {
      _lastSpokenAt.remove(oldest[i].key);
    }
  }

  @visibleForTesting
  int get dedupeCacheSize => _lastSpokenAt.length;

  bool get _hasCriticalEewSpeech =>
      (_activeJob?.isCriticalEew == true && _activeJob?.obsolete != true) ||
      _queue.any((job) => job.isCriticalEew);

  void _queueEewJob(_TtsJob job) {
    final key = job.eewEventKey;
    _queue.removeWhere(
      (pending) =>
          pending.eewEventKey == key &&
          (job.isCriticalEew || pending.eewKind == EewSpeechKind.update),
    );
    if (!job.isCriticalEew) {
      for (final pending in _queue) {
        if (pending.eewEventKey == key && pending.isCriticalEew) {
          pending.text = job.text;
          return;
        }
      }
      if (_activeJob?.eewEventKey == key &&
          _activeJob?.isCriticalEew == true &&
          _activeJob?.playbackStarted == false) {
        _activeJob!.text = job.text;
        return;
      }
      if (_activeJob?.eewEventKey == key &&
          _activeJob?.eewKind == EewSpeechKind.update &&
          _activeJob?.playbackStarted == false) {
        _activeJob!.obsolete = true;
        _cancelActiveDelay();
      }
    } else if (_activeJob?.eewEventKey == key) {
      _activeJob!.obsolete = true;
      _cancelActiveDelay();
    } else if (_activeJob != null && !_activeJob!.isCriticalEew) {
      _activeJob!.obsolete = true;
      _cancelActiveDelay();
    }

    final pending = _queue.toList();
    final insertAt = pending.indexWhere(
      (other) => other.priority > job.priority,
    );
    if (insertAt < 0) {
      _queue.add(job);
    } else {
      pending.insert(insertAt, job);
      _queue
        ..clear()
        ..addAll(pending);
    }
  }

  void discardEew(String eventKey) {
    _queue.removeWhere((job) => job.eewEventKey == eventKey);
    if (_activeJob?.eewEventKey != eventKey) return;
    _activeJob!.obsolete = true;
    _cancelActiveDelay();
    unawaited(_stopActivePlayback());
  }

  void discardEvent(String eventKey) {
    _queue.removeWhere((job) => job.eventKey == eventKey);
    if (_activeJob?.eventKey != eventKey) return;
    _activeJob!.obsolete = true;
    _cancelActiveDelay();
    unawaited(_stopActivePlayback());
  }

  void _cancelActiveDelay() {
    if (_activeDelayCanceled?.isCompleted == false) {
      _activeDelayCanceled!.complete();
    }
  }

  Future<void> _stopActivePlayback() async {
    if (_activeJob?.playbackStarted != true) return;
    final pendingStop = _playbackStopFuture;
    if (pendingStop != null) {
      await pendingStop;
      return;
    }
    final stop = _stopActivePlaybackBackend();
    _playbackStopFuture = stop;
    try {
      await stop;
    } finally {
      if (identical(_playbackStopFuture, stop)) _playbackStopFuture = null;
    }
  }

  Future<void> _stopActivePlaybackBackend() async {
    if (gptSovitsEnabled) {
      _gptSovitsGeneration++;
      if (_gptSovitsPlaybackCanceled?.isCompleted == false) {
        _gptSovitsPlaybackCanceled!.complete();
      }
      await _gptSovitsPlayer?.stop();
    } else if (!kIsWeb && Platform.isWindows) {
      _windowsGeneration++;
      _windowsSynthesisProcess?.kill();
      if (_windowsPlaybackCanceled?.isCompleted == false) {
        _windowsPlaybackCanceled!.complete();
      }
      await _windowsTtsPlayer?.stop();
    } else if (_engineReady) {
      await _safeTtsCall(() => _flutterTts.stop());
    }
  }

  Future<void> stop() async {
    _queue.clear();
    _generation++;
    _activeJob?.obsolete = true;
    _cancelActiveDelay();
    _gptSovitsGeneration++;
    _windowsGeneration++;
    _windowsSynthesisProcess?.kill();
    if (_gptSovitsPlaybackCanceled?.isCompleted == false) {
      _gptSovitsPlaybackCanceled!.complete();
    }
    if (_windowsPlaybackCanceled?.isCompleted == false) {
      _windowsPlaybackCanceled!.complete();
    }
    _windowsPlaybackCanceled = null;
    if (_engineReady) {
      await _safeTtsCall(() => _flutterTts.stop());
    }
    await _gptSovitsPlayer?.stop();
    await _windowsTtsPlayer?.stop();
  }

  Future<List<TtsVoiceOption>> _loadWindowsVoices() async {
    const script = r'''
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$items = @()
foreach ($v in $s.GetInstalledVoices()) {
  $items += [PSCustomObject]@{
    name = $v.VoiceInfo.Name
    culture = $v.VoiceInfo.Culture.Name
  }
}
$s.Dispose()
$items | ConvertTo-Json -Compress
''';
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ], runInShell: false).timeout(const Duration(seconds: 6));
      if (result.exitCode != 0) {
        debugPrint('[TTS] Windows voice list failed: ${result.stderr}');
        return _voices;
      }
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return _voices;
      final decoded = json.decode(output);
      final list = decoded is List ? decoded : [decoded];
      final parsed = <TtsVoiceOption>[TtsVoiceOption.systemDefault];
      for (final item in list) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        final locale = item['culture']?.toString();
        if (name.isEmpty) continue;
        parsed.add(
          TtsVoiceOption(
            id: _voiceId(name, locale),
            label: locale == null || locale.isEmpty ? name : '$name ($locale)',
            name: name,
            locale: locale,
          ),
        );
      }
      parsed.sort(_sortVoice);
      _voices = parsed;
    } catch (e) {
      debugPrint('[TTS] Windows voice list error: $e');
      _voices = const [TtsVoiceOption.systemDefault];
    }
    return _voices;
  }

  Future<void> _speakViaWindowsSapi(String text) async {
    final generation = _windowsGeneration;
    if (generation != _windowsGeneration || !enabled) return;

    const script = r'''
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.Rate = [int]$env:RQ_TTS_RATE
$s.Volume = [int]$env:RQ_TTS_VOLUME
if (![string]::IsNullOrWhiteSpace($env:RQ_TTS_VOICE)) {
  try { $s.SelectVoice($env:RQ_TTS_VOICE) } catch {}
}
$s.SetOutputToWaveFile($env:RQ_TTS_FILE)
$s.Speak($env:RQ_TTS_TEXT)
$s.Dispose()
''';
    File? file;
    Process? process;
    StreamSubscription<void>? completionSubscription;
    Completer<void>? playbackCanceled;
    try {
      final dir = await getTemporaryDirectory();
      if (generation != _windowsGeneration) return;
      file = File(
        '${dir.path}/rq_windows_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      final env = Map<String, String>.from(Platform.environment);
      env['RQ_TTS_TEXT'] = text;
      env['RQ_TTS_FILE'] = file.path;
      env['RQ_TTS_RATE'] = _windowsRate().toString();
      env['RQ_TTS_VOLUME'] = (volume.clamp(0.0, 1.0) * 100).round().toString();
      env['RQ_TTS_VOICE'] = _selectedVoice()?.name ?? '';

      process = await Process.start(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        environment: env,
        runInShell: false,
      );
      _windowsSynthesisProcess = process;
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      if (generation != _windowsGeneration) process.kill();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          process!.kill();
          return -1;
        },
      );
      if (exitCode != 0 && generation == _windowsGeneration) {
        debugPrint('[TTS] Windows SAPI failed with exit code $exitCode');
        return;
      }
      if (generation != _windowsGeneration || !await file.exists()) return;

      _windowsTtsPlayer ??= AudioPlayer();
      final player = _windowsTtsPlayer!;
      final playbackFinished = Completer<void>();
      playbackCanceled = Completer<void>();
      _windowsPlaybackCanceled = playbackCanceled;
      completionSubscription = player.onPlayerComplete.listen((_) {
        if (!playbackFinished.isCompleted) playbackFinished.complete();
      });
      await player.play(DeviceFileSource(file.path));
      if (generation != _windowsGeneration) {
        await player.stop();
        return;
      }
      await Future.any([
        playbackFinished.future,
        playbackCanceled.future,
      ]).timeout(const Duration(minutes: 5), onTimeout: () {});
      if (!playbackFinished.isCompleted && !playbackCanceled.isCompleted) {
        await player.stop();
      }
    } catch (e) {
      debugPrint('[TTS] Windows SAPI error: $e');
    } finally {
      if (identical(_windowsSynthesisProcess, process)) {
        _windowsSynthesisProcess = null;
      }
      await completionSubscription?.cancel();
      if (file != null && await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (identical(_windowsPlaybackCanceled, playbackCanceled)) {
        _windowsPlaybackCanceled = null;
      }
    }
  }

  Future<void> _speakViaGptSovits(String text) async {
    final generation = _gptSovitsGeneration;
    if (generation != _gptSovitsGeneration || !enabled) return;

    File? file;
    StreamSubscription<void>? completionSubscription;
    final playbackCanceled = Completer<void>();
    _gptSovitsPlaybackCanceled = playbackCanceled;
    try {
      final normalizedText = _normalizeGptSovitsText(text);
      final resp = await Future.any<http.Response?>([
        _requestGptSovitsAudio(
          url: gptSovitsUrl,
          text: normalizedText,
          refAudioPath: gptSovitsRefAudioPath,
          promptText: gptSovitsPromptText,
          timeout: const Duration(seconds: 30),
        ),
        playbackCanceled.future.then((_) => null),
      ]);
      if (resp == null) return;
      if (!_looksLikeAudio(resp)) return;
      if (generation != _gptSovitsGeneration || playbackCanceled.isCompleted) {
        return;
      }

      final dir = await getTemporaryDirectory();
      file = File(
        '${dir.path}/rq_gpt_sovits_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(resp.bodyBytes);
      if (generation != _gptSovitsGeneration || playbackCanceled.isCompleted) {
        return;
      }

      _gptSovitsPlayer ??= AudioPlayer();
      final player = _gptSovitsPlayer!;
      final playbackFinished = Completer<void>();
      completionSubscription = player.onPlayerComplete.listen((_) {
        if (!playbackFinished.isCompleted) playbackFinished.complete();
      });
      await player.play(DeviceFileSource(file.path));
      if (generation != _gptSovitsGeneration) {
        await player.stop();
        return;
      }
      await Future.any([
        playbackFinished.future,
        playbackCanceled.future,
      ]).timeout(const Duration(minutes: 5), onTimeout: () {});
      if (!playbackFinished.isCompleted && !playbackCanceled.isCompleted) {
        await player.stop();
      }
    } catch (e) {
      debugPrint('[GPT-SoVITS] error: $e');
    } finally {
      await completionSubscription?.cancel();
      if (file != null && await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (identical(_gptSovitsPlaybackCanceled, playbackCanceled)) {
        _gptSovitsPlaybackCanceled = null;
      }
    }
  }

  Future<http.Response?> _requestGptSovitsAudio({
    required String url,
    required String text,
    required String refAudioPath,
    required String promptText,
    required Duration timeout,
  }) async {
    final endpoints = _lastGptSovitsEndpoint == 'root'
        ? const ['root', 'tts']
        : const ['tts', 'root'];
    for (final endpoint in endpoints) {
      final uri = _buildGptSovitsUri(
        url: url,
        endpoint: endpoint,
        text: text,
        refAudioPath: refAudioPath,
        promptText: promptText,
      );
      final resp = await http.get(uri).timeout(timeout);
      if (resp.statusCode == 200) {
        if (_looksLikeAudio(resp)) {
          _lastGptSovitsEndpoint = endpoint;
          return resp;
        }
        debugPrint(
          '[GPT-SoVITS] $endpoint returned non-audio: '
          '${resp.headers['content-type'] ?? 'unknown'}',
        );
        continue;
      }
      debugPrint(
        '[GPT-SoVITS] $endpoint HTTP ${resp.statusCode}: ${resp.body}',
      );
      if (resp.statusCode != 404) {
        return null;
      }
    }
    return null;
  }

  Uri _buildGptSovitsUri({
    required String url,
    required String endpoint,
    required String text,
    required String refAudioPath,
    required String promptText,
  }) {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    final path = endpoint == 'root' ? normalized : '$normalized/tts';
    return Uri.parse(path).replace(
      queryParameters: {
        'text': text,
        'text_lang': 'zh',
        if (refAudioPath.trim().isNotEmpty)
          'ref_audio_path': refAudioPath.trim(),
        'prompt_lang': 'zh',
        if (promptText.trim().isNotEmpty) 'prompt_text': promptText.trim(),
        'text_split_method': 'cut5',
        'batch_size': '1',
        'media_type': 'wav',
        'streaming_mode': 'false',
      },
    );
  }

  bool _looksLikeAudio(http.Response resp) {
    final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('audio') ||
        contentType.contains('wav') ||
        contentType.contains('octet-stream')) {
      return true;
    }
    final bytes = resp.bodyBytes;
    if (bytes.length < 4) return false;
    final b0 = bytes[0];
    final b1 = bytes[1];
    final b2 = bytes[2];
    final b3 = bytes[3];
    return (b0 == 0x52 && b1 == 0x49 && b2 == 0x46 && b3 == 0x46) ||
        (b0 == 0x49 && b1 == 0x44 && b2 == 0x33) ||
        (b0 == 0xff && (b1 & 0xe0) == 0xe0) ||
        (b0 == 0x4f && b1 == 0x67 && b2 == 0x67 && b3 == 0x53);
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final pendingStop = _playbackStopFuture;
        if (pendingStop != null) await pendingStop;
        final job = _queue.removeFirst();
        final generation = _generation;
        _activeJob = job;
        try {
          if (job.delay > Duration.zero) {
            final canceled = Completer<void>();
            _activeDelayCanceled = canceled;
            await Future.any([
              Future<void>.delayed(job.delay),
              canceled.future,
            ]);
            if (identical(_activeDelayCanceled, canceled)) {
              _activeDelayCanceled = null;
            }
          }
          if (generation != _generation ||
              !enabled ||
              job.obsolete ||
              job.isCurrent?.call() == false ||
              (job.expiresAt != null &&
                  DateTime.now().isAfter(job.expiresAt!))) {
            continue;
          }
          job.playbackStarted = true;
          if (gptSovitsEnabled) {
            await _speakViaGptSovits(job.text);
            continue;
          }
          if (!kIsWeb && Platform.isWindows) {
            await (windowsSpeechOverrideForTest?.call(job.text) ??
                _speakViaWindowsSapi(job.text));
            continue;
          }
          await _ensureEngineReady();
          if (!_engineReady || job.obsolete) continue;
          if (job.interrupt) {
            await _safeTtsCall(() => _flutterTts.stop());
          }
          await _applyEngineConfig();
          if (!job.obsolete) {
            await _safeTtsCall(() => _flutterTts.speak(job.text));
          }
        } finally {
          if (identical(_activeJob, job)) _activeJob = null;
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _ensureEngineReady() async {
    if (_engineReady) return;
    try {
      await _flutterTts.awaitSpeakCompletion(true);
      _engineReady = true;
    } catch (e) {
      debugPrint('[TTS] init error: $e');
    }
  }

  Future<void> _applyEngineConfig() async {
    await _ensureEngineReady();
    if (!_engineReady) return;

    await _safeTtsCall(() => _flutterTts.setLanguage('zh-CN'));
    await _safeTtsCall(
      () => _flutterTts.setSpeechRate(speechRate.clamp(0.1, 1.0)),
    );
    await _safeTtsCall(() => _flutterTts.setPitch(pitch.clamp(0.5, 2.0)));
    await _safeTtsCall(() => _flutterTts.setVolume(volume.clamp(0.0, 1.0)));

    final voice = _selectedVoice();
    if (voice != null && voice.id.isNotEmpty) {
      final payload = <String, String>{'name': voice.name};
      if (voice.locale != null && voice.locale!.isNotEmpty) {
        payload['locale'] = voice.locale!;
      }
      await _safeTtsCall(() => _flutterTts.setVoice(payload));
    }

    if (!kIsWeb && Platform.isIOS) {
      await _safeTtsCall(
        () => _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker],
        ),
      );
    }
  }

  TtsVoiceOption? _selectedVoice() {
    if (voiceId.isNotEmpty) {
      for (final voice in _voices) {
        if (voice.id == voiceId) return voice;
      }
    }

    const preferredNames = [
      'xiaoxiao',
      'xiaoyi',
      'huihui',
      'yaoyao',
      'hanhan',
      'kang',
    ];
    for (final preferredName in preferredNames) {
      for (final voice in _voices) {
        if (voice.name.toLowerCase().contains(preferredName)) {
          return voice;
        }
      }
    }
    for (final voice in _voices) {
      if (_isChineseVoice(voice)) return voice;
    }
    return null;
  }

  Future<void> _safeTtsCall(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[TTS] platform error: $e');
    }
  }

  int _windowsRate() {
    final normalized = ((speechRate.clamp(0.1, 1.0) - 0.55) / 0.45) * 10;
    return normalized.round().clamp(-6, 8);
  }

  static int _sortVoice(TtsVoiceOption a, TtsVoiceOption b) {
    if (a.id.isEmpty) return -1;
    if (b.id.isEmpty) return 1;
    final aCn = _isChineseVoice(a);
    final bCn = _isChineseVoice(b);
    if (aCn != bCn) return aCn ? -1 : 1;
    return a.label.compareTo(b.label);
  }

  static String _voiceId(String name, String? locale) {
    return '$name|${locale ?? ''}';
  }

  static bool _isChineseVoice(TtsVoiceOption voice) {
    final haystack = '${voice.name} ${voice.locale ?? ''}'.toLowerCase();
    return haystack.contains('zh') ||
        haystack.contains('cn') ||
        haystack.contains('huihui') ||
        haystack.contains('xiaoxiao') ||
        haystack.contains('xiaoyi') ||
        haystack.contains('yaoyao') ||
        haystack.contains('hanhan') ||
        haystack.contains('kang');
  }

  static String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[|]+'), ',')
        .trim();
  }

  static String _normalizeGptSovitsText(String text) {
    var normalized = text
        .replaceAll(RegExp(r'^[\s,，。.!！?？、；;：:]+'), '')
        .replaceAllMapped(_gptSovitsAcronymPattern, (match) {
          final prefix = match.group(1) ?? '';
          final token = (match.group(2) ?? '').toUpperCase();
          return '$prefix${_gptSovitsAcronymReadings[token] ?? token}';
        })
        .replaceAllMapped(RegExp(r'(-?\d+)\.(\d+)'), (match) {
          final integer = match.group(1) ?? '';
          final fraction = match.group(2) ?? '';
          if (integer.isEmpty || fraction.isEmpty) return match.group(0)!;
          return '${_numberToChinese(integer)}点${_digitsToChinese(fraction)}';
        });
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static final RegExp _gptSovitsAcronymPattern = RegExp(
    r'(^|[^A-Za-z0-9])(EMSC|GFZ)(?=$|[^A-Za-z0-9])',
    caseSensitive: false,
  );

  static const Map<String, String> _gptSovitsAcronymReadings = {
    'EMSC': '\u6b27\u6d32\u5730\u4e2d\u6d77\u5730\u9707\u4e2d\u5fc3',
    'GFZ': '\u5fb7\u56fd\u5730\u5b66\u7814\u7a76\u4e2d\u5fc3',
  };

  static String _numberToChinese(String value) {
    if (value.isEmpty) return '';
    final negative = value.startsWith('-');
    final digits = negative ? value.substring(1) : value;
    final parsed = int.tryParse(digits);
    if (parsed == null) return _digitsToChinese(digits);
    if (parsed == 0) return negative ? '负零' : '零';

    const units = ['', '十', '百', '千'];
    const bigUnits = ['', '万', '亿'];
    final groups = <String>[];
    var n = parsed;
    while (n > 0) {
      groups.add(_fourDigitGroupToChinese(n % 10000, units));
      n ~/= 10000;
    }

    final parts = <String>[];
    for (var i = groups.length - 1; i >= 0; i--) {
      final group = groups[i];
      if (group.isEmpty) {
        if (parts.isNotEmpty && parts.last != '零') parts.add('零');
        continue;
      }
      parts.add('$group${bigUnits[i]}');
      if (i > 0 && groups[i - 1].isNotEmpty) {
        final lower = parsed ~/ _powInt(10000, i - 1) % 10000;
        if (lower > 0 && lower < 1000) parts.add('零');
      }
    }

    var result = parts.join();
    result = result
        .replaceAll(RegExp(r'零+'), '零')
        .replaceAll(RegExp(r'零$'), '');
    if (result.startsWith('一十')) result = result.substring(1);
    return negative ? '负$result' : result;
  }

  static String _fourDigitGroupToChinese(int value, List<String> units) {
    if (value <= 0) return '';
    final chars = value.toString().split('');
    final parts = <String>[];
    for (var i = 0; i < chars.length; i++) {
      final digit = int.parse(chars[i]);
      final unitIndex = chars.length - i - 1;
      if (digit == 0) {
        if (parts.isNotEmpty && parts.last != '零') parts.add('零');
        continue;
      }
      parts.add('${_digitToChinese(digit)}${units[unitIndex]}');
    }
    return parts.join().replaceAll(RegExp(r'零$'), '');
  }

  static int _powInt(int base, int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  static String _digitsToChinese(String value) {
    return value.split('').map((char) {
      final digit = int.tryParse(char);
      return digit == null ? char : _digitToChinese(digit);
    }).join();
  }

  static String _digitToChinese(int digit) {
    const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    if (digit < 0 || digit > 9) return digit.toString();
    return digits[digit];
  }
}
