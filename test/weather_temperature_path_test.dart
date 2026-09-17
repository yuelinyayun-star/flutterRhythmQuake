import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/weather_temperature_path.dart';

void main() {
  test('curve passes endpoints without overshoot and has smooth joins', () {
    const points = [Offset(0, 80), Offset(90, 20), Offset(180, 65)];
    final path = weatherTemperaturePath(points);
    final metric = path.computeMetrics().single;
    expect(metric.getTangentForOffset(0)!.position.dx, closeTo(0, .01));
    expect(
      metric.getTangentForOffset(metric.length)!.position.dy,
      closeTo(65, .01),
    );
    expect(metric.getTangentForOffset(0)!.vector.dy, closeTo(0, .001));
    expect(
      metric.getTangentForOffset(metric.length)!.vector.dy,
      closeTo(0, .001),
    );
    for (var i = 0; i <= 200; i++) {
      final point = metric
          .getTangentForOffset(metric.length * i / 200)!
          .position;
      expect(point.dy, inInclusiveRange(19.99, point.dx <= 90 ? 80.01 : 65.01));
    }
    final first = weatherTemperaturePath(
      points.take(2),
    ).computeMetrics().single;
    final second = weatherTemperaturePath(
      points.skip(1),
    ).computeMetrics().single;
    expect(first.getTangentForOffset(first.length)!.position, points[1]);
    expect(second.getTangentForOffset(0)!.position, points[1]);
    expect(
      first.getTangentForOffset(first.length)!.vector.dy,
      closeTo(0, .001),
    );
    expect(second.getTangentForOffset(0)!.vector.dy, closeTo(0, .001));
    // At the start, the curve is not the old straight diagonal.
    final nearStart = first.getTangentForOffset(first.length * .1)!.position;
    final straightY = 80 - nearStart.dx * 60 / 90;
    expect(nearStart.dy, greaterThan(straightY + 1));
  });

  test('missing readings leave separate contours', () {
    final path = weatherTemperaturePath(const [
      Offset(0, 80),
      Offset(90, 20),
      null,
      Offset(270, 50),
      Offset(360, 30),
    ]);
    final contours = path.computeMetrics().toList();
    expect(contours, hasLength(2));
    expect(
      contours[0].getTangentForOffset(contours[0].length)!.position.dx,
      90,
    );
    expect(contours[1].getTangentForOffset(0)!.position.dx, 270);
  });

  test('flat and empty series stay flat or empty', () {
    expect(weatherTemperaturePath(const []).computeMetrics(), isEmpty);
    expect(weatherTemperaturePath(const [null]).computeMetrics(), isEmpty);
    final metric = weatherTemperaturePath(const [
      Offset(0, 50),
      Offset(90, 50),
    ]).computeMetrics().single;
    for (var i = 0; i <= 10; i++) {
      expect(
        metric.getTangentForOffset(metric.length * i / 10)!.position.dy,
        50,
      );
    }
  });
}
