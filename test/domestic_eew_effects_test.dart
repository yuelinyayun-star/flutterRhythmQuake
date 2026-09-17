import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/domestic_eew_effects.dart';

UnifiedQuakeData report(String source, {String? id, double magnitude = 5}) =>
    UnifiedQuakeData(
      source: source,
      origin: 1,
      eventId: id ?? source,
      isEew: true,
      timeZone: 8,
      titleText: '',
      reportNumText: '第1報',
      useShindo: false,
      maxIntensity: '5',
      className: 'green',
      hypocenter: '',
      originTime: DateTime(2026, 9, 9, 10),
      lat: 30,
      lng: 105,
      magnitude: magnitude,
      depth: 10,
    );

void main() {
  test('identical reports share only fill and threshold flags', () {
    final effects = DomesticEewEffects();
    final a = report('ceaEew');
    final b = report('scEew');
    effects.observe(a);
    expect(effects.claimThresholdSound(a, warn: false), isTrue);
    effects.observe(b);
    expect(effects.shouldDrawFill(a), isTrue);
    expect(effects.shouldDrawFill(b), isFalse);
    expect(effects.claimThresholdSound(b, warn: false), isFalse);
    expect(effects.claimThresholdSound(b, warn: true), isTrue);
    expect(effects.claimThresholdSound(a, warn: true), isFalse);
  });

  test('continued reports replace fill; stalled and late old copies do not', () {
    final effects = DomesticEewEffects();
    final a = report('ceaEew');
    final b = report('scEew');
    effects.observe(a);
    effects.observe(b);
    final updated = b.copyWith(magnitude: 5.8, reportNumText: '第2報');
    effects.observe(updated);
    expect(effects.shouldDrawFill(a), isFalse);
    expect(effects.shouldDrawFill(updated), isTrue);
    final late = report('fjEew');
    effects.observe(late);
    expect(effects.shouldDrawFill(late), isFalse);
    expect(effects.shouldDrawFill(updated), isTrue);
    // Removing the owner must not resurrect a stale fill from a stalled source.
    effects.retainActive([a, late]);
    expect(effects.shouldDrawFill(a), isFalse);
    expect(effects.shouldDrawFill(late), isFalse);
    effects.retainActive([]);
    effects.observe(a);
    expect(effects.shouldDrawFill(a), isTrue);
  });

  test('known older publication cannot replace newer fill', () {
    final effects = DomesticEewEffects();
    final a = report(
      'ceaEew',
    ).copyWith(reportTime: DateTime(2026, 9, 9, 10, 1));
    final b = report('scEew').copyWith(reportTime: a.reportTime);
    effects.observe(a);
    effects.observe(b);
    effects.observe(
      b.copyWith(magnitude: 4.8, reportTime: DateTime(2026, 9, 9, 10, 0, 30)),
    );
    expect(effects.shouldDrawFill(a), isTrue);
    expect(effects.shouldDrawFill(b), isFalse);
  });

  test(
    'does not guess from proximity, IDs, missing values or foreign sources',
    () {
      final a = report('ceaEew');
      final variants = [
        report('scEew').copyWith(lat: 30.001),
        report(
          'scEew',
        ).copyWith(originTime: a.originTime!.add(const Duration(seconds: 1))),
        report('scEew', magnitude: 5.1),
        report('scEew').copyWith(depth: -1),
        report('jmaEew'),
        report('cwaEew'),
        report('kmaEew'),
        report('ceaEew', id: 'another-event'),
      ];
      for (final b in variants) {
        final effects = DomesticEewEffects();
        effects.observe(a);
        effects.claimThresholdSound(a, warn: true);
        effects.observe(b);
        expect(effects.shouldDrawFill(b), isTrue);
        expect(effects.claimThresholdSound(b, warn: true), isTrue);
      }
    },
  );

  test(
    'matching historical report retains sound flags across later revisions',
    () {
      final effects = DomesticEewEffects();
      final a = report('ceaEew');
      effects.observe(a);
      effects.claimThresholdSound(a, warn: true);
      effects.observe(a.copyWith(magnitude: 6));
      final b = report('scEew');
      effects.observe(b);
      expect(effects.claimThresholdSound(b, warn: false), isFalse);
      expect(effects.claimThresholdSound(b, warn: true), isFalse);
      expect(effects.shouldDrawFill(b), isFalse);
    },
  );

  test('normalizes source wall time without rounding physical data', () {
    final effects = DomesticEewEffects();
    final a = report('ceaEew');
    final b = report(
      'scEew',
    ).copyWith(timeZone: 0, originTime: DateTime.utc(2026, 9, 9, 2));
    effects.observe(a);
    effects.observe(b);
    expect(effects.shouldDrawFill(b), isFalse);
  });

  test('newer dated correction may return to previously seen parameters', () {
    final effects = DomesticEewEffects();
    final a = report(
      'ceaEew',
    ).copyWith(reportTime: DateTime(2026, 9, 9, 10, 1));
    final b = report('scEew').copyWith(reportTime: a.reportTime);
    effects.observe(a);
    effects.observe(b);
    effects.observe(
      b.copyWith(magnitude: 5.5, reportTime: DateTime(2026, 9, 9, 10, 2)),
    );
    final corrected = a.copyWith(reportTime: DateTime(2026, 9, 9, 10, 3));
    effects.observe(corrected);
    expect(effects.shouldDrawFill(corrected), isTrue);
    expect(effects.shouldDrawFill(b), isFalse);
  });

  test('later evidence shares already played flags without replaying them', () {
    final effects = DomesticEewEffects();
    final a = report('ceaEew');
    final b = report('scEew', magnitude: 5.1);
    effects.observe(a);
    effects.observe(b);
    effects.claimThresholdSound(a, warn: false);
    effects.claimThresholdSound(b, warn: true);
    final converged = a.copyWith(magnitude: 5.1);
    effects.observe(converged);
    expect(effects.claimThresholdSound(converged, warn: true), isFalse);
    expect([converged, b].where(effects.shouldDrawFill), hasLength(1));
    effects.clear();
    effects.observe(a);
    expect(effects.claimThresholdSound(a, warn: true), isTrue);
  });
}
