/// Chooses which local weather provider should be active for a coordinate.
class LocalWeatherRegion {
  static bool usesJapan(double lat, double lng) {
    return _isInJapan(lat, lng);
  }

  static bool usesChina(double lat, double lng) {
    if (_isInTaiwan(lat, lng)) return false;
    return _isInChina(lat, lng) && !_isInJapan(lat, lng);
  }

  static bool _isInChina(double lat, double lon) {
    return lat >= 18.0 && lat <= 54.0 && lon >= 73.0 && lon <= 135.0;
  }

  static bool _isInJapan(double lat, double lon) {
    if (_isKoreanPeninsula(lat, lon)) return false;
    if (lat >= 24.0 && lat <= 31.2 && lon >= 122.8 && lon <= 131.5) {
      return true;
    }
    return lat >= 30.2 && lat <= 45.8 && lon >= 129.2 && lon <= 146.0;
  }

  static bool _isKoreanPeninsula(double lat, double lon) {
    if (lat < 33.0 || lat > 38.8 || lon < 124.4 || lon > 129.55) {
      return false;
    }
    final tsushimaOrIki =
        lat >= 33.7 && lat <= 34.85 && lon >= 129.15 && lon <= 129.55;
    return !tsushimaOrIki;
  }

  static bool _isInTaiwan(double lat, double lon) {
    return lat >= 21.0 && lat <= 26.0 && lon >= 119.0 && lon <= 122.0;
  }
}
