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

class _TtsJob {
  final String text;
  final Duration delay;
  final bool interrupt;

  const _TtsJob({
    required this.text,
    this.delay = Duration.zero,
    this.interrupt = false,
  });
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

  final FlutterTts _flutterTts = FlutterTts();
  final Queue<_TtsJob> _queue = Queue<_TtsJob>();
  final Map<String, DateTime> _lastSpokenAt = {};

  bool _initialized = false;
  bool _engineReady = false;
  bool _processing = false;
  int _generation = 0;
  int _gptSovitsGeneration = 0;
  int _windowsGeneration = 0;
  AudioPlayer? _gptSovitsPlayer;
  AudioPlayer? _windowsTtsPlayer;
  List<TtsVoiceOption> _voices = const [TtsVoiceOption.systemDefault];

  bool enabled = true;
  bool eventEnabled = true;
  bool countdownEnabled = true;
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
    enabled = prefs.getBool(enabledKey) ?? true;
    eventEnabled = prefs.getBool(eventEnabledKey) ?? true;
    countdownEnabled = prefs.getBool(countdownEnabledKey) ?? true;
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
    bool isUpdate = false,
    Duration delay = const Duration(milliseconds: 1150),
  }) {
    if (!eventEnabled) return Future.value();
    if (isUpdate && !updateEnabled) return Future.value();
    return speak(
      text,
      dedupeKey: 'event:$dedupeKey',
      dedupeWindow: const Duration(seconds: 4),
      delay: delay,
      interrupt: false,
    );
  }

  Future<void> speakCountdown(String eventId, int seconds) {
    if (!countdownEnabled) return Future.value();
    return speak(
      '$seconds',
      dedupeKey: 'countdown:$eventId:$seconds',
      dedupeWindow: const Duration(seconds: 30),
      interrupt: true,
    );
  }

  Future<void> speakArrival(String eventId) {
    if (!countdownEnabled) return Future.value();
    return speak(
      '\u5730\u9707\u6ce2\u5230\u8fbe\u3002',
      dedupeKey: 'arrival:$eventId',
      dedupeWindow: const Duration(minutes: 3),
      interrupt: true,
    );
  }

  Future<void> speak(
    String text, {
    String? dedupeKey,
    Duration dedupeWindow = Duration.zero,
    Duration delay = Duration.zero,
    bool interrupt = false,
  }) async {
    await _ensureInitialized();
    final cleaned = _cleanText(text);
    if (!enabled || cleaned.isEmpty) return;

    if (dedupeKey != null && dedupeWindow > Duration.zero) {
      final now = DateTime.now();
      final last = _lastSpokenAt[dedupeKey];
      if (last != null && now.difference(last) < dedupeWindow) return;
      _lastSpokenAt[dedupeKey] = now;
    }

    if (gptSovitsEnabled) {
      unawaited(
        _speakViaGptSovits(cleaned, delay: delay, interrupt: interrupt),
      );
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      unawaited(
        _speakViaWindowsSapi(cleaned, delay: delay, interrupt: interrupt),
      );
      return;
    }

    if (interrupt) {
      _queue.clear();
      _generation++;
      if (_engineReady) {
        await _safeTtsCall(() => _flutterTts.stop());
      }
    }

    _queue.add(_TtsJob(text: cleaned, delay: delay, interrupt: interrupt));
    unawaited(_processQueue());
  }

  Future<void> stop() async {
    _queue.clear();
    _generation++;
    _gptSovitsGeneration++;
    _windowsGeneration++;
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

  Future<void> _speakViaWindowsSapi(
    String text, {
    Duration delay = Duration.zero,
    bool interrupt = false,
  }) async {
    if (interrupt) {
      _windowsGeneration++;
      await _windowsTtsPlayer?.stop();
    }
    final generation = _windowsGeneration;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
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
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/rq_windows_tts.wav');
      final env = Map<String, String>.from(Platform.environment);
      env['RQ_TTS_TEXT'] = text;
      env['RQ_TTS_FILE'] = file.path;
      env['RQ_TTS_RATE'] = _windowsRate().toString();
      env['RQ_TTS_VOLUME'] = (volume.clamp(0.0, 1.0) * 100).round().toString();
      env['RQ_TTS_VOICE'] = _selectedVoice()?.name ?? '';

      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        environment: env,
        runInShell: false,
      ).timeout(const Duration(seconds: 12));
      if (result.exitCode != 0) {
        debugPrint('[TTS] Windows SAPI failed: ${result.stderr}');
        return;
      }
      if (generation != _windowsGeneration || !await file.exists()) return;

      _windowsTtsPlayer ??= AudioPlayer();
      await _windowsTtsPlayer!.play(DeviceFileSource(file.path));
    } catch (e) {
      debugPrint('[TTS] Windows SAPI error: $e');
    }
  }

  Future<void> _speakViaGptSovits(
    String text, {
    Duration delay = Duration.zero,
    bool interrupt = false,
  }) async {
    if (interrupt) {
      _gptSovitsGeneration++;
      await _gptSovitsPlayer?.stop();
    }
    final generation = _gptSovitsGeneration;

    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (generation != _gptSovitsGeneration || !enabled) return;

    try {
      final normalizedText = _normalizeGptSovitsText(text);
      final resp = await _requestGptSovitsAudio(
        url: gptSovitsUrl,
        text: normalizedText,
        refAudioPath: gptSovitsRefAudioPath,
        promptText: gptSovitsPromptText,
        timeout: const Duration(seconds: 30),
      );
      if (resp == null) return;
      if (!_looksLikeAudio(resp)) return;
      if (generation != _gptSovitsGeneration) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/rq_gpt_sovits.wav');
      await file.writeAsBytes(resp.bodyBytes);
      if (generation != _gptSovitsGeneration) return;

      _gptSovitsPlayer ??= AudioPlayer();
      await _gptSovitsPlayer!.play(DeviceFileSource(file.path));
    } catch (e) {
      debugPrint('[GPT-SoVITS] error: $e');
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
        final job = _queue.removeFirst();
        final generation = _generation;
        if (job.delay > Duration.zero) {
          await Future<void>.delayed(job.delay);
        }
        if (generation != _generation || !enabled) continue;
        await _ensureEngineReady();
        if (!_engineReady) continue;
        if (job.interrupt) {
          await _safeTtsCall(() => _flutterTts.stop());
        }
        await _applyEngineConfig();
        await _safeTtsCall(() => _flutterTts.speak(job.text));
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
