import '../models/obs_automation_preset.dart';
import 'native_obs_automation_policy_types.dart';
export 'native_obs_automation_policy_types.dart';

/// Only used where station-core native execution is not supported.
abstract final class NativeObsAutomationPolicy {
  static bool get supported => false;
  static int get calls => 0;
  static int get outputs => 0;
  static List<int> missingShakeAlertRules(List<ObsAutomationPreset> presets) =>
      [
        for (var index = 0; index < presets.length; index++)
          if (const {
                'EEW 分机构自动录制',
                'EEW M5 分机构自动录制',
              }.contains(presets[index].name) &&
              !presets[index].stacks.any(
                (stack) => stack.blocks.any(
                  (block) =>
                      block.type == ObsAutomationBlockType.eewAgency &&
                      block.parameters['value'] == 'shakeAlert',
                ),
              ))
            index,
      ];
  static bool sourceMatches(
    String? source,
    String expected,
    String operator, {
    bool isJmaLpgm = false,
  }) {
    if (source == null) return false;
    final right = expected.trim().toLowerCase();
    final left = right == 'jmalpgm' && isJmaLpgm
        ? 'jmalpgm'
        : source.trim().toLowerCase();
    return switch (operator) {
      'equals' => left == right,
      'notEquals' => left != right,
      'contains' => left.contains(right),
      'notContains' => !left.contains(right),
      _ => false,
    };
  }

  static Map<String, dynamic> tsunamiProjection(Map<String, dynamic> message) {
    int? instant(String key) {
      final text = message[key]?.toString().trim() ?? '';
      final parsed = DateTime.tryParse(text.replaceAll('/', '-'));
      if (parsed == null) return null;
      if (RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text)) {
        return parsed.toUtc().millisecondsSinceEpoch;
      }
      return DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          )
          .subtract(Duration(hours: message['timeZone'] as int? ?? 0))
          .millisecondsSinceEpoch;
    }

    return {
      'source': 'obs_tsunami_${message['source'] ?? ''}',
      'eventId': (message['eventId'] as String?)?.isNotEmpty == true
          ? message['eventId']
          : message['id'] ?? '',
      'originUtcMs': instant('originTime'),
      'reportUtcMs': instant('reportTime'),
      'latitude': message['epicenterLat'],
      'longitude': message['epicenterLng'],
      'magnitude': message['magnitude'],
      'depth': message['depth'],
    };
  }

  static List<ObsEnabledRules> select(List<ObsAutomationPreset> presets) => [
    for (var p = 0; p < presets.length; p++)
      if (presets[p].enabled)
        (
          presetIndex: p,
          stackIndices: [
            for (var s = 0; s < presets[p].stacks.length; s++)
              if (presets[p].stacks[s].enabled) s,
          ],
        ),
  ];
}
