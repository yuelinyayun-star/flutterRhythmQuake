/// Explicit implementation for platforms without station-core native support.
abstract final class NativeWeatherMapPolicy {
  static bool get supported => false;
  static int requiredSources(int general, int mobile) =>
      (general | mobile) & 0x7f;
}
