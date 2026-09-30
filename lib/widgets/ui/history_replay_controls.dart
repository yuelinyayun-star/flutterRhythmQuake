import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/debug/history_replay.dart';
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
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || !mounted) return;
      final selected = result.files.single;
      if (selected.size > HistoryReplayPackage.maxBytes) {
        throw const FormatException('回放包超过 16 MiB');
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
          throw const FormatException('回放包超过 16 MiB');
        }
      } else {
        throw const FormatException('无法读取选中的回放包');
      }
      final package = HistoryReplayPackage.decode(utf8.decode(bytes));
      if (mounted) widget.controller.load(package);
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final package = controller.package;
      if (!widget.allowImport && package == null) {
        return const SizedBox.shrink();
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.replay, size: 22, color: Color(0xFF82B1FF)),
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
              if (widget.allowImport)
                IconButton(
                  tooltip: '导入回放包',
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                ),
              IconButton(
                tooltip: controller.active ? '重新回放' : '播放回放',
                onPressed: package == null || _busy
                    ? null
                    : () {
                        controller.play();
                        if (controller.active) widget.onPlaybackStarted?.call();
                      },
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
            ],
          ),
          if (package != null) ...[
            Text(
              '${controller.holding
                  ? '已播完，展示 30 秒'
                  : controller.active
                  ? '回放中'
                  : '待播放'}'
              ' · ${controller.played}/${package.reports.length} 报'
              '${package.manualTiming ? ' · 缺少报时，逐报播放' : ''}'
              '${package.omittedReports > 0 ? ' · ${package.omittedReports} 报无报文' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: controller.played / package.reports.length,
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
        ],
      );
    },
  );
}
