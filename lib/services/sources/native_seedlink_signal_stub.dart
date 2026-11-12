import '../../core/seedlink_activity.dart';

class NativeSeedLinkSignal {
  static bool get supported => false;
  SeedLinkActivity get snapshot => const SeedLinkActivity();
  SeedLinkActivity accept(List<int> samples, double rate, DateTime start) =>
      throw UnsupportedError('Native SeedLink signal requires Windows');
  void dispose() {}
}
