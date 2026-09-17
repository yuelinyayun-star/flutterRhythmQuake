import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/obs_automation_preset.dart';
import '../../models/obs_automation_builtin_presets.dart';
import '../../models/obs_automation_value_expression.dart';
import '../../services/obs_automation_input_service.dart';
import '../../services/obs_automation_runtime_service.dart';
import '../../services/obs_websocket_service.dart';

class ObsAutomationPresetsPage extends StatefulWidget {
  const ObsAutomationPresetsPage({super.key});

  @override
  State<ObsAutomationPresetsPage> createState() =>
      _ObsAutomationPresetsPageState();
}

enum _PaletteCategory {
  events,
  logic,
  operators,
  uiConditions,
  stationConditions,
  variables,
  control,
  obs,
}

class _ObsAutomationPresetsPageState extends State<ObsAutomationPresetsPage> {
  static const _preferenceKey = obsAutomationPresetsPreferenceKey;
  static const _accent = Color(0xFF82B1FF);
  static const _panel = Color.fromRGBO(42, 43, 49, 0.82);
  static const _surface = Color.fromRGBO(25, 26, 31, 0.82);
  static const _border = Color.fromRGBO(255, 255, 255, 0.16);
  static const _muted = Color.fromRGBO(255, 255, 255, 0.58);
  static const _eventColor = Color(0xFFE3A018);
  static const _logicColor = Color(0xFF4E9B43);
  static const _operatorColor = Color(0xFF65A83E);
  static const _uiConditionColor = Color(0xFF2E9D78);
  static const _stationConditionColor = Color(0xFF3478B9);
  static const _variableColor = Color(0xFFD85D5D);
  static const _controlColor = Color(0xFFE57A35);
  static const _obsColor = Color(0xFFB65ACF);
  static const _blockWidth = 640.0;
  static const _blockHeight = 58.0;
  static const _blockPitch = 52.0;
  static const _canvasExtraWidth = 360.0;
  static const _canvasExtraHeight = 300.0;
  static const _inputHatTypes = <ObsAutomationBlockType>{
    ObsAutomationBlockType.unifiedEvent,
    ObsAutomationBlockType.networkDetection,
    ObsAutomationBlockType.stationChange,
  };
  static const _uiConditionTypes = <ObsAutomationBlockType>{
    ObsAutomationBlockType.unifiedPhase,
    ObsAutomationBlockType.isEew,
    ObsAutomationBlockType.isInformation,
    ObsAutomationBlockType.eewAgency,
    ObsAutomationBlockType.informationAgency,
    ObsAutomationBlockType.informationReviewType,
    ObsAutomationBlockType.eventType,
    ObsAutomationBlockType.source,
    ObsAutomationBlockType.magnitude,
    ObsAutomationBlockType.estimatedIntensity,
    ObsAutomationBlockType.reportNumber,
    ObsAutomationBlockType.isFinal,
  };
  static const _stationConditionTypes = <ObsAutomationBlockType>{
    ObsAutomationBlockType.networkPhase,
    ObsAutomationBlockType.stationPhase,
    ObsAutomationBlockType.networkMaxIntensity,
    ObsAutomationBlockType.detectedStationCount,
    ObsAutomationBlockType.stationId,
    ObsAutomationBlockType.stationName,
    ObsAutomationBlockType.currentStationIntensity,
    ObsAutomationBlockType.previousStationIntensity,
  };
  static const _variableConditionTypes = <ObsAutomationBlockType>{
    ObsAutomationBlockType.sameEarthquakeAsVariable,
    ObsAutomationBlockType.valueVariableCondition,
    ObsAutomationBlockType.inputFieldMatchesVariable,
  };
  static const _conditionTypes = <ObsAutomationBlockType>{
    ..._uiConditionTypes,
    ..._stationConditionTypes,
    ..._variableConditionTypes,
    ObsAutomationBlockType.inputFieldCondition,
    ObsAutomationBlockType.compareValues,
  };
  static const _expressionReporterTypes = <ObsAutomationBlockType>{
    ObsAutomationBlockType.arithmeticValue,
    ObsAutomationBlockType.randomValue,
    ObsAutomationBlockType.moduloValue,
    ObsAutomationBlockType.roundValue,
    ObsAutomationBlockType.mathValue,
    ObsAutomationBlockType.textJoinValue,
    ObsAutomationBlockType.textLengthValue,
    ObsAutomationBlockType.textContainsValue,
    ObsAutomationBlockType.comparisonValue,
    ObsAutomationBlockType.booleanValue,
    ObsAutomationBlockType.notValue,
  };
  static const _actionTypes = <ObsAutomationBlockType>{
    ObsAutomationBlockType.wait,
    ObsAutomationBlockType.waitForInput,
    ObsAutomationBlockType.setEventVariable,
    ObsAutomationBlockType.setValueVariable,
    ObsAutomationBlockType.setVariable,
    ObsAutomationBlockType.changeVariable,
    ObsAutomationBlockType.stopScript,
    ObsAutomationBlockType.startRecord,
    ObsAutomationBlockType.stopRecord,
    ObsAutomationBlockType.pauseRecord,
    ObsAutomationBlockType.resumeRecord,
    ObsAutomationBlockType.splitRecordFile,
    ObsAutomationBlockType.createRecordChapter,
    ObsAutomationBlockType.setTextSourceText,
    ObsAutomationBlockType.setCurrentProgramScene,
    ObsAutomationBlockType.setSceneItemEnabled,
    ObsAutomationBlockType.startReplayBuffer,
    ObsAutomationBlockType.stopReplayBuffer,
    ObsAutomationBlockType.saveReplayBuffer,
  };
  static const _shindoValues = <String, String>{
    '0': '0',
    '1': '1',
    '2': '2',
    '3': '3',
    '4': '4',
    '5': '5弱',
    '6': '5强',
    '7': '6弱',
    '8': '6强',
    '9': '7',
  };
  static const _numericOperators = <String, String>{
    'equals': '=',
    'notEquals': '≠',
    'greaterThan': '>',
    'greaterThanOrEqual': '≥',
    'lessThan': '<',
    'lessThanOrEqual': '≤',
  };
  static const _textOperators = <String, String>{
    'equals': '等于',
    'notEquals': '不等于',
    'contains': '包含',
    'notContains': '不包含',
  };
  static const _dynamicOperators = <String, String>{
    'equals': '=',
    'notEquals': '≠',
    'greaterThan': '>',
    'greaterThanOrEqual': '≥',
    'lessThan': '<',
    'lessThanOrEqual': '≤',
    'contains': '包含',
    'notContains': '不包含',
  };
  static final _inputFieldValues = <String, String>{
    for (final field in obsAutomationInputFields) field.key: field.label,
  };

  final GlobalKey _canvasKey = GlobalKey();
  final ScrollController _categoryController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final ValueNotifier<_SnapTarget?> _activeSnapNotifier = ValueNotifier(null);

  List<ObsAutomationPreset> _presets = const [];
  String? _selectedId;
  _PaletteCategory _category = _PaletteCategory.events;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  int _idSequence = 0;
  Size _currentCanvasSize = const Size(1360, 900);
  String _selectedUnifiedInputField = 'eventType';
  String _selectedStationInputField = 'network';
  String? _selectedValueVariable;
  int? _canvasPanPointer;

