import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/system_voice_availability.dart';
import 'settings_controls.dart';

/// Shared by enabling speech and switching an enabled backend to system speech.
Future<bool> ensureSystemVoiceAvailable(
  BuildContext context, {
  required Future<SystemVoiceAvailability> Function() check,
  required Future<bool> Function() openSettings,
  VoidCallback? onChecked,
}) async {
  SystemVoiceAvailability result;
  try {
    result = await check();
  } catch (error) {
    result = SystemVoiceAvailability(
      SystemVoiceState.checkFailed,
      diagnostic: error.toString(),
    );
  }
  onChecked?.call();
  if (!context.mounted) return false;
  if (result.available) return true;
  await showDialog<void>(
    context: context,
    builder: (_) => SystemVoicePrompt(
      detectionFailed: result.state == SystemVoiceState.checkFailed,
      openSettings: openSettings,
    ),
  );
  return false;
}

class SystemVoiceEnableSwitch extends StatefulWidget {
  const SystemVoiceEnableSwitch({
    super.key,
    required this.value,
    required this.requiresSystemVoice,
    required this.check,
    required this.openSettings,
    required this.onChanged,
    this.onBusyChanged,
    this.blocked = false,
  });
  final bool value;
  final bool requiresSystemVoice;
  final bool blocked;
  final Future<SystemVoiceAvailability> Function() check;
  final Future<bool> Function() openSettings;
  final Future<void> Function(bool) onChanged;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<SystemVoiceEnableSwitch> createState() =>
      _SystemVoiceEnableSwitchState();
}

class _SystemVoiceEnableSwitchState extends State<SystemVoiceEnableSwitch> {
  bool _busy = false;
  bool _checking = false;
  Future<void> _change(bool value) async {
    if (_busy || widget.blocked) return;
    setState(() {
      _busy = true;
      _checking = value && widget.requiresSystemVoice;
    });
    widget.onBusyChanged?.call(true);
    try {
      if (value && widget.requiresSystemVoice) {
        final ready = await ensureSystemVoiceAvailable(
          context,
          check: widget.check,
          openSettings: widget.openSettings,
          onChecked: () {
            if (mounted) setState(() => _checking = false);
          },
        );
        if (!mounted || !ready) return;
      }
      if (mounted) await widget.onChanged(value);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _checking = false;
        });
      }
      widget.onBusyChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_checking) ...[
        const Tooltip(
          message: '正在检测系统语音',
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: SettingsControlStyle.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
      Switch(
        key: const ValueKey('tts-enabled-switch'),
        value: widget.value,
        activeThumbColor: SettingsControlStyle.accent,
        activeTrackColor: SettingsControlStyle.accent.withValues(alpha: .38),
        inactiveThumbColor: Colors.white70,
        inactiveTrackColor: Colors.white24,
        onChanged: _busy || widget.blocked ? null : _change,
      ),
    ],
  );
}

class SystemVoicePrompt extends StatefulWidget {
  const SystemVoicePrompt({
    super.key,
    required this.detectionFailed,
    required this.openSettings,
  });
  final bool detectionFailed;
  final Future<bool> Function() openSettings;
  @override
  State<SystemVoicePrompt> createState() => _SystemVoicePromptState();
}

class _SystemVoicePromptState extends State<SystemVoicePrompt> {
  bool _opening = false;
  bool _openFailed = false;
  Future<void> _open() async {
    setState(() {
      _opening = true;
      _openFailed = false;
    });
    bool opened;
    try {
      opened = await widget.openSettings();
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (opened) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _opening = false;
      _openFailed = true;
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('system-voice-prompt'),
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: SettingsControlStyle.blurSigma,
            sigmaY: SettingsControlStyle.blurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: SettingsControlStyle.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SettingsControlStyle.border),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.detectionFailed
                            ? Icons.info_outline
                            : Icons.voice_over_off_outlined,
                        size: 18,
                        color: SettingsControlStyle.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.detectionFailed ? '暂时无法检测系统语音' : '未检测到可用系统语音',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.detectionFailed
                        ? '语音播报尚未开启，请稍后重新尝试。'
                        : '请先安装 Windows 文字转语音包，再回来开启语音播报。',
                    style: const TextStyle(
                      color: SettingsControlStyle.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  if (!widget.detectionFailed) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SettingsControlStyle.field,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SettingsControlStyle.divider),
                      ),
                      child: const Text(
                        'Windows 设置 → 时间和语言 → 语音\n在“添加语音”中下载中文语音包。',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '如果已安装语音包，请确认系统语音可用后重新开启。',
                      style: TextStyle(
                        color: SettingsControlStyle.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (_openFailed) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '未能打开系统设置，请按上方路径手动进入。',
                      style: TextStyle(
                        color: SettingsControlStyle.accent,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: SettingsControlStyle.divider),
                  const SizedBox(height: 14),
                  if (widget.detectionFailed)
                    SettingsGlassAction(
                      label: '知道了',
                      emphasized: true,
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final actions = [
                          SettingsGlassAction(
                            label: '暂不开启',
                            onPressed: () => Navigator.pop(context),
                          ),
                          SettingsGlassAction(
                            label: '前往安装',
                            icon: Icons.open_in_new,
                            emphasized: true,
                            busy: _opening,
                            onPressed: _opening ? null : _open,
                          ),
                        ];
                        if (constraints.maxWidth < 300 &&
                            MediaQuery.textScalerOf(context).scale(13) > 18) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              actions[0],
                              const SizedBox(height: 8),
                              actions[1],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: actions[0]),
                            const SizedBox(width: 10),
                            Expanded(child: actions[1]),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
