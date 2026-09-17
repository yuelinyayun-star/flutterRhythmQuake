import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/background_source_reload_plan.dart';

void main() {
  test('profile, observation caches and UI history never reconnect stations', () {
    for (final key in BackgroundSourceReloadPlan.runtimeKeys) {
      final plan = BackgroundSourceReloadPlan({key: 'old'}, {key: 'new'});
      expect(plan.requiresFullReload, isFalse, reason: key);
      expect(plan.stations, isEmpty, reason: key);
    }
  });
  test('unchanged settings and persisted event history do not reconnect', () {
    final plan = BackgroundSourceReloadPlan(
      {
        'nied_data_source': 'lmoni',
        'seen_usgs_info_body_keys': ['old'],
      },
      {
        'nied_data_source': 'lmoni',
        'seen_usgs_info_body_keys': ['new'],
      },
    );
    expect(plan.requiresFullReload, isFalse);
    expect(plan.stations, isEmpty);
  });
  test('NIED source selection only reloads NIED', () {
    final plan = BackgroundSourceReloadPlan(
      {'nied_data_source': 'lmoni', 'api_source_palert_enabled': true},
      {'nied_data_source': 'kmoni', 'api_source_palert_enabled': true},
    );
    expect(plan.requiresFullReload, isFalse);
    expect(plan.stations, {'nied'});
  });
  test('each supported switch, including disable, targets its station', () {
    for (final entry in BackgroundSourceReloadPlan.stationKeys.entries) {
      final plan = BackgroundSourceReloadPlan(
        {entry.key: true},
        {entry.key: false},
      );
      expect(plan.requiresFullReload, isFalse);
      expect(plan.stations, {entry.value});
    }
  });
  test('auth, filters and unknown settings retain full reload semantics', () {
    for (final key in [
      'api_source_whews_authorized',
      'api_source_jian_enabled',
      'source_mag_filter_jma',
      'future_setting',
    ]) {
      final plan = BackgroundSourceReloadPlan({key: 0}, {key: 1});
      expect(plan.requiresFullReload, isTrue);
    }
  });
  test('list preferences compare contents rather than object identity', () {
    final plan = BackgroundSourceReloadPlan(
      {
        'list': ['a'],
      },
      {
        'list': ['a'],
      },
    );
    expect(plan.requiresFullReload, isFalse);
  });
}