  ObsAutomationPreset? get _selectedPreset {
    final id = _selectedId;
    if (id == null) return null;
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  List<String> get _availableValueVariables {
    final names = <String>{};
    for (final stack in _selectedPreset?.stacks ?? const []) {
      for (final block in stack.blocks) {
        if (block.type != ObsAutomationBlockType.setValueVariable &&
            block.type != ObsAutomationBlockType.setVariable &&
            block.type != ObsAutomationBlockType.changeVariable) {
          continue;
        }
        final name = block.parameters['name']?.trim() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
    }
    return names.toList(growable: false)..sort();
  }

  String get _activeValueVariable {
    final variables = _availableValueVariables;
    final selected = _selectedValueVariable;
    if (selected != null && variables.contains(selected)) return selected;
    return variables.isEmpty ? '变量' : variables.first;
  }

  bool _isInputHat(ObsAutomationBlockType type) =>
      _inputHatTypes.contains(type);

  bool _isCondition(ObsAutomationBlockType type) =>
      _conditionTypes.contains(type);

  bool _isAction(ObsAutomationBlockType type) => _actionTypes.contains(type);

  bool _isValueReporter(ObsAutomationBlockType type) =>
      type == ObsAutomationBlockType.inputFieldValue ||
      type == ObsAutomationBlockType.variableValue ||
      _expressionReporterTypes.contains(type);

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _horizontalController.dispose();
    _verticalController.dispose();
    _activeSnapNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_preferenceKey);
    var loaded = <ObsAutomationPreset>[];
    String? error;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException('invalid root');
        loaded = ObsAutomationPresetDocument.fromJson(
          Map<String, dynamic>.from(decoded),
        ).presets;
      } catch (_) {
        error = 'OBS 自动化预设读取失败，原配置未被覆盖';
      }
    }
    var builtInAdded = false;
    ObsAutomationPreset? builtInPreset;
    if (error == null) {
      for (final preset in loaded) {
        if (preset.name == obsEewM5RecordingPresetName) {
          builtInPreset = preset;
          break;
        }
      }
      if (builtInPreset == null) {
        builtInPreset = buildEewM5RecordingPreset(nextId: _newId);
        loaded = [...loaded, builtInPreset];
        builtInAdded = true;
      }
    }
    final onlyDefaultBlankPresets = loaded
        .where((preset) => preset.id != builtInPreset?.id)
        .every((preset) => preset.name == '新建 OBS 预设' && preset.stacks.isEmpty);
    final selectedId = builtInPreset != null && onlyDefaultBlankPresets
        ? builtInPreset.id
        : (loaded.isEmpty ? null : loaded.first.id);
    if (!mounted) return;
    setState(() {
      _presets = loaded;
      _selectedId = selectedId;
      _loading = false;
      _dirty = builtInAdded;
    });
    if (error != null) _showMessage(error);
  }

  String _newId(String prefix) {
    _idSequence++;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idSequence';
  }

  ObsAutomationPreset _blankPreset() {
    return ObsAutomationPreset(
      id: _newId('preset'),
      name: '新建 OBS 预设',
      enabled: false,
      stacks: const [],
    );
  }

  void _createPreset() {
    final preset = _blankPreset();
    setState(() {
      _presets = [..._presets, preset];
      _selectedId = preset.id;
      _dirty = true;
    });
  }

  void _createEewM5RecordingPreset() {
    for (final preset in _presets) {
      if (preset.name == obsEewM5RecordingPresetName) {
        setState(() => _selectedId = preset.id);
        return;
      }
    }
    final preset = buildEewM5RecordingPreset(nextId: _newId);
    setState(() {
      _presets = [..._presets, preset];
      _selectedId = preset.id;
      _dirty = true;
    });
  }

  void _duplicatePreset() {
    final source = _selectedPreset;
    if (source == null) return;
    final copy = ObsAutomationPreset(
      id: _newId('preset'),
      name: '${source.name} 副本',
      enabled: false,
      stacks: source.stacks
          .map(
            (stack) => ObsAutomationStack(
              id: _newId('stack'),
              x: stack.x + 28,
              y: stack.y + 28,
              blocks: stack.blocks
                  .map(
                    (block) => ObsAutomationBlock(
                      id: _newId('block'),
                      type: block.type,
                      parameters: Map<String, String>.from(block.parameters),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
    setState(() {
      _presets = [..._presets, copy];
      _selectedId = copy.id;
      _dirty = true;
    });
  }

  Future<void> _renamePreset() async {
    final preset = _selectedPreset;
    if (preset == null) return;
    final controller = TextEditingController(text: preset.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF202127),
        title: const Text('重命名预设'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '预设名称'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    _updateSelected((item) => item.copyWith(name: name.trim()));
  }

  Future<void> _deletePreset() async {
    final preset = _selectedPreset;
    if (preset == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF202127),
        title: const Text('删除预设'),
        content: Text('删除“${preset.name}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final remaining = _presets.where((item) => item.id != preset.id).toList();
    if (remaining.isEmpty) remaining.add(_blankPreset());
    setState(() {
      _presets = remaining;
      _selectedId = remaining.first.id;
      _dirty = true;
    });
  }

  void _updateSelected(
    ObsAutomationPreset Function(ObsAutomationPreset preset) transform,
  ) {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    setState(() {
      _presets = _presets
          .map((preset) => preset.id == selectedId ? transform(preset) : preset)
          .toList();
      _dirty = true;
    });
  }

  Future<void> _savePresets() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(
        ObsAutomationPresetDocument(presets: _presets).toJson(),
      );
      if (!await prefs.setString(_preferenceKey, payload)) {
        throw StateError('SharedPreferences rejected write');
      }
      await ObsAutomationRuntimeService().reloadPresets(preferences: prefs);
      if (!mounted) return;
      setState(() => _dirty = false);
      _showMessage('OBS 自动化预设已保存');
    } catch (_) {
      if (mounted) _showMessage('OBS 自动化预设保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openConnectionSettings() async {
    final runtime = ObsAutomationRuntimeService();
    final settings = await runtime.loadConnectionSettings();
    if (!mounted) return;
    final hostController = TextEditingController(text: settings.host);
    final portController = TextEditingController(
      text: settings.port.toString(),
    );
    final passwordController = TextEditingController(text: settings.password);
    var enabled = settings.enabled;
    var autoReconnect = settings.autoReconnect;
    var obscurePassword = true;
    final result = await showDialog<_ObsConnectionFormValue>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF202127),
          title: const Text('OBS WebSocket'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用连接'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  TextField(
                    controller: hostController,
                    enabled: enabled,
                    decoration: const InputDecoration(labelText: '主机地址'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: portController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '端口'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    enabled: enabled,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      suffixIcon: IconButton(
                        tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: enabled
                            ? () => setDialogState(
                                () => obscurePassword = !obscurePassword,
                              )
                            : null,
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('断线自动重连'),
                    value: autoReconnect,
                    onChanged: enabled
                        ? (value) => setDialogState(() => autoReconnect = value)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final port = int.tryParse(portController.text.trim());
                if (port == null || port < 1 || port > 65535) {
                  _showMessage('OBS 端口必须为 1 到 65535');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _ObsConnectionFormValue(
                    enabled: enabled,
                    host: hostController.text,
                    port: port,
                    password: passwordController.text,
                    autoReconnect: autoReconnect,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    hostController.dispose();
    portController.dispose();
    passwordController.dispose();
    if (result == null || !mounted) return;
    try {
      await runtime.configureConnection(
        enabled: result.enabled,
        host: result.host,
        port: result.port,
        password: result.password,
        autoReconnect: result.autoReconnect,
      );
      if (mounted) _showMessage(result.enabled ? 'OBS 连接配置已保存' : 'OBS 连接已关闭');
    } catch (error) {
      if (mounted) _showMessage('OBS 连接失败：$error');
    }
  }

  String _connectionStateLabel(ObsConnectionState state) => switch (state) {
    ObsConnectionState.disconnected => '未连接',
    ObsConnectionState.connecting => '连接中',
    ObsConnectionState.authenticating => '认证中',
    ObsConnectionState.connected => '已连接',
    ObsConnectionState.reconnecting => '重连中',
    ObsConnectionState.authenticationFailed => '认证失败',
    ObsConnectionState.unsupported => '版本不支持',
    ObsConnectionState.error => '连接错误',
  };

  Color _connectionStateColor(ObsConnectionState state) => switch (state) {
    ObsConnectionState.connected => const Color(0xFF58C77B),
    ObsConnectionState.connecting ||
    ObsConnectionState.authenticating ||
    ObsConnectionState.reconnecting => const Color(0xFFFFC857),
    ObsConnectionState.authenticationFailed ||
    ObsConnectionState.unsupported ||
    ObsConnectionState.error => const Color(0xFFE86666),
    ObsConnectionState.disconnected => _muted,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020208),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _panel,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        _buildToolbar(),
                        const Divider(height: 1, color: _border),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final paletteWidth = constraints.maxWidth < 700
                                  ? 176.0
                                  : 260.0;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: paletteWidth,
                                    child: _buildPalette(),
                                  ),
                                  const VerticalDivider(
                                    width: 1,
                                    color: _border,
                                  ),
                                  Expanded(child: _buildCanvas()),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final title = Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                'OBS 自动化',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (_dirty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('未保存', style: TextStyle(color: Color(0xFFFFC857))),
              ),
            ValueListenableBuilder<ObsConnectionState>(
              valueListenable:
                  ObsAutomationRuntimeService().obs.connectionStateNotifier,
              builder: (context, state, _) => TextButton.icon(
                key: const ValueKey('obs-connection-status'),
                style: TextButton.styleFrom(
                  foregroundColor: _connectionStateColor(state),
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _openConnectionSettings,
                icon: const Icon(Icons.circle, size: 9),
                label: Text(
                  'OBS ${_connectionStateLabel(state)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _saving || !_dirty ? null : _savePresets,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存'),
            ),
          ],
        );
        final presetTools = _buildPresetToolbar();
        if (compact) {
          return SizedBox(
            height: 112,
            child: Column(
              children: [
                SizedBox(
                  height: 58,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: title,
                  ),
                ),
                const Divider(height: 1, color: _border),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: presetTools,
                  ),
                ),
              ],
            ),
          );
        }
        return SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 18),
                presetTools,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetToolbar() {
    final preset = _selectedPreset;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 220,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedId,
              isExpanded: true,
              dropdownColor: const Color(0xFF292B31),
              items: _presets
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedId = value);
              },
            ),
          ),
        ),
        IconButton(
          tooltip: '新建预设',
          onPressed: _createPreset,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: '添加 EEW M5 分机构自动录制预设',
          onPressed: _createEewM5RecordingPreset,
          icon: const Icon(Icons.playlist_add, size: 20),
        ),
        IconButton(
          tooltip: '重命名预设',
          onPressed: _renamePreset,
          icon: const Icon(Icons.edit_outlined, size: 19),
        ),
        IconButton(
          tooltip: '复制预设',
          onPressed: _duplicatePreset,
          icon: const Icon(Icons.copy_outlined, size: 19),
        ),
        IconButton(
          tooltip: '删除预设',
          onPressed: _deletePreset,
          icon: const Icon(Icons.delete_outline, size: 20),
        ),
        const SizedBox(width: 4),
        const Text('启用', style: TextStyle(color: _muted)),
        Switch(
          value: preset?.enabled ?? false,
          onChanged: preset == null
              ? null
              : (value) =>
                    _updateSelected((item) => item.copyWith(enabled: value)),
        ),
      ],
    );
  }

  Widget _buildPalette() {
    final types = _paletteTypes(_category);
    return ColoredBox(
      color: _surface.withValues(alpha: 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 66,
            child: Scrollbar(
              controller: _categoryController,
              thumbVisibility: true,
              interactive: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView(
                  key: const ValueKey('palette-category-scroll'),
                  controller: _categoryController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                  children: _PaletteCategory.values
                      .map((category) => _categoryButton(category))
                      .toList(),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: _border),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 18),
              itemCount: types.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _paletteBlock(types[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryButton(_PaletteCategory category) {
    final selected = category == _category;
    final color = _categoryColor(category);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: _categoryLabel(category),
        child: InkWell(
          key: ValueKey('palette-category-${category.name}'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _category = category),
          child: Container(
            width: 62,
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.24)
                  : Colors.transparent,
              border: Border.all(color: selected ? color : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_categoryIcon(category), color: color, size: 17),
                const SizedBox(height: 2),
                Text(
                  _categoryLabel(category),
                  style: TextStyle(
                    color: selected ? Colors.white : _muted,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paletteBlock(ObsAutomationBlockType type) {
    final block = _newBlock(type, category: _category);
    if (_isValueReporter(type)) {
      final payload = _ValueDragPayload.fromBlock(block);
      return _valueReporterBody(
        block,
        category: _category,
        interactive: true,
        dragPayload: payload,
        dragKey: ValueKey(
          type == ObsAutomationBlockType.inputFieldValue
              ? 'palette-${_category.name}-${type.name}'
              : 'palette-${type.name}',
        ),
      );
    }
    return Draggable<_BlockDragPayload>(
      data: _BlockDragPayload.template(block),
      feedback: Material(
        type: MaterialType.transparency,
        child: _blockFeedback([block]),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _paletteBlockBody(block, category: _category),
      ),
      child: KeyedSubtree(
        key: ValueKey(
          type == ObsAutomationBlockType.inputFieldCondition
              ? 'palette-${_category.name}-${type.name}'
              : 'palette-${type.name}',
        ),
        child: _paletteBlockBody(block, category: _category),
      ),
    );
  }

  Widget _valueReporterBody(
    ObsAutomationBlock block, {
    required _PaletteCategory category,
    bool interactive = false,
    _ValueDragPayload? dragPayload,
    Key? dragKey,
  }) {
    if (_expressionReporterTypes.contains(block.type)) {
      return _expressionReporterPaletteBody(
        block,
        dragPayload: dragPayload,
        dragKey: dragKey,
      );
    }
    final color = _blockColor(block, paletteCategory: category);
    final isInputField = block.type == ObsAutomationBlockType.inputFieldValue;
    final isStation = block.parameters['family'] == 'station';
    final fields = isInputField
        ? _inputFieldsForFamily(block.parameters['family'])
        : const <ObsAutomationInputFieldDefinition>[];
    final fieldValues = {for (final field in fields) field.key: field.label};
    final field = fieldValues.containsKey(block.parameters['field'])
        ? block.parameters['field']!
        : (fieldValues.isEmpty ? '' : fieldValues.keys.first);
    final variables = _availableValueVariables;
    final variable = variables.contains(block.parameters['value'])
        ? block.parameters['value']!
        : _activeValueVariable;
    final prefix = isInputField ? (isStation ? '测站字段' : 'UI 字段') : '变量';
    final selectedLabel = isInputField
        ? (fieldValues[field] ?? '选择字段')
        : r'$' + variable;
    final dragHandle = Tooltip(
      message: '拖动值模块',
      child: SizedBox(
        key: dragKey,
        height: 34,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.drag_indicator, size: 16, color: Colors.white),
            const SizedBox(width: 2),
            Text(
              prefix,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Container(
        height: 42,
        constraints: const BoxConstraints(minWidth: 132, maxWidth: 234),
        padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Row(
          children: [
            if (interactive && dragPayload != null)
              Draggable<_ValueDragPayload>(
                data: dragPayload,
                feedback: Material(
                  type: MaterialType.transparency,
                  child: _valueReporterFeedback(
                    color: color,
                    prefix: prefix,
                    value: selectedLabel,
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.35, child: dragHandle),
                child: dragHandle,
              )
            else
              dragHandle,
            const SizedBox(width: 4),
            Expanded(
              child: interactive
                  ? _reporterDropdown(
                      key: ValueKey(
                        isInputField
                            ? 'palette-field-selector-${isStation ? 'station' : 'unified'}'
                            : 'palette-variable-selector',
                      ),
                      value: isInputField ? field : variable,
                      values: isInputField
                          ? fieldValues
                          : {
                              for (final name in variables) name: r'$' + name,
                              if (variables.isEmpty) '变量': r'$变量',
                            },
                      onChanged: isInputField
                          ? (value) => setState(() {
                              if (isStation) {
                                _selectedStationInputField = value;
                              } else {
                                _selectedUnifiedInputField = value;
                              }
                            })
                          : variables.isEmpty
                          ? null
                          : (value) =>
                                setState(() => _selectedValueVariable = value),
                    )
                  : Text(
                      selectedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueReporterFeedback({
    required Color color,
    required String prefix,
    required String value,
  }) {
    return Container(
      width: 210,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            prefix,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expressionReporterPaletteBody(
    ObsAutomationBlock block, {
    required _ValueDragPayload? dragPayload,
    required Key? dragKey,
  }) {
    final body = Container(
      key: dragKey,
      height: 42,
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 234),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _operatorColor,
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: Colors.white),
          const SizedBox(width: 5),
          Icon(_blockIcon(block.type), size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _blockLabel(block.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (dragPayload == null) return body;
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Draggable<_ValueDragPayload>(
        data: dragPayload,
        feedback: Material(type: MaterialType.transparency, child: body),
        childWhenDragging: Opacity(opacity: 0.35, child: body),
        child: body,
      ),
    );
  }

  Widget _reporterDropdown({
    required Key key,
    required String value,
    required Map<String, String> values,
    required ValueChanged<String>? onChanged,
  }) {
    return Container(
      key: key,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: values.containsKey(value) ? value : values.keys.first,
          isDense: true,
          isExpanded: true,
          dropdownColor: const Color(0xFF292B31),
          items: values.entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged == null
              ? null
              : (next) {
                  if (next != null) onChanged(next);
                },
        ),
      ),
    );
  }

  Widget _paletteBlockBody(
    ObsAutomationBlock block, {
    required _PaletteCategory category,
  }) {
    final type = block.type;
    final color = _blockColor(block, paletteCategory: category);
    return CustomPaint(
      painter: _ScratchBlockPainter(
        color: color,
        isHat: _isInputHat(type),
        compact: true,
      ),
      child: SizedBox(
        height: _isInputHat(type) ? 54 : 46,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 7, 10, 6),
          child: Row(
            children: [
              Icon(_blockIcon(type), size: 15, color: Colors.white),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _blockLabel(type),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = _canvasSizeFor(constraints);
        _currentCanvasSize = canvasSize;
        return Listener(
          key: const ValueKey('automation-canvas-pan-surface'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleCanvasPointerDown,
          onPointerMove: _handleCanvasPointerMove,
          onPointerUp: _handleCanvasPointerEnd,
          onPointerCancel: _handleCanvasPointerEnd,
          child: Scrollbar(
            controller: _verticalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _verticalController,
              child: Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.depth == 1,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: DragTarget<_BlockDragPayload>(
                    onWillAcceptWithDetails: (_) => true,
                    onMove: (details) {
                      final point = _canvasPoint(details.offset);
                      if (point == null) return;
                      _activeSnapNotifier.value = _findSnapTarget(
                        point,
                        details.data,
                      );
                    },
                    onLeave: (_) => _activeSnapNotifier.value = null,
                    onAcceptWithDetails: (details) {
                      final point = _canvasPoint(details.offset);
                      if (point != null) _acceptDrop(details.data, point);
                      _activeSnapNotifier.value = null;
                    },
                    builder: (context, _, _) => SizedBox(
                      key: _canvasKey,
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned.fill(
                            child: CustomPaint(painter: _CanvasGridPainter()),
                          ),
                          if ((_selectedPreset?.stacks ?? const []).isEmpty)
                            const Positioned(
                              left: 42,
                              top: 34,
                              child: Text(
                                '画布为空',
                                style: TextStyle(color: _muted, fontSize: 14),
                              ),
                            ),
                          for (final stack
                              in _selectedPreset?.stacks ??
                                  const <ObsAutomationStack>[])
                            Positioned(
                              left: stack.x,
                              top: stack.y,
                              child: _buildCanvasStack(stack),
                            ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ValueListenableBuilder<_SnapTarget?>(
                                valueListenable: _activeSnapNotifier,
                                builder: (context, snap, _) {
                                  if (snap == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Stack(
                                    children: [
                                      Positioned(
                                        left: snap.x,
                                        top: snap.y - 2,
                                        child: Container(
                                          width: _blockWidth,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: _accent,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleCanvasPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kMiddleMouseButton == 0) {
      return;
    }
    _canvasPanPointer = event.pointer;
  }

  void _handleCanvasPointerMove(PointerMoveEvent event) {
    if (_canvasPanPointer != event.pointer) return;
    if (event.buttons & kMiddleMouseButton == 0) {
      _canvasPanPointer = null;
      return;
    }
    _panController(_horizontalController, -event.delta.dx);
    _panController(_verticalController, -event.delta.dy);
  }

  void _handleCanvasPointerEnd(PointerEvent event) {
    if (_canvasPanPointer == event.pointer) _canvasPanPointer = null;
  }

  void _panController(ScrollController controller, double delta) {
    if (!controller.hasClients || delta == 0) return;
    final position = controller.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target != position.pixels) controller.jumpTo(target);
  }

  Size _canvasSizeFor(BoxConstraints constraints) {
    var contentWidth = constraints.maxWidth + _canvasExtraWidth;
    var contentHeight = constraints.maxHeight + _canvasExtraHeight;
    for (final stack
        in _selectedPreset?.stacks ?? const <ObsAutomationStack>[]) {
      contentWidth = math.max(
        contentWidth,
        stack.x + _blockWidth + _canvasExtraWidth / 2,
      );
      final stackHeight =
          _blockHeight + (stack.blocks.length - 1) * _blockPitch;
      contentHeight = math.max(
        contentHeight,
        stack.y + stackHeight + _canvasExtraHeight / 2,
      );
    }
    return Size(contentWidth, contentHeight);
  }

  Widget _buildCanvasStack(ObsAutomationStack stack) {
    final height = _blockHeight + (stack.blocks.length - 1) * _blockPitch;
    return SizedBox(
      width: _blockWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < stack.blocks.length; index++)
            Positioned(
              top: index * _blockPitch,
              child: KeyedSubtree(
                key: ValueKey('canvas-block-${stack.blocks[index].type.name}'),
                child: _canvasBlock(stack, index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _canvasBlock(ObsAutomationStack stack, int index) {
    final block = stack.blocks[index];
    final color = _blockColor(block);
    final payload = _BlockDragPayload.existing(
      stackId: stack.id,
      startIndex: index,
      firstType: block.type,
    );
    return CustomPaint(
      painter: _ScratchBlockPainter(
        color: color,
        isHat: index == 0 && _isInputHat(block.type),
      ),
      child: SizedBox(
        width: _blockWidth,
        height: _blockHeight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            9,
            index == 0 && _isInputHat(block.type) ? 14 : 8,
            8,
            7,
          ),
          child: Row(
            children: [
              Draggable<_BlockDragPayload>(
                data: payload,
                feedback: Material(
                  type: MaterialType.transparency,
                  child: _blockFeedback(stack.blocks.sublist(index)),
                ),
                childWhenDragging: const Opacity(
                  opacity: 0.25,
                  child: Icon(Icons.drag_indicator, color: Colors.white),
                ),
                child: Tooltip(
                  message: index == 0 ? '拖动积木堆' : '从这里拆开并拖动',
                  child: const Icon(
                    Icons.drag_indicator,
                    size: 21,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(_blockIcon(block.type), size: 17, color: Colors.white),
              const SizedBox(width: 7),
              Expanded(child: _blockEditor(block)),
              IconButton(
                tooltip: '删除积木',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                onPressed: () => _deleteBlock(stack.id, index),
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blockFeedback(List<ObsAutomationBlock> blocks) {
    final visible = blocks.take(5).toList();
    return SizedBox(
      width: _blockWidth,
      height: _blockHeight + (visible.length - 1) * _blockPitch,
      child: Stack(
        children: [
          for (var index = 0; index < visible.length; index++)
            Positioned(
              top: index * _blockPitch,
              child: CustomPaint(
                painter: _ScratchBlockPainter(
                  color: _blockColor(visible[index]),
                  isHat: index == 0 && _isInputHat(visible[index].type),
                ),
                child: SizedBox(
                  width: _blockWidth,
                  height: _blockHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _blockLabel(visible[index].type),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _blockEditor(ObsAutomationBlock block) {
    switch (block.type) {
      case ObsAutomationBlockType.unifiedEvent:
        return const Text('当统一 UI 事件输入');
      case ObsAutomationBlockType.networkDetection:
        return _inlineRow([
          const Text('当台网'),
          _stationNetworkDropdown(block, detectionOnly: true),
          const Text('检出输入'),
        ]);
      case ObsAutomationBlockType.stationChange:
        return _inlineRow([
          const Text('当'),
          _stationNetworkDropdown(block),
          const Text('测站变化输入'),
        ]);
      case ObsAutomationBlockType.orBranch:
        return const Text('或者', style: TextStyle(fontWeight: FontWeight.w800));
      case ObsAutomationBlockType.andBranch:
        return const Text('并且', style: TextStyle(fontWeight: FontWeight.w800));
      case ObsAutomationBlockType.unifiedPhase:
        return _enumConditionEditor(
          block,
          label: '事件阶段',
          values: const {
            'added': '进入',
            'updated': '更新',
            'canceled': '取消',
            'removed': '结束或过期',
          },
        );
      case ObsAutomationBlockType.networkPhase:
        return _enumConditionEditor(
          block,
          label: '检出状态',
          values: const {
            'candidate': '候选',
            'confirmed': '确认',
            'enhanced': '增强',
            'strong': '强震',
            'weakened': '减弱',
            'ended': '结束',
            'rejected': '拒绝',
          },
        );
      case ObsAutomationBlockType.stationPhase:
        return _enumConditionEditor(
          block,
          label: '测站变化',
          values: const {
            'rising': '开始上升',
            'triggered': '首次触发',
            'strong': '强震',
            'intensityIncreased': '震度增强',
            'intensityDecreased': '震度减弱',
            'ended': '恢复',
          },
        );
      case ObsAutomationBlockType.isEew:
        return const Text('是 EEW');
      case ObsAutomationBlockType.isInformation:
        return const Text('是信息');
      case ObsAutomationBlockType.eewAgency:
        return _enumConditionEditor(
          block,
          label: 'EEW 机构',
          values: const {
            'jma': 'JMA',
            'cwa': 'CWA',
            'cea': 'CEA',
            'sichuan': '四川省地震局',
            'fujian': '福建省地震局',
            'chongqing': '重庆市地震局',
            'kma': 'KMA',
            'shakeAlert': 'ShakeAlert',
            'globalQuake': 'GlobalQuake',
          },
        );
      case ObsAutomationBlockType.informationAgency:
        return _enumConditionEditor(
          block,
          label: '信息机构',
          values: const {
            'jma': 'JMA',
            'cwa': 'CWA',
            'cenc': 'CENC',
            'kma': 'KMA',
            'usgs': 'USGS',
            'fssn': 'FSSN',
            'hko': 'HKO',
            'emsc': 'EMSC',
            'bcsf': 'BCSF',
            'gfz': 'GFZ',
            'usp': 'USP',
            'geonet': 'GeoNet',
            'bmkg': 'BMKG',
            'tmd': 'TMD',
            'ingv': 'INGV',
            'nrcan': 'NRCan',
            'mmd': 'MMD',
            'phivolcs': 'PHIVOLCS',
            'sgc': 'SGC',
            'ga': 'GA',
            'cenais': 'CENAIS',
            'gsras': 'GSRAS',
            'bgs': 'BGS',
            'ipma': 'IPMA',
            'ssn': 'SSN',
            'afad': 'AFAD',
            'sed': 'SED',
            'noa': 'NOA',
            'scsn': 'SCSN',
            'iag': 'IAG',
            'igp': 'IGP',
              'nepal': 'NEPAL',
              'ipgp': 'IPGP',
              'infp': 'INFP',
              'isc': 'ISC',
              'knmi': 'KNMI',
              'ncedc': 'NCEDC',
              'lmu': 'LMU',
              'koeri': 'KOERI',
              'csn': 'CSN',
              'igepn': 'IGEPN',
              'earlyEst': 'Early-est',
            'ningxia': '宁夏地震局',
            'guangxi': '广西地震局',
            'shanxi': '山西地震局',
            'beijing': '北京地震局',
            'yunnan': '云南地震局',
          },
        );
      case ObsAutomationBlockType.informationReviewType:
        return _enumConditionEditor(
          block,
          label: '测定类型',
          values: const {'automatic': '自动测定', 'reviewed': '正式测定'},
        );
      case ObsAutomationBlockType.sameEarthquakeAsVariable:
        return _inlineRow([
          const Text('与'),
          _inlineTextField(block, parameter: 'variable', width: 70),
          const Text('同震 ≤'),
          _inlineTextField(
            block,
            parameter: 'maxSeconds',
            width: 42,
            numeric: true,
          ),
          const Text('秒'),
          const Text('/'),
          _inlineTextField(
            block,
            parameter: 'maxDistanceKm',
            width: 42,
            numeric: true,
          ),
          const Text('km'),
        ], spacing: 3);
      case ObsAutomationBlockType.inputFieldMatchesVariable:
        return _inlineRow([
          _inlineDropdown(
            value: block.parameters['field'] ?? 'eventId',
            values: _inputFieldValues,
            minWidth: 86,
            maxWidth: 112,
            onChanged: (value) => _setBlockParameter(block.id, 'field', value),
          ),
          _inlineDropdown(
            value: block.parameters['operator'] ?? 'equals',
            values: _dynamicOperators,
            minWidth: 48,
            maxWidth: 62,
            onChanged: (value) =>
                _setBlockParameter(block.id, 'operator', value),
          ),
          const Text(r'$'),
          _inlineTextField(block, parameter: 'variable', width: 82),
        ], spacing: 3);
      case ObsAutomationBlockType.inputFieldCondition:
        return _inputFieldConditionEditor(block);
      case ObsAutomationBlockType.compareValues:
        return _inlineRow([
          _valueSocket(
            block,
            kindParameter: 'leftKind',
            valueParameter: 'leftValue',
            familyParameter: 'leftFamily',
          ),
          _inlineDropdown(
            value: block.parameters['operator'] ?? 'equals',
            values: _dynamicOperators,
            minWidth: 46,
            maxWidth: 46,
            onChanged: (value) =>
                _setBlockParameter(block.id, 'operator', value),
          ),
          _valueSocket(
            block,
            kindParameter: 'rightKind',
            valueParameter: 'rightValue',
            familyParameter: 'rightFamily',
          ),
        ], spacing: 3);
      case ObsAutomationBlockType.valueVariableCondition:
        return _inlineRow([
          const Text(r'$'),
          _inlineTextField(block, parameter: 'variable', width: 76),
          _inlineDropdown(
            value: block.parameters['operator'] ?? 'equals',
            values: _dynamicOperators,
            minWidth: 48,
            maxWidth: 62,
            onChanged: (value) =>
                _setBlockParameter(block.id, 'operator', value),
          ),
          _inlineTextField(block, parameter: 'value', width: 84),
        ], spacing: 3);
      case ObsAutomationBlockType.eventType:
        return _enumConditionEditor(
          block,
          label: '事件类型',
          values: const {
            'eew': '地震预警',
            'earthquake': '地震信息',
            'tsunami': '海啸信息',
            'volcano': '火山信息',
            'ashfall': '降灰预报',
            'cmt': 'CMT',
            'weather': '气象预警',
          },
        );
      case ObsAutomationBlockType.source:
        return _comparisonEditor(block, label: '来源', textValue: true);
      case ObsAutomationBlockType.magnitude:
        return _comparisonEditor(block, label: '震级', numericValue: true);
      case ObsAutomationBlockType.estimatedIntensity:
        return _comparisonEditor(block, label: '最大震度/烈度', numericValue: true);
      case ObsAutomationBlockType.reportNumber:
        return _comparisonEditor(block, label: '报数', numericValue: true);
      case ObsAutomationBlockType.isFinal:
        return _inlineRow([
          const Text('最终报'),
          _inlineDropdown(
            value: block.parameters['value'] ?? 'true',
            values: const {'true': '是', 'false': '否'},
            onChanged: (value) => _setBlockParameter(block.id, 'value', value),
          ),
        ]);
      case ObsAutomationBlockType.networkMaxIntensity:
        return _intensityConditionEditor(block, label: '台网最大震度');
      case ObsAutomationBlockType.detectedStationCount:
        return _comparisonEditor(block, label: '检出测站数', numericValue: true);
      case ObsAutomationBlockType.stationId:
        return _comparisonEditor(block, label: '测站编号', textValue: true);
      case ObsAutomationBlockType.stationName:
        return _comparisonEditor(block, label: '测站名称', textValue: true);
      case ObsAutomationBlockType.currentStationIntensity:
        return _intensityConditionEditor(block, label: '当前震度');
      case ObsAutomationBlockType.previousStationIntensity:
        return _intensityConditionEditor(block, label: '上一震度');
      case ObsAutomationBlockType.wait:
        return _inlineRow([
          const Text('等待'),
          _inlineTextField(
            block,
            parameter: 'seconds',
            width: 72,
            numeric: true,
          ),
          const Text('秒'),
        ]);
      case ObsAutomationBlockType.waitForUnifiedEvent:
        return _inlineRow([
          const Text('等待统一 UI 事件，最多'),
          _inlineTextField(
            block,
            parameter: 'timeoutSeconds',
            width: 72,
            numeric: true,
          ),
          const Text('秒'),
        ]);
      case ObsAutomationBlockType.waitForInput:
        return _inlineRow([
          const Text('等'),
          _inlineDropdown(
            value: block.parameters['kind'] ?? 'unifiedEvent',
            values: const {
              'unifiedEvent': '统一 UI',
              'networkDetection': '台网检出',
              'stationChange': '单测站变化',
            },
            minWidth: 80,
            maxWidth: 100,
            onChanged: (value) => _setBlockParameter(block.id, 'kind', value),
          ),
          const Text('≤'),
          _inlineTextField(
            block,
            parameter: 'timeoutSeconds',
            width: 46,
            numeric: true,
          ),
          const Text('s'),
          _inlineDropdown(
            value: block.parameters['onTimeout'] ?? 'stopScript',
            values: const {
              'stopScript': '超时结束',
              'continue': '超时继续',
              'stopRecord': '超时停录',
            },
            minWidth: 72,
            maxWidth: 88,
            onChanged: (value) =>
                _setBlockParameter(block.id, 'onTimeout', value),
          ),
        ], spacing: 3);
      case ObsAutomationBlockType.setEventVariable:
        return _inlineRow([
          const Text('保存当前输入为'),
          _inlineTextField(block, parameter: 'name', width: 120),
        ]);
      case ObsAutomationBlockType.setValueVariable:
        return _inlineRow([
          const Text('取'),
          _inlineDropdown(
            value: block.parameters['field'] ?? 'eventId',
            values: _inputFieldValues,
            minWidth: 92,
            maxWidth: 128,
            onChanged: (value) => _setBlockParameter(block.id, 'field', value),
          ),
          const Text('存为'),
          _inlineTextField(block, parameter: 'name', width: 104),
        ], spacing: 4);
      case ObsAutomationBlockType.setVariable:
        return _inlineRow([
          const Text('设置'),
          const Text(r'$'),
          _inlineTextField(block, parameter: 'name', width: 104),
          const Text('为'),
          _valueSocket(
            block,
            kindParameter: 'valueKind',
            valueParameter: 'value',
            familyParameter: 'valueFamily',
          ),
        ], spacing: 3);
      case ObsAutomationBlockType.changeVariable:
        return _inlineRow([
          const Text(r'$'),
          _inlineTextField(block, parameter: 'name', width: 72),
          _inlineDropdown(
            value: block.parameters['operation'] ?? 'add',
            values: const {
              'add': '增加',
              'subtract': '减少',
              'multiply': '乘以',
              'divide': '除以',
              'append': '追加',
            },
            minWidth: 52,
            maxWidth: 66,
            onChanged: (value) =>
                _setBlockParameter(block.id, 'operation', value),
          ),
          _inlineTextField(block, parameter: 'operand', width: 76),
          _variableInsertButton(block, 'operand'),
        ], spacing: 3);
      case ObsAutomationBlockType.createRecordChapter:
        return _inlineRow([
          const Text('添加录像章节'),
          _inlineTextField(block, parameter: 'text', width: 126),
          _variableInsertButton(block, 'text'),
        ]);
      case ObsAutomationBlockType.setTextSourceText:
        return _inlineRow([
          const Text('设置文本源'),
          _inlineTextField(block, parameter: 'inputName', width: 112),
          const Text('内容为'),
          _valueSocket(
            block,
            kindParameter: 'textKind',
            valueParameter: 'textValue',
            familyParameter: 'textFamily',
          ),
        ], spacing: 3);
      case ObsAutomationBlockType.setCurrentProgramScene:
        return _inlineRow([
          const Text('切换当前场景为'),
          _inlineTextField(block, parameter: 'sceneName', width: 132),
          _variableInsertButton(block, 'sceneName'),
        ], spacing: 3);
      case ObsAutomationBlockType.setSceneItemEnabled:
        return _inlineRow([
          const Text('场景'),
          _inlineTextField(block, parameter: 'sceneName', width: 92),
          const Text('来源'),
          _inlineTextField(block, parameter: 'sourceName', width: 92),
          const Text('显示为'),
          _valueSocket(
            block,
            kindParameter: 'enabledKind',
            valueParameter: 'enabledValue',
            familyParameter: 'enabledFamily',
          ),
        ], spacing: 3);
      default:
        return Text(
          _blockLabel(block.type),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        );
    }
  }

  Widget _variableInsertButton(ObsAutomationBlock block, String parameter) {
    return PopupMenuButton<String>(
      tooltip: '插入变量',
      enabled: _availableValueVariables.isNotEmpty,
      onSelected: (name) {
        final current = block.parameters[parameter] ?? '';
        _setBlockParameter(block.id, parameter, '$current{{$name}}');
      },
      itemBuilder: (context) => _availableValueVariables
          .map((name) => PopupMenuItem<String>(value: name, child: Text(name)))
          .toList(growable: false),
      icon: const Icon(Icons.data_object, size: 18),
    );
  }

  Widget _valueSocket(
    ObsAutomationBlock block, {
    required String kindParameter,
    required String valueParameter,
    String? familyParameter,
  }) {
    final kind = block.parameters[kindParameter] ?? 'literal';
    final family = familyParameter == null
        ? null
        : block.parameters[familyParameter];
    final Widget valueEditor;
    if (kind == 'empty') {
      valueEditor = const SizedBox.shrink();
    } else if (kind == 'inputField') {
      final fields = _inputFieldsForFamily(family);
      final requested = block.parameters[valueParameter];
      final selected = fields.any((field) => field.key == requested)
          ? requested!
          : fields.first.key;
      valueEditor = _inlineDropdown(
        value: selected,
        values: {for (final field in fields) field.key: field.label},
        minWidth: 144,
        maxWidth: 144,
        menuWidth: 260,
        horizontalPadding: 4,
        onChanged: (value) =>
            _setBlockParameter(block.id, valueParameter, value),
      );
    } else if (kind == 'expression') {
      final expression = ObsAutomationValueNode.tryDecode(
        block.parameters[valueParameter] ?? '',
      );
      valueEditor = expression == null
          ? const Text('无效运算')
          : _expressionNodeEditor(
              block,
              root: expression,
              node: expression,
              kindParameter: kindParameter,
              valueParameter: valueParameter,
              path: const [],
            );
    } else if (kind == 'variable') {
      valueEditor = _inlineRow([
        const Text(r'$'),
        _inlineTextField(block, parameter: valueParameter, width: 110),
      ], spacing: 1);
    } else {
      valueEditor = _inlineTextField(
        block,
        parameter: valueParameter,
        width: 110,
      );
    }

    return DragTarget<_ValueDragPayload>(
      key: ValueKey('value-socket-${block.id}-$kindParameter'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        _setBlockParameters(block.id, {
          kindParameter: details.data.kind,
          valueParameter: details.data.value,
          if (familyParameter != null && details.data.family != null)
            familyParameter: details.data.family!,
        });
      },
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 38,
        constraints: kind == 'empty'
            ? const BoxConstraints(minWidth: 112)
            : const BoxConstraints(),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.black.withValues(alpha: 0.15)
              : _accent.withValues(alpha: 0.34),
          border: Border.all(
            color: candidates.isEmpty
                ? Colors.white.withValues(alpha: 0.22)
                : _accent,
          ),
          borderRadius: BorderRadius.circular(19),
        ),
        child: kind == 'empty'
            ? PopupMenuButton<String>(
                key: ValueKey('value-socket-picker-${block.id}-$kindParameter'),
                tooltip: '选择数值来源',
                padding: EdgeInsets.zero,
                onSelected: (nextKind) => _setValueSocketKind(
                  block,
                  kindParameter: kindParameter,
                  valueParameter: valueParameter,
                  familyParameter: familyParameter,
                  kind: nextKind,
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'literal', child: Text('常量')),
                  PopupMenuItem(value: 'inputField', child: Text('输入字段')),
                  PopupMenuItem(value: 'variable', child: Text('变量')),
                  PopupMenuItem(value: 'expression', child: Text('运算')),
                ],
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.input, size: 15, color: Colors.white70),
                    SizedBox(width: 4),
                    Text(
                      '拖入数值',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            : _inlineRow([
                _inlineDropdown(
                  value: kind,
                  values: const {
                    'literal': '值',
                    'inputField': '字段',
                    'variable': '变量',
                    'expression': '运算',
                  },
                  minWidth: 60,
                  maxWidth: 60,
                  menuWidth: 110,
                  horizontalPadding: 3,
                  onChanged: (nextKind) => _setValueSocketKind(
                    block,
                    kindParameter: kindParameter,
                    valueParameter: valueParameter,
                    familyParameter: familyParameter,
                    kind: nextKind,
                  ),
                ),
                valueEditor,
              ], spacing: 2),
      ),
    );
  }

  List<ObsAutomationInputFieldDefinition> _inputFieldsForFamily(
    String? family,
  ) {
    final target = family == 'station'
        ? ObsAutomationInputFieldFamily.station
        : ObsAutomationInputFieldFamily.unified;
    return obsAutomationInputFields
        .where(
          (field) =>
              field.family == ObsAutomationInputFieldFamily.common ||
              field.family == target,
        )
        .toList(growable: false);
  }

  void _setValueSocketKind(
    ObsAutomationBlock block, {
    required String kindParameter,
    required String valueParameter,
    required String? familyParameter,
    required String kind,
  }) {
    final updates = <String, String>{kindParameter: kind};
    switch (kind) {
      case 'inputField':
        final family = familyParameter == null
            ? null
            : block.parameters[familyParameter];
        updates[valueParameter] = _inputFieldsForFamily(family).first.key;
        break;
      case 'variable':
        updates[valueParameter] = _availableValueVariables.isEmpty
            ? '变量'
            : _availableValueVariables.first;
        break;
      case 'expression':
        updates[valueParameter] = _defaultExpression(
          ObsAutomationBlockType.arithmeticValue,
        ).encode();
        break;
      default:
        updates[valueParameter] = '0';
        break;
    }
    _setBlockParameters(block.id, updates);
  }

  Widget _expressionNodeEditor(
    ObsAutomationBlock block, {
    required ObsAutomationValueNode root,
    required ObsAutomationValueNode node,
    required String kindParameter,
    required String valueParameter,
    required List<int> path,
  }) {
    Widget operand(int index) {
      final argument = index < node.arguments.length
          ? node.arguments[index]
          : const ObsAutomationValueNode.literal('');
      return _expressionOperandSocket(
        block,
        root: root,
        node: argument,
        kindParameter: kindParameter,
        valueParameter: valueParameter,
        path: [...path, index],
      );
    }

    Widget operatorDropdown(Map<String, String> values, {double width = 52}) {
      return _inlineDropdown(
        value: node.options['operator'] ?? values.keys.first,
        values: values,
        minWidth: width,
        maxWidth: width,
        menuWidth: math.max(width, 132.0),
        horizontalPadding: 3,
        onChanged: (value) => _replaceExpressionNode(
          block,
          root: root,
          replacement: node.copyWith(
            options: {...node.options, 'operator': value},
          ),
          valueParameter: valueParameter,
          path: path,
        ),
      );
    }

    final Widget content = switch (node.value) {
      'arithmetic' => _inlineRow([
        operand(0),
        operatorDropdown(const {
          'add': '+',
          'subtract': '-',
          'multiply': '×',
          'divide': '÷',
        }),
        operand(1),
      ], spacing: 2),
      'random' => _inlineRow([
        const Text('随机'),
        operand(0),
        const Text('到'),
        operand(1),
      ], spacing: 3),
      'modulo' => _inlineRow([
        operand(0),
        const Text('除以'),
        operand(1),
        const Text('的余数'),
      ], spacing: 3),
      'round' => _inlineRow([const Text('四舍五入'), operand(0)], spacing: 3),
      'math' => _inlineRow([
        operatorDropdown(const {
          'abs': '绝对值',
          'floor': '向下取整',
          'ceil': '向上取整',
          'sqrt': '平方根',
          'sin': 'sin',
          'cos': 'cos',
          'tan': 'tan',
          'ln': 'ln',
          'log10': 'log',
          'pow10': '10 ^',
        }, width: 82),
        operand(0),
      ], spacing: 3),
      'join' => _inlineRow([
        const Text('连接'),
        operand(0),
        const Text('和'),
        operand(1),
      ], spacing: 3),
      'length' => _inlineRow([operand(0), const Text('的长度')], spacing: 3),
      'contains' => _inlineRow([
        operand(0),
        const Text('包含'),
        operand(1),
      ], spacing: 3),
      'comparison' => _inlineRow([
        operand(0),
        operatorDropdown(_dynamicOperators, width: 52),
        operand(1),
      ], spacing: 2),
      'boolean' => _inlineRow([
        operand(0),
        operatorDropdown(const {'and': '并且', 'or': '或者'}, width: 64),
        operand(1),
      ], spacing: 2),
      'not' => _inlineRow([const Text('不成立'), operand(0)], spacing: 3),
      _ => const Text('未知运算'),
    };

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _operatorColor.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
      ),
      child: content,
    );
  }

  Widget _expressionOperandSocket(
    ObsAutomationBlock block, {
    required ObsAutomationValueNode root,
    required ObsAutomationValueNode node,
    required String kindParameter,
    required String valueParameter,
    required List<int> path,
  }) {
    final pathKey = path.join('-');
    return DragTarget<_ValueDragPayload>(
      key: ValueKey('expression-socket-${block.id}-$kindParameter-$pathKey'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _replaceExpressionNode(
        block,
        root: root,
        replacement: details.data.toValueNode(),
        valueParameter: valueParameter,
        path: path,
      ),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: node.isOperation ? 34 : 28,
        padding: EdgeInsets.symmetric(horizontal: node.isOperation ? 1 : 4),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.black.withValues(alpha: 0.2)
              : _accent.withValues(alpha: 0.45),
          border: Border.all(
            color: candidates.isEmpty
                ? Colors.white.withValues(alpha: 0.2)
                : _accent,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: node.isOperation
            ? _expressionNodeEditor(
                block,
                root: root,
                node: node,
                kindParameter: kindParameter,
                valueParameter: valueParameter,
                path: path,
              )
            : _expressionLeafEditor(
                block,
                root: root,
                node: node,
                valueParameter: valueParameter,
                path: path,
              ),
      ),
    );
  }

  Widget _expressionLeafEditor(
    ObsAutomationBlock block, {
    required ObsAutomationValueNode root,
    required ObsAutomationValueNode node,
    required String valueParameter,
    required List<int> path,
  }) {
    if (node.kind == 'literal') {
      return SizedBox(
        width: 70,
        height: 26,
        child: TextFormField(
          key: ValueKey('expression-literal-${block.id}-${path.join('-')}'),
          initialValue: node.value,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          ),
          onChanged: (value) => _replaceExpressionNode(
            block,
            root: root,
            replacement: ObsAutomationValueNode.literal(value),
            valueParameter: valueParameter,
            path: path,
          ),
        ),
      );
    }
    final label = switch (node.kind) {
      'inputField' => _expressionInputFieldLabel(node),
      'variable' => r'$' + node.value,
      _ => node.value,
    };
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  String _expressionInputFieldLabel(ObsAutomationValueNode node) {
    final fields = _inputFieldsForFamily(node.family);
    for (final field in fields) {
      if (field.key == node.value) return field.label;
    }
    return node.value;
  }

  void _replaceExpressionNode(
    ObsAutomationBlock block, {
    required ObsAutomationValueNode root,
    required ObsAutomationValueNode replacement,
    required String valueParameter,
    required List<int> path,
  }) {
    _setBlockParameter(
      block.id,
      valueParameter,
      root.replaceAt(path, replacement).encode(),
    );
  }

  Widget _enumConditionEditor(
    ObsAutomationBlock block, {
    required String label,
    required Map<String, String> values,
  }) {
    return _inlineRow([
      Text(label),
      _inlineDropdown(
        value: block.parameters['operator'] ?? 'equals',
        values: const {'equals': '是', 'notEquals': '不是'},
        minWidth: 58,
        maxWidth: 72,
        onChanged: (value) => _setBlockParameter(block.id, 'operator', value),
      ),
      _inlineDropdown(
        value: block.parameters['value'] ?? values.keys.first,
        values: values,
        minWidth: 76,
        maxWidth: 116,
        onChanged: (value) => _setBlockParameter(block.id, 'value', value),
      ),
    ]);
  }

  Widget _intensityConditionEditor(
    ObsAutomationBlock block, {
    required String label,
  }) {
    return _inlineRow([
      Text(label),
      _inlineDropdown(
        value: block.parameters['operator'] ?? 'greaterThanOrEqual',
        values: _numericOperators,
        minWidth: 48,
        maxWidth: 62,
        onChanged: (value) => _setBlockParameter(block.id, 'operator', value),
      ),
      _inlineDropdown(
        value: block.parameters['value'] ?? '4',
        values: _shindoValues,
        minWidth: 62,
        maxWidth: 76,
        onChanged: (value) => _setBlockParameter(block.id, 'value', value),
      ),
    ]);
  }

  Widget _comparisonEditor(
    ObsAutomationBlock block, {
    required String label,
    Map<String, String>? values,
    bool textValue = false,
    bool numericValue = false,
  }) {
    final operators = numericValue ? _numericOperators : _textOperators;
    final valueEditor = values != null
        ? _inlineDropdown(
            value: values.containsKey(block.parameters['value'])
                ? block.parameters['value']!
                : values.keys.first,
            values: values,
            onChanged: (value) => _setBlockParameter(block.id, 'value', value),
          )
        : _inlineTextField(
            block,
            parameter: 'value',
            width: textValue ? 110 : 84,
            numeric: numericValue,
          );
    return _inlineRow([
      Text(label),
      _inlineDropdown(
        value: operators.containsKey(block.parameters['operator'])
            ? block.parameters['operator']!
            : operators.keys.first,
        values: operators,
        minWidth: numericValue ? 48 : 72,
        maxWidth: numericValue ? 62 : 88,
        onChanged: (value) => _setBlockParameter(block.id, 'operator', value),
      ),
      valueEditor,
    ]);
  }

  Widget _inputFieldConditionEditor(ObsAutomationBlock block) {
    final fields = _inputFieldsForBlock(block);
    final requestedField = block.parameters['field'];
    final field = fields.any((item) => item.key == requestedField)
        ? fields.firstWhere((item) => item.key == requestedField)
        : fields.first;
    final operators = switch (field.valueType) {
      ObsAutomationInputValueType.number => _numericOperators,
      ObsAutomationInputValueType.boolean ||
      ObsAutomationInputValueType.choice => const {
        'equals': '是',
        'notEquals': '不是',
      },
      ObsAutomationInputValueType.text => _textOperators,
    };
    final requestedOperator = block.parameters['operator'];
    final operator = operators.containsKey(requestedOperator)
        ? requestedOperator!
        : operators.keys.first;
    final requestedValue = block.parameters['value'] ?? '';
    final Widget valueEditor;
    if (field.valueType == ObsAutomationInputValueType.boolean) {
      valueEditor = _inlineDropdown(
        value: requestedValue == 'false' ? 'false' : 'true',
        values: const {'true': '是', 'false': '否'},
        minWidth: 54,
        maxWidth: 66,
        onChanged: (value) => _setBlockParameter(block.id, 'value', value),
      );
    } else if (field.valueType == ObsAutomationInputValueType.choice &&
        field.options.isNotEmpty) {
      valueEditor = _inlineDropdown(
        value: field.options.containsKey(requestedValue)
            ? requestedValue
            : field.options.keys.first,
        values: field.options,
        minWidth: 76,
        maxWidth: 112,
        onChanged: (value) => _setBlockParameter(block.id, 'value', value),
      );
    } else {
      valueEditor = _inlineRow([
        _inlineTextField(
          block,
          parameter: 'value',
          width: field.valueType == ObsAutomationInputValueType.number
              ? 74
              : 96,
          numeric: field.valueType == ObsAutomationInputValueType.number,
        ),
        _variableInsertButton(block, 'value'),
      ], spacing: 1);
    }

    return _inlineRow([
      _inlineDropdown(
        value: field.key,
        values: {for (final item in fields) item.key: item.label},
        minWidth: 94,
        maxWidth: 128,
        onChanged: (value) => _setInputFieldConditionField(block, value),
      ),
      _inlineDropdown(
        value: operator,
        values: operators,
        minWidth: 48,
        maxWidth: 76,
        onChanged: (value) => _setBlockParameter(block.id, 'operator', value),
      ),
      valueEditor,
    ], spacing: 3);
  }

  List<ObsAutomationInputFieldDefinition> _inputFieldsForBlock(
    ObsAutomationBlock block,
  ) {
    final family = block.parameters['family'];
    final target = family == 'station'
        ? ObsAutomationInputFieldFamily.station
        : ObsAutomationInputFieldFamily.unified;
    return obsAutomationInputFields
        .where(
          (field) =>
              field.family == ObsAutomationInputFieldFamily.common ||
              field.family == target,
        )
        .toList(growable: false);
  }

  void _setInputFieldConditionField(ObsAutomationBlock block, String fieldKey) {
    final definition = obsAutomationInputFields.firstWhere(
      (field) => field.key == fieldKey,
    );
    final defaultValue = switch (definition.valueType) {
      ObsAutomationInputValueType.boolean => 'true',
      ObsAutomationInputValueType.choice => definition.options.keys.first,
      ObsAutomationInputValueType.number => '0',
      ObsAutomationInputValueType.text => '',
    };
    _setBlockParameters(block.id, {
      'field': fieldKey,
      'operator': 'equals',
      'value': defaultValue,
    });
  }

  Widget _stationNetworkDropdown(
    ObsAutomationBlock block, {
    bool detectionOnly = false,
  }) {
    return _inlineDropdown(
      value: block.parameters['network'] ?? 'any',
      values: detectionOnly
          ? const {'any': '任意台网', 'nied': 'NIED', 'kma': 'KMA', 'trem': 'TREM'}
          : const {
              'any': '任意台网',
              'nied': 'NIED',
              'kma': 'KMA',
              'trem': 'TREM',
              'snet': 'S-Net',
              'palert': 'P-Alert',
              'fdsn': 'FDSN/SeedLink',
              'seisjs': 'Wolfx SeisJS',
            },
      minWidth: detectionOnly ? 88 : 104,
      maxWidth: detectionOnly ? 104 : 124,
      onChanged: (value) => _setBlockParameter(block.id, 'network', value),
    );
  }

  Widget _inlineRow(List<Widget> children, {double spacing = 7}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) SizedBox(width: spacing),
          children[index],
        ],
      ],
    );
  }

  Widget _inlineDropdown({
    required String value,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
    double minWidth = 56,
    double maxWidth = 150,
    double? menuWidth,
    double horizontalPadding = 8,
  }) {
    return Container(
      height: 32,
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: values.containsKey(value) ? value : values.keys.first,
          isDense: true,
          isExpanded: true,
          menuWidth: menuWidth,
          dropdownColor: const Color(0xFF292B31),
          items: values.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }

  Widget _inlineTextField(
    ObsAutomationBlock block, {
    required String parameter,
    required double width,
    bool numeric = false,
  }) {
    return SizedBox(
      width: width,
      height: 32,
      child: TextFormField(
        key: ValueKey('field-${block.id}-$parameter'),
        initialValue: block.parameters[parameter] ?? '',
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.24),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Colors.white),
          ),
        ),
        onChanged: (value) => _setBlockParameter(block.id, parameter, value),
      ),
    );
  }

  Offset? _canvasPoint(Offset globalOffset) {
    final box = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return null;
    return box.globalToLocal(globalOffset);
  }

  void _acceptDrop(_BlockDragPayload payload, Offset point) {
    final preset = _selectedPreset;
    if (preset == null) return;
    final stacks = [...preset.stacks];
    late List<ObsAutomationBlock> segment;

    if (payload.template != null) {
      final template = payload.template!;
      segment = [
        ObsAutomationBlock(
          id: _newId('block'),
          type: template.type,
          parameters: Map<String, String>.from(template.parameters),
        ),
      ];
    } else {
      final sourceIndex = stacks.indexWhere(
        (stack) => stack.id == payload.sourceStackId,
      );
      if (sourceIndex < 0) return;
      final source = stacks[sourceIndex];
      if (payload.startIndex < 0 ||
          payload.startIndex >= source.blocks.length) {
        return;
      }
      segment = source.blocks.sublist(payload.startIndex);
      final prefix = source.blocks.sublist(0, payload.startIndex);
      if (prefix.isEmpty) {
        stacks.removeAt(sourceIndex);
      } else {
        stacks[sourceIndex] = source.copyWith(blocks: prefix);
      }
    }

    final snap = _findSnapTargetInStacks(point, segment, stacks);
    if (snap == null) {
      stacks.add(
        ObsAutomationStack(
          id: _newId('stack'),
          x: point.dx.clamp(
            12,
            math.max(12, _currentCanvasSize.width - _blockWidth - 12),
          ),
          y: point.dy.clamp(
            12,
            math.max(12, _currentCanvasSize.height - _blockHeight - 12),
          ),
          blocks: segment,
        ),
      );
    } else {
      final destinationIndex = stacks.indexWhere(
        (stack) => stack.id == snap.stackId,
      );
      if (destinationIndex < 0) return;
      final destination = stacks[destinationIndex];
      final blocks = [...destination.blocks]
        ..insertAll(
          snap.insertIndex.clamp(0, destination.blocks.length),
          segment,
        );
      stacks[destinationIndex] = destination.copyWith(blocks: blocks);
    }
    _updateSelected((item) => item.copyWith(stacks: stacks));
  }

  _SnapTarget? _findSnapTarget(Offset point, _BlockDragPayload payload) {
    final preset = _selectedPreset;
    if (preset == null) return null;
    var stacks = [...preset.stacks];
    List<ObsAutomationBlock>? segment;
    if (payload.template != null) {
      segment = [payload.template!];
    }
    if (payload.sourceStackId != null) {
      final index = stacks.indexWhere(
        (stack) => stack.id == payload.sourceStackId,
      );
      if (index >= 0) {
        final source = stacks[index];
        segment = source.blocks.sublist(
          payload.startIndex.clamp(0, source.blocks.length),
        );
        final prefix = source.blocks.sublist(
          0,
          payload.startIndex.clamp(0, source.blocks.length),
        );
        if (prefix.isEmpty) {
          stacks.removeAt(index);
        } else {
          stacks[index] = source.copyWith(blocks: prefix);
        }
      }
    }
    if (segment == null || segment.isEmpty) return null;
    return _findSnapTargetInStacks(point, segment, stacks);
  }

  _SnapTarget? _findSnapTargetInStacks(
    Offset point,
    List<ObsAutomationBlock> segment,
    List<ObsAutomationStack> stacks,
  ) {
    _SnapTarget? best;
    var bestDistance = double.infinity;
    for (final stack in stacks) {
      final minIndex = _isInputHat(stack.blocks.first.type) ? 1 : 0;
      for (var index = minIndex; index <= stack.blocks.length; index++) {
        final candidate = [...stack.blocks]..insertAll(index, segment);
        if (!_isValidConnectedSequence(candidate)) continue;
        final target = Offset(stack.x, stack.y + index * _blockPitch);
        final dx = (point.dx - target.dx).abs();
        final dy = (point.dy - target.dy).abs();
        if (dx > 110 || dy > 48) continue;
        final distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = _SnapTarget(
            stackId: stack.id,
            insertIndex: index,
            x: target.dx,
            y: target.dy,
          );
        }
      }
    }
    return best;
  }

  bool _isValidConnectedSequence(List<ObsAutomationBlock> blocks) {
    if (blocks.isEmpty) return true;
    if (!_isInputHat(blocks.first.type)) {
      if (blocks.length == 1 &&
          (blocks.first.type == ObsAutomationBlockType.orBranch ||
              blocks.first.type == ObsAutomationBlockType.andBranch)) {
        return true;
      }
      return _isValidProgramSequence(blocks, allowLeadingConditions: true);
    }

    var index = 0;
    while (index < blocks.length) {
      if (!_isInputHat(blocks[index].type)) return false;
      index++;
      var sawCondition = false;
      var expectsConditionAfterAnd = false;
      while (index < blocks.length) {
        if (_isCondition(blocks[index].type)) {
          sawCondition = true;
          expectsConditionAfterAnd = false;
          index++;
          continue;
        }
        if (blocks[index].type == ObsAutomationBlockType.andBranch) {
          if (!sawCondition || expectsConditionAfterAnd) return false;
          expectsConditionAfterAnd = true;
          index++;
          if (index >= blocks.length) return true;
          continue;
        }
        break;
      }
      if (expectsConditionAfterAnd) return false;
      if (index < blocks.length &&
          blocks[index].type == ObsAutomationBlockType.orBranch) {
        index++;
        if (index >= blocks.length) return true;
        continue;
      }
      break;
    }
    return _isValidProgramSequence(blocks.sublist(index));
  }

  bool _isValidProgramSequence(
    List<ObsAutomationBlock> blocks, {
    bool allowLeadingConditions = false,
  }) {
    var acceptsConditions = allowLeadingConditions;
    var previousWasCondition = false;
    var expectsConditionAfterAnd = false;
    for (final block in blocks) {
      if (_isCondition(block.type)) {
        if (!acceptsConditions) return false;
        previousWasCondition = true;
        expectsConditionAfterAnd = false;
        continue;
      }
      if (block.type == ObsAutomationBlockType.andBranch) {
        if (!previousWasCondition || expectsConditionAfterAnd) return false;
        expectsConditionAfterAnd = true;
        continue;
      }
      if (expectsConditionAfterAnd) return false;
      if (block.type == ObsAutomationBlockType.waitForUnifiedEvent ||
          block.type == ObsAutomationBlockType.waitForInput) {
        acceptsConditions = true;
        previousWasCondition = false;
        continue;
      }
      if (block.type == ObsAutomationBlockType.setEventVariable ||
          block.type == ObsAutomationBlockType.setValueVariable ||
          block.type == ObsAutomationBlockType.setVariable ||
          block.type == ObsAutomationBlockType.changeVariable) {
        acceptsConditions = true;
        previousWasCondition = false;
        continue;
      }
      if (_isAction(block.type)) {
        acceptsConditions = false;
        previousWasCondition = false;
        continue;
      }
      return false;
    }
    return true;
  }

  void _deleteBlock(String stackId, int index) {
    final preset = _selectedPreset;
    if (preset == null) return;
    final stacks = [...preset.stacks];
    final stackIndex = stacks.indexWhere((stack) => stack.id == stackId);
    if (stackIndex < 0) return;
    final stack = stacks[stackIndex];
    final blocks = [...stack.blocks]..removeAt(index);
    if (blocks.isEmpty) {
      stacks.removeAt(stackIndex);
    } else {
      stacks[stackIndex] = stack.copyWith(blocks: blocks);
    }
    _updateSelected((item) => item.copyWith(stacks: stacks));
  }

  void _setBlockParameter(String blockId, String key, String value) {
    _setBlockParameters(blockId, {key: value});
  }

  void _setBlockParameters(String blockId, Map<String, String> parameters) {
    final preset = _selectedPreset;
    if (preset == null) return;
    final stacks = preset.stacks.map((stack) {
      final blocks = stack.blocks.map((block) {
        if (block.id != blockId) return block;
        return block.copyWith(parameters: {...block.parameters, ...parameters});
      }).toList();
      return stack.copyWith(blocks: blocks);
    }).toList();
    _updateSelected((item) => item.copyWith(stacks: stacks));
  }

  ObsAutomationBlock _newBlock(
    ObsAutomationBlockType type, {
    _PaletteCategory? category,
  }) {
    if (_expressionReporterTypes.contains(type)) {
      return ObsAutomationBlock(
        id: 'template-${type.name}',
        type: type,
        parameters: {
          'kind': 'expression',
          'value': _defaultExpression(type).encode(),
        },
      );
    }
    final parameters = switch (type) {
      ObsAutomationBlockType.networkDetection ||
      ObsAutomationBlockType.stationChange => const {'network': 'any'},
      ObsAutomationBlockType.unifiedPhase => const {
        'operator': 'equals',
        'value': 'added',
      },
      ObsAutomationBlockType.networkPhase => const {
        'operator': 'equals',
        'value': 'confirmed',
      },
      ObsAutomationBlockType.stationPhase => const {
        'operator': 'equals',
        'value': 'triggered',
      },
      ObsAutomationBlockType.eventType => const {
        'operator': 'equals',
        'value': 'eew',
      },
      ObsAutomationBlockType.eewAgency => const {
        'operator': 'equals',
        'value': 'jma',
      },
      ObsAutomationBlockType.informationAgency => const {
        'operator': 'equals',
        'value': 'cenc',
      },
      ObsAutomationBlockType.informationReviewType => const {
        'operator': 'equals',
        'value': 'automatic',
      },
      ObsAutomationBlockType.sameEarthquakeAsVariable => const {
        'variable': '触发事件',
        'maxSeconds': '300',
        'maxDistanceKm': '300',
      },
      ObsAutomationBlockType.inputFieldMatchesVariable => const {
        'field': 'eventId',
        'operator': 'equals',
        'variable': '事件编号',
      },
      ObsAutomationBlockType.inputFieldCondition =>
        category == _PaletteCategory.stationConditions
            ? const {
                'family': 'station',
                'field': 'network',
                'operator': 'equals',
                'value': 'nied',
              }
            : const {
                'family': 'unified',
                'field': 'eventType',
                'operator': 'equals',
                'value': 'eew',
              },
      ObsAutomationBlockType.compareValues => const {
        'leftKind': 'empty',
        'leftValue': '',
        'leftFamily': 'unified',
        'operator': 'equals',
        'rightKind': 'empty',
        'rightValue': '',
        'rightFamily': 'unified',
      },
      ObsAutomationBlockType.inputFieldValue =>
        category == _PaletteCategory.stationConditions
            ? {
                'kind': 'inputField',
                'field': _selectedStationInputField,
                'family': 'station',
              }
            : {
                'kind': 'inputField',
                'field': _selectedUnifiedInputField,
                'family': 'unified',
              },
      ObsAutomationBlockType.variableValue => {
        'kind': 'variable',
        'value': _activeValueVariable,
      },
      ObsAutomationBlockType.valueVariableCondition => const {
        'variable': '事件编号',
        'operator': 'equals',
        'value': '',
      },
      ObsAutomationBlockType.source => const {
        'operator': 'equals',
        'value': '',
      },
      ObsAutomationBlockType.magnitude => const {
        'operator': 'greaterThanOrEqual',
        'value': '5.0',
      },
      ObsAutomationBlockType.estimatedIntensity => const {
        'operator': 'greaterThanOrEqual',
        'value': '5.0',
      },
      ObsAutomationBlockType.reportNumber => const {
        'operator': 'greaterThanOrEqual',
        'value': '1',
      },
      ObsAutomationBlockType.isFinal => const {'value': 'true'},
      ObsAutomationBlockType.networkMaxIntensity ||
      ObsAutomationBlockType.currentStationIntensity ||
      ObsAutomationBlockType.previousStationIntensity => const {
        'operator': 'greaterThanOrEqual',
        'value': '4',
      },
      ObsAutomationBlockType.detectedStationCount => const {
        'operator': 'greaterThanOrEqual',
        'value': '3',
      },
      ObsAutomationBlockType.stationId || ObsAutomationBlockType.stationName =>
        const {'operator': 'equals', 'value': ''},
      ObsAutomationBlockType.wait => const {'seconds': '1'},
      ObsAutomationBlockType.waitForUnifiedEvent => const {
        'timeoutSeconds': '1800',
      },
      ObsAutomationBlockType.waitForInput => const {
        'kind': 'unifiedEvent',
        'timeoutSeconds': '1800',
        'onTimeout': 'stopScript',
      },
      ObsAutomationBlockType.setEventVariable => const {'name': '目标事件'},
      ObsAutomationBlockType.setValueVariable => const {
        'field': 'eventId',
        'name': '事件编号',
      },
      ObsAutomationBlockType.setVariable => const {
        'name': '变量',
        'valueKind': 'empty',
        'value': '',
        'valueFamily': 'unified',
      },
      ObsAutomationBlockType.changeVariable => const {
        'name': '变量',
        'operation': 'add',
        'operand': '1',
      },
      ObsAutomationBlockType.createRecordChapter => const {'text': '地震事件'},
      ObsAutomationBlockType.setTextSourceText => const {
        'inputName': '地震字幕',
        'textKind': 'empty',
        'textValue': '',
        'textFamily': 'unified',
      },
      ObsAutomationBlockType.setCurrentProgramScene => const {
        'sceneName': '地震画面',
      },
      ObsAutomationBlockType.setSceneItemEnabled => const {
        'sceneName': '地震画面',
        'sourceName': '地震字幕',
        'enabledKind': 'literal',
        'enabledValue': 'true',
        'enabledFamily': 'unified',
      },
      _ => const <String, String>{},
    };
    return ObsAutomationBlock(
      id: 'template-${type.name}',
      type: type,
      parameters: parameters,
    );
  }

  ObsAutomationValueNode _defaultExpression(ObsAutomationBlockType type) {
    const zero = ObsAutomationValueNode.literal('0');
    const one = ObsAutomationValueNode.literal('1');
    return switch (type) {
      ObsAutomationBlockType.arithmeticValue =>
        const ObsAutomationValueNode.operation(
          'arithmetic',
          options: {'operator': 'add'},
          arguments: [one, one],
        ),
      ObsAutomationBlockType.randomValue =>
        const ObsAutomationValueNode.operation(
          'random',
          arguments: [one, ObsAutomationValueNode.literal('10')],
        ),
      ObsAutomationBlockType.moduloValue =>
        const ObsAutomationValueNode.operation(
          'modulo',
          arguments: [ObsAutomationValueNode.literal('10'), one],
        ),
      ObsAutomationBlockType.roundValue =>
        const ObsAutomationValueNode.operation(
          'round',
          arguments: [ObsAutomationValueNode.literal('1.5')],
        ),
      ObsAutomationBlockType.mathValue =>
        const ObsAutomationValueNode.operation(
          'math',
          options: {'operator': 'abs'},
          arguments: [zero],
        ),
      ObsAutomationBlockType.textJoinValue =>
        const ObsAutomationValueNode.operation(
          'join',
          arguments: [
            ObsAutomationValueNode.literal('文本'),
            ObsAutomationValueNode.literal('内容'),
          ],
        ),
      ObsAutomationBlockType.textLengthValue =>
        const ObsAutomationValueNode.operation(
          'length',
          arguments: [ObsAutomationValueNode.literal('文本')],
        ),
      ObsAutomationBlockType.textContainsValue =>
        const ObsAutomationValueNode.operation(
          'contains',
          arguments: [
            ObsAutomationValueNode.literal('文本'),
            ObsAutomationValueNode.literal('内容'),
          ],
        ),
      ObsAutomationBlockType.comparisonValue =>
        const ObsAutomationValueNode.operation(
          'comparison',
          options: {'operator': 'equals'},
          arguments: [zero, zero],
        ),
      ObsAutomationBlockType.booleanValue =>
        const ObsAutomationValueNode.operation(
          'boolean',
          options: {'operator': 'and'},
          arguments: [
            ObsAutomationValueNode.literal('true'),
            ObsAutomationValueNode.literal('true'),
          ],
        ),
      ObsAutomationBlockType.notValue => const ObsAutomationValueNode.operation(
        'not',
        arguments: [ObsAutomationValueNode.literal('true')],
      ),
      _ => zero,
    };
  }

  List<ObsAutomationBlockType> _paletteTypes(_PaletteCategory category) {
    return switch (category) {
      _PaletteCategory.events => const [
        ObsAutomationBlockType.unifiedEvent,
        ObsAutomationBlockType.networkDetection,
        ObsAutomationBlockType.stationChange,
      ],
      _PaletteCategory.logic => const [
        ObsAutomationBlockType.compareValues,
        ObsAutomationBlockType.andBranch,
        ObsAutomationBlockType.orBranch,
      ],
      _PaletteCategory.operators => const [
        ObsAutomationBlockType.arithmeticValue,
        ObsAutomationBlockType.randomValue,
        ObsAutomationBlockType.moduloValue,
        ObsAutomationBlockType.roundValue,
        ObsAutomationBlockType.mathValue,
        ObsAutomationBlockType.textJoinValue,
        ObsAutomationBlockType.textLengthValue,
        ObsAutomationBlockType.textContainsValue,
        ObsAutomationBlockType.comparisonValue,
        ObsAutomationBlockType.booleanValue,
        ObsAutomationBlockType.notValue,
      ],
      _PaletteCategory.uiConditions => const [
        ObsAutomationBlockType.inputFieldValue,
        ObsAutomationBlockType.inputFieldCondition,
        ObsAutomationBlockType.unifiedPhase,
        ObsAutomationBlockType.isEew,
        ObsAutomationBlockType.isInformation,
        ObsAutomationBlockType.eewAgency,
        ObsAutomationBlockType.informationAgency,
        ObsAutomationBlockType.informationReviewType,
        ObsAutomationBlockType.eventType,
        ObsAutomationBlockType.magnitude,
      ],
      _PaletteCategory.stationConditions => const [
        ObsAutomationBlockType.inputFieldValue,
        ObsAutomationBlockType.inputFieldCondition,
      ],
      _PaletteCategory.variables => const [
        ObsAutomationBlockType.variableValue,
        ObsAutomationBlockType.setEventVariable,
        ObsAutomationBlockType.setValueVariable,
        ObsAutomationBlockType.setVariable,
        ObsAutomationBlockType.changeVariable,
        ObsAutomationBlockType.sameEarthquakeAsVariable,
      ],
      _PaletteCategory.control => const [
        ObsAutomationBlockType.wait,
        ObsAutomationBlockType.waitForUnifiedEvent,
        ObsAutomationBlockType.waitForInput,
        ObsAutomationBlockType.stopScript,
      ],
      _PaletteCategory.obs => const [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.stopRecord,
        ObsAutomationBlockType.pauseRecord,
        ObsAutomationBlockType.resumeRecord,
        ObsAutomationBlockType.splitRecordFile,
        ObsAutomationBlockType.createRecordChapter,
        ObsAutomationBlockType.setTextSourceText,
        ObsAutomationBlockType.setCurrentProgramScene,
        ObsAutomationBlockType.setSceneItemEnabled,
        ObsAutomationBlockType.startReplayBuffer,
        ObsAutomationBlockType.stopReplayBuffer,
        ObsAutomationBlockType.saveReplayBuffer,
      ],
    };
  }

  Color _categoryColor(_PaletteCategory category) => switch (category) {
    _PaletteCategory.events => _eventColor,
    _PaletteCategory.logic => _logicColor,
    _PaletteCategory.operators => _operatorColor,
    _PaletteCategory.uiConditions => _uiConditionColor,
    _PaletteCategory.stationConditions => _stationConditionColor,
    _PaletteCategory.variables => _variableColor,
    _PaletteCategory.control => _controlColor,
    _PaletteCategory.obs => _obsColor,
  };

  String _categoryLabel(_PaletteCategory category) => switch (category) {
    _PaletteCategory.events => '事件',
    _PaletteCategory.logic => '逻辑',
    _PaletteCategory.operators => '运算',
    _PaletteCategory.uiConditions => 'UI 数据',
    _PaletteCategory.stationConditions => '测站数据',
    _PaletteCategory.variables => '变量',
    _PaletteCategory.control => '控制',
    _PaletteCategory.obs => 'OBS',
  };

  IconData _categoryIcon(_PaletteCategory category) => switch (category) {
    _PaletteCategory.events => Icons.bolt_outlined,
    _PaletteCategory.logic => Icons.alt_route,
    _PaletteCategory.operators => Icons.calculate_outlined,
    _PaletteCategory.uiConditions => Icons.view_compact_outlined,
    _PaletteCategory.stationConditions => Icons.sensors_outlined,
    _PaletteCategory.variables => Icons.data_object,
    _PaletteCategory.control => Icons.alt_route,
    _PaletteCategory.obs => Icons.videocam_outlined,
  };

  Color _blockColor(
    ObsAutomationBlock block, {
    _PaletteCategory? paletteCategory,
  }) {
    final type = block.type;
    if (_isInputHat(type)) return _eventColor;
    if (type == ObsAutomationBlockType.andBranch ||
        type == ObsAutomationBlockType.orBranch ||
        type == ObsAutomationBlockType.compareValues) {
      return _logicColor;
    }
    if (_expressionReporterTypes.contains(type)) return _operatorColor;
    if (type == ObsAutomationBlockType.setEventVariable ||
        type == ObsAutomationBlockType.setValueVariable ||
        type == ObsAutomationBlockType.setVariable ||
        type == ObsAutomationBlockType.changeVariable ||
        type == ObsAutomationBlockType.variableValue ||
        _variableConditionTypes.contains(type)) {
      return _variableColor;
    }
    if (type == ObsAutomationBlockType.inputFieldCondition ||
        type == ObsAutomationBlockType.inputFieldValue) {
      final isStation =
          paletteCategory == _PaletteCategory.stationConditions ||
          block.parameters['family'] == 'station';
      return isStation ? _stationConditionColor : _uiConditionColor;
    }
    if (_uiConditionTypes.contains(type)) return _uiConditionColor;
    if (_stationConditionTypes.contains(type)) return _stationConditionColor;
    if (type == ObsAutomationBlockType.wait ||
        type == ObsAutomationBlockType.waitForUnifiedEvent ||
        type == ObsAutomationBlockType.waitForInput ||
        type == ObsAutomationBlockType.stopScript) {
      return _controlColor;
    }
    return _obsColor;
  }

  IconData _blockIcon(ObsAutomationBlockType type) {
    if (_isInputHat(type)) return Icons.bolt;
    if (type == ObsAutomationBlockType.andBranch) return Icons.add_link;
    if (type == ObsAutomationBlockType.orBranch) return Icons.call_split;
    if (type == ObsAutomationBlockType.inputFieldValue) {
      return Icons.input_outlined;
    }
    if (type == ObsAutomationBlockType.variableValue) {
      return Icons.data_object;
    }
    if (_expressionReporterTypes.contains(type)) {
      return Icons.calculate_outlined;
    }
    if (_isCondition(type)) {
      return Icons.check_circle_outline;
    }
    if (type == ObsAutomationBlockType.wait) return Icons.timer_outlined;
    if (type == ObsAutomationBlockType.waitForUnifiedEvent ||
        type == ObsAutomationBlockType.waitForInput) {
      return Icons.hourglass_bottom;
    }
    if (type == ObsAutomationBlockType.setEventVariable ||
        type == ObsAutomationBlockType.setValueVariable ||
        type == ObsAutomationBlockType.setVariable ||
        type == ObsAutomationBlockType.changeVariable) {
      return Icons.data_object;
    }
    if (type == ObsAutomationBlockType.stopScript) return Icons.stop_circle;
    if (type == ObsAutomationBlockType.setTextSourceText) {
      return Icons.closed_caption_outlined;
    }
    if (type == ObsAutomationBlockType.setCurrentProgramScene) {
      return Icons.layers_outlined;
    }
    if (type == ObsAutomationBlockType.setSceneItemEnabled) {
      return Icons.visibility_outlined;
    }
    return Icons.videocam_outlined;
  }

  String _blockLabel(ObsAutomationBlockType type) => switch (type) {
    ObsAutomationBlockType.unifiedEvent => '统一 UI 事件输入',
    ObsAutomationBlockType.networkDetection => '台网检出输入',
    ObsAutomationBlockType.stationChange => '单测站变化输入',
    ObsAutomationBlockType.andBranch => '并且',
    ObsAutomationBlockType.orBranch => '或者',
    ObsAutomationBlockType.unifiedPhase => '事件阶段是进入',
    ObsAutomationBlockType.networkPhase => '检出状态是确认',
    ObsAutomationBlockType.stationPhase => '测站变化是首次触发',
    ObsAutomationBlockType.isEew => '是 EEW',
    ObsAutomationBlockType.isInformation => '是信息',
    ObsAutomationBlockType.eewAgency => 'EEW 机构是 JMA',
    ObsAutomationBlockType.informationAgency => '信息机构是 CENC',
    ObsAutomationBlockType.informationReviewType => '测定类型是自动测定',
    ObsAutomationBlockType.sameEarthquakeAsVariable => '当前事件与变量是同一地震',
    ObsAutomationBlockType.valueVariableCondition => '变量与值比较',
    ObsAutomationBlockType.inputFieldMatchesVariable => '输入字段与变量比较',
    ObsAutomationBlockType.inputFieldCondition => '输入字段与值比较',
    ObsAutomationBlockType.compareValues => '比较两个值',
    ObsAutomationBlockType.inputFieldValue => '输入字段值',
    ObsAutomationBlockType.variableValue => '变量值',
    ObsAutomationBlockType.arithmeticValue => '加减乘除',
    ObsAutomationBlockType.randomValue => '随机数',
    ObsAutomationBlockType.moduloValue => '取余数',
    ObsAutomationBlockType.roundValue => '四舍五入',
    ObsAutomationBlockType.mathValue => '数学函数',
    ObsAutomationBlockType.textJoinValue => '连接文本',
    ObsAutomationBlockType.textLengthValue => '文本长度',
    ObsAutomationBlockType.textContainsValue => '文本包含',
    ObsAutomationBlockType.comparisonValue => '比较结果',
    ObsAutomationBlockType.booleanValue => '并且 / 或者',
    ObsAutomationBlockType.notValue => '取反',
    ObsAutomationBlockType.eventType => '事件类型等于地震预警',
    ObsAutomationBlockType.source => '来源等于',
    ObsAutomationBlockType.magnitude => '震级大于等于 5.0',
    ObsAutomationBlockType.estimatedIntensity => '最大震度/烈度大于等于 5.0',
    ObsAutomationBlockType.reportNumber => '报数大于等于 1',
    ObsAutomationBlockType.isFinal => '是最终报',
    ObsAutomationBlockType.networkMaxIntensity => '台网最大震度大于等于 4',
    ObsAutomationBlockType.detectedStationCount => '检出测站数大于等于 3',
    ObsAutomationBlockType.stationId => '测站编号等于',
    ObsAutomationBlockType.stationName => '测站名称等于',
    ObsAutomationBlockType.currentStationIntensity => '当前震度大于等于 4',
    ObsAutomationBlockType.previousStationIntensity => '上一震度大于等于 4',
    ObsAutomationBlockType.wait => '等待 1 秒',
    ObsAutomationBlockType.waitForUnifiedEvent => '等待统一 UI 事件',
    ObsAutomationBlockType.waitForInput => '等待指定输入',
    ObsAutomationBlockType.setEventVariable => '保存当前输入为变量',
    ObsAutomationBlockType.setValueVariable => '提取输入参数为变量',
    ObsAutomationBlockType.setVariable => '设置变量',
    ObsAutomationBlockType.changeVariable => '修改变量',
    ObsAutomationBlockType.stopScript => '停止当前脚本',
    ObsAutomationBlockType.startRecord => '开始录制',
    ObsAutomationBlockType.stopRecord => '结束录制',
    ObsAutomationBlockType.pauseRecord => '暂停录制',
    ObsAutomationBlockType.resumeRecord => '恢复录制',
    ObsAutomationBlockType.splitRecordFile => '分割录像文件',
    ObsAutomationBlockType.createRecordChapter => '添加录像章节',
    ObsAutomationBlockType.setTextSourceText => '设置 OBS 文本源内容',
    ObsAutomationBlockType.setCurrentProgramScene => '切换 OBS 当前场景',
    ObsAutomationBlockType.setSceneItemEnabled => '显示或隐藏 OBS 来源',
    ObsAutomationBlockType.startReplayBuffer => '启动回放缓存',
    ObsAutomationBlockType.stopReplayBuffer => '停止回放缓存',
    ObsAutomationBlockType.saveReplayBuffer => '保存回放',
  };
}

class _BlockDragPayload {
  const _BlockDragPayload._({
    this.template,
    this.sourceStackId,
    this.startIndex = 0,
    required this.firstType,
  });

  factory _BlockDragPayload.template(ObsAutomationBlock block) {
    return _BlockDragPayload._(template: block, firstType: block.type);
  }

  factory _BlockDragPayload.existing({
    required String stackId,
    required int startIndex,
    required ObsAutomationBlockType firstType,
  }) {
    return _BlockDragPayload._(
      sourceStackId: stackId,
      startIndex: startIndex,
      firstType: firstType,
    );
  }

  final ObsAutomationBlock? template;
  final String? sourceStackId;
  final int startIndex;
  final ObsAutomationBlockType firstType;
}

class _ValueDragPayload {
  const _ValueDragPayload({
    required this.kind,
    required this.value,
    this.family,
  });

  factory _ValueDragPayload.fromBlock(ObsAutomationBlock block) {
    return switch (block.type) {
      ObsAutomationBlockType.inputFieldValue => _ValueDragPayload(
        kind: 'inputField',
        value: block.parameters['field'] ?? 'eventType',
        family: block.parameters['family'] ?? 'unified',
      ),
      ObsAutomationBlockType.variableValue => _ValueDragPayload(
        kind: 'variable',
        value: block.parameters['value'] ?? '变量',
      ),
      ObsAutomationBlockType.arithmeticValue ||
      ObsAutomationBlockType.randomValue ||
      ObsAutomationBlockType.moduloValue ||
      ObsAutomationBlockType.roundValue ||
      ObsAutomationBlockType.mathValue ||
      ObsAutomationBlockType.textJoinValue ||
      ObsAutomationBlockType.textLengthValue ||
      ObsAutomationBlockType.textContainsValue ||
      ObsAutomationBlockType.comparisonValue ||
      ObsAutomationBlockType.booleanValue ||
      ObsAutomationBlockType.notValue => _ValueDragPayload(
        kind: 'expression',
        value: block.parameters['value'] ?? '',
      ),
      _ => throw ArgumentError.value(block.type, 'block.type'),
    };
  }

  final String kind;
  final String value;
  final String? family;

  ObsAutomationValueNode toValueNode() {
    if (kind == 'expression') {
      return ObsAutomationValueNode.tryDecode(value) ??
          const ObsAutomationValueNode.literal('');
    }
    return ObsAutomationValueNode(kind: kind, value: value, family: family);
  }
}

class _ObsConnectionFormValue {
  const _ObsConnectionFormValue({
    required this.enabled,
    required this.host,
    required this.port,
    required this.password,
    required this.autoReconnect,
  });

  final bool enabled;
  final String host;
  final int port;
  final String password;
  final bool autoReconnect;
}

class _SnapTarget {
  const _SnapTarget({
    required this.stackId,
    required this.insertIndex,
    required this.x,
    required this.y,
  });

  final String stackId;
  final int insertIndex;
  final double x;
  final double y;

  @override
  bool operator ==(Object other) {
    return other is _SnapTarget &&
        other.stackId == stackId &&
        other.insertIndex == insertIndex &&
        other.x == x &&
        other.y == y;
  }

  @override
  int get hashCode => Object.hash(stackId, insertIndex, x, y);
}

class _ScratchBlockPainter extends CustomPainter {
  const _ScratchBlockPainter({
    required this.color,
    required this.isHat,
    this.compact = false,
  });

  final Color color;
  final bool isHat;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = compact ? 5.0 : 7.0;
    final notchX = compact ? 30.0 : 48.0;
    final notchWidth = compact ? 25.0 : 34.0;
    final notchDepth = compact ? 4.0 : 6.0;
    final path = Path();
    if (isHat) {
      path.moveTo(0, 18);
      path.quadraticBezierTo(size.width * 0.12, 0, size.width * 0.30, 7);
      path.lineTo(size.width - radius, 7);
      path.quadraticBezierTo(size.width, 7, size.width, 7 + radius);
    } else {
      path.moveTo(radius, 0);
      path.lineTo(notchX, 0);
      path.lineTo(notchX + 7, notchDepth);
      path.lineTo(notchX + notchWidth - 7, notchDepth);
      path.lineTo(notchX + notchWidth, 0);
      path.lineTo(size.width - radius, 0);
      path.quadraticBezierTo(size.width, 0, size.width, radius);
    }
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - radius,
      size.height,
    );
    path.lineTo(notchX + notchWidth, size.height);
    path.lineTo(notchX + notchWidth - 7, size.height + notchDepth);
    path.lineTo(notchX + 7, size.height + notchDepth);
    path.lineTo(notchX, size.height);
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.close();

    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _ScratchBlockPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isHat != isHat ||
        oldDelegate.compact != compact;
  }
}

class _CanvasGridPainter extends CustomPainter {
  const _CanvasGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color.fromRGBO(19, 20, 24, 0.86),
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    const step = 24.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
