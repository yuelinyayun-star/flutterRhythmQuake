import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../models/quake_message.dart';
import '../../core/utils/quake_time.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

/// 地震列表面板组件
///
/// 该组件负责显示地震事件列表，支持筛选和过滤功能。
/// 提供震级过滤和数据源过滤功能。
///
/// 主要功能：
/// - 显示地震事件列表
/// - 按震级筛选 (M0.0 - M8.0+)
/// - 按数据源筛选 (JMA, CENC, USGS, FSSN, KMA, CWA)
/// - 点击跳转到震中位置
/// - 显示烈度/震度信息
/// - 区分自动测定和正式测定
///
/// 烈度显示说明：
/// - JMA震度: 日本气象厅震度等级 (1-7)
/// - CSIS烈度: 中国地震烈度等级 (I-XII)
class EqlistPanel extends StatefulWidget {
  const EqlistPanel({super.key});

  @override
  State<EqlistPanel> createState() => _EqlistPanelState();
}

class _EqlistPanelState extends State<EqlistPanel> {
  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 参考宽度，用于响应式缩放计算
  static const double _refWidth = 1700.0;

  /// 计算缩放比例
  double _scale(BuildContext c) =>
      (MediaQuery.of(c).size.width / _refWidth).clamp(0.55, 1.0);

  /// 应用缩放到尺寸值
  double _s(double v, BuildContext c) => v * _scale(c);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale(context);

