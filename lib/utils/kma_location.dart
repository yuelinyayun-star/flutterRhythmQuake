import 'fe_regions.dart';

/// KMA display names use the same offline coordinate mapping for every origin.
/// Without a valid epicenter, retain the upstream name rather than map (0, 0).
String kmaDisplayLocation(
  String original,
  double? latitude,
  double? longitude,
) {
  if (latitude == null ||
      longitude == null ||
      !latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180 ||
      (latitude == 0 && longitude == 0)) {
    return original;
  }
  final mapped = getFEName(latitude, longitude);
  return mapped.isNotEmpty ? mapped : original;
}
