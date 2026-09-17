import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/android_background_settings.dart';

class AndroidBackgroundPowerSettings extends StatefulWidget {
  const AndroidBackgroundPowerSettings({super.key});

  @override
  State<AndroidBackgroundPowerSettings> createState() =>
      _AndroidBackgroundPowerSettingsState();
}

class _AndroidBackgroundPowerSettingsState
    extends State<AndroidBackgroundPowerSettings>
    with WidgetsBindingObserver {
  final _settings = AndroidBackgroundSettings();
  AndroidBackgroundPowerStatus? _status;
  bool _loading = false;
  bool _failed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    AndroidBackgroundPowerStatus? status;
    var failed = false;
    try {
      status = await _settings.readStatus();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _failed = failed;
      _loading = false;
    });
  }

  Future<void> _open(Future<bool> Function() action) async {
    if (_opening) return;
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await action();
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开系统设置，请在手机设置中查看本应用。')));
    }
  }

  String _label(bool? value, String yes, String no) => value == null
      ? '未知'
      : value
      ? yes
      : no;

  Widget _row(String title, String value, {Widget? action}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$title：'),
                TextSpan(
                  text: value,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ),
        ?action,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row(
        '系统后台状态',
        _loading
            ? '读取中'
            : _failed
            ? '读取失败'
            : '已更新',
        action: IconButton(
          tooltip: '刷新后台状态',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh, size: 19),
        ),
      ),
      _row(
        '电池优化',
        _label(_status?.batteryOptimizationExempt, '已豁免', '未豁免'),
        action: IconButton(
          tooltip: '打开系统电池优化设置',
          onPressed: _opening
              ? null
              : () => _open(_settings.openBatterySettings),
          icon: const Icon(Icons.battery_saver_outlined, size: 19),
        ),
      ),
      _row('系统省电模式', _label(_status?.powerSaveMode, '已开启', '已关闭')),
      _row('系统后台限制', _label(_status?.backgroundRestricted, '受限制', '未受限制')),
      _row(
        '厂商自启动权限',
        '需在系统中确认',
        action: IconButton(
          tooltip: '打开应用系统设置',
          onPressed: _opening ? null : () => _open(_settings.openAppSettings),
          icon: const Icon(Icons.settings_outlined, size: 19),
        ),
      ),
    ],
  );
}
