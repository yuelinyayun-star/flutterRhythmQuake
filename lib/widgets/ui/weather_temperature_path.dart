import 'dart:ui';

Path weatherTemperaturePath(Iterable<Offset?> points) {
  final path = Path();
  Offset? previous;
  for (final point in points) {
    if (point == null) {
      previous = null;
      continue;
    }
    if (previous == null) {
      path.moveTo(point.dx, point.dy);
    } else {
      // Horizontal tangents keep each segment within its observed endpoints.
      final middleX = (previous.dx + point.dx) / 2;
      path.cubicTo(middleX, previous.dy, middleX, point.dy, point.dx, point.dy);
    }
    previous = point;
  }
  return path;
}
