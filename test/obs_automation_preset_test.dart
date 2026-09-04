import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/obs_automation_value_expression.dart';

void main() {
  test('nested value expression JSON preserves every original operand', () {
    const expression = ObsAutomationValueNode.operation(
      'arithmetic',
      options: {'operator': 'add'},
      arguments: [
        ObsAutomationValueNode.inputField('magnitude', family: 'unified'),
        ObsAutomationValueNode.operation(
          'round',
          arguments: [ObsAutomationValueNode.variable('偏移')],
        ),
      ],
    );
    final decoded = ObsAutomationValueNode.tryDecode(expression.encode());

    expect(decoded?.toJson(), expression.toJson());
  });

  test('OBS automation canvas preserves stacks, positions and block order', () {
    const document = ObsAutomationPresetDocument(
      presets: [
        ObsAutomationPreset(
          id: 'preset-1',
          name: '强震录制',
          enabled: true,
          stacks: [
            ObsAutomationStack(
              id: 'stack-1',
              x: 124.5,
              y: 86.0,
              blocks: [
                ObsAutomationBlock(
                  id: 'block-1',
                  type: ObsAutomationBlockType.unifiedEvent,
                ),
                ObsAutomationBlock(
                  id: 'block-2',
                  type: ObsAutomationBlockType.estimatedIntensity,
                  parameters: {
                    'operator': 'greaterThanOrEqual',
                    'value': '5.0',
                  },
                ),
                ObsAutomationBlock(
                  id: 'block-3',
                  type: ObsAutomationBlockType.saveReplayBuffer,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final decoded = ObsAutomationPresetDocument.fromJson(document.toJson());
    final preset = decoded.presets.single;
    final stack = preset.stacks.single;

    expect(preset.name, '强震录制');
    expect(preset.enabled, isTrue);
    expect(stack.x, 124.5);
    expect(stack.y, 86.0);
    expect(stack.blocks.map((block) => block.type), [
      ObsAutomationBlockType.unifiedEvent,
      ObsAutomationBlockType.estimatedIntensity,
      ObsAutomationBlockType.saveReplayBuffer,
    ]);
    expect(stack.blocks[1].parameters['value'], '5.0');
  });

  test('schema version 1 form presets migrate into a block stack', () {
    final document = ObsAutomationPresetDocument.fromJson({
      'schemaVersion': 1,
      'presets': [
        {
          'id': 'legacy-preset',
          'name': '旧预设',
          'enabled': true,
          'trigger': 'unifiedEventUpdated',
          'conditions': [
            {
              'id': 'legacy-condition',
              'field': 'magnitude',
              'operator': 'greaterThanOrEqual',
              'value': '5.5',
            },
          ],
          'actions': [
            {
              'id': 'legacy-action',
              'type': 'createRecordChapter',
              'parameter': '地震事件',
            },
          ],
        },
      ],
    });

    final stack = document.presets.single.stacks.single;
    expect(stack.blocks, hasLength(4));
    expect(stack.blocks[0].type, ObsAutomationBlockType.unifiedEvent);
    expect(stack.blocks[1].type, ObsAutomationBlockType.unifiedPhase);
    expect(stack.blocks[1].parameters['value'], 'updated');
    expect(stack.blocks[2].type, ObsAutomationBlockType.magnitude);
    expect(stack.blocks[2].parameters['value'], '5.5');
    expect(stack.blocks[3].type, ObsAutomationBlockType.createRecordChapter);
    expect(stack.blocks[3].parameters['text'], '地震事件');
  });

  test('schema version 2 input filters migrate into condition blocks', () {
    final document = ObsAutomationPresetDocument.fromJson({
      'schemaVersion': 2,
      'presets': [
        {
          'id': 'v2-preset',
          'name': '旧台网条件',
          'enabled': true,
          'stacks': [
            {
              'id': 'stack-1',
              'x': 10,
              'y': 20,
              'blocks': [
                {
                  'id': 'input-1',
                  'type': 'networkDetection',
                  'parameters': {'network': 'nied', 'phase': 'strong'},
                },
                {'id': 'action-1', 'type': 'startRecord'},
              ],
            },
          ],
        },
      ],
    });

    final blocks = document.presets.single.stacks.single.blocks;
    expect(blocks, hasLength(3));
    expect(blocks[0].parameters, const {'network': 'nied'});
    expect(blocks[1].type, ObsAutomationBlockType.networkPhase);
    expect(blocks[1].parameters, const {
      'operator': 'equals',
      'value': 'strong',
    });
    expect(blocks[2].type, ObsAutomationBlockType.startRecord);
  });
}
