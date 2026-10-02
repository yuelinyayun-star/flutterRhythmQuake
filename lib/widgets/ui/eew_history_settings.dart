import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/eew_history_retention.dart';
import '../../providers/quake_provider.dart';
import 'settings_controls.dart';

class EewHistorySettings extends StatefulWidget {
  const EewHistorySettings({super.key});

  @override
  State<EewHistorySettings> createState() => _EewHistorySettingsState();
}

class _EewHistorySettingsState extends State<EewHistorySettings> {
  late final QuakeProvider _provider;
  late final TextEditingController _limit;
  late int _savedLimit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<QuakeProvider>();
    _savedLimit = _provider.eewHistoryRetention.maxPerSource;
    _limit = TextEditingController(text: '$_savedLimit');
    _provider.historyListenable.addListener(_syncLimit);
  }

  void _syncLimit() {
    final value = _provider.eewHistoryRetention.maxPerSource;
    if (value == _savedLimit) return;
    _savedLimit = value;
    _limit.text = '$value';
  }

  @override
  void dispose() {
    _provider.historyListenable.removeListener(_syncLimit);
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save({required bool keepForever}) async {
    if (_saving) return;
    final count = keepForever
        ? _provider.eewHistoryRetention.maxPerSource
        : int.tryParse(_limit.text);
    if (count == null || count < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存上限必须是大于 0 的整数')));
      return;
    }
    final retention = EewHistoryRetention(
      maxPerSource: count,
      keepForever: keepForever,
    );
    final removed =
        _provider.eewHistory.length -
        retention.apply(_provider.eewHistory).length;
    if (removed > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('调整历史保存上限'),
          content: Text('将移除 $removed 个超出上限的旧事件及其各报。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await _provider.setEewHistoryRetention(retention);
      if (mounted && keepForever) _limit.text = '$count';
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('历史设置保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: _provider.historyListenable,
    builder: (context, _, child) {
      final retention = _provider.eewHistoryRetention;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsControlRow(
            title: '永久保存',
            leading: Icons.all_inclusive,
            control: Align(
              alignment: Alignment.centerRight,
              child: Switch(
                value: retention.keepForever,
                onChanged: _saving
                    ? null
                    : (value) => _save(keepForever: value),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SettingsControlRow(
            title: '每个预警源保存上限',
            leading: Icons.history,
            control: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('eew-history-limit'),
                    controller: _limit,
                    enabled: !_saving && !retention.keepForever,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      suffixText: '个事件',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _save(keepForever: false),
                  ),
                ),
                IconButton(
                  tooltip: '保存上限',
                  onPressed: _saving || retention.keepForever
                      ? null
                      : () => _save(keepForever: false),
                  icon: const Icon(Icons.check),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
