import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/obs_automation_builtin_presets.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/services/native_obs_automation_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing SA production policy crosses Rust and releases output', () {
    var sequence = 0;
    final full = buildEewRecordingPreset(nextId: (p) => '$p-${sequence++}');
    final missing = full.copyWith(
      stacks: full.stacks
          .where(
            (row) => !row.blocks.any(
              (b) =>
                  b.type == ObsAutomationBlockType.eewAgency &&
                  b.parameters['value'] == 'shakeAlert',
            ),
          )
          .toList(),
    );
    final calls = NativeObsAutomationPolicy.calls;
    expect(
      NativeObsAutomationPolicy.missingShakeAlertRules([
        missing,
        full,
        missing.copyWith(name: 'custom'),
      ]),
      [0],
    );
    expect(NativeObsAutomationPolicy.outputs, 0);
    if (NativeObsAutomationPolicy.supported) {
      expect(NativeObsAutomationPolicy.calls, calls + 1);
    }
  });
  test(
    'native selection preserves fixed steps and independently filters rule switches',
    () {
      var sequence = 0;
      final original = buildEewRecordingPreset(
        nextId: (prefix) => '$prefix-${sequence++}',
        enabled: true,
      );
      final preset = original.copyWith(
        stacks: [
          for (var index = 0; index < original.stacks.length; index++)
            original.stacks[index].copyWith(enabled: index.isEven),
        ],
      );
      final before = jsonEncode(preset.toJson());
      final result = NativeObsAutomationPolicy.select([
        preset,
        original.copyWith(enabled: false),
      ]);
      expect(result, hasLength(1));
      expect(result.single.presetIndex, 0);
      expect(result.single.stackIndices, [
        for (var index = 0; index < preset.stacks.length; index += 2) index,
      ]);
      expect(jsonEncode(preset.toJson()), before);
    },
  );

  test(
    'old rule configuration remains enabled and native outputs are released',
    () {
      final old = ObsAutomationPreset.fromJson({
        'id': 'original',
        'name': 'original',
        'enabled': true,
        'stacks': [
          {
            'id': 'one',
            'x': 48,
            'y': 48,
            'blocks': [
              {'id': 'input', 'type': 'unifiedEvent'},
            ],
          },
        ],
      });
      expect(old.stacks.single.enabled, isTrue);
      expect(old.stacks.single.toJson().containsKey('enabled'), isFalse);
      final calls = NativeObsAutomationPolicy.calls;
      for (var count = 0; count < 100; count++) {
        final selected = NativeObsAutomationPolicy.select([old]);
        expect(selected.single.presetIndex, 0);
        expect(selected.single.stackIndices, [0]);
        expect(NativeObsAutomationPolicy.outputs, 0);
      }
      if (NativeObsAutomationPolicy.supported) {
        expect(NativeObsAutomationPolicy.calls - calls, 100);
      }
    },
  );
}
