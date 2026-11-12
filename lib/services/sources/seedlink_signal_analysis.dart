import '../../core/seedlink_activity.dart';
import 'native_seedlink_signal.dart';
import 'seedlink_signal_analysis_dart.dart';

/// Continuous raw-waveform processing, independent for each NSLC.
/// Windows owns numeric state in Rust. Other targets use the existing Dart path.
class SeedLinkSignalAnalysis {
  static bool get usesNative => NativeSeedLinkSignal.supported;
  SeedLinkSignalAnalysis()
    : _native = NativeSeedLinkSignal.supported ? NativeSeedLinkSignal() : null {
    if (_native == null) _dart = DartSeedLinkSignalAnalysis();
  }

  final NativeSeedLinkSignal? _native;
  DartSeedLinkSignalAnalysis? _dart;
  SeedLinkActivity get snapshot => _native?.snapshot ?? _dart!.snapshot;

  SeedLinkActivity accept(List<int> samples, double rate, DateTime start) =>
      _native?.accept(samples, rate, start) ??
      _dart!.accept(samples, rate, start);

  void dispose() => _native?.dispose();
}
