import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import '../../core/source_estimation/source_estimation_models.dart';
import '../../models/station_history_frame.dart';
import '../sources/nied_source_estimation_worker.dart';
import '../sources/palert_source_worker.dart';
import 'station_replay_blocks.dart';

/// Replay owns separate workers and output; never publishes into live trackers,
/// archives, TTS, or automatic replay logging. Original frame times are inputs.
class ReplaySourceEstimation extends ChangeNotifier {
  static final instance = ReplaySourceEstimation();
  NiedSourceEstimationWorker? _nied;
  PAlertSourceWorker? _palert;
  String? session;
  int _generation = 0;
  DateTime Function()? _clock;
  SeismicActiveEvent? nied;
  DateTime? niedFrameReceivedAt;
  List<SeismicActiveEvent> palert = const [];
  Object? error;
  Queue<_ReplayInferenceJob> _jobs = Queue();
  bool _draining = false;
  Timer? _uiNotifyTimer;
  bool _uiNotifyPending = false;
  static const _uiNotifyInterval = Duration(milliseconds: 80);
  StationReplayReadCursor _reader = StationReplayReadCursor();
  int processedFrames = 0;
  int peakPendingFrames = 0;
  int lastComputationMicroseconds = 0;
  int get pendingFrames => _jobs.length;
  bool get isIdle => !_draining && _jobs.isEmpty;
  DateTime get now => _clock!();

  void start(String id, DateTime Function() clock, {int sensitivity = 2}) {
    stop();
    session = id;
    _clock = clock;
    _nied = NiedSourceEstimationWorker(displayOnly: true)
      ..setSensitivity(sensitivity);
    _palert = PAlertSourceWorker()..setSensitivity(sensitivity);
    notifyListeners();
  }

  Future<void> processEntry(StationReplayEntry entry) =>
      _enqueue(entry.kind, () => _reader.loadAsync(entry));

  Future<void> process(StationHistoryFrame frame) =>
      _enqueue(frame.kind, () => frame);

  Future<void> _enqueue(
    String kind,
    FutureOr<StationHistoryFrame> Function() load,
  ) {
    if (session == null || (kind != 'nied' && kind != 'palert')) {
      return Future.value();
    }
    final job = _ReplayInferenceJob(load);
    _jobs.add(job);
    if (_jobs.length > peakPendingFrames) peakPendingFrames = _jobs.length;
    if (!_draining) unawaited(_drain(_generation));
    return job.done.future;
  }

  Future<void> _drain(int generation) async {
    _draining = true;
    try {
      while (generation == _generation && _jobs.isNotEmpty) {
        final job = _jobs.removeFirst();
        try {
          final frame = await job.load();
          if (generation == _generation) await _processFrame(frame);
          if (generation == _generation) processedFrames++;
        } catch (failure, stack) {
          if (generation == _generation) {
            error = failure;
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: failure,
                stack: stack,
                library: 'Replay source frame loading',
              ),
            );
          }
        } finally {
          job.done.complete();
        }
      }
    } finally {
      if (generation == _generation) _draining = false;
    }
  }

  Future<void> _processFrame(StationHistoryFrame frame) async {
    if (session == null) return;
    final generation = _generation;
    try {
      switch (frame.kind) {
        case 'nied':
          final rawStations = frame.snapshot['stations'];
          if (rawStations is! List || rawStations.isEmpty) return;
          final result = await _nied!.processRawStations(rawStations);
          if (generation != _generation || result == null) return;
          nied = result.event;
          lastComputationMicroseconds = result.computationMicroseconds;
          niedFrameReceivedAt = frame.receivedAt;
        case 'palert':
          final events = await _palert!.processRecordedSnapshot(
            frame.snapshot,
            receivedAt: frame.receivedAt,
          );
          if (generation != _generation || events == null) return;
          palert = events;
        default:
          return;
      }
      error = null;
      _scheduleUiNotification();
    } catch (failure, stack) {
      if (generation != _generation) return;
      error = failure;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: failure,
          stack: stack,
          library: 'Replay source estimation',
        ),
      );
    }
  }

  void stop() {
    _generation++;
    _reader.dispose();
    _reader = StationReplayReadCursor();
    for (final job in _jobs) {
      job.done.complete();
    }
    _jobs = Queue();
    _draining = false;
    processedFrames = peakPendingFrames = lastComputationMicroseconds = 0;
    _nied?.dispose();
    _palert?.dispose();
    _nied = null;
    _palert = null;
    session = null;
    _clock = null;
    nied = null;
    niedFrameReceivedAt = null;
    palert = const [];
    error = null;
    _uiNotifyTimer?.cancel();
    _uiNotifyTimer = null;
    _uiNotifyPending = false;
    notifyListeners();
  }

  void _scheduleUiNotification() {
    _uiNotifyPending = true;
    if (_uiNotifyTimer != null) return;
    _uiNotifyTimer = Timer(_uiNotifyInterval, () {
      _uiNotifyTimer = null;
      if (!_uiNotifyPending) return;
      _uiNotifyPending = false;
      if (session != null) notifyListeners();
    });
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

class _ReplayInferenceJob {
  _ReplayInferenceJob(this.load);
  final FutureOr<StationHistoryFrame> Function() load;
  final done = Completer<void>();
}
