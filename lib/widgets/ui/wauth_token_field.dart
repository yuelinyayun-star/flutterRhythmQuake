import 'package:flutter/material.dart';

import 'settings_controls.dart';

class WAuthTokenField extends StatefulWidget {
  const WAuthTokenField({
    super.key,
    required this.controller,
    required this.onSave,
    this.busy = false,
  });

  final TextEditingController controller;
  final VoidCallback onSave;
  final bool busy;

  @override
  State<WAuthTokenField> createState() => _WAuthTokenFieldState();
}

class _WAuthTokenFieldState extends State<WAuthTokenField>
    with WidgetsBindingObserver {
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant WAuthTokenField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy) _obscured = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_obscured) {
      setState(() => _obscured = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: widget.controller,
          enabled: !widget.busy,
          obscureText: _obscured,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onSubmitted: (_) {
            if (!widget.busy) widget.onSave();
          },
          decoration: InputDecoration(
            hintText: 'API Token',
            hintStyle: const TextStyle(color: SettingsControlStyle.muted),
            filled: true,
            fillColor: SettingsControlStyle.field,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: _border(SettingsControlStyle.divider),
            disabledBorder: _border(SettingsControlStyle.divider),
            focusedBorder: _border(SettingsControlStyle.accent),
            suffixIcon: IconButton(
              tooltip: _obscured ? '显示 Token' : '隐藏 Token',
              onPressed: widget.busy
                  ? null
                  : () => setState(() => _obscured = !_obscured),
              icon: Icon(
                _obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              color: Colors.white70,
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      IconButton(
        tooltip: '保存 WAuth API Token',
        onPressed: widget.busy ? null : widget.onSave,
        icon: const Icon(Icons.save_outlined),
        color: SettingsControlStyle.accent,
        visualDensity: VisualDensity.compact,
      ),
    ],
  );

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color),
  );
}
