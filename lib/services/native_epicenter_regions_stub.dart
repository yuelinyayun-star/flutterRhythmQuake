abstract final class NativeEpicenterRegions {
  static bool get supported => false;

  static void prepare() => throw UnsupportedError('Native epicenter regions');

  static String? lookup(
    double latitude,
    double longitude, {
    bool chinaOnly = false,
  }) => throw UnsupportedError('Native epicenter regions');
}
