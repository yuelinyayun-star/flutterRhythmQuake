import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/quake_provider.dart';
import '../../services/external_subtitle_timeline.dart';

class ExternalSubtitleSettings extends ChangeNotifier {
  ExternalSubtitleSettings(this._prefs)
    : enabled = _prefs.getBool(_enabledKey) ?? false;

  static const _enabledKey = 'external_earthquake_subtitles';
  static const channel = MethodChannel('flutterrhythmquake/external_subtitle');
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android);

  final SharedPreferences _prefs;
  bool enabled;

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    await _prefs.setBool(_enabledKey, value);
    if (value && defaultTargetPlatform == TargetPlatform.android) {
      await channel.invokeMethod<void>('requestPermission');
    }
  }
}

/// Owns the subscription and the native window for the lifetime of the UI
/// engine. The app's source, catalogue and notification owners stay separate.
class ExternalSubtitleHost extends StatefulWidget {
  const ExternalSubtitleHost({super.key, required this.child});

  final Widget child;

  @override
  State<ExternalSubtitleHost> createState() => _ExternalSubtitleHostState();
}

class _ExternalSubtitleHostState extends State<ExternalSubtitleHost> {
  final _clock = Stopwatch()..start();
  ExternalSubtitleSettings? _settings;
  QuakeProvider? _provider;
  ExternalSubtitleTimeline? _timeline;
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  List<SubtitleLine> _sent = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ExternalSubtitleSettings.supported) return;
    final settings = context.read<ExternalSubtitleSettings?>();
    if (identical(settings, _settings)) return;
    _settings?.removeListener(_applySetting);
    _settings = settings;
    _settings?.addListener(_applySetting);
    _applySetting();
  }

  void _applySetting() {
    if (_settings?.enabled != true) {
      _detach();
      return;
    }
    if (_provider != null) return;
    _provider = context.read<QuakeProvider>()..addListener(_sync);
    _timeline = ExternalSubtitleTimeline();
    if (defaultTargetPlatform == TargetPlatform.android) {
      _lifecycle = AppLifecycleListener(onResume: () => _render(force: true));
    }
    _sync(force: true);
  }

  void _sync({bool force = false}) {
    _timeline!.update(
      _provider!.unifiedDisplayEvents,
      _clock.elapsedMilliseconds,
    );
    _render(force: force);
  }

  void _render({bool force = false}) {
    final timeline = _timeline;
    if (timeline == null) return;
    _timer?.cancel();
    final now = _clock.elapsedMilliseconds;
    final next = timeline.frame(now);
    if (force || !listEquals(next, _sent)) {
      _sent = next;
      unawaited(_present(next));
    }
    if (timeline.nextChangeAt case final at?) {
      _timer = Timer(Duration(milliseconds: at - now), _render);
    }
  }

  Future<void> _present(List<SubtitleLine> frame, {bool close = false}) async {
    try {
      await ExternalSubtitleSettings.channel.invokeMethod<void>(
        close ? 'close' : 'present',
        [
          for (final row in frame)
            {
              'text': row.text,
              'style': row.style,
              'japanese': row.japanese,
              'hidden': row.hidden,
              'badge': row.badge,
            },
        ],
      );
    } on PlatformException catch (error) {
      debugPrint('[ExternalSubtitle] ${error.message ?? error.code}');
    }
  }

  void _detach() {
    if (_provider == null) return;
    _provider?.removeListener(_sync);
    _provider = null;
    _timeline = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _timer?.cancel();
    _sent = const [];
    unawaited(_present(const [], close: true));
  }

  @override
  void dispose() {
    _settings?.removeListener(_applySetting);
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
