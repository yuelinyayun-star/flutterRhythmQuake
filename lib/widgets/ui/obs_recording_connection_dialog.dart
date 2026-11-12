import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/obs_automation_runtime_service.dart';
import 'settings_controls.dart';

class ObsRecordingConnectionDialog extends StatefulWidget {
  const ObsRecordingConnectionDialog({
    super.key,
    required this.connection,
    required this.expandedSources,
    required this.matchSeconds,
    required this.matchDistanceKm,
    required this.waitSeconds,
    required this.onConnectionChanged,
    required this.onExpandedChanged,
    required this.onRecordingChanged,
  });
  final ObsAutomationConnectionSettings connection;
  final bool expandedSources;
  final String? matchSeconds, matchDistanceKm, waitSeconds;
  final Future<void> Function(ObsAutomationConnectionSettings)
  onConnectionChanged;
  final Future<void> Function(bool) onExpandedChanged;
  final Future<void> Function(String key, String value) onRecordingChanged;
  @override
  State<ObsRecordingConnectionDialog> createState() =>
      _ObsRecordingConnectionDialogState();
}

class _ObsRecordingConnectionDialogState
    extends State<ObsRecordingConnectionDialog> {
  late final _host = TextEditingController(text: widget.connection.host);
  late final _port = TextEditingController(
    text: widget.connection.port.toString(),
  );
  late final _password = TextEditingController(
    text: widget.connection.password,
  );
  late final _seconds = TextEditingController(text: widget.matchSeconds ?? '');
  late final _distance = TextEditingController(
    text: widget.matchDistanceKm ?? '',
  );
  late final _wait = TextEditingController(text: widget.waitSeconds ?? '');
  late bool _enabled = widget.connection.enabled;
  late bool _reconnect = widget.connection.autoReconnect;
  late bool _expanded = widget.expandedSources;
  bool _obscure = true,
      _connectionDirty = false,
      _saving = false,
      _closing = false;
  String? _error;
  Timer? _connectionTimer;

  void _queueConnection({bool immediate = false}) {
    _connectionDirty = true;
    _connectionTimer?.cancel();
    if (immediate) {
      unawaited(_persistConnection());
    } else {
      _connectionTimer = Timer(
        const Duration(milliseconds: 600),
        () => unawaited(_persistConnection()),
      );
    }
  }

  Future<void> _persistConnection() async {
    if (!_connectionDirty) return;
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      if (mounted && !_closing) setState(() => _error = '端口须为 1–65535，尚未保存');
      return;
    }
    _connectionDirty = false;
    final settings = ObsAutomationConnectionSettings(
      enabled: _enabled,
      host: _host.text,
      port: port,
      password: _password.text,
      autoReconnect: _reconnect,
    );
    if (mounted && !_closing) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }
    try {
      await widget.onConnectionChanged(settings);
    } catch (error) {
      if (mounted && !_closing) setState(() => _error = '连接设置未能应用：$error');
    } finally {
      if (mounted && !_closing) setState(() => _saving = false);
    }
  }

  void _queueRecording(String key, String value) {
    final number = double.tryParse(value);
    setState(() {});
    if (number == null || !number.isFinite || number <= 0) return;
    unawaited(widget.onRecordingChanged(key, value));
  }

  @override
  void dispose() {
    _closing = true;
    _connectionTimer?.cancel();
    unawaited(_persistConnection());
    _host.dispose();
    _port.dispose();
    _password.dispose();
    _seconds.dispose();
    _distance.dispose();
    _wait.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint, String? error}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        isDense: true,
        filled: true,
        fillColor: SettingsControlStyle.field,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SettingsControlStyle.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SettingsControlStyle.accent),
        ),
      );
  Widget _number(TextEditingController controller, String key, String label) {
    final number = double.tryParse(controller.text);
    final invalid =
        controller.text.isNotEmpty &&
        (number == null || !number.isFinite || number <= 0);
    return TextField(
      key: ValueKey('obs-common-$key'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      decoration: _decoration(
        label,
        hint: '各规则不同',
        error: invalid ? '须大于 0，尚未保存' : null,
      ),
      onChanged: (value) => _queueRecording(key, value),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF292B31),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: SettingsControlStyle.border),
    ),
    title: const Text(
      '连接●录制设置',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用 OBS 连接', style: TextStyle(fontSize: 14)),
              value: _enabled,
              onChanged: (value) {
                setState(() => _enabled = value);
                _queueConnection(immediate: true);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    decoration: _decoration('主机地址'),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => _queueConnection(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _port,
                    decoration: _decoration('端口'),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => _queueConnection(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _obscure,
              onChanged: (_) => _queueConnection(),
              style: const TextStyle(fontSize: 13),
              decoration: _decoration('密码').copyWith(
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('断线自动重连', style: TextStyle(fontSize: 14)),
              value: _reconnect,
              onChanged: (value) {
                setState(() => _reconnect = value);
                _queueConnection(immediate: true);
              },
            ),
            const Divider(height: 26, color: SettingsControlStyle.divider),
            SwitchListTile(
              key: const ValueKey('obs-expand-end-sources'),
              contentPadding: EdgeInsets.zero,
              title: const Text('扩展其他机构', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '结束录制可选择其他机构的全部情报类型',
                style: TextStyle(
                  fontSize: 12,
                  color: SettingsControlStyle.muted,
                ),
              ),
              value: _expanded,
              onChanged: (value) {
                setState(() => _expanded = value);
                unawaited(widget.onExpandedChanged(value));
              },
            ),
            const SizedBox(height: 18),
            const Text(
              '同一地震判定',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            const Text(
              '按发震时间和震中距离匹配，修改后应用于当前全部录制规则。',
              style: TextStyle(fontSize: 12, color: SettingsControlStyle.muted),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _number(_seconds, 'maxSeconds', '发震时间差 ≤ 秒')),
                const SizedBox(width: 12),
                Expanded(
                  child: _number(_distance, 'maxDistanceKm', '震中距离 ≤ km'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _number(_wait, 'timeoutSeconds', '等待结束情报的最长时间 / 秒'),
            const SizedBox(height: 12),
            Text(
              _error ?? (_saving ? '正在自动保存…' : '更改自动保存'),
              style: TextStyle(
                fontSize: 12,
                color: _error == null
                    ? SettingsControlStyle.muted
                    : const Color(0xFFE86666),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