    return Consumer<QuakeProvider>(
      builder: (context, provider, _) {
        final items = provider.historyList;
        final sourceBuckets = provider.historyBySource;

        return SizedBox(
          width: _s(420, context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterBar(context, provider, sourceBuckets, scale),
              if (items.isEmpty)
                _buildEmpty(context, scale)
              else
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(_s(10, context)),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: _listBg(context),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          itemBuilder: (_, i) =>
                              _EqCard(eq: items[i], scale: scale, scaleFn: _s),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 构建筛选栏
  ///
  /// 包含震级下拉选择器和数据源筛选标签
  Widget _buildFilterBar(
    BuildContext context,
    QuakeProvider provider,
    Map<String, List<QuakeMessage>> buckets,
    double scale,
  ) {
    final sourceLabels = {
      'jmaEqlist': 'JMA',
      'cencEqlist': 'CENC',
      'usgsEqlist': 'USGS',
      'fssnEqlist': 'FSSN',
      'kmaEqlist': 'KMA',
      'cwaEqlist': 'CWA',
      'emscEqlist': 'EMSC',
    };
    final sourceColors = {
      'jmaEqlist': 0xFFE74C3C,
      'cencEqlist': 0xFF2ECC71,
      'usgsEqlist': 0xFF3498DB,
      'fssnEqlist': 0xFF9B59B6,
      'kmaEqlist': 0xFFE67E22,
      'cwaEqlist': 0xFF1ABC9C,
      'emscEqlist': 0xFFF39C12,
    };
    final magOptions = [
      0.0,
      2.0,
      2.5,
      3.0,
      3.5,
      4.0,
      4.5,
      5.0,
      5.5,
      6.0,
      6.5,
      7.0,
      7.5,
      8.0,
    ];

    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(_s(10, context)),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _s(12, context),
            vertical: _s(6, context),
          ),
          decoration: BoxDecoration(
            color: const Color(0xCC141416),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_s(10, context)),
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              _dropdown<String>(
                value: provider.magFilter == 0
                    ? 'All'
                    : 'M${provider.magFilter.toStringAsFixed(1)}+',
                items: magOptions
                    .map((m) => m == 0 ? 'All' : 'M${m.toStringAsFixed(1)}+')
                    .toList(),
                onChanged: (v) {
                  final idx = [
                    'All',
                    ...magOptions
                        .where((m) => m > 0)
                        .map((m) => 'M${m.toStringAsFixed(1)}+'),
                  ].indexOf(v!);
                  provider.setMagFilter(idx <= 0 ? 0 : magOptions[idx]);
                },
                scale: scale,
              ),
              SizedBox(width: _s(8, context)),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: sourceLabels.entries.map((e) {
                        final enabled = provider.sourceFilter.contains(e.key);
                        final count = buckets[e.key]?.length ?? 0;
                        return Padding(
                          padding: EdgeInsets.only(right: _s(5, context)),
                          child: _sourceChip(
                            label: '${e.value}($count)',
                            color: Color(sourceColors[e.key]!),
                            selected: enabled,
                            onTap: () => provider.toggleSource(e.key),
                            scale: scale,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建下拉选择器
  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required void Function(T?) onChanged,
    required double scale,
  }) {
    return Container(
      height: _s(26, context),
      padding: EdgeInsets.symmetric(horizontal: _s(8, context)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(_s(4, context)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF1E1E1E),
          style: TextStyle(
            fontSize: _s(11, context),
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e.toString())))
              .toList(),
          onChanged: onChanged,
          isDense: true,
        ),
      ),
    );
  }

  /// 构建数据源筛选标签
  Widget _sourceChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    required double scale,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: _s(6, context),
          vertical: _s(2, context),
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(_s(4, context)),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: _s(10, context),
            color: selected ? color : Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 构建空状态提示
  Widget _buildEmpty(BuildContext context, double scale) {
    return Container(
      width: _s(420, context),
      padding: EdgeInsets.symmetric(vertical: _s(24, context)),
      decoration: _listBg(context),
      child: Center(
        child: Text(
          '暂无地震记录',
          style: TextStyle(color: Colors.white24, fontSize: _s(12, context)),
        ),
      ),
    );
  }

  /// 列表背景样式
  BoxDecoration _listBg(BuildContext context) {
    return BoxDecoration(
      color: const Color(0xCC0D0D0D),
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(_s(10, context)),
      ),
      border: Border(
        left: BorderSide(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
        right: BorderSide(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
        bottom: BorderSide(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
    );
  }
}

class _EqCard extends StatefulWidget {
  final QuakeMessage eq;
  final double scale;
  final double Function(double, BuildContext) scaleFn;

  const _EqCard({required this.eq, required this.scale, required this.scaleFn});

  @override
  State<_EqCard> createState() => _EqCardState();
}

class _EqCardState extends State<_EqCard> {
  bool _hovered = false;

  QuakeMessage get eq => widget.eq;
  double get scale => widget.scale;
  double _s(double v) => widget.scaleFn(v, context);

  bool get _isJma =>
      eq.source == QuakeSourceType.wolfx ||
      eq.source == QuakeSourceType.p2p ||
      eq.source == QuakeSourceType.jma_fan ||
      eq.source == QuakeSourceType.cwa;

  Color get _borderColor {
    if (_isJma && eq.jmaShindo != null) {
      return _jmaShindoColorStatic(eq.jmaShindo!);
    }
    final i = eq.maxIntensity ?? 6;
    if (i >= 10) return const Color(0xFF8E44AD);
    if (i >= 8) return const Color(0xFFE74C3C);
    if (i >= 6) return const Color(0xFFE67E22);
    if (i >= 4) return const Color(0xFFEBC033);
    if (i >= 2) return const Color(0xFF2E9B5F);
    return const Color(0xFF4B7BB1);
  }

  static Color _jmaShindoColorStatic(String s) {
    switch (s) {
      case '7':
        return const Color(0xFF8E44AD);
      case '6+':
      case '6-':
        return const Color(0xFFE74C3C);
      case '5+':
      case '5-':
        return const Color(0xFFE67E22);
      case '4':
        return const Color(0xFFEBC033);
      case '3':
        return const Color(0xFF2E9B5F);
      case '2':
        return const Color(0xFF4B7BB1);
      case '1':
        return const Color(0xFF808080);
      default:
        return const Color(0xFF34495E);
    }
  }

  static Color _magColorStatic(double mag) {
    if (mag >= 7) return const Color(0xFFE74C3C);
    if (mag >= 6) return const Color(0xFFE67E22);
    if (mag >= 5) return const Color(0xFFEBC033);
    if (mag >= 4) return const Color(0xFF2E9B5F);
    return const Color(0xFF4B7BB1);
  }

  static String _sourceLabelStatic(QuakeSourceType s) {
    switch (s) {
      case QuakeSourceType.cenc:
      case QuakeSourceType.cea:
      case QuakeSourceType.cea_pr:
        return 'CENC';
      case QuakeSourceType.wolfx:
        return 'JMA';
      case QuakeSourceType.p2p:
        return 'P2P';
      case QuakeSourceType.usgs:
        return 'USGS';
      case QuakeSourceType.fssn:
      case QuakeSourceType.fssnCmt:
        return 'FSSN';
      case QuakeSourceType.kma_eq:
      case QuakeSourceType.kma_eew_fan:
        return 'KMA';
      case QuakeSourceType.cwa:
      case QuakeSourceType.cwa_eew:
        return 'CWA';
      case QuakeSourceType.gfz:
        return 'GFZ';
      case QuakeSourceType.hko:
        return 'HKO';
      case QuakeSourceType.emsc:
        return 'EMSC';
      case QuakeSourceType.bcsf:
        return 'BCSF';
      case QuakeSourceType.usp:
        return 'USP';
      case QuakeSourceType.sa:
        return 'ShakeAlert';
      case QuakeSourceType.nied:
        return 'NIED';
      case QuakeSourceType.jma_fan:
        return 'JMA';
      default:
        return s.name;
    }
  }

  String _magShindoStatic(double mag) {
    if (mag >= 7) return '7';
    if (mag >= 6) return '6-';
    if (mag >= 5) return '5-';
    if (mag >= 4) return '4';
    if (mag >= 3) return '3';
    if (mag >= 2) return '2';
    return '1';
  }

  String _csisLabelStatic(QuakeMessage q) {
    final i = q.maxIntensity;
    if (i == null) return '?';
    if (i >= 12) return 'XII';
    if (i >= 11) return 'XI';
    if (i >= 10) return 'X';
    if (i >= 9) return 'IX';
    if (i >= 8) return 'VIII';
    if (i >= 7) return 'VII';
    if (i >= 6) return 'VI';
    if (i >= 5) return 'V';
    if (i >= 4) return 'IV';
    if (i >= 3) return 'III';
    if (i >= 2) return 'II';
    return 'I';
  }

  String _buildCopyText() {
    final label = _isJma
        ? (eq.jmaShindo ?? _magShindoStatic(eq.magnitude))
        : _csisLabelStatic(eq);
    final intLabel = _isJma ? '震度$label' : '烈度$label';
    final magStr = eq.magnitude > 0
        ? 'M${eq.magnitude.toStringAsFixed(1)}'
        : '規模調査中';
    final depthStr = eq.depth > 0
        ? '深度${eq.depth.toStringAsFixed(0)}km'
        : eq.depth == 0 ? '極浅' : '';
    final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(QuakeTime.displayClock(eq));
    final zoneStr = QuakeTime.zoneLabel(eq);
    final source = _sourceLabelStatic(eq.source);
    final parts = [intLabel, magStr, eq.location, timeStr, '($zoneStr)', depthStr, source].where((p) => p.isNotEmpty);
    return '[RhythmQuake] ${parts.join(' ')}';
  }

  void _copyInfo() {
    Clipboard.setData(ClipboardData(text: _buildCopyText()));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: ${_buildCopyText()}', style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 60, left: 20, right: 20),
      ),
    );
  }

  void _showOnMap() {
    final mapState = context.read<MapStateProvider>();
    if (mapState.isSelectedHistoryEvent(eq)) {
      mapState.clearSelectedHistoryEvent();
      Future.delayed(const Duration(milliseconds: 300), () {
        mapState.resumeAutoZoom();
      });
    } else {
      mapState.selectHistoryEvent(eq);
      mapState.pauseAutoZoom();
      mapState.animatedMove(LatLng(eq.latitude, eq.longitude), 7.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisplayed = context.watch<MapStateProvider>().isSelectedHistoryEvent(eq);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.04),
            width: 0.5,
          ),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () {
            final mapState = context.read<MapStateProvider>();
            if (mapState.isSelectedHistoryEvent(eq)) {
              mapState.clearSelectedHistoryEvent();
              Future.delayed(const Duration(milliseconds: 300), () {
                if (!context.mounted) return;
                context.read<MapStateProvider>().resumeAutoZoom();
              });
              return;
            }
            mapState.selectHistoryEvent(eq);
            mapState.pauseAutoZoom();
            mapState.animatedMove(LatLng(eq.latitude, eq.longitude), 7.0);
          },
          child: Container(
            margin: EdgeInsets.symmetric(
              vertical: _s(2),
              horizontal: _s(4),
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: _borderColor.withValues(alpha: 0.25),
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(_s(6)),
            ),
            child: Stack(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: _s(12),
                    vertical: _s(6),
                  ),
                  child: Row(
                    children: [
                      _buildIntBadge(),
                      SizedBox(width: _s(10)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              eq.location.length > 25
                                  ? '${eq.location.substring(0, 25)}…'
                                  : eq.location,
                              style: TextStyle(
                                fontSize: _s(15),
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: _s(2)),
                            Text(
                              '${DateFormat('yyyy-MM-dd HH:mm').format(QuakeTime.displayClock(eq))} (${QuakeTime.zoneLabel(eq)})',
                              style: TextStyle(
                                fontSize: _s(11),
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                            SizedBox(height: _s(2)),
                            Row(
                              children: [
                                Text(
                                  eq.magnitude > 0
                                      ? 'M${eq.magnitude.toStringAsFixed(1)}'
                                      : '規模 調査中',
                                  style: TextStyle(
                                    fontSize: _s(13),
                                    fontWeight: FontWeight.w800,
                                    color: _magColorStatic(eq.magnitude),
                                  ),
                                ),
                                SizedBox(width: _s(12)),
                                if (eq.depth >= 0)
                                  Text(
                                    eq.depth > 0
                                        ? '${eq.depth.toStringAsFixed(0)}km'
                                        : '極浅',
                                    style: TextStyle(
                                      fontSize: _s(13),
                                      color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                const Spacer(),
                                if ((eq.source == QuakeSourceType.cenc ||
                                        eq.source == QuakeSourceType.usgs) &&
                                    (eq.infoTypeName != null &&
                                            eq.infoTypeName!.isNotEmpty ||
                                        eq.reviewType != null &&
                                            eq.reviewType!.isNotEmpty))
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _s(5),
                                      vertical: _s(1),
                                    ),
                                    margin: EdgeInsets.only(right: _s(4)),
                                    decoration: BoxDecoration(
                                      color:
                                          (eq.source == QuakeSourceType.cenc
                                                  ? const Color(0xFF2ECC71)
                                                  : eq.reviewType == '正式测定' ||
                                                        eq.reviewType == 'reviewed'
                                                  ? const Color(0xFF2ECC71)
                                                  : const Color(0xFFE67E22))
                                              .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(_s(3)),
                                    ),
                                    child: Text(
                                      eq.source == QuakeSourceType.cenc &&
                                              eq.infoTypeName != null &&
                                              eq.infoTypeName!.isNotEmpty
                                          ? eq.infoTypeName!
                                          : eq.reviewType == '正式测定' ||
                                                eq.reviewType == 'reviewed'
                                          ? '正式测定'
                                          : '自动测定',
                                      style: TextStyle(
                                        fontSize: _s(9),
                                        color: eq.source == QuakeSourceType.cenc
                                            ? const Color(0xFF2ECC71)
                                            : eq.reviewType == '正式测定' ||
                                                  eq.reviewType == 'reviewed'
                                            ? const Color(0xFF2ECC71)
                                            : const Color(0xFFE67E22),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: _s(6),
                                    vertical: _s(1),
                                  ),
                                  decoration: BoxDecoration(
                                    color: _borderColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(_s(3)),
                                  ),
                                  child: Text(
                                    _sourceLabelStatic(eq.source),
                                    style: TextStyle(
                                      fontSize: _s(10),
                                      color: _borderColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hovered)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_s(6)),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        child: Container(
                          color: const Color(0xCC0D0D0D).withValues(alpha: 0.7),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _actionButton(label: '复制信息', onTap: _copyInfo),
                              SizedBox(width: _s(8)),
                              _actionButton(
                                label: isDisplayed ? '取消显示' : '地图显示',
                                onTap: _showOnMap,
                                highlight: isDisplayed,
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
    );
  }

  Widget _buildIntBadge() {
    final label = _isJma
        ? (eq.jmaShindo ?? _magShindoStatic(eq.magnitude))
        : _csisLabelStatic(eq);
    return Container(
      width: _s(60),
      height: _s(60),
      decoration: BoxDecoration(
        color: _borderColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_s(4)),
        border: Border.all(color: _borderColor.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: _isJma ? _s(24) : _s(28),
                fontWeight: FontWeight.w900,
                color: _borderColor,
                height: 1.0,
              ),
            ),
          ),
          Text(
            _isJma ? '震度' : '烈度',
            style: TextStyle(
              fontSize: _s(9),
              color: _borderColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_s(3)),
        ),
        onTap: onTap,
        child: Container(
          height: _s(28),
          padding: EdgeInsets.symmetric(horizontal: _s(12)),
          decoration: BoxDecoration(
            color: highlight
                ? const Color(0xFFE74C3C).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(_s(3)),
            border: Border.all(
              color: highlight
                  ? const Color(0xFFE74C3C).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: _s(10),
                color: highlight
                    ? const Color(0xFFE74C3C)
                    : Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
