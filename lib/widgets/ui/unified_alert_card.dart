import 'package:flutter/material.dart';
import 'dart:ui';
import '../../models/unified_quake_data.dart';

class UnifiedAlertCard extends StatefulWidget {
  final UnifiedQuakeData event;
  final int eventCount;
  final int currentIndex;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const UnifiedAlertCard({
    super.key,
    required this.event,
    this.eventCount = 0,
    this.currentIndex = 0,
    this.onPrev,
    this.onNext,
  });

  @override
  State<UnifiedAlertCard> createState() => _UnifiedAlertCardState();
}

class _UnifiedAlertCardState extends State<UnifiedAlertCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;

  static const double _refWidth = 1700.0;

  double _scale(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    return (w / _refWidth).clamp(0.55, 1.0);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _flashAnimation = Tween(begin: 0.3, end: 0.9).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant UnifiedAlertCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFlash();
  }

  void _updateFlash() {
    if (widget.event.isRed) {
      if (!_flashController.isAnimating) {
        _flashController.repeat(reverse: true);
      }
    } else {
      if (_flashController.isAnimating) {
        _flashController.stop();
      }
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_s(10, context)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: _s(420, context),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D0D),
            borderRadius: BorderRadius.circular(_s(10, context)),
            border: _buildBorder(context),
            boxShadow: _buildShadow(context),
          ),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Border _buildBorder(BuildContext context) {
    if (widget.event.isRed) {
      return Border.all(
        color: Colors.red.withAlpha(
          (_flashAnimation.value * 255).round(),
        ),
        width: _s(1.2, context),
      );
    }
    return Border.all(
      color: _colorFromClass(widget.event.className).withAlpha(80),
      width: _s(1.0, context),
    );
  }

  List<BoxShadow> _buildShadow(BuildContext context) {
    if (widget.event.isRed) {
      return [
        BoxShadow(
          color: Colors.red.withAlpha(
            (40 * _flashAnimation.value).round(),
          ),
          blurRadius: _s(20, context),
          spreadRadius: _s(1, context),
        ),
      ];
    }
    return [];
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopBar(context),
        _buildBottomSection(context),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final headerColor = _colorFromClass(widget.event.className);
    final showCarousel = widget.eventCount > 1 && !widget.event.isEmpty;

    return Container(
      height: _s(28, context),
      decoration: BoxDecoration(
        color: headerColor.withAlpha(200),
      ),
      child: Row(
        children: [
          SizedBox(width: _s(10, context)),
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: headerColor,
            ),
          ),
          SizedBox(width: _s(8, context)),
          Expanded(
            child: Text(
              widget.event.titleText,
              style: TextStyle(
                color: Colors.white,
                fontSize: _s(11, context),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showCarousel) _buildCarouselNav(context),
        ],
      ),
    );
  }

  Widget _buildCarouselNav(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onPrev,
          child: Padding(
            padding: EdgeInsets.all(_s(4, context)),
            child: Icon(Icons.chevron_left, size: _s(14, context), color: Colors.white70),
          ),
        ),
        Text(
          '${widget.currentIndex + 1}/${widget.eventCount}',
          style: TextStyle(
            color: Colors.white70,
            fontSize: _s(10, context),
          ),
        ),
        GestureDetector(
          onTap: widget.onNext,
          child: Padding(
            padding: EdgeInsets.all(_s(4, context)),
            child: Icon(Icons.chevron_right, size: _s(14, context), color: Colors.white70),
          ),
        ),
        SizedBox(width: _s(6, context)),
      ],
    );
  }

  Widget _buildBottomSection(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(_s(10, context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildBadge(context),
          SizedBox(width: _s(12, context)),
          Expanded(child: _buildInfoColumn(context)),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context) {
    if (widget.event.useShindo) {
      return _buildShindoBadge(context);
    }
    return _buildIntensityBadge(context);
  }

  Widget _buildIntensityBadge(BuildContext context) {
    final color = _colorFromClass(widget.event.className);
    final value = double.tryParse(widget.event.maxIntensity);
    final display = value != null ? value.toInt().toString() : widget.event.maxIntensity;
    final isNumeric = value != null;
    return Container(
      width: _s(48, context),
      height: _s(48, context),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              display,
              style: TextStyle(
                fontSize: isNumeric ? _s(18, context) : _s(14, context),
                fontWeight: FontWeight.w900,
                color: color,
                height: 1,
              ),
            ),
          ),
          SizedBox(height: _s(1, context)),
          Text(
            '烈度',
            style: TextStyle(
              fontSize: _s(7, context),
              fontWeight: FontWeight.w500,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShindoBadge(BuildContext context) {
    final color = _colorFromClass(widget.event.className);
    final text = widget.event.maxIntensity;
    final hasSubscript = text.length > 1 && (text.contains('弱') || text.contains('強'));
    final mainChar = hasSubscript ? text.substring(0, 1) : text;
    final subChar = hasSubscript ? text.substring(1) : '';

    return Container(
      width: _s(48, context),
      height: _s(48, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(color: color.withValues(alpha: 0.4), width: _s(1.2, context)),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mainChar,
                style: TextStyle(
                  color: color,
                  fontSize: _s(22, context),
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              if (subChar.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: _s(1, context)),
                  child: Text(
                    subChar,
                    style: TextStyle(
                      color: color,
                      fontSize: _s(13, context),
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: _s(1, context)),
          Text(
            '震度',
            style: TextStyle(
              fontSize: _s(7, context),
              fontWeight: FontWeight.w500,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(BuildContext context) {
    final event = widget.event;
    final isScalePrompt = event.magnitude < 0 && event.hypocenter.isEmpty;

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
          _formatMagDepth(event, context),
          style: TextStyle(
            color: Colors.white70,
            fontSize: _s(11, context),
          ),
        ),
        SizedBox(height: _s(3, context)),
        Text(
          _formatTime(event, context),
          style: TextStyle(
            color: Colors.white54,
            fontSize: _s(10, context),
          ),
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

  String _formatMagDepth(UnifiedQuakeData event, BuildContext context) {
    final isScalePrompt = event.magnitude < 0 && event.hypocenter.isEmpty;
    if (isScalePrompt) return '規模 調査中';
    if (event.isAssumption) return '仮定震源要素';
    final magStr = event.magnitude >= 0
        ? 'M${event.magnitude.toStringAsFixed(1)}'
        : 'M--';
    if (event.depthText.isNotEmpty) {
      return '$magStr  ·  ${event.depthText}';
    }
    final depthStr = event.depth >= 0 ? '深度 ${event.depth.round()}km' : '深度 --';
    return '$magStr  ·  $depthStr';
  }

  String _formatTime(UnifiedQuakeData event, BuildContext context) {
    if (event.originTime == null) return '--:--:--';
    return event.originTime!.toLocal().toString().substring(11, 19);
  }

  Color _colorFromClass(String className) {
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
}