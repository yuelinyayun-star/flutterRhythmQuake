import 'dart:async';
import 'native_windows_tts.dart';

/// Native Rust SAPI synthesis bridge for Windows.
/// Does not spawn external shell/PowerShell processes, and degrades cleanly on
/// non-Windows platforms or devices without speech engines.
class WindowsSapiWorker {
  Completer<void>? _activeCancel;
  bool _closed = false;

  bool get isSynthesizing => _activeCancel != null;

  /// Kept for compatibility; Rust COM SAPI initializes lazily on first request
  /// so devices without TTS never touch SAPI during app startup.
  Future<void> warmUp() async {
    if (_closed) throw StateError('SAPI worker closed');
  }

  Future<void> synthesize({
    required String text,
    required String file,
    required int rate,
    required int volume,
    required String voice,
  }) async {
    if (_closed) throw StateError('SAPI worker closed');
    if (!NativeWindowsTts.supported) {
      throw UnsupportedError('Windows SAPI synthesis unavailable');
    }
    if (_activeCancel != null) throw StateError('Concurrent SAPI synthesis');

    final canceled = Completer<void>();
    _activeCancel = canceled;
    try {
      await Future.any<void>([
        NativeWindowsTts.synthesize(
          text: text,
          file: file,
          rate: rate,
          volume: volume,
          voice: voice,
        ),
        canceled.future,
      ]);
      if (canceled.isCompleted) {
        throw StateError('Windows SAPI synthesis cancelled');
      }
    } finally {
      if (identical(_activeCancel, canceled)) {
        _activeCancel = null;
      }
    }
  }

  void abort() {
    NativeWindowsTts.abort();
    final canceled = _activeCancel;
    _activeCancel = null;
    if (canceled != null && !canceled.isCompleted) {
      canceled.complete();
    }
  }

  void close() {
    _closed = true;
    abort();
  }
}
