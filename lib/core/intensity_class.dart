/// Shared application palette for reported and presentation-only intensities.
String intensityClassName(double intensity, {bool useShindo = false}) {
  if (useShindo) {
    if (intensity >= 7.0) return 'purple';
    if (intensity >= 6.5) return 'dark-red';
    if (intensity >= 6.0) return 'red';
    if (intensity >= 5.5) return 'dark-orange';
    if (intensity >= 5.0) return 'orange';
    if (intensity >= 4.0) return 'yellow';
    if (intensity >= 3.0) return 'green';
    if (intensity >= 2.0) return 'blue';
    if (intensity >= 1.0) return 'gray';
    return 'dark-gray';
  }
  final level = intensity.round();
  if (level >= 10) return 'purple';
  if (level == 9) return 'red';
  if (level == 8) return 'dark-orange';
  if (level == 7) return 'orange';
  if (level == 6) return 'yellow';
  if (level == 5) return 'green';
  if (level == 4) return 'blue';
  if (level == 3) return 'sky-blue';
  if (level == 2) return 'gray';
  if (level == 1) return 'dark-gray';
  return 'gray';
}
