import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../services/ntp_service.dart';
import '../../models/intensity_theme.dart';
import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../models/weather_alarm.dart';
import '../../core/intensity_calculator.dart';
import '../../core/utils/quake_time.dart';

class AlertModule extends StatefulWidget {
  const AlertModule({super.key});

  @override
  State<AlertModule> createState() => _AlertModuleState();
}

class _AlertModuleState extends State<AlertModule>
    with TickerProviderStateMixin {
  late AnimationController _flashController;
  Timer? _unifiedPageTimer;
  int _unifiedPageIndex = 0;
  String _unifiedPageSignature = '';

  static const int _unifiedPageSize = 4;

  static const double _refWidth = 1700.0;

  double _scale(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    return (w / _refWidth).clamp(0.55, 1.0);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  /// 获取 EEW 顶栏颜色类
  ///
  /// 参考 kanameishi 的 getBarClass：
  /// - 取消报：深灰
  /// - 警报级 (isWarn)：红色
  /// - 普通：橙色
  Color _eewBarColor(QuakeMessage event) {
    if (event.isCanceled) return const Color(0xFF555555);
    if (event.isWarn) return Colors.red;
    return const Color(0xFFE67E22);
  }

  /// 获取 EEW 顶栏文本颜色
  Color _eewBarTextColor(QuakeMessage event) {
    if (event.isCanceled) return Colors.white54;
    if (event.isWarn) return Colors.redAccent;
    return const Color(0xFFFF9800);
  }

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _stopUnifiedPageTimer();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<QuakeProvider>(
      builder: (context, provider, child) {
        final bool hasUnified = provider.unifiedEvents.isNotEmpty;
        final Widget alertContent = _buildAlertContent(provider);

        // 底部分隔条带仅在统一 UI 模式显示
        if (!hasUnified) return alertContent;

        final unifiedCount = provider.unifiedEvents.length;
        final pageIndicator = unifiedCount > _unifiedPageSize
            ? '${_unifiedPageIndex + 1}/${_unifiedPageCount(unifiedCount)}'
            : null;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: _s(6, context)),
            alertContent,
            SizedBox(height: _s(6, context)),
            _bottomStrip(context, pageText: pageIndicator),
          ],
        );
      },
    );
  }

  /// 底部分隔条带：双线中间夹页码（如 1/3）
  Widget _bottomStrip(BuildContext context, {String? pageText}) {
    final line = Container(
      width: _s(420, context),
      height: 1,
      color: const Color(0xCC0D0D0D),
    );

    if (pageText == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line,
          SizedBox(height: _s(3, context)),
          line,
        ],
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            line,
            SizedBox(height: _s(3, context)),
            line,
          ],
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: _s(10, context)),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D0D),
            borderRadius: BorderRadius.circular(_s(4, context)),
          ),
          child: Text(
            pageText,
            style: TextStyle(
              color: Colors.white54,
              fontSize: _s(8, context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertContent(QuakeProvider provider) {
    final hasUnified = provider.unifiedEvents.isNotEmpty;

    if (hasUnified) {
      return _buildStackedUnifiedView(provider);
    }

    _stopUnifiedPageTimer();

    final event = provider.currentEvent;
    final warningCount = provider.activeWarningCount;
    final isShowingTempInfo = provider.isShowingTempInfo;
    final isShowingInfoEvent = provider.isShowingInfoEvent;

    if (event == null) {
      if (provider.shouldShowWeatherAlarm) {
        return _buildWeatherAlarmCard(context, provider.weatherAlarm!);
      }
      return _buildStandbyState(context, provider);
    }

    if (isShowingTempInfo || (isShowingInfoEvent && warningCount == 0)) {
      final double intensity = _badgeIntensity(event);
      final Color themeColor = IntensityTheme.getColor(intensity);
      final bool isSerious = intensity >= 5.0;
      final int totalCount = provider.totalDisplayCount;

      return _buildInfoEventCard(
        context,
        event,
        intensity,
        themeColor,
        isSerious,
        totalCount,
        provider,
      );
    }

    final double distance = provider.currentDistance;
    final normalizedOrigin = QuakeTime.normalizedOriginLocal(event);
    final double elapsed =
        NtpService().now.difference(normalizedOrigin).inMilliseconds / 1000.0;
    final double sArrival = distance / 3.5;
    final int countdown = (sArrival - elapsed).floor();

    if (countdown < -60 && warningCount == 0) {
      return _buildStandbyState(context, provider);
    }

    final double intensity = _badgeIntensity(event);
    final Color themeColor = IntensityTheme.getColor(intensity);
    final bool isSerious = intensity >= 5.0;

    // 有效预警卡（带闪烁边框）渲染分支。
    return AnimatedBuilder(
      animation: _flashController,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(_s(10, context)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: _s(420, context),
              decoration: BoxDecoration(
                color: const Color(0xCC0D0D0D),
                borderRadius: BorderRadius.circular(_s(10, context)),
                border: Border.all(
                  color: isSerious
                      ? Color.lerp(
                          Colors.red.withValues(alpha: 0.3),
                          Colors.red.withValues(alpha: 0.9),
                          _flashController.value,
                        )!
                      : themeColor.withValues(alpha: 0.35),
                  width: _s(1.2, context),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSerious
                        ? Colors.red.withValues(
                            alpha: _flashController.value * 0.3,
                          )
                        : themeColor.withValues(alpha: 0.08),
                    blurRadius: _s(20, context),
                    spreadRadius: _s(1, context),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(
            context,
            event,
            themeColor,
            isSerious,
            warningCount,
            provider,
          ),
          _buildBody(
            context,
            event,
            intensity,
            themeColor,
            countdown,
            distance,
          ),
        ],
      ),
    );
  }

  Widget _buildStackedUnifiedView(QuakeProvider provider) {
    final events = provider.unifiedEvents;
    final eew = events.where((e) => e.isEew).toList();
    final info = events.where((e) => !e.isEew).toList();
    final ordered = [...eew, ...info];
    final visibleEvents = _visibleUnifiedPage(ordered);

    // 轮播模式：每页固定 _unifiedPageSize 槽位，不足用 null 占位，防止高度跳动
    final paddedEvents = ordered.length > _unifiedPageSize
        ? [
            ...visibleEvents,
            for (int i = visibleEvents.length; i < _unifiedPageSize; i++) null,
          ]
        : visibleEvents;

    return SizedBox(
      width: _s(420, context),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 680),
        reverseDuration: const Duration(milliseconds: 520),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.045, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(
            'unified_page_${_unifiedPageIndex}_${visibleEvents.map((e) => '${e.source}:${e.eventId}:${e.reportNumText}').join('|')}',
          ),
          child: _buildCardColumn(
            paddedEvents,
            animateItems: ordered.length <= _unifiedPageSize,
          ),
        ),
      ),
    );
  }

  List<UnifiedQuakeData> _visibleUnifiedPage(List<UnifiedQuakeData> ordered) {
    _syncUnifiedPagination(ordered);

    if (ordered.length <= _unifiedPageSize) {
      return ordered;
    }

    final pageCount = _unifiedPageCount(ordered.length);
    final pageIndex = _unifiedPageIndex.clamp(0, pageCount - 1);
    final start = pageIndex * _unifiedPageSize;
    final end = (start + _unifiedPageSize).clamp(0, ordered.length);
    return ordered.sublist(start, end);
  }

  void _syncUnifiedPagination(List<UnifiedQuakeData> ordered) {
    final signature = ordered
        .map(
          (e) =>
              '${e.source}:${e.eventId}:${e.reportNumText}:${e.arrivedAt?.millisecondsSinceEpoch ?? 0}',
        )
        .join('|');

    if (signature != _unifiedPageSignature) {
      _unifiedPageSignature = signature;
      _unifiedPageIndex = 0;
    }

    if (ordered.length <= _unifiedPageSize) {
      _stopUnifiedPageTimer();
      _unifiedPageIndex = 0;
      return;
    }

    final pageCount = _unifiedPageCount(ordered.length);
    if (_unifiedPageIndex >= pageCount) {
      _unifiedPageIndex = pageCount - 1;
    }

    if (_unifiedPageTimer?.isActive == true) return;
    _unifiedPageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final count = context.read<QuakeProvider>().unifiedEvents.length;
      final nextPageCount = _unifiedPageCount(count);
      if (nextPageCount <= 1) {
        _stopUnifiedPageTimer();
        if (mounted) {
          setState(() {
            _unifiedPageIndex = 0;
          });
        }
        return;
      }
      setState(() {
        _unifiedPageIndex = (_unifiedPageIndex + 1) % nextPageCount;
      });
    });
  }

  int _unifiedPageCount(int itemCount) {
    return (itemCount / _unifiedPageSize).ceil();
  }

  void _stopUnifiedPageTimer() {
    _unifiedPageTimer?.cancel();
    _unifiedPageTimer = null;
  }

  Widget _buildCardColumn(
    List<UnifiedQuakeData?> events, {
    bool animateItems = true,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: events.asMap().entries.map((entry) {
        final event = entry.value;
        final isLast = entry.key == events.length - 1;

        // 透明占位：保持每页固定高度，防止列表跳动
        if (event == null) {
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : _s(4, context)),
            child: const SizedBox(height: 90),
          );
        }

        final card = _buildCompactUnifiedCard(event);
        return Padding(
          key: ValueKey(
            'unified_card_${event.source}_${event.eventId}_${event.reportNumText}',
          ),
          padding: EdgeInsets.only(bottom: isLast ? 0 : _s(4, context)),
          child: animateItems
              ? TweenAnimationBuilder<Offset>(
                  tween: Tween(
                    begin: const Offset(-1.0, 0.0),
                    end: Offset.zero,
                  ),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  builder: (context, offset, child) {
                    return FractionalTranslation(
                      translation: offset,
                      child: child,
                    );
                  },
                  child: card,
                )
              : card,
        );
      }).toList(),
    );
  }

  Widget _buildCompactUnifiedCard(UnifiedQuakeData event) {
    final color = _uicColorFromClass(event.className);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_s(10, context)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D0D),
            borderRadius: BorderRadius.circular(_s(10, context)),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: _s(1.2, context),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: _s(20, context),
                spreadRadius: _s(1, context),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCompactTopBar(event),
              _buildCompactBottomSection(event),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTopBar(UnifiedQuakeData event) {
    final color = _uicColorFromClass(event.className);
    return Container(
      height: _s(28, context),
      decoration: BoxDecoration(
        color: color.withAlpha(200),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: _s(10, context)),
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: _s(8, context)),
          Expanded(
            child: Text(
              event.reportNumText.isNotEmpty
                  ? '${event.titleText} ${event.reportNumText}'
                  : event.titleText,
              style: TextStyle(
                color: Colors.white,
                fontSize: _s(11, context),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: _s(10, context)),
        ],
      ),
    );
  }

  Widget _buildCompactBottomSection(UnifiedQuakeData event) {
    return Padding(
      padding: EdgeInsets.all(_s(10, context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildCompactBadge(event),
          SizedBox(width: _s(12, context)),
          Expanded(child: _buildCompactInfoColumn(event)),
        ],
      ),
    );
  }

  Widget _buildCompactBadge(UnifiedQuakeData event) {
    final color = _uicColorFromClass(event.className);
    final label = event.useShindo ? '震度' : '烈度';

    if (event.useShindo) {
      final text = event.maxIntensity;
      final hasSubscript =
          text.length > 1 && (text.contains('弱') || text.contains('強'));
      final mainChar = hasSubscript ? text.substring(0, 1) : text;
      final subChar = hasSubscript ? text.substring(1) : '';

      return Container(
        width: _s(44, context),
        height: _s(44, context),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(_s(8, context)),
          border: Border.all(
            color: color.withValues(alpha: 0.4),
            width: _s(1.2, context),
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subChar.isEmpty)
              Text(
                mainChar,
                style: TextStyle(
                  fontSize: _s(18, context),
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainChar,
                    style: TextStyle(
                      fontSize: _s(18, context),
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    ),
                  ),
                  Text(
                    subChar,
                    style: TextStyle(
                      fontSize: _s(11, context),
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1,
                    ),
                  ),
                ],
              ),
            SizedBox(height: _s(1, context)),
            Text(
              label,
              style: TextStyle(
                fontSize: _s(6, context),
                fontWeight: FontWeight.w500,
                color: color,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    final value = double.tryParse(event.maxIntensity);
    final display = value != null
        ? value.toInt().toString()
        : event.maxIntensity;
    return Container(
      width: _s(44, context),
      height: _s(44, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: _s(1.2, context),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            display,
            style: TextStyle(
              fontSize: _s(16, context),
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
          SizedBox(height: _s(1, context)),
          Text(
            label,
            style: TextStyle(
              fontSize: _s(6, context),
              fontWeight: FontWeight.w500,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoColumn(UnifiedQuakeData event) {
    final isScalePrompt = event.magnitude < 0 && event.hypocenter.isEmpty;
    final isAssumption = event.isAssumption;
    final magStr = isScalePrompt
        ? '規模 調査中'
        : isAssumption
        ? '仮定震源要素'
        : (event.magnitude >= 0
              ? 'M${event.magnitude.toStringAsFixed(1)}'
              : 'M--');
    final depthStr = isScalePrompt || isAssumption
        ? ''
        : (event.depthText.isNotEmpty
              ? event.depthText
              : (event.depth >= 0 ? '深度 ${event.depth.toInt()}km' : '深度 --'));
    final timeStr = event.originTime != null
        ? event.originTime!.toLocal().toString().substring(5, 19)
        : '--:--:--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isScalePrompt ? '震源 調査中' : event.hypocenter,
          style: TextStyle(
            color: Colors.white,
            fontSize: _s(13, context),
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: _s(3, context)),
        Text(
          depthStr.isNotEmpty ? '$magStr  ·  $depthStr' : magStr,
          style: TextStyle(
            color: Colors.white70,
            fontSize: _s(11, context),
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: _s(3, context)),
        Text(
          timeStr,
          style: TextStyle(color: Colors.white54, fontSize: _s(10, context)),
        ),
        if (event.apiTypeLabel.isNotEmpty) ...[
          SizedBox(height: _s(2, context)),
          Text(
            event.apiTypeLabel,
            style: TextStyle(
              color: Colors.white38,
              fontSize: _s(8, context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Color _uicColorFromClass(String className) {
    switch (className) {
      case 'purple':
        return const Color(0xFF7F007F);
      case 'dark-red':
        return const Color(0xFFAF0000);
      case 'red':
        return const Color(0xFFDF0F0F);
      case 'dark-orange':
        return const Color(0xFFFF4F00);
      case 'orange':
        return const Color(0xFFFF8F00);
      case 'yellow':
        return const Color(0xFFF7E757);
      case 'green':
        return const Color(0xFF5FDF8F);
      case 'blue':
        return const Color(0xFF3FAFFF);
      case 'sky-blue':
        return const Color(0xFF5FCFFF);
      case 'dark-gray':
        return const Color(0xFF9F9F9F);
      case 'gray':
      default:
        return const Color(0xFFCFCFCF);
    }
  }

  Widget _buildWeatherAlarmCard(BuildContext context, WeatherAlarm alarm) {
    final themeColor = alarm.levelColor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_s(10, context)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: _s(420, context),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D0D),
            borderRadius: BorderRadius.circular(_s(10, context)),
            border: Border.all(
              color: themeColor.withValues(alpha: 0.3),
              width: _s(1.2, context),
            ),
            boxShadow: [
              BoxShadow(
                color: themeColor.withValues(alpha: 0.1),
                blurRadius: _s(20, context),
                spreadRadius: _s(1, context),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildWeatherHeader(context, alarm),
              _buildWeatherBody(context, alarm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherHeader(BuildContext context, WeatherAlarm alarm) {
    final themeColor = alarm.levelColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(16, context),
        vertical: _s(6, context),
      ),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
        border: Border(
          bottom: BorderSide(
            color: themeColor.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: themeColor,
              boxShadow: [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.6),
                  blurRadius: _s(4, context),
                ),
              ],
            ),
          ),
          SizedBox(width: _s(10, context)),
          Expanded(
            child: Text(
              '中国气象局气象预警',
              style: TextStyle(
                fontSize: _s(12, context),
                fontWeight: FontWeight.w700,
                color: themeColor,
                letterSpacing: _s(1.5, context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherBody(BuildContext context, WeatherAlarm alarm) {
    final themeColor = alarm.levelColor;
    final disasterType = alarm.disasterType;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _s(16, context),
        _s(10, context),
        _s(16, context),
        _s(12, context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: _s(48, context),
                height: _s(48, context),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(_s(8, context)),
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.4),
                    width: _s(1.2, context),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  alarm.levelLabel,
                  style: TextStyle(
                    fontSize: _s(16, context),
                    fontWeight: FontWeight.w900,
                    color: themeColor,
                  ),
                ),
              ),
              SizedBox(width: _s(12, context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (disasterType.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: _s(6, context),
                          vertical: _s(1, context),
                        ),
                        margin: EdgeInsets.only(bottom: _s(4, context)),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(_s(3, context)),
                        ),
                        child: Text(
                          disasterType,
                          style: TextStyle(
                            fontSize: _s(9, context),
                            color: themeColor.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      alarm.headline,
                      style: TextStyle(
                        fontSize: _s(15, context),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: _s(8, context)),
          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: _s(12, context),
                color: Colors.white38,
              ),
              SizedBox(width: _s(6, context)),
              Text(
                alarm.effective,
                style: TextStyle(
                  fontSize: _s(12, context),
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandbyState(BuildContext context, QuakeProvider provider) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_s(10, context)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: _s(420, context),
          padding: EdgeInsets.symmetric(vertical: _s(39, context)),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D0D),
            borderRadius: BorderRadius.circular(_s(10, context)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          child: Center(
            child: Text(
              '当前无预警信息',
              style: TextStyle(
                color: Colors.white54,
                fontSize: _s(14, context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    QuakeMessage event,
    Color themeColor,
    bool isSerious,
    int warningCount,
    QuakeProvider provider,
  ) {
    final sourceLabel = _sourceLabel(event, includeProvince: true);
    final barColor = _eewBarColor(event);
    final barTextColor = _eewBarTextColor(event);
    final titleText = event.isCanceled
        ? '${_safeWarningLabel(event)} (已取消)'
        : '${_safeWarningLabel(event)}${event.reportNumText != null ? ' ${event.reportNumText}' : ''}';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(16, context),
        vertical: _s(6, context),
      ),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
        border: Border(
          bottom: BorderSide(
            color: barColor.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: barColor,
              boxShadow: [
                BoxShadow(
                  color: barColor.withValues(alpha: 0.6),
                  blurRadius: _s(4, context),
                ),
              ],
            ),
          ),
          SizedBox(width: _s(10, context)),
          Expanded(
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: _s(12, context),
                fontWeight: FontWeight.w700,
                color: barTextColor,
                letterSpacing: _s(1.5, context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (warningCount > 1) ...[
            _buildCarouselNav(context, provider, warningCount, barColor),
            SizedBox(width: _s(6, context)),
          ],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _s(6, context),
              vertical: _s(2, context),
            ),
            decoration: BoxDecoration(
              color: barColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(_s(4, context)),
              border: Border.all(
                color: barColor.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _s(98, context)),
              child: Text(
                sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _s(10, context),
                  color: barColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: _s(0.5, context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselNav(
    BuildContext context,
    QuakeProvider provider,
    int total,
    Color themeColor,
  ) {
    final current = provider.currentWarningIndex + 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: provider.prevWarning,
          child: Icon(
            Icons.chevron_left,
            size: _s(14, context),
            color: themeColor.withValues(alpha: 0.7),
          ),
        ),
        Text(
          '$current/$total',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: _s(10, context),
            color: themeColor.withValues(alpha: 0.8),
            fontWeight: FontWeight.w700,
          ),
        ),
        GestureDetector(
          onTap: provider.nextWarning,
          child: Icon(
            Icons.chevron_right,
            size: _s(14, context),
            color: themeColor.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    QuakeMessage event,
    double intensity,
    Color themeColor,
    int countdown,
    double distance,
  ) {
    final double localIntensity = IntensityCalculator.calculate(
      mag: event.magnitude,
      distance: distance,
    );
    final displayTime = QuakeTime.displayClock(event);
    final displayTimeText =
        '${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')}:${displayTime.second.toString().padLeft(2, '0')} ${QuakeTime.zoneLabel(event)}';
    final reportText = _reportText(event);
    final useShindoBadge = _useShindo(event);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _s(16, context),
        _s(10, context),
        _s(16, context),
        _s(10, context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (useShindoBadge && event.jmaShindo != null)
                _buildShindoBadge(context, event.jmaShindo!, themeColor)
              else
                _buildIntensityBadge(context, intensity, themeColor),
              SizedBox(width: _s(12, context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.location,
                      style: TextStyle(
                        fontSize: _s(18, context),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: _s(4, context)),
                    Text(
                      'M${event.magnitude.toStringAsFixed(1)}  ·  深度 ${event.depth.toStringAsFixed(0)} km',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: _s(12, context),
                      ),
                    ),
                    SizedBox(height: _s(4, context)),
                    Wrap(
                      spacing: _s(6, context),
                      runSpacing: _s(4, context),
                      children: [
                        _metaChip(
                          context,
                          Icons.access_time,
                          '发震 $displayTimeText',
                        ),
                        _metaChip(context, Icons.receipt_long, reportText),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: _s(8, context)),
          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Text(
                'S 娉㈡姷杈? ',
                style: TextStyle(
                  fontSize: _s(12, context),
                  color: Colors.white54,
                ),
              ),
              Expanded(
                child: Text(
                  countdown > 0
                      ? '${countdown.toString().padLeft(2, '0')} 秒'
                      : '已到达',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: _s(22, context),
                    fontWeight: FontWeight.w900,
                    color: countdown > 0 ? themeColor : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Text(
                '鏈湴鐑堝害  ',
                style: TextStyle(
                  fontSize: _s(10, context),
                  color: Colors.white38,
                ),
              ),
              Text(
                '${localIntensity.toStringAsFixed(2)} 度',
                style: TextStyle(
                  fontSize: _s(14, context),
                  fontWeight: FontWeight.w700,
                  color: IntensityTheme.getColor(localIntensity),
                ),
              ),
            ],
          ),
          SizedBox(height: _s(6, context)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: _s(6, context)),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(_s(6, context)),
              border: Border.all(
                color: themeColor.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: Text(
              IntensityTheme.getAction(intensity),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeColor,
                fontSize: _s(12, context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _safeWarningLabel(QuakeMessage event) {
    try {
      return event.source.warningLabel;
    } catch (_) {
      return '鍦伴渿棰勮';
    }
  }

  /// 判断是否使用 JMA 震度显示
  bool _useShindo(QuakeMessage event) {
    return event.jmaShindo != null && event.jmaShindo!.isNotEmpty;
  }

  bool _isScalePrompt(QuakeMessage event) => event.infoTypeName == '震度速報';

  bool _isDestination(QuakeMessage event) => event.infoTypeName == '震源に関する情報';

  /// 生成信息事件标题
  ///
  /// 参考 kanameishi 的 setEqMessage 标题生成逻辑
  String _infoEventTitle(QuakeMessage event) {
    switch (event.source) {
      case QuakeSourceType.cenc:
        return '中国地震台网地震信息';
      case QuakeSourceType.usgs:
        final rt = event.reviewType;
        if (rt == 'reviewed' || rt == '正式测定') return 'USGS正式测定';
        if (rt != null) return 'USGS自动测定';
        return 'USGS測定';
      case QuakeSourceType.fssn:
        final rt = event.reviewType;
        if (rt == '正式(已核实)') return 'FSSN正式测定';
        if (rt == '已确认') return 'FSSN自动测定';
        return 'FSSN地震报告';
      case QuakeSourceType.fssnCmt:
        return 'FSSN 地震矩心矩张量解';
      case QuakeSourceType.hko:
        final verify = event.verify;
        if (verify == 'Y') return '香港天文台已核实';
        if (verify == 'N') return '香港天文台初步报告';
        return '香港天文台地震报告';
      case QuakeSourceType.emsc:
        return '欧洲地中海地震中心';
      case QuakeSourceType.bcsf:
        return '法国中央地震研究所';
      case QuakeSourceType.gfz:
        return '德国地学研究中心';
      case QuakeSourceType.usp:
        return '巴西圣保罗大学';
      case QuakeSourceType.kma_eq:
        return '기상청 지진 정보';
      case QuakeSourceType.ningxia:
        return '宁夏地震局';
      case QuakeSourceType.guangxi:
        return '广西地震局';
      case QuakeSourceType.shanxi:
        return '山西地震局';
      case QuakeSourceType.beijing:
        return '北京地震局';
      case QuakeSourceType.yunnan:
        return '云南地震局';
      case QuakeSourceType.cwa:
      case QuakeSourceType.cwa_eew:
        return '中央氣象署地震報告';
      case QuakeSourceType.wolfx:
      case QuakeSourceType.p2p:
      case QuakeSourceType.jma_fan:
        return event.infoTypeName ?? '鍦伴渿鎯呭牨';
      default:
        return '鍦伴渿鎯呭牨';
    }
  }

  /// 获取数据源类型标签
  ///
  /// 参考 kanameishi 的 sourceTypes 映射
  String _sourceTypeLabel(QuakeMessage event) {
    if (event.source == QuakeSourceType.wolfx) return 'Wolfx';
    if (event.source == QuakeSourceType.p2p) return 'P2PQ';
    if (event.source == QuakeSourceType.jma_fan) return 'FAN';
    if (event.source == QuakeSourceType.cwa ||
        event.source == QuakeSourceType.cwa_eew) {
      return 'FAN';
    }
    if (event.source == QuakeSourceType.cenc) return 'FAN';
    if (event.source == QuakeSourceType.fssn ||
        event.source == QuakeSourceType.fssnCmt) {
      return 'FAN';
    }
    if (event.source == QuakeSourceType.usgs) return 'FAN';
    if (event.source == QuakeSourceType.hko) return 'FAN';
    if (event.source == QuakeSourceType.emsc) return 'FAN';
    if (event.source == QuakeSourceType.bcsf) return 'FAN';
    if (event.source == QuakeSourceType.gfz) return 'FAN';
    if (event.source == QuakeSourceType.usp) return 'FAN';
    if (event.source == QuakeSourceType.kma_eq ||
        event.source == QuakeSourceType.kma_eew_fan) {
      return 'KMA';
    }
    if (event.source == QuakeSourceType.sa) return 'FAN';
    return '';
  }

  /// 获取徽章烈度/震度值
  ///
  /// 优先级：API 原始值 > 当地标准震中(距离=0)公式
  /// 注意：本方法不用于"本地烈度"行，本地烈度在 _buildBody 中单独计算
  double _badgeIntensity(QuakeMessage event) {
    if (event.maxIntensity != null) {
      return event.maxIntensity!.clamp(0.0, 12.0).toDouble();
    }

    // 无 API 值：按当地标准计算震中(距离=0)烈度
    switch (event.source) {
      case QuakeSourceType.cenc:
      case QuakeSourceType.cea:
      case QuakeSourceType.cea_pr:
      case QuakeSourceType.sc_eew:
      case QuakeSourceType.fj_eew:
      case QuakeSourceType.cq_eew:
      case QuakeSourceType.sa:
        return IntensityCalculator.calcCsisLevel(
          event.magnitude,
          event.depth,
          0,
        ).toDouble();
      case QuakeSourceType.cwa_eew:
      case QuakeSourceType.cwa:
        return IntensityCalculator.calcCwbLevel(
          event.magnitude,
          event.depth,
          0,
        ).toDouble();
      default:
        // JMA 公式计算震中震度 (distance=1 最小值)
        return IntensityCalculator.calculate(mag: event.magnitude, distance: 1);
    }
  }

  Widget _buildIntensityBadge(
    BuildContext context,
    double intensity,
    Color color,
  ) {
    return Container(
      width: _s(58, context),
      height: _s(64, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: _s(1.2, context),
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: _s(3, context),
          horizontal: _s(2, context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                intensity >= 0 ? intensity.toStringAsFixed(2) : '?',
                style: TextStyle(
                  fontSize: _s(22, context),
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.0,
                ),
              ),
            ),
            SizedBox(height: _s(1, context)),
            Text(
              '浼版祴鐑堝害',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _s(8, context),
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建震度徽章
  ///
  /// 用于显示 JMA 震度 (如 "5-", "6+", "7")
  /// 参考 kanameishi 的 shindo 显示样式
  Widget _buildShindoBadge(BuildContext context, String shindo, Color color) {
    final display = shindo;
    final mainChar = display.isNotEmpty ? display[0] : '?';
    final subChar = display.length > 1 ? display.substring(1) : '';

    return Container(
      width: _s(58, context),
      height: _s(64, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: _s(1.2, context),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (subChar.isEmpty)
            Text(
              mainChar,
              style: TextStyle(
                fontSize: _s(28, context),
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.0,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mainChar,
                  style: TextStyle(
                    fontSize: _s(28, context),
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.0,
                  ),
                ),
                Text(
                  subChar,
                  style: TextStyle(
                    fontSize: _s(16, context),
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          SizedBox(height: _s(1, context)),
          Text(
            '最大震度',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _s(8, context),
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoEventCard(
    BuildContext context,
    QuakeMessage event,
    double intensity,
    Color themeColor,
    bool isSerious,
    int totalCount,
    QuakeProvider provider,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_s(10, context)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: _s(420, context),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D0D),
            borderRadius: BorderRadius.circular(_s(10, context)),
            border: Border.all(
              color: _isScalePrompt(event)
                  ? const Color(0xFF666666).withValues(alpha: 0.35)
                  : themeColor.withValues(alpha: 0.35),
              width: _s(1.2, context),
            ),
            boxShadow: [
              BoxShadow(
                color: themeColor.withValues(alpha: 0.08),
                blurRadius: _s(20, context),
                spreadRadius: _s(1, context),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoEventHeader(
                context,
                event,
                themeColor,
                totalCount,
                provider,
              ),
              _buildInfoEventBody(context, event, intensity, themeColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoEventHeader(
    BuildContext context,
    QuakeMessage event,
    Color themeColor,
    int totalCount,
    QuakeProvider provider,
  ) {
    final title = _infoEventTitle(event);
    final sourceLabel = _sourceLabel(event, includeProvince: true);
    final typeLabel = _sourceTypeLabel(event);
    final isScale = _isScalePrompt(event);
    final barColor = isScale ? const Color(0xFF666666) : themeColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(16, context),
        vertical: _s(6, context),
      ),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
        border: Border(
          bottom: BorderSide(
            color: barColor.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: barColor,
              boxShadow: [
                BoxShadow(
                  color: barColor.withValues(alpha: 0.6),
                  blurRadius: _s(4, context),
                ),
              ],
            ),
          ),
          SizedBox(width: _s(10, context)),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: _s(12, context),
                      fontWeight: FontWeight.w700,
                      color: barColor,
                      letterSpacing: _s(1.5, context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (typeLabel.isNotEmpty) ...[
                  SizedBox(width: _s(6, context)),
                  _buildTopChip(context, typeLabel, barColor),
                ],
              ],
            ),
          ),
          if (totalCount > 1) ...[
            _buildCarouselNav(context, provider, totalCount, barColor),
            SizedBox(width: _s(6, context)),
          ],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _s(6, context),
              vertical: _s(2, context),
            ),
            decoration: BoxDecoration(
              color: barColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(_s(4, context)),
              border: Border.all(
                color: barColor.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _s(98, context)),
              child: Text(
                sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _s(10, context),
                  color: barColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: _s(0.5, context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoEventBody(
    BuildContext context,
    QuakeMessage event,
    double intensity,
    Color themeColor,
  ) {
    final displayTime = QuakeTime.displayClock(event);
    final useShindo = _useShindo(event);
    final isScale = _isScalePrompt(event);
    final isDest = _isDestination(event);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _s(16, context),
        _s(10, context),
        _s(16, context),
        _s(10, context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (useShindo && event.jmaShindo != null)
                _buildShindoBadge(context, event.jmaShindo!, themeColor)
              else
                _buildIntensityBadge(context, intensity, themeColor),
              SizedBox(width: _s(12, context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isScale ? '震源地: 調査中' : event.location,
                      style: TextStyle(
                        fontSize: _s(18, context),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: _s(4, context)),
                    if (!isScale)
                      Text(
                        'M${event.magnitude.toStringAsFixed(1)}  ·  深度 ${event.depth.toStringAsFixed(0)} km',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: _s(12, context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: _s(8, context)),
          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: _s(14, context),
                color: Colors.white38,
              ),
              SizedBox(width: _s(6, context)),
              Text(
                '${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')}:${displayTime.second.toString().padLeft(2, '0')} ${QuakeTime.zoneLabel(event)}',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: _s(15, context),
                  fontWeight: FontWeight.w900,
                  color: themeColor,
                ),
              ),
            ],
          ),
          SizedBox(height: _s(6, context)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: _s(6, context)),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(_s(6, context)),
              border: Border.all(
                color: themeColor.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: Text(
              isDest
                  ? '最大震度: 不明'
                  : useShindo
                  ? '最大震度 ${event.jmaShindo ?? '?'}'
                  : '预估最大烈度 ${intensity.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeColor,
                fontSize: _s(12, context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _reportText(QuakeMessage event) {
    final n = event.reportNumber;
    if (n != null && n > 0) return '第${n}报';
    return '第?报';
  }

  String _sourceLabel(QuakeMessage event, {bool includeProvince = false}) {
    // /cea-pr 顶部来源标签要求带省级分中心字段。
    if (includeProvince && event.source == QuakeSourceType.cea_pr) {
      final province = _provinceLabel(event);
      if (province != null && province.isNotEmpty) {
        return '省级网/$province';
      }
      return '省级网';
    }
    return event.source.displayName;
  }

  String? _provinceLabel(QuakeMessage event) {
    // 仅从注册字段 province 读取，不再从 location 兜底推断。
    if (event.source == QuakeSourceType.cea_pr &&
        event.province != null &&
        event.province!.isNotEmpty) {
      return event.province;
    }
    return null;
  }

  Widget _buildTopChip(BuildContext context, String text, Color themeColor) {
    return Container(
      constraints: BoxConstraints(maxWidth: _s(88, context)),
      padding: EdgeInsets.symmetric(
        horizontal: _s(5, context),
        vertical: _s(2, context),
      ),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_s(3, context)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: _s(9, context),
          color: themeColor.withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String text) {
    return Container(
      constraints: BoxConstraints(maxWidth: _s(195, context)),
      padding: EdgeInsets.symmetric(
        horizontal: _s(6, context),
        vertical: _s(2, context),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_s(4, context)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _s(11, context), color: Colors.white54),
          SizedBox(width: _s(4, context)),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _s(10, context),
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
