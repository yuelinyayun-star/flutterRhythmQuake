import 'fe_regions.dart';

bool hasCatalogCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    (latitude != 0 || longitude != 0);

/// Preserve upstream Chinese names; map foreign catalog names offline.
String catalogDisplayLocation(String original, double? lat, double? lng) {
  if (!hasCatalogCoordinates(lat, lng) ||
      RegExp(r'[\u4e00-\u9fff]').hasMatch(original)) {
    return original;
  }
  final mapped = getFEName(lat!, lng!);
  return mapped.isEmpty ? original : mapped;
}
