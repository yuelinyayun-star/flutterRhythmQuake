const int niedNearbyStationLimit = 6;

double niedDetectionGridDecimalPart(double value) {
  final fraction = (value + 180.0) % 1.0;
  return (fraction * 10.0).roundToDouble() / 10.0;
}

int niedDetectionGridAxisIndex(double value, double decimal) {
  return (value - decimal).round();
}

double niedDetectionGridAxisCenter(int index, double decimal) {
  return index + decimal;
}

String niedDetectionGridKey(int latitudeIndex, int longitudeIndex) {
  return '$latitudeIndex,$longitudeIndex';
}

Set<String> niedDetectionSurroundingGridKeys(Iterable<String> activeGridKeys) {
  final result = <String>{};
  for (final key in activeGridKeys) {
    final parts = key.split(',');
    if (parts.length != 2) continue;
    final latitudeIndex = int.tryParse(parts[0]);
    final longitudeIndex = int.tryParse(parts[1]);
    if (latitudeIndex == null || longitudeIndex == null) continue;
    for (var latitudeOffset = -1; latitudeOffset <= 1; latitudeOffset++) {
      for (var longitudeOffset = -1; longitudeOffset <= 1; longitudeOffset++) {
        result.add(
          niedDetectionGridKey(
            latitudeIndex + latitudeOffset,
            longitudeIndex + longitudeOffset,
          ),
        );
      }
    }
  }
  return result;
}

const Map<int, List<double>> niedActivityThresholds = {
  1: [double.infinity, 10, 14, 16, 18, 19, 20],
  2: [double.infinity, 8, 11, 13, 14, 15, 16],
  3: [double.infinity, 6, 9, 11, 12, 13, 14],
};

double niedStationCountThreshold(int sensitivity, int nearbyCount) {
  return switch (sensitivity) {
    1 => nearbyCount / 2.0 + 1,
    2 => nearbyCount <= 2 ? (nearbyCount + 1) / 2.0 : nearbyCount / 2.0,
    3 => nearbyCount / 2.0,
    _ => double.infinity,
  };
}

double niedActivityThreshold(int sensitivity, int nearbyCount) {
  final thresholds = niedActivityThresholds[sensitivity];
  if (thresholds == null) return double.infinity;
  final index = nearbyCount.clamp(0, niedNearbyStationLimit);
  return thresholds[index];
}

bool isNiedAbnormalStationPair({
  required int firstTriggerStamp,
  required int secondTriggerStamp,
  required double distanceKm,
}) {
  if (firstTriggerStamp <= 0 || secondTriggerStamp <= 0) return false;
  if (!distanceKm.isFinite || distanceKm < 0) return false;
  final maxDiffSeconds = distanceKm / 3.5 + 2;
  final triggerDiffSeconds =
      (firstTriggerStamp - secondTriggerStamp).abs() / 1000.0;
  return maxDiffSeconds < triggerDiffSeconds;
}
