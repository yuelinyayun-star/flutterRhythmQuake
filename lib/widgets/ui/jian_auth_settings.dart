import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/jian_auth_service.dart';
import 'settings_controls.dart';

class JianAuthSettings extends StatefulWidget {
  const JianAuthSettings({
    super.key,
    required this.onChanged,
    this.store,
    this.auth,
  });
  final Future<void> Function() onChanged;
  final JianCredentialStore? store;
  final JianAuthService? auth;
  @override
  State<JianAuthSettings> createState() => _JianAuthSettingsState();
}

class _JianAuthSettingsState extends State<JianAuthSettings> {
  late final _store = widget.store ?? JianCredentialStore();
  bool _saved = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _store.read();
      if (mounted) {
        setState(() {
          _saved = value.isNotEmpty;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取安全存储');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => JianCredentialDialog(store: _store, auth: widget.auth),
    );
    if (!mounted || changed != true) return;
    await _changed();
  }

  Future<void> _changed() async {
    await _load();
    try {
      await widget.onChanged();
    } catch (_) {
      if (mounted) setState(() => _error = '凭证已更新，连接重载失败');
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _JianConfirmationDialog(
        title: '移除 Jian 凭证？',
        message: '此设备将停止 Jian 业务连接，重新配置凭证后才能恢复。',
        cancelLabel: '取消',
        confirmLabel: '移除',
        icon: Icons.delete_outline,
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _store.clear();
      await _changed();
    } catch (_) {
      if (mounted) setState(() => _error = '移除失败，原凭证已保留');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsControlRow(
    title: 'Jian 个人鉴权',
    subtitle:
        _error ??
        (_busy
            ? '正在读取'
            : _saved
            ? '长期凭证已保存'
            : '未配置 · 需要鉴权'),
    leading: _saved ? Icons.verified_user_outlined : Icons.key_outlined,
    control: Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (_saved)
          IconButton(
            tooltip: '移除凭证',
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            color: Colors.white70,
          ),
        Tooltip(
          message: '配置凭证',
          child: SizedBox(
            width: 160,
            height: 40,
            child: SettingsGlassAction(
              label: _saved ? '更换凭证' : '配置凭证',
              icon: _saved ? Icons.edit_outlined : Icons.key_outlined,
              emphasized: true,
              busy: _busy,
              onPressed: _busy ? null : _edit,
            ),
          ),
        ),
      ],
    ),
  );
}

class JianCredentialDialog extends StatefulWidget {
  const JianCredentialDialog({super.key, required this.store, this.auth});
  final JianCredentialStore store;
  final JianAuthService? auth;
  @override
  State<JianCredentialDialog> createState() => _JianCredentialDialogState();
}

class _JianCredentialDialogState extends State<JianCredentialDialog> {
  final _controller = TextEditingController();
  late final _auth = widget.auth ?? JianAuthService();
  bool _busy = false;
  bool _obscured = true;
  String? _error;
  JianCredential? _pendingToken;

  @override
  void dispose() {
    _controller.dispose();
    if (widget.auth == null) _auth.close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pendingToken == null) {
        final input = _controller.text.trim();
        if (isJianCredential(input, 'lk_')) {
          // An lk_ can be redeemed only once. Retain the returned rt_ in
          // memory until secure storage succeeds, so Save can be retried.
          _pendingToken = await _auth.exchangeLoginKeyCredential(input);
        } else if (isJianCredential(input, 'rt_')) {
          _pendingToken = JianCredential(input);
        } else {
          throw const JianAuthException('invalid_login_key');
        }
      }
      await widget.store.write(
        _pendingToken!.token,
        expiresAt: _pendingToken!.expiresAt,
      );
      _pendingToken = null;
      if (mounted) Navigator.pop(context, true);
    } on JianAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '安全保存失败，凭证暂留本窗口，请重试保存。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_pendingToken != null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => _JianConfirmationDialog(
          title: '放弃未保存的凭证？',
          message: '新凭证尚未保存，关闭后将丢失。',
          cancelLabel: '返回',
          confirmLabel: '放弃',
          icon: Icons.warning_amber_outlined,
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _register() async {
    try {
      final opened = await launchUrl(
        JianAuthService.registrationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) setState(() => _error = '无法打开鉴权网站');
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开鉴权网站');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _pendingToken == null,
    child: _JianDialogSurface(
      title: 'Jian 个人鉴权',
      icon: Icons.key_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '登录密钥 / 长期 Token',
            style: TextStyle(color: SettingsControlStyle.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            enabled: !_busy && _pendingToken == null,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: SettingsControlStyle.accent,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'lk_… / rt_…',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: SettingsControlStyle.field,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: _fieldBorder(SettingsControlStyle.divider),
              disabledBorder: _fieldBorder(SettingsControlStyle.divider),
              focusedBorder: _fieldBorder(SettingsControlStyle.accent),
              suffixIcon: IconButton(
                tooltip: _obscured ? '显示凭证' : '隐藏凭证',
                color: Colors.white70,
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: SettingsControlStyle.accent,
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _busy ? null : _register,
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('申请登录密钥'),
            ),
          ),
        ],
      ),
      actions: [
        SettingsGlassAction(label: '取消', onPressed: _busy ? null : _cancel),
        SettingsGlassAction(
          label: _busy ? '正在保存' : '保存',
          icon: Icons.save_outlined,
          busy: _busy,
          emphasized: true,
          onPressed: _busy ? null : _save,
        ),
      ],
    ),
  );

  OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color),
  );
}

class _JianConfirmationDialog extends StatelessWidget {
  const _JianConfirmationDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.icon,
  });
  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _JianDialogSurface(
    title: title,
    icon: icon,
    content: Text(
      message,
      style: const TextStyle(
        color: SettingsControlStyle.muted,
        fontSize: 12,
        height: 1.5,
      ),
    ),
    actions: [
      SettingsGlassAction(
        label: cancelLabel,
        onPressed: () => Navigator.pop(context, false),
      ),
      SettingsGlassAction(
        label: confirmLabel,
        icon: Icons.delete_outline,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
}

class _JianDialogSurface extends StatelessWidget {
  const _JianDialogSurface({
    required this.title,
    required this.icon,
    required this.content,
    required this.actions,
  });
  final String title;
  final IconData icon;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
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
                      Icon(icon, size: 18, color: SettingsControlStyle.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
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
                  content,
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: SettingsControlStyle.divider),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          constraints.maxWidth < 300 &&
                          MediaQuery.textScalerOf(context).scale(13) > 18;
                      if (stacked) {
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
