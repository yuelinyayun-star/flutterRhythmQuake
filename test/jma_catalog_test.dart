import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/jma_catalog.dart';

void main() {
  final catalog = JmaCatalog.fromJson({
    'schemaVersion': 1,
    'catalogId': 'jma-test-202606',
    'revision': '2026-06-21T00:00:00Z',
    'sourceUrl': 'https://example.test/jma/catalog',
    'generatedAt': '2026-06-21T00:00:00Z',
    'events': [
      {
        'eventId': 'event-a',
        'resourceId': 'jma:event-a',
        'revision': 'final-1',
        'status': 'final',
        'originTime': '2026-06-20T12:25:27Z',
        'latitude': 39.893,
        'longitude': 142.512,
        'depthKm': 38,
        'magnitude': 3.4,
        'region': 'Iwate offshore',
        'sourceUrl': 'https://example.test/jma/event-a',
      },
      {
        'eventId': 'event-b',
        'resourceId': 'jma:event-b',
        'revision': 'final-1',
        'status': 'final',
        'originTime': '2026-06-20T12:30:00Z',
        'latitude': 40.5,
        'longitude': 143,
        'depthKm': 20,
        'magnitude': 4.2,
        'region': 'Offshore',
        'sourceUrl': null,
      },
    ],
  });

  test('validates a versioned final JMA catalog', () {
    expect(catalog.validate(), isEmpty);
  });

  test('matches by time, distance, and magnitude', () {
    final result = const JmaCatalogMatcher().match(
      catalog,
      JmaCatalogReference(
        originTime: DateTime.utc(2026, 6, 20, 12, 25, 30),
        latitude: 39.9,
        longitude: 142.5,
        magnitude: 3.5,
      ),
    );

    expect(result.status, JmaCatalogMatchStatus.matched);
    expect(result.match?.event.eventId, 'event-a');
    expect(result.match?.timeDifferenceSeconds, 3);
    expect(result.match?.distanceKm, lessThan(2));
  });

  test('does not force a match outside the gates', () {
    final result = const JmaCatalogMatcher().match(
      catalog,
      JmaCatalogReference(
        originTime: DateTime.utc(2026, 6, 20, 15),
        latitude: 35,
        longitude: 135,
        magnitude: 3,
      ),
    );

    expect(result.status, JmaCatalogMatchStatus.noMatch);
    expect(result.match, isNull);
  });

  test('requires review when the two best candidates are too close', () {
    final ambiguousCatalog = JmaCatalog.fromJson({
      'schemaVersion': 1,
      'catalogId': 'ambiguous',
      'revision': 'r1',
      'sourceUrl': 'https://example.test/catalog',
      'generatedAt': '2026-06-21T00:00:00Z',
      'events': [
        for (final suffix in ['a', 'b'])
          {
            'eventId': suffix,
            'resourceId': 'jma:$suffix',
            'revision': 'final',
            'status': 'final',
            'originTime': suffix == 'a'
                ? '2026-06-20T12:00:00Z'
                : '2026-06-20T12:00:01Z',
            'latitude': 36.0,
            'longitude': 141.0,
            'depthKm': 10,
            'magnitude': 2.0,
            'region': 'test',
            'sourceUrl': null,
          },
      ],
    });

    final result = const JmaCatalogMatcher().match(
      ambiguousCatalog,
      JmaCatalogReference(
        originTime: DateTime.utc(2026, 6, 20, 12),
        latitude: 36,
        longitude: 141,
        magnitude: 2,
      ),
    );

    expect(result.status, JmaCatalogMatchStatus.ambiguous);
    expect(result.match, isNull);
  });
}
