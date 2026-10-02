import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/debug/history_replay.dart';
import 'settings_controls.dart';
import 'history_replay_file_web.dart'
    if (dart.library.io) 'history_replay_file_io.dart'
    as replay_file;

Future<bool> exportHistoryReplay(HistoryReplayPackage package) async {
  final bytes = Uint8List.fromList(utf8.encode(package.encode()));
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '导出回放包',
    fileName:
        'RhythmQuake_${package.times.first.millisecondsSinceEpoch}.rqreplay',
    type: FileType.custom,
    allowedExtensions: ['rqreplay'],
    bytes: kIsWeb || replay_file.isMobile ? bytes : null,
  );
  if (path == null) return false;
  if (!kIsWeb && !replay_file.isMobile) {
    await replay_file.writeBytes(path, bytes);
  }
  return true;
}

class HistoryReplayControls extends StatefulWidget {
  final HistoryReplayController controller;
  final bool allowImport;
  final VoidCallback? onPlaybackStarted;
  const HistoryReplayControls({
    super.key,
    required this.controller,
    this.allowImport = true,
    this.onPlaybackStarted,
  });

  @override
  State<HistoryReplayControls> createState() => _HistoryReplayControlsState();
}

class _HistoryReplayControlsState extends State<HistoryReplayControls> {
  bool _busy = false;
  String? _error;

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['rqreplay', 'json'],
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result == null || !mounted) return;
      final packages = <HistoryReplayPackage>[];
      for (final selected in result.files) {
        if (selected.size > HistoryReplayPackage.maxBytes) {
          throw const FormatException('回放包超过 128 MiB');
        }
        final Uint8List bytes;
        if (!kIsWeb && selected.path != null) {
          bytes = await replay_file.readBytes(
            selected.path!,
            maxBytes: HistoryReplayPackage.maxBytes,
          );
        } else if (selected.bytes != null) {
          bytes = selected.bytes!;
          if (bytes.length > HistoryReplayPackage.maxBytes) {
            throw const FormatException('回放包超过 128 MiB');
          }
        } else {
          throw const FormatException('无法读取选中的回放包');
        }
        packages.add(HistoryReplayPackage.decode(utf8.decode(bytes)));
      }
      if (mounted) widget.controller.importPackages(packages);
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _play() {
    try {
      widget.controller.play();
      setState(() => _error = null);
      if (widget.controller.active) widget.onPlaybackStarted?.call();
    } catch (error) {
      setState(() => _error = '回放失败：$error');
    }
  }

  Widget _timelineSwitch() => Row(
    children: [
      const Icon(Icons.timeline, size: 20, color: SettingsControlStyle.accent),
      const SizedBox(width: 8),
      const Expanded(child: Text('时间轴联动回放', style: TextStyle(fontSize: 13))),
      Switch(
        activeThumbColor: SettingsControlStyle.accent,
        value: widget.controller.timelineLinked,
        onChanged: widget.controller.setTimelineLinked,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final package = controller.package;
      if (!widget.allowImport && package == null) {
        return _timelineSwitch();
      }
      final actions = <Widget>[
        if (widget.allowImport)
          IconButton(
            tooltip: '导入回放包',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
          ),
        if (controller.importedPackages.length > 1)
          PopupMenuButton<HistoryReplayPackage>(
            tooltip: '已导入回放',
            icon: const Icon(Icons.playlist_play),
            onSelected: controller.load,
            itemBuilder: (context) => [
              for (final imported in controller.importedPackages)
                PopupMenuItem(
                  value: imported,
                  child: Text(
                    imported.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        IconButton(
          tooltip: controller.active ? '重新回放' : '播放回放',
          onPressed: package == null || _busy ? null : _play,
          icon: Icon(controller.active ? Icons.replay : Icons.play_arrow),
        ),
        IconButton(
          tooltip: '停止回放',
          onPressed: controller.active ? controller.stop : null,
          icon: const Icon(Icons.stop),
        ),
        if (package?.manualTiming == true)
          IconButton(
            tooltip: '下一报',
            onPressed: controller.active && !controller.holding
                ? controller.next
                : null,
            icon: const Icon(Icons.skip_next),
          ),
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final separateActions =
                  constraints.maxWidth < actions.length * 48 + 120;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.replay,
                        size: 22,
                        color: SettingsControlStyle.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          package?.name ?? '报文回放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!separateActions) ...actions,
                    ],
                  ),
                  if (separateActions)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(children: actions),
                    ),
                ],
              );
            },
          ),
          if (package != null) ...[
            Text(
              '${controller.holding
                  ? '报文已播完，继续回放'
                  : controller.active
                  ? '回放中'
                  : '待播放'}'
              ' · ${controller.played}/${controller.totalReports} 报'
              '${controller.linkedEventCount > 1 ? ' · 联动 ${controller.linkedEventCount} 个事件' : ''}'
              '${controller.totalStationFrames > 0 ? ' · 测站 ${controller.totalStationFrames} 帧' : ' · 无测站记录'}'
              '${package.manualTiming ? ' · 报时缺失或冲突，逐报播放' : ''}'
              '${controller.usesArrivalTimeline ? ' · 按保存的接收时间回放' : ''}'
              '${controller.missingTimelineTime ? ' · 时间信息不足，未联动' : ''}'
              '${controller.skippedLinkedEvents > 0 ? ' · ${controller.skippedLinkedEvents} 个记录无法联动' : ''}'
              '${package.usesDeviceArrivalTimeZone ? ' · 旧接收时间按本机时区解释' : ''}'
              '${package.omittedReports > 0 ? ' · ${package.omittedReports} 报无报文' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: SettingsControlStyle.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: controller.played / controller.totalReports,
              color: SettingsControlStyle.accent,
              backgroundColor: SettingsControlStyle.divider,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
          _timelineSwitch(),
          if (_error != null)
            Tooltip(
              message: _error!,
              child: Text(
                _error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
        ],
      );
    },
  );
}
