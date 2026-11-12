import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../core/utils/quake_time.dart';
import '../../models/quake_message.dart';
import '../../models/usgs_dyfi.dart';
import '../map/usgs_dyfi_layer.dart';

class UsgsDyfiListCard extends StatefulWidget {
  const UsgsDyfiListCard({
    super.key,
    required this.event,
    required this.frame,
    required this.scale,
    required this.selected,
    required this.onToggle,
    this.status,
  });
  final QuakeMessage event;
  final UsgsDyfiFrame? frame;
  final double scale;
  final bool selected;
  final VoidCallback onToggle;
  final String? status;
  @override
  State<UsgsDyfiListCard> createState() => _UsgsDyfiListCardState();
}

class _UsgsDyfiListCardState extends State<UsgsDyfiListCard> {
  bool _hovered = false;
  double s(double v) => v * widget.scale;
  Widget text(
    String value,
    double size, {
    Color color = Colors.white,
    bool bold = false,
    int lines = 1,
  }) => Text(
    value,
    style: TextStyle(
      fontSize: s(size),
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      height: 1.25,
    ),
    maxLines: lines,
    overflow: TextOverflow.ellipsis,
  );

  Future<void> _copy() async {
    final frame = widget.frame;
    await Clipboard.setData(
      ClipboardData(
        text: [
          '[RhythmQuake] USGS DYFI 公众体感报告',
          widget.event.location,
          '最高 CDI ${frame?.product.maxCdiText ?? '未知'}',
          '收到 ${frame?.product.responses ?? '未知'} 份报告',
          if (frame?.cells != null)
            '${frame!.cells!.length} 个体感网格 · ${frame.product.gridKm} km',
          if (frame != null)
            '更新 ${DateFormat('yyyy-MM-dd HH:mm:ss').format(frame.product.updated.toLocal())} (${QuakeTime.systemZoneLabel})',
        ].join('\n'),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制 DYFI 体感信息'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget action(
    String label,
    VoidCallback callback, {
    bool highlight = false,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: callback,
      child: Container(
        height: s(28),
        padding: EdgeInsets.symmetric(horizontal: s(12)),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFFE74C3C).withValues(alpha: .2)
              : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(s(3)),
          border: Border.all(
            width: .5,
            color: highlight
                ? const Color(0xFFE74C3C).withValues(alpha: .5)
                : Colors.white.withValues(alpha: .15),
          ),
        ),
        child: Center(
          child: text(
            label,
            10,
            color: highlight ? const Color(0xFFE74C3C) : Colors.white,
            bold: true,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    final color = dyfiColor(frame?.product.maxCdi);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: s(4), vertical: s(2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: s(10), top: s(4), bottom: s(6)),
            child: Row(
              children: [
                Container(
                  width: s(2),
                  height: s(12),
                  color: color.withValues(alpha: .5),
                ),
                SizedBox(width: s(8)),
                text('该地震的公众体感报告', 10, color: Colors.white54),
              ],
            ),
          ),
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onToggle,
              onLongPress: _copy,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0x66151515),
                  borderRadius: BorderRadius.circular(s(6)),
                  border: Border.all(
                    color: color.withValues(alpha: .3),
                    width: 1.2,
                  ),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(s(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: text('DYFI 公众体感', 14, bold: true),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: s(5),
                                  vertical: s(2),
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: .14),
                                  borderRadius: BorderRadius.circular(s(3)),
                                ),
                                child: text(
                                  'USGS-DYFI',
                                  10,
                                  color: color,
                                  bold: true,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: s(10)),
                          if (frame != null)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final mapWidth = (constraints.maxWidth * .38)
                                    .clamp(s(80), s(144));
                                final levels =
                                    (frame.cells ?? <UsgsDyfiCell>[])
                                        .map((c) => c.cdi.round())
                                        .toSet()
                                        .toList()
                                      ..sort();
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: mapWidth,
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            width: mapWidth,
                                            height: s(116),
                                            child:
                                                frame.cells?.isNotEmpty == true
                                                ? UsgsDyfiMiniMap(frame: frame)
                                                : Center(
                                                    child: text(
                                                      frame.cells == null
                                                          ? '体感网格未知'
                                                          : '暂无可绘制体感网格',
                                                      11,
                                                      color: Colors.white54,
                                                      lines: 2,
                                                    ),
                                                  ),
                                          ),
                                          if (levels.isNotEmpty)
                                            SizedBox(height: s(6)),
                                          if (levels.isNotEmpty)
                                            Wrap(
                                              spacing: s(6),
                                              runSpacing: s(2),
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                text(
                                                  'CDI',
                                                  9,
                                                  color: Colors.white54,
                                                ),
                                                for (final level in levels)
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: s(8),
                                                        height: s(8),
                                                        color: dyfiColor(
                                                          level.toDouble(),
                                                        ),
                                                      ),
                                                      SizedBox(width: s(2)),
                                                      text(
                                                        '$level',
                                                        9,
                                                        color: Colors.white70,
                                                      ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: s(12)),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          text(
                                            widget.event.location,
                                            13,
                                            bold: true,
                                            lines: 2,
                                          ),
                                          SizedBox(height: s(9)),
                                          text(
                                            '最高体感',
                                            10,
                                            color: Colors.white54,
                                          ),
                                          text(
                                            'CDI ${frame.product.maxCdiText}',
                                            22,
                                            color: color,
                                            bold: true,
                                          ),
                                          SizedBox(height: s(7)),
                                          text(
                                            '收到 ${frame.product.responses ?? '未知'} 份报告',
                                            13,
                                            bold: true,
                                          ),
                                          SizedBox(height: s(4)),
                                          text(
                                            frame.cells == null
                                                ? '体感网格未知'
                                                : '${frame.cells!.length} 个体感网格 · ${frame.product.gridKm} km',
                                            10,
                                            color: Colors.white60,
                                            lines: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            )
                          else
                            SizedBox(
                              height: s(80),
                              child: Center(
                                child: text(
                                  widget.status ?? '正在加载 DYFI 体感数据',
                                  12,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          if (frame != null) ...[
                            SizedBox(height: s(10)),
                            text(
                              '更新 ${DateFormat('MM-dd HH:mm:ss').format(frame.product.updated.toLocal())} (${QuakeTime.systemZoneLabel})',
                              10,
                              color: Colors.white54,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_hovered || widget.selected)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(s(6)),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                            child: Container(
                              color: const Color(0xB30D0D0D),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  action('复制信息', _copy),
                                  SizedBox(width: s(8)),
                                  action(
                                    widget.selected ? '取消显示' : '地图显示',
                                    widget.onToggle,
                                    highlight: widget.selected,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
