import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'dart:async';
import '../../services/ntp_service.dart';
import '../../services/location_service.dart';
import '../../services/sources/source_manager.dart';
import '../../services/sources/mock_input_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/nied_yahoo_service.dart';
import '../../core/nied_replay_logger.dart';
import '../map/quake_map_view.dart';
import 'ui_scale.dart';
import '../../services/debug/local_inject_decoder.dart';
import 'local_inject_settings.dart';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import 'history_replay_controls.dart';

/// 顶部状态栏组件
///
/// 该组件负责显示应用顶部的状态信息栏。
/// 包含位置信息、时间显示和模拟注入功能入口。
///
/// 主要功能：
/// - 显示当前终端位置坐标
/// - 显示实时时间(支持NTP同步)
/// - 提供模拟预警注入入口(调试功能)
/// - 毛玻璃背景效果
///
/// 时间同步说明：
/// - NTP: 使用网络时间协议同步，精度高
/// - LOC: 使用本地时间，可能有偏差
class TopStatusBar extends StatefulWidget {
  const TopStatusBar({super.key});

  @override
  State<TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends State<TopStatusBar> {
  /// 定时器
  /// 每秒更新时间显示
  late Timer _timer;

  /// 当前显示时间
  late final ValueNotifier<DateTime> _currentTime;

  OverlayEntry? _mockOverlayEntry;
  ValueNotifier<Offset>? _mockOverlayPosition;

  @override
  void initState() {
    super.initState();
    _currentTime = ValueNotifier<DateTime>(NtpService().now);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentTime.value = NtpService().now;
    });
  }

  @override
  void dispose() {
    _closeMockOverlay();
    _timer.cancel();
    _currentTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = UiScale.topChrome(context);
    double s(double value) => value * scale;

    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            height: s(50),
            padding: EdgeInsets.symmetric(horizontal: s(24)),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: s(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.blueAccent,
                        size: s(16),
                      ),
                      SizedBox(width: s(10)),
                      Flexible(
                        child: ValueListenableBuilder(
                          valueListenable: LocationService().statusListenable,
                          builder: (context, status, _) {
                            return ValueListenableBuilder(
                              valueListenable:
                                  LocationService().positionListenable,
                              builder: (context, position, _) {
                                return Text(
                                  _locationText(status, position),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'JetBrainsMono',
                                    color: Colors.white60,
                                    fontSize: s(12),
                                    letterSpacing: 0,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '模拟注入',
                      onPressed: _openMockDialog,
                      icon: Icon(
                        Icons.science_outlined,
                        color: Colors.lightBlueAccent,
                        size: s(18),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        minWidth: s(28),
                        minHeight: s(28),
                      ),
                    ),
                    SizedBox(width: s(8)),
                    Icon(
                      Icons.access_time,
                      color: Colors.blueAccent,
                      size: s(16),
                    ),
                    SizedBox(width: s(10)),
                    ValueListenableBuilder<DateTime>(
                      valueListenable: _currentTime,
                      builder: (context, time, _) {
                        final syncState = NtpService().syncState;
                        final syncColor = _syncColor(syncState);
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('yyyy-MM-dd HH:mm:ss').format(time),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(15),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                            SizedBox(width: s(6)),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: s(6),
                                vertical: s(2),
                              ),
                              decoration: BoxDecoration(
                                color: syncColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(s(4)),
                                border: Border.all(
                                  color: syncColor.withValues(alpha: 0.3),
                                  width: s(0.5),
                                ),
                              ),
                              child: Text(
                                _syncLabel(syncState),
                                style: TextStyle(
                                  color: syncColor,
                                  fontSize: s(9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _locationText(LocationServiceStatus status, dynamic position) {
    if (status == LocationServiceStatus.available && position != null) {
      return "终端位置: ${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}";
    }
    return switch (status) {
      LocationServiceStatus.locating => "正在获取位置...",
      LocationServiceStatus.serviceDisabled => "定位服务未开启",
      LocationServiceStatus.permissionDenied => "定位权限未授予",
      LocationServiceStatus.failed => "定位获取失败",
      LocationServiceStatus.idle || LocationServiceStatus.available => "未设置位置",
    };
  }

  Color _syncColor(NtpSyncState state) {
    return switch (state) {
      NtpSyncState.synced => Colors.green,
      NtpSyncState.stale => Colors.amber,
      NtpSyncState.local => Colors.orange,
    };
  }

  String _syncLabel(NtpSyncState state) {
    return switch (state) {
      NtpSyncState.synced => "NTP",
      NtpSyncState.stale => "OLD",
      NtpSyncState.local => "LOC",
    };
  }

  /// 打开模拟注入对话框
  ///
  /// 用于调试和测试，可以手动注入预警消息
  void _openMockDialog() {
    if (_mockOverlayEntry != null) return;
    final replay = context.read<QuakeProvider?>()?.historyReplay;

    var payload = '';
    var format = 'auto';
    var source = '';
    var zipPath = '';
    var niedGifPath = '';
    final position = ValueNotifier<Offset>(const Offset(40, 74));
    _mockOverlayPosition = position;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final screenSize = MediaQuery.sizeOf(overlayContext);
        final panelWidth = (screenSize.width - 32)
            .clamp(280.0, 520.0)
            .toDouble();
        final panelHeight = (screenSize.height - 64)
            .clamp(280.0, 720.0)
            .toDouble();

        return ValueListenableBuilder<Offset>(
          valueListenable: position,
          builder: (context, offset, _) {
            final left = offset.dx
                .clamp(0.0, math.max(0.0, screenSize.width - panelWidth))
                .toDouble();
            final top = offset.dy
                .clamp(0.0, math.max(0.0, screenSize.height - panelHeight))
                .toDouble();

            return Positioned(
              left: left,
              top: top,
              width: panelWidth,
              height: panelHeight,
              child: Material(
                color: const Color(0xFF151515),
                elevation: 18,
                shadowColor: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            Expanded(
                              child: MouseRegion(
                                cursor: SystemMouseCursors.move,
                                child: GestureDetector(
                                  key: const ValueKey(
                                    'mock-injection-drag-handle',
                                  ),
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (details) {
                                    position.value =
                                        position.value + details.delta;
                                  },
                                  child: const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '模拟注入',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              onPressed: _closeMockOverlay,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const LocalInjectSettings(),
                              if (replay != null) ...[
                                const Divider(height: 24),
                                HistoryReplayControls(controller: replay),
                              ],
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: format,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '报文格式',
                                  isDense: true,
                                ),
                                items: [
                                  for (final value
                                      in LocalInjectDecoder.formats)
                                    DropdownMenuItem(
                                      value: value,
                                      child: Text(
                                        value == 'auto' ? '自动识别' : value,
                                      ),
                                    ),
                                ],
                                onChanged: (value) => format = value ?? 'auto',
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                onChanged: (value) => source = value.trim(),
                                decoration: const InputDecoration(
                                  labelText: '机构 / 适配器（可选）',
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '原始报文',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                onChanged: (value) => payload = value,
                                maxLines: 8,
                                minLines: 6,
                                style: const TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: 12,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      '例如: const msg = {...}; 或 [{"type":"jma_eew",...}]',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.35),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0E0E0E),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Divider(color: Colors.white12),
                              const SizedBox(height: 8),
                              const Text(
                                'K-NET ASCII zip 路径 (PGA → 检测)：',
                                style: TextStyle(
                                  color: Colors.lightBlueAccent,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                onChanged: (value) => zipPath = value,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.lightBlueAccent,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      r'D:\Downloads\20260601055432_ascii.zip',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0E0E0E),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Colors.lightBlueAccent.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Divider(color: Colors.white12),
                              const SizedBox(height: 8),
                              const Text(
                                'NIED GIF 文件/目录路径（直接按 GIF 注入）：',
                                style: TextStyle(
                                  color: Colors.lightBlueAccent,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                onChanged: (value) => niedGifPath = value,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.lightBlueAccent,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      r'D:\captures\20260630_iwate 或 D:\captures\20260630112425.jma_s.gif',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0E0E0E),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Colors.lightBlueAccent.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: _closeMockOverlay,
                            child: const Text('取消'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.lightBlueAccent
                                  .withValues(alpha: 0.15),
                            ),
                            onPressed: () {
                              final path = zipPath.trim();
                              if (path.isNotEmpty) _submitKnetZip(path);
                            },
                            child: const Text(
                              '注入K-NET',
                              style: TextStyle(color: Colors.lightBlueAccent),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.lightBlueAccent
                                  .withValues(alpha: 0.15),
                            ),
                            onPressed: () {
                              final path = niedGifPath.trim();
                              if (path.isNotEmpty) {
                                unawaited(_submitNiedGifPath(path));
                              }
                            },
                            child: const Text(
                              '注入NIED GIF',
                              style: TextStyle(color: Colors.lightBlueAccent),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (payload.trim().isNotEmpty) {
                                _submitMockPayload(
                                  payload,
                                  format: format,
                                  source: source.isEmpty ? null : source,
                                );
                              }
                            },
                            child: const Text('注入报文'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    _mockOverlayEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _closeMockOverlay() {
    final entry = _mockOverlayEntry;
    _mockOverlayEntry = null;
    _mockOverlayPosition?.dispose();
    _mockOverlayPosition = null;
    entry?.remove();
  }

  bool _submitKnetZip(String path) {
    try {
      // 1. 停止 3 个 NIED 实时路径 + 开启 Logger
      NiedMonitorService().stop();
      NiedYahooService().stop();
      final logger = NiedReplayLogger.instance;
      logger.setEnabled(true);
      _toast('已停止 NIED/lmoni/kmoni/Yahoo，Logger 已开启');

      // 2. 注入 K-NET 数据（内部会跑检测帧）
      final mockService = SourceManager().getSource<MockInputService>();
      if (mockService == null) {
        _toast('模拟注入源未初始化');
        return false;
      }
      final count = mockService.injectFromKnetZip(path);

      // 3. 保存日志
      Future.delayed(const Duration(milliseconds: 500), () {
        logger.save().then((_) {
          logger.setEnabled(false);
          debugPrint('[TopBar] K-NET logger saved to ${logger.lastLogPath}');
        });
      });

      _toast('K-NET注入成功：$count 站 → 日志已保存');
      return true;
    } catch (e) {
      _toast('K-NET注入失败：$e');
      return false;
    }
  }

  Future<bool> _submitNiedGifPath(String path) async {
    final previousSource = QuakeMapView.niedSourceNotifier.value;
    try {
      QuakeMapView.niedSourceNotifier.value = 'lmoni';
      NiedMonitorService().stop();
      NiedYahooService().stop();
      _toast('已停止 NIED 实时源，开始注入 GIF');

      final mockService = SourceManager().getSource<MockInputService>();
      if (mockService == null) {
        _toast('模拟注入源未初始化');
        return false;
      }
      final count = await mockService.injectFromNiedGifPath(path);
      _toast('NIED GIF注入成功：$count 秒，已恢复实时源');
      return true;
    } catch (e) {
      _toast('NIED GIF注入失败：$e');
      return false;
    } finally {
      QuakeMapView.restoreNiedLiveSource(previousSource);
    }
  }

  /// 提交模拟数据
  ///
  /// 将用户输入的模拟数据注入到预警系统
  /// [raw] 原始报文数据
  void _submitMockPayload(
    String raw, {
    String format = 'auto',
    String? source,
  }) {
    try {
      final mockService = SourceManager().getSource<MockInputService>();
      if (mockService == null) {
        _toast('模拟注入源未初始化');
        return;
      }
      final count = mockService.injectFromJs(
        raw,
        format: format,
        source: source,
      );
      _toast('模拟注入成功：$count 条');
    } catch (e) {
      _toast('模拟注入失败：$e');
    }
  }

  /// 显示提示消息
  ///
  /// [message] 要显示的消息内容
  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
