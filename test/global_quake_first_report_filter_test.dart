import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/global_quake_first_report_filter.dart';

void main() {
  test('GQ filter locks rejection to the first received report magnitude', () {
    final filter = GlobalQuakeFirstReportMagnitudeFilter(threshold: 5.0);

    final first = filter.evaluate(eventId: 'event-a', magnitude: 4.8);
    final update = filter.evaluate(eventId: 'event-a', magnitude: 6.2);

    expect(first.isFirstReceivedReport, isTrue);
    expect(first.allowed, isFalse);
    expect(first.firstMagnitude, 4.8);
    expect(update.isFirstReceivedReport, isFalse);
    expect(update.allowed, isFalse);
    expect(update.firstMagnitude, 4.8);
  });

  test('GQ filter locks acceptance to the first received report magnitude', () {
    final filter = GlobalQuakeFirstReportMagnitudeFilter(threshold: 5.0);

    final first = filter.evaluate(eventId: 'event-b', magnitude: 5.1);
    final update = filter.evaluate(eventId: 'event-b', magnitude: 3.9);

    expect(first.allowed, isTrue);
    expect(update.allowed, isTrue);
    expect(update.firstMagnitude, 5.1);
  });

  test('changing the threshold starts a new first-report decision window', () {
    final filter = GlobalQuakeFirstReportMagnitudeFilter(threshold: 5.0);
    expect(
      filter.evaluate(eventId: 'event-c', magnitude: 4.9).allowed,
      isFalse,
    );

    filter.configure(4.0);
    final next = filter.evaluate(eventId: 'event-c', magnitude: 4.2);

    expect(next.isFirstReceivedReport, isTrue);
    expect(next.allowed, isTrue);
    expect(next.firstMagnitude, 4.2);
  });

  test('zero threshold disables filtering', () {
    final filter = GlobalQuakeFirstReportMagnitudeFilter();

    expect(filter.evaluate(eventId: 'event-d', magnitude: -1).allowed, isTrue);
    expect(filter.evaluate(eventId: 'event-d', magnitude: 1).allowed, isTrue);
  });
}
