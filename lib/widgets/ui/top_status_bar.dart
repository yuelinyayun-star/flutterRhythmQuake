import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../services/ntp_service.dart';
import '../../services/location_service.dart';
import '../../services/sources/source_manager.dart';
import '../../services/sources/mock_input_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/nied_yahoo_service.dart';
import '../../core/nied_replay_logger.dart';

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
  late DateTime _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = NtpService().now;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = NtpService().now;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.05),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    LocationService().currentPosition != null
                        ? "终端位置: ${LocationService().currentPosition!.latitude.toStringAsFixed(2)}, ${LocationService().currentPosition!.longitude.toStringAsFixed(2)}"
                        : "正在获取位置...",
                    style: TextStyle(fontFamily: 'JetBrainsMono',
                      color: Colors.white60, 
                      fontSize: 12, 
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              Row(
                children: [
                  IconButton(
                    tooltip: '模拟注入',
                    onPressed: _openMockDialog,
                    icon: const Icon(
                      Icons.science_outlined,
                      color: Colors.lightBlueAccent,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time, color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('yyyy-MM-dd HH:mm:ss').format(_currentTime),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (NtpService().isSynced ? Colors.green : Colors.orange).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (NtpService().isSynced ? Colors.green : Colors.orange).withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      NtpService().isSynced ? "NTP" : "LOC",
                      style: TextStyle(
                        color: NtpService().isSynced ? Colors.green : Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开模拟注入对话框
  /// 
  /// 用于调试和测试，可以手动注入预警消息
  Future<void> _openMockDialog() async {
    final controller = TextEditingController();
    final zipController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151515),
          title: const Text('模拟注入'),
          content: SizedBox(
            width: 700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '粘贴 Wolfx / FAN / P2P 的 js/json 报文：',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  minLines: 6,
                  style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '例如: const msg = {...}; 或 [{"type":"jma_eew",...}]',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                    filled: true,
                    fillColor: const Color(0xFF0E0E0E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                const Text(
                  'K-NET ASCII zip 路径 (PGA → 检测)：',
                  style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: zipController,
                  style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent),
                  decoration: InputDecoration(
                    hintText: r'D:\Downloads\20260601055432_ascii.zip',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: const Color(0xFF0E0E0E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.lightBlueAccent.withOpacity(0.3)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.15),
              ),
              onPressed: () {
                final path = zipController.text.trim();
                if (path.isNotEmpty) {
                  _submitKnetZip(path);
                }
              },
              child: const Text('注入K-NET', style: TextStyle(color: Colors.lightBlueAccent)),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _submitMockPayload(controller.text);
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('注入报文'),
            ),
          ],
        );
      },
    );
  }

  void _submitKnetZip(String path) {
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
        return;
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
    } catch (e) {
      _toast('K-NET注入失败：$e');
    }
  }

  /// 提交模拟数据
  /// 
  /// 将用户输入的模拟数据注入到预警系统
  /// [raw] 原始报文数据
  void _submitMockPayload(String raw) {
    try {
      final mockService = SourceManager().getSource<MockInputService>();
      if (mockService == null) {
        _toast('模拟注入源未初始化');
        return;
      }
      final count = mockService.injectFromJs(raw);
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
