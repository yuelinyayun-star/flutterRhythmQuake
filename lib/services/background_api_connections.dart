import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/background_api.dart';
import '../models/source_status.dart';
import 'native_background_api_policy.dart';
import 'sources/source_manager.dart';

/// Owns only the Android service's background API selection. The registered
/// services still own authentication, reconnects and event processing.
class BackgroundApiConnections {
  BackgroundApiConnections({
    required this.sources,
    required this.enabledInForeground,
    required this.setSourceEnabled,
    required this.whewsCoverageReady,
  });

  final Map<BackgroundApi, List<String>> sources;
  final Set<BackgroundApi> enabledInForeground;
  final void Function(String, bool) setSourceEnabled;
  final bool Function() whewsCoverageReady;

  static const _maximumSample = Duration(seconds: 15);
  static const _sampleLifetime = Duration(minutes: 15);
  static const _failureGrace = Duration(seconds: 45);
  static const _retryBackoff = Duration(minutes: 2);
  final _startedAt = <BackgroundApi, Stopwatch>{};
  final _readySamples = <BackgroundApi, (Duration, DateTime)>{};
  final _readySources = <String>{};
  final _failureTimers = <BackgroundApi, Timer>{};
  final _ready = <BackgroundApi>{};
  final _retrying = <BackgroundApi>{};
  Set<BackgroundApi> _active = {};
  Set<BackgroundApi> _eligible = {};
  Set<BackgroundApi> _manual = {};
  bool _visible = false;
  bool _automatic = true;
  bool _disposed = false;
  Timer? _retryTimer;

  void configure({
    required bool visible,
    required bool automatic,
    required Set<BackgroundApi> manual,
    required Set<BackgroundApi> eligible,
  }) {
    if (_visible != visible || _automatic != automatic) {
      _retrying.clear();
      _startedAt.clear();
    }
    _visible = visible;
    _automatic = automatic;
    _manual = manual;
    _eligible = eligible.intersection(enabledInForeground);
    _retrying.retainAll(_eligible);
    _apply();
  }

  void forgetReadiness(BackgroundApi api) {
    _readySamples.remove(api);
    _startedAt.remove(api);
    _ready.remove(api);
    for (final source in sources[api] ?? const <String>[]) {
      _readySources.remove(source);
    }
  }

  void onStatus(SourceStatusUpdate update) {
    if (_disposed) return;
    for (final entry in sources.entries) {
      final api = entry.key;
      if (api.feeds.isEmpty ||
          !_active.contains(api) ||
          !entry.value.contains(update.sourceName)) {
        continue;
      }
      if (update.status == SourceStatus.connected) {
        _readySources.add(update.sourceName);
      } else {
        _readySources.remove(update.sourceName);
      }
      final ready = api == BackgroundApi.whews
          ? whewsCoverageReady()
          : entry.value.any(_readySources.contains);
      if (ready) {
        _ready.add(api);
        final elapsed = _startedAt.remove(api)?.elapsed;
        if (elapsed != null && elapsed <= _maximumSample) {
          _readySamples[api] = (elapsed, DateTime.now());
        }
        if (_retrying.remove(api)) _apply();
      } else {
        _ready.remove(api);
        if (update.status == SourceStatus.connecting) {
          _startedAt.putIfAbsent(api, () => Stopwatch()..start());
        } else if (update.status != SourceStatus.synchronizing) {
          _startedAt.remove(api);
        }
      }
      _watchFailure(api);
      _watchRecovery();
      return;
    }
  }

  void _apply() {
    if (_disposed) return;
    final next = _visible
        ? enabledInForeground
        : _automatic
        ? _select()
        : _manual.intersection(_eligible);
    final previous = _active;
    _active = next;
    if (kDebugMode &&
        (next.length != previous.length || !next.containsAll(previous))) {
      final mode = _visible ? 'foreground' : (_automatic ? 'auto' : 'manual');
      debugPrint(
        '[Background API] $mode: ${next.map((api) => api.label).join(', ')}',
      );
    }
    for (final api in sources.keys) {
      if (next.contains(api)) continue;
      for (final source in sources[api]!) {
        setSourceEnabled(source, false);
        _readySources.remove(source);
      }
      _ready.remove(api);
      _startedAt.remove(api);
      _watchFailure(api);
    }
    _watchRecovery();
    for (final api in next) {
      if (!previous.contains(api)) {
        _ready.remove(api);
        for (final source in sources[api]!) {
          _readySources.remove(source);
        }
        if (!_visible) {
          _startedAt[api] = Stopwatch()..start();
        }
        for (final source in sources[api]!) {
          setSourceEnabled(source, true);
        }
      } else if (!_visible &&
          !_ready.contains(api) &&
          !_startedAt.containsKey(api)) {
        _startedAt[api] = Stopwatch()..start();
      }
      _watchFailure(api);
    }
  }

  void _watchFailure(BackgroundApi api) {
    if (_visible ||
        !_automatic ||
        !_active.contains(api) ||
        api.feeds.isEmpty ||
        _ready.contains(api) ||
        _retrying.contains(api)) {
      _failureTimers.remove(api)?.cancel();
      return;
    }
    _failureTimers.putIfAbsent(
      api,
      () => Timer(_failureGrace, () {
        _failureTimers.remove(api);
        _retrying.add(api);
        _readySamples.remove(api);
        _apply();
      }),
    );
  }

  void _watchRecovery() {
    if (_visible ||
        !_automatic ||
        _active.isEmpty ||
        !_active.every(_retrying.contains)) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    _retryTimer ??= Timer(_retryBackoff, () {
      _retryTimer = null;
      _retrying.clear();
      _apply();
    });
  }

  Set<BackgroundApi> _select() {
    final candidates = [
      for (final api in BackgroundApi.values)
        if (_eligible.contains(api) && api.feeds.isNotEmpty) api,
    ];
    if (candidates.isEmpty) return {};
    final priorityOnly = candidates.any((api) => api.priorityRegions != 0);
    final now = DateTime.now();
    _readySamples.removeWhere(
      (_, sample) => now.difference(sample.$2) > _sampleLifetime,
    );
    final mask = selectNativeBackgroundApis([
      for (final api in candidates) ...[
        api.priorityRegions | (_retrying.contains(api) ? 8 : 0),
        api.feedMask(priorityOnly: priorityOnly),
        _readySamples[api]?.$1.inMilliseconds ?? 0xffffffff,
      ],
    ]);
    return {
      for (var i = 0; i < candidates.length; i++)
        if (mask & (1 << i) != 0) candidates[i],
    };
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    for (final timer in _failureTimers.values) {
      timer.cancel();
    }
    _failureTimers.clear();
  }
}
