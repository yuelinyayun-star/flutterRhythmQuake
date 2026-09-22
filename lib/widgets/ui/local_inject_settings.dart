import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/debug/local_inject_server.dart';

class LocalInjectSettings extends StatefulWidget {
  const LocalInjectSettings({super.key});

  @override
  State<LocalInjectSettings> createState() => _LocalInjectSettingsState();
}

class _LocalInjectSettingsState extends State<LocalInjectSettings> {
  final _port = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    LocalInjectServer.revision.addListener(_onServiceChanged);
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _port.text = LocalInjectServer.configuredPort(prefs).toString();
      _enabled = LocalInjectServer.isUserEnabled(prefs);
      _loaded = true;
    });
  }

  void _onServiceChanged() {
    if (!_busy) _load();
  }

  @override
  void dispose() {
    LocalInjectServer.revision.removeListener(_onServiceChanged);
    _port.dispose();
    super.dispose();
  }

  Future<void> _save({bool? enabled}) async {
    final port = int.tryParse(_port.text.trim());
    if (enabled != false && (port == null || port < 1 || port > 65535)) {
      setState(() => _error = '端口范围为 1–65535');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (enabled == null) {
        await LocalInjectServer.setPort(port!);
      } else {
        await LocalInjectServer.setEnabled(enabled, port: enabled ? port : null);
      }
      if (mounted && enabled != null) setState(() => _enabled = enabled);
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: LocalInjectServer.revision,
    builder: (context, _, child) {
      final running = LocalInjectServer.isRunning;
      final editable =
          _loaded && !_busy && LocalInjectServer.isSupportedPlatform;
      final error = _error ?? LocalInjectServer.lastError;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lan_outlined,
                color: Color(0xFF82B1FF),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本地注入 API',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      running
                          ? 'http://127.0.0.1:${LocalInjectServer.boundPort}/inject'
                          : !LocalInjectServer.isSupportedPlatform
                          ? '仅桌面端可监听'
                          : '未监听',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: editable ? (value) => _save(enabled: value) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('local-inject-port'),
                  controller: _port,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: '监听端口',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '保存端口',
                onPressed: editable ? () => _save() : null,
                icon: const Icon(Icons.save_outlined),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
        ],
      );
    },
  );
}
