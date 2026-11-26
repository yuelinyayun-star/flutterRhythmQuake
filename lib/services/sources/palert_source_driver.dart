import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../core/source_estimation/source_estimation_models.dart';
import 'palert_service.dart';
import 'palert_source_state.dart';
import 'palert_source_worker.dart';

/// Owns the live inference session and freshness; widgets only project output.
class PAlertSourceDriver {
  PAlertSourceDriver({
    PAlertSourceWorker? worker,
    DateTime Function()? clock,
    ValueNotifier<List<SeismicActiveEvent>>? events,
    this.onChanged,
  }) : _worker = worker ?? PAlertSourceWorker(),
       _clock = clock ?? DateTime.now,
       events = events ?? PAlertSourceState.events;

  final PAlertSourceWorker _worker;
  final DateTime Function() _clock;
  final ValueNotifier<List<SeismicActiveEvent>> events;
  final VoidCallback? onChanged;
  Timer? _expiry;
  DateTime? _expiresAt;
  int _generation = 0;
  bool _disposed = false;
  Object? lastError;
  int processedFrames = 0;

  Future<void> process(List<PAlertStation> stations, Set<String> ids) async {
    if (_disposed) return;
    DateTime? received;
    for (final station in stations) {
      final time = station.receivedAt;
      if (time != null && (received == null || time.isAfter(received))) {
        received = time;
      }
    }
    return _process(
      received,
      (now) => _worker.process(stations, ids, now: now),
    );
  }

  Future<void> processPreparedSnapshot(
    Map<String, dynamic> snapshot,
    DateTime? received,
  ) => _process(
    received,
    (now) => _worker.processPreparedSnapshot(snapshot, receivedAt: now),
  );

  Future<void> _process(
    DateTime? received,
    Future<List<SeismicActiveEvent>?> Function(DateTime) submit,
  ) async {
    if (_disposed) return;
    final now = _clock();
    if (received == null || PAlertService.isFrameStale(received, now)) {
      clear();
      return;
    }
    _expiresAt = received.add(PAlertService.frameStaleAfter);
    _expiry?.cancel();
    _expiry = Timer(_expiresAt!.difference(now), clear);
    final generation = _generation;
    try {
      final result = await submit(now);
      if (_disposed ||
          generation != _generation ||
          result == null ||
          PAlertService.isFrameStale(received, _clock())) {
        return;
      }
      processedFrames++;
      lastError = null;
      if (result.isEmpty && events.value.isEmpty) return;
      events.value = result;
      onChanged?.call();
    } catch (error, stack) {
      if (_disposed || generation != _generation) return;
      lastError = error;
      debugPrint('P-Alert source estimation failed: $error\n$stack');
      clear(releaseWorker: true);
    }
  }

  void recheckExpiry({DateTime? now}) {
    final deadline = _expiresAt;
    if (deadline == null) return;
    _expiry?.cancel();
    final remaining = deadline.difference(now ?? _clock());
    if (remaining <= Duration.zero) {
      clear();
    } else {
      _expiry = Timer(remaining, clear);
    }
  }

  /// Expiry clears visible output, retaining raw warm-up and immutable geometry.
  /// Source-time gaps still invalidate individual picks in the estimator.
  /// Disable/dispose are the only normal operations that release the worker.
  void clear({bool releaseWorker = false}) {
    _generation++;
    _expiry?.cancel();
    _expiry = null;
    _expiresAt = null;
    if (releaseWorker) _worker.reset();
    if (events.value.isNotEmpty) {
      events.value = const [];
      onChanged?.call();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
    _worker.dispose();
  }
}
