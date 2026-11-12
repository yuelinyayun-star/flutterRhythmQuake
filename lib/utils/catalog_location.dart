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
  if (original.trim() != '未知地区' &&
      original.trim() != '韩国附近' &&
      RegExp(r'[\u4e00-\u9fff]').hasMatch(original)) {
    return original;
  }
  if (!hasCatalogCoordinates(lat, lng)) {
    return original.trim() == '韩国附近'
        ? '未知'
        : translateFERegionName(original) ?? original;
  }
  final mapped = getFEName(lat!, lng!);
  return mapped.isEmpty ? original : mapped;
}
