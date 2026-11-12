import 'dart:convert';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/obs_automation_preset.dart';
import '../../models/obs_automation_builtin_presets.dart';
import '../../services/obs_automation_runtime_service.dart';
import '../../services/obs_websocket_service.dart';
import 'app_page_background.dart';
import 'settings_controls.dart';
import 'obs_recording_form.dart';
import 'obs_recording_connection_dialog.dart';

class ObsAutomationPresetsPage extends StatefulWidget {
  const ObsAutomationPresetsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ObsAutomationPresetsPage> createState() =>
      _ObsAutomationPresetsPageState();
}

class _ObsAutomationPresetsPageState extends State<ObsAutomationPresetsPage> {
  static const _preferenceKey = obsAutomationPresetsPreferenceKey;
  static const _accent = SettingsControlStyle.accent;
  static const _border = SettingsControlStyle.border;
  static const _muted = SettingsControlStyle.muted;
  static const _numericOperators = {
    'equals': '=',
    'notEquals': '≠',
    'greaterThan': '>',
    'greaterThanOrEqual': '≥',
    'lessThan': '<',
    'lessThanOrEqual': '≤',
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

  final _horizontalController = ScrollController();
  final _verticalController = ScrollController();
  List<ObsAutomationPreset> _presets = const [];
  String? _selectedId;
  bool _loading = true, _saving = false, _dirty = false, _saveAgain = false;
  int _idSequence = 0, _revision = 0;
  Timer? _autoSaveTimer;
  bool _expandedEndSources = false;
  String? _matchSeconds, _matchDistanceKm, _waitSeconds, _saveError;
  final _draftUnits = <String, ObsAutomationBlockType>{};
  final _draftValues = <String, String>{};
  final _triggerErrors = <String, String>{};
  static const _expandedKey = 'obs_recording_extended_end_sources';
  static const _matchSecondsKey = 'obs_recording_match_seconds';
  static const _matchDistanceKey = 'obs_recording_match_distance_km';
  static const _waitSecondsKey = 'obs_recording_wait_seconds';
  ObsAutomationPreset? get _selectedPreset =>
      _presets.where((preset) => preset.id == _selectedId).firstOrNull;
  bool _isAction(ObsAutomationBlockType type) => _actionTypes.contains(type);
  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (_dirty) unawaited(_savePresets(updateUi: false));
    _horizontalController.dispose();
    _verticalController.dispose();
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
        error = 'OBS 设置读取失败，原配置未被覆盖';
      }
    }
    final upgraded = upgradeBuiltInEewRecordingPresets(loaded);
    var builtInAdded = !identical(upgraded, loaded);
    loaded = upgraded;
    ObsAutomationPreset? builtInPreset;
    if (error == null) {
      for (final preset in loaded) {
        if (isBuiltInEewRecordingPreset(preset)) {
          builtInPreset = preset;
          break;
        }
      }
      if (builtInPreset == null) {
        builtInPreset = buildEewRecordingPreset(nextId: _newId);
        loaded = [...loaded, builtInPreset];
        builtInAdded = true;
      }
    }
    final selectedId =
        builtInPreset?.id ?? (loaded.isEmpty ? null : loaded.first.id);
    final existing = builtInPreset?.stacks ?? const <ObsAutomationStack>[];
    String? common(
      ObsAutomationBlockType type,
      String parameter,
      String preference,
      String fallback,
    ) {
      final values = existing
          .expand((rule) => rule.blocks)
          .where((block) => block.type == type)
          .map((block) => block.parameters[parameter])
          .whereType<String>()
          .toSet();
      return values.length > 1
          ? null
          : values.firstOrNull ?? prefs.getString(preference) ?? fallback;
    }

    _matchSeconds = common(
      ObsAutomationBlockType.sameEarthquakeAsVariable,
      'maxSeconds',
      _matchSecondsKey,
      '300',
    );
    _matchDistanceKm = common(
      ObsAutomationBlockType.sameEarthquakeAsVariable,
      'maxDistanceKm',
      _matchDistanceKey,
      '300',
    );
    _waitSeconds = common(
      ObsAutomationBlockType.waitForUnifiedEvent,
      'timeoutSeconds',
      _waitSecondsKey,
      obsRecordingDefaultLimitSeconds,
    );
    if (builtInPreset != null && !existing.any(obsIsCencInformationRule)) {
      final updated = builtInPreset.copyWith(
        stacks: [
          ...existing,
          obsBuildCencInformationRule(
            builtInPreset.id,
            _newId,
            maxSeconds: _matchSeconds ?? '300',
            maxDistanceKm: _matchDistanceKm ?? '300',
            timeoutSeconds: _waitSeconds ?? obsRecordingDefaultLimitSeconds,
          ),
        ],
      );
      loaded = [
        for (final preset in loaded) preset.id == updated.id ? updated : preset,
      ];
      builtInAdded = true;
    }
    if (!mounted) return;
    setState(() {
      _presets = loaded;
      _selectedId = selectedId;
      _loading = false;
      _dirty = builtInAdded;
      _expandedEndSources = prefs.getBool(_expandedKey) ?? false;
    });
    if (error != null) _showMessage(error);
    if (builtInAdded) _scheduleSave();
  }

  String _newId(String prefix) {
    _idSequence++;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idSequence';
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
      _revision++;
      _saveError = null;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_savePresets()),
    );
  }

  Future<void> _savePresets({
    bool announce = false,
    bool updateUi = true,
  }) async {
    if (_saving) {
      _saveAgain = true;
      return;
    }
    if (mounted && updateUi) {
      setState(() => _saving = true);
    } else {
      _saving = true;
    }
    var savedRevision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      do {
        _saveAgain = false;
        savedRevision = _revision;
        final payload = jsonEncode(
          ObsAutomationPresetDocument(presets: _presets).toJson(),
        );
        if (!await prefs.setString(_preferenceKey, payload)) {
          throw StateError('Settings write rejected');
        }
        await ObsAutomationRuntimeService().reloadPresets(preferences: prefs);
        final error = ObsAutomationRuntimeService().presetErrorNotifier.value;
        if (error != null) throw StateError(error);
      } while (_saveAgain);
      if (!mounted) return;
      setState(() => _dirty = _revision != savedRevision);
      if (announce) _showMessage('OBS 设置已保存');
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = '自动保存失败：$error');
        _showMessage('OBS 设置保存失败');
      }
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
    final connection = await runtime.loadConnectionSettings();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ObsRecordingConnectionDialog(
        connection: connection,
        expandedSources: _expandedEndSources,
        matchSeconds: _matchSeconds,
        matchDistanceKm: _matchDistanceKm,
        waitSeconds: _waitSeconds,
        onConnectionChanged: (settings) => runtime.configureConnection(
          enabled: settings.enabled,
          host: settings.host,
          port: settings.port,
          password: settings.password,
          autoReconnect: settings.autoReconnect,
        ),
        onExpandedChanged: (value) async {
          if (mounted) setState(() => _expandedEndSources = value);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_expandedKey, value);
        },
        onRecordingChanged: _changeCommonRecording,
      ),
    );
  }

  Future<void> _changeCommonRecording(String key, String value) async {
    if (mounted) {
      _updateSelected(
        (preset) => preset.copyWith(
          stacks: [
            for (final rule in preset.stacks)
              rule.copyWith(
                blocks: [
                  for (final block in rule.blocks)
                    if (key == 'timeoutSeconds' &&
                            (block.type ==
                                    ObsAutomationBlockType
                                        .waitForUnifiedEvent ||
                                block.type ==
                                    ObsAutomationBlockType.waitForInput) ||
                        key != 'timeoutSeconds' &&
                            block.type ==
                                ObsAutomationBlockType.sameEarthquakeAsVariable)
                      block.copyWith(
                        parameters: {...block.parameters, key: value},
                      )
                    else
                      block,
                ],
              ),
          ],
        ),
      );
      setState(() {
        switch (key) {
          case 'maxSeconds':
            _matchSeconds = value;
          case 'maxDistanceKm':
            _matchDistanceKm = value;
          case 'timeoutSeconds':
            _waitSeconds = value;
        }
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(switch (key) {
      'maxSeconds' => _matchSecondsKey,
      'maxDistanceKm' => _matchDistanceKey,
      _ => _waitSecondsKey,
    }, value);
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
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(primary: _accent),
    ),
    child: widget.embedded
        ? _buildRecordingContent()
        : Scaffold(
            backgroundColor: const Color(0xFF020208),
            body: Stack(
              children: [
                const AppPageBackground(),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: SettingsControlStyle.blurSigma,
                          sigmaY: SettingsControlStyle.blurSigma,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: SettingsControlStyle.panel,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border),
                          ),
                          child: _buildRecordingContent(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _buildRecordingContent() => _loading
      ? const Center(child: CircularProgressIndicator())
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.embedded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 20, 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'OBS 自动录制',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: SettingsControlStyle.divider),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: ValueListenableBuilder<ObsConnectionState>(
                valueListenable:
                    ObsAutomationRuntimeService().obs.connectionStateNotifier,
                builder: (context, state, _) => SettingsControlRow(
                  title: 'OBS 连接',
                  subtitle: '连接 OBS WebSocket 后执行自动录制',
                  leading: Icons.videocam_outlined,
                  control: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          'OBS ${_connectionStateLabel(state)}',
                          key: const ValueKey('obs-connection-status'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: _connectionStateColor(state),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SettingsGlassAction(
                        label: '连接●录制设置',
                        icon: Icons.settings_outlined,
                        onPressed: _openConnectionSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: SettingsControlStyle.divider),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Text(
                    '自动录制规则',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_selectedPreset?.stacks.length ?? 0} 项',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const Spacer(),
                  const Flexible(
                    child: Text(
                      '固定机构 · 独立启用',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildRulesTable()),
            const Divider(height: 1, color: SettingsControlStyle.divider),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                _saveError ??
                    (_triggerErrors.isNotEmpty
                        ? '有未完成的触发数值，尚未保存。'
                        : _saving
                        ? '正在自动保存…'
                        : _dirty
                        ? '等待自动保存…'
                        : '已自动保存'),
                style: TextStyle(
                  fontSize: 12,
                  color: _dirty ? _accent : _muted,
                ),
              ),
            ),
          ],
        );

  Widget _buildRulesTable() {
    final rules = _selectedPreset?.stacks ?? const <ObsAutomationStack>[];
    if (rules.isEmpty) {
      return const Center(
        child: Text('暂无自动录制规则', style: TextStyle(color: _muted)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          key: const ValueKey('obs-rule-horizontal-scroll'),
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalController,
                child: DataTable(
                  key: const ValueKey('obs-rules-table'),
                  horizontalMargin: 20,
                  columnSpacing: 28,
                  headingRowHeight: 40,
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 60,
                  headingRowColor: WidgetStatePropertyAll(
                    Colors.white.withValues(alpha: .04),
                  ),
                  headingTextStyle: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  dataTextStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  border: const TableBorder(
                    horizontalInside: BorderSide(
                      color: SettingsControlStyle.divider,
                    ),
                  ),
                  columns: const [
                    DataColumn(label: Text('机构')),
                    DataColumn(label: Text('触发条件')),
                    DataColumn(label: Text('结束录制')),
                    DataColumn(label: Text('附加时间 / 秒')),
                    DataColumn(label: Text('启用')),
                  ],
                  rows: [for (final rule in rules) _ruleRow(rule)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _ruleRow(ObsAutomationStack rule) {
    final filter = rule.blocks
        .takeWhile((block) => !_isAction(block.type))
        .where(
          (block) =>
              block.type == ObsAutomationBlockType.magnitude ||
              block.type == ObsAutomationBlockType.estimatedIntensity,
        )
        .firstOrNull;
    final unit =
        _draftUnits[rule.id] ??
        (rule.triggerField == 'estimatedIntensity'
            ? ObsAutomationBlockType.estimatedIntensity
            : filter?.type ?? ObsAutomationBlockType.magnitude);
    final text =
        _draftValues[rule.id] ??
        _triggerDisplay(rule, unit, filter?.parameters['value'] ?? '0');
    final currentEnd = obsRecordingCurrentEnd(rule);
    final endChoices = obsRecordingAvailableEnds(
      rule,
      expanded: _expandedEndSources,
    );
    final delay = obsRecordingDelay(rule);
    return DataRow(
      key: ValueKey('obs-rule-${rule.id}'),
      cells: [
        DataCell(
          SizedBox(
            width: 174,
            child: Text(
              _ruleTitle(rule),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        DataCell(
          obsRecordingUsesAlertTrigger(rule)
              ? _selectField<String>(
                  key: ValueKey('obs-alert-trigger-${rule.id}'),
                  width: 196,
                  value: obsRecordingAlertTrigger(rule),
                  options: {
                    ...obsRecordingAlertTriggers,
                    if (obsRecordingAlertTrigger(rule) == 'custom')
                      'custom': '按当前已确认条件',
                  },
                  onChanged: (value) => _replaceRecordingRule(
                    obsRecordingChooseAlertTrigger(rule, value, _newId),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _selectField<ObsAutomationBlockType>(
                          key: ValueKey('obs-trigger-unit-${rule.id}'),
                          width: 94,
                          value: unit,
                          options: {
                            ObsAutomationBlockType.magnitude: '震级 M',
                            ObsAutomationBlockType.estimatedIntensity:
                                obsRecordingIntensityLabel(rule),
                          },
                          onChanged: (value) =>
                              _changeTrigger(rule.id, value, text),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 94,
                          height: 34,
                          child: TextFormField(
                            key: ValueKey(
                              'obs-trigger-${rule.id}-${unit.name}',
                            ),
                            initialValue: text,
                            keyboardType:
                                unit ==
                                        ObsAutomationBlockType
                                            .estimatedIntensity &&
                                    obsRecordingUsesShindo(rule)
                                ? TextInputType.text
                                : const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            style: const TextStyle(fontSize: 13),
                            decoration: _numberDecoration(hintText: '不限').copyWith(
                              prefixText:
                                  '${_numericOperators[filter?.parameters['operator']] ?? '≥'} ',
                            ),
                            onChanged: (value) =>
                                _changeTrigger(rule.id, unit, value),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        DataCell(
          PopupMenuButton<String>(
            key: ValueKey('obs-end-${rule.id}'),
            tooltip: '选择结束录制的情报类型',
            initialValue: currentEnd?.id,
            color: const Color(0xFF292B31),
            constraints: const BoxConstraints(
              minWidth: 240,
              maxWidth: 350,
              maxHeight: 480,
            ),
            onSelected: (id) {
              final option = obsRecordingEndChoices.firstWhere(
                (choice) => choice.id == id,
              );
              _replaceRecordingRule(
                obsRecordingChooseEnd(
                  rule,
                  option,
                  _newId,
                  maxSeconds: _matchSeconds ?? '300',
                  maxDistanceKm: _matchDistanceKm ?? '300',
                  timeoutSeconds: _waitSeconds,
                ),
              );
            },
            itemBuilder: (_) => [
              for (final choice in endChoices)
                CheckedPopupMenuItem<String>(
                  value: choice.id,
                  checked: choice.id == currentEnd?.id,
                  child: Text(
                    choice.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            child: Container(
              width: 246,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: SettingsControlStyle.field,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SettingsControlStyle.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      currentEnd?.label ?? '按当前已确认条件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, size: 17, color: _muted),
                ],
              ),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 86,
            height: 34,
            child: TextFormField(
              key: ValueKey(
                'obs-extra-time-${rule.id}-${delay.isEmpty ? 'timed' : 'information'}',
              ),
              initialValue: delay,
              enabled: delay.isNotEmpty,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 13),
              decoration: _numberDecoration(hintText: '—'),
              onChanged: (value) {
                final number = double.tryParse(value);
                if (number != null && number.isFinite && number >= 0) {
                  final current = _selectedPreset!.stacks.firstWhere(
                    (item) => item.id == rule.id,
                  );
                  _replaceRecordingRule(
                    obsRecordingSetDelay(current, value, _newId),
                  );
                }
              },
            ),
          ),
        ),
        DataCell(
          Switch(
            key: ValueKey('obs-rule-enabled-${rule.id}'),
            value: _selectedPreset!.enabled && rule.enabled,
            activeTrackColor: _accent,
            activeThumbColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            inactiveThumbColor: Colors.white70,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (value) => _setRuleEnabled(rule.id, value),
          ),
        ),
      ],
    );
  }

  Widget _selectField<T>({
    required Key key,
    required double width,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
  }) => Container(
    key: key,
    width: width,
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: SettingsControlStyle.field,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: SettingsControlStyle.border),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        dropdownColor: const Color(0xFF292B31),
        icon: const Icon(Icons.expand_more, size: 17),
        items: [
          for (final entry in options.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(
                entry.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ),
  );

  String _triggerDisplay(
    ObsAutomationStack rule,
    ObsAutomationBlockType unit,
    String raw,
  ) {
    if (unit != ObsAutomationBlockType.estimatedIntensity ||
        !obsRecordingUsesShindo(rule)) {
      return raw;
    }
    final number = double.tryParse(raw);
    if (number == null || number != number.roundToDouble()) return raw;
    return const {
          0: '0',
          1: '1',
          2: '2',
          3: '3',
          4: '4',
          5: '5-',
          6: '5+',
          7: '6-',
          8: '6+',
          9: '7',
        }[number.toInt()] ??
        raw;
  }

  void _changeTrigger(String ruleId, ObsAutomationBlockType unit, String raw) {
    final rule = _selectedPreset!.stacks.firstWhere(
      (item) => item.id == ruleId,
    );
    String? stored;
    final value = raw.trim();
    if (value.isNotEmpty &&
        unit == ObsAutomationBlockType.estimatedIntensity &&
        obsRecordingUsesShindo(rule)) {
      final normalized = value.replaceAll('−', '-').replaceAll('＋', '+');
      stored = const {
        '0': '0',
        '1': '1',
        '2': '2',
        '3': '3',
        '4': '4',
        '5': '5',
        '5-': '5',
        '5+': '6',
        '6': '7',
        '6-': '7',
        '6+': '8',
        '7': '9',
      }[normalized];
      if (stored == null) {
        final number = double.tryParse(normalized);
        if (number != null && number == number.roundToDouble()) {
          stored = const {
            0: '0',
            1: '1',
            2: '2',
            3: '3',
            4: '4',
            5: '5',
            6: '7',
            7: '9',
          }[number.toInt()];
        }
      }
    } else if (value.isNotEmpty) {
      final number = double.tryParse(value);
      if (number != null && number.isFinite && number >= 0) stored = raw;
    }
    setState(() {
      _draftUnits[ruleId] = unit;
      _draftValues[ruleId] = raw;
      if (value.isNotEmpty && stored == null) {
        _triggerErrors[ruleId] =
            obsRecordingUsesShindo(rule) &&
                unit == ObsAutomationBlockType.estimatedIntensity
            ? '可填 0–4、5-/5+、6-/6+、7'
            : '请填写有效数值';
      } else {
        _triggerErrors.remove(ruleId);
      }
    });
    if (_triggerErrors.containsKey(ruleId)) return;
    final firstAction = rule.blocks.indexWhere(
      (block) => _isAction(block.type),
    );
    final boundary = firstAction < 0 ? rule.blocks.length : firstAction;
    final old = rule.blocks
        .take(boundary)
        .where(
          (block) =>
              block.type == ObsAutomationBlockType.magnitude ||
              block.type == ObsAutomationBlockType.estimatedIntensity,
        )
        .firstOrNull;
    final blocks = [...rule.blocks];
    if (value.isEmpty ||
        unit == ObsAutomationBlockType.magnitude &&
            double.tryParse(stored ?? '') == 0) {
      blocks.removeWhere(
        (block) =>
            rule.blocks.indexOf(block) < boundary &&
            (block.type == ObsAutomationBlockType.magnitude ||
                block.type == ObsAutomationBlockType.estimatedIntensity),
      );
    } else if (old != null) {
      blocks[blocks.indexOf(old)] = old.copyWith(
        type: unit,
        parameters: {...old.parameters, 'value': stored!},
      );
    } else {
      blocks.insert(
        boundary,
        ObsAutomationBlock(
          id: _newId('block'),
          type: unit,
          parameters: {'operator': 'greaterThanOrEqual', 'value': stored!},
        ),
      );
    }
    _replaceRecordingRule(
      rule.copyWith(
        blocks: blocks,
        triggerField: rule.triggerField != null || old?.type != unit
            ? unit.name
            : null,
      ),
    );
  }

  void _replaceRecordingRule(ObsAutomationStack rule) => _updateSelected(
    (preset) => preset.copyWith(
      stacks: [
        for (final item in preset.stacks) item.id == rule.id ? rule : item,
      ],
    ),
  );

  Future<void> _setRuleEnabled(String ruleId, bool value) async {
    _updateSelected(
      (preset) => preset.copyWith(
        enabled: true,
        stacks: [
          for (final stack in preset.stacks)
            stack.copyWith(
              enabled: stack.id == ruleId
                  ? value
                  : preset.enabled && stack.enabled,
            ),
        ],
      ),
    );
    await _savePresets(announce: false);
  }

  InputDecoration _numberDecoration({String? hintText}) => InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(fontSize: 12, color: _muted),
    isDense: true,
    filled: true,
    fillColor: SettingsControlStyle.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: SettingsControlStyle.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _accent),
    ),
  );

  String _ruleTitle(ObsAutomationStack stack) {
    if (obsIsCencInformationRule(stack)) return 'CENC 自动测定';
    const agencies = {
      'cea': 'CEA',
      'sichuan': '四川省地震局',
      'fujian': '福建省地震局',
      'chongqing': '重庆市地震局',
      'jma': 'JMA',
      'cwa': 'CWA',
      'kma': 'KMA',
      'icl': 'ICL',
      'globalQuake': 'GlobalQuake',
      'sasmex': 'SASMEX',
      'shakeAlert': 'ShakeAlert',
    };
    for (final block in stack.blocks) {
      if (block.type == ObsAutomationBlockType.eewAgency) {
        return '${agencies[block.parameters['value']] ?? block.parameters['value']}-EEW';
      }
      if (block.type == ObsAutomationBlockType.networkDetection) {
        return '${block.parameters['network'] == 'any' ? '任意台网' : block.parameters['network']?.toUpperCase()}检出';
      }
      if (block.type == ObsAutomationBlockType.stationChange) {
        return '${block.parameters['network'] == 'any' ? '任意台网' : block.parameters['network']?.toUpperCase()}测站变化';
      }
    }
    return '规则 ${(_selectedPreset?.stacks.indexOf(stack) ?? 0) + 1}';
  }
}
