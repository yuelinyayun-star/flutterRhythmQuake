import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';

class WeatherMarquee extends StatelessWidget {
  const WeatherMarquee({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<QuakeProvider>(
      builder: (context, provider, child) {
        final alarm = provider.weatherAlarm;
        if (alarm == null) return const SizedBox.shrink();

        final text = alarm.marqueeText;
        final color = alarm.levelColor;

        return Container(
          height: 34,
          width: double.infinity,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            clipBehavior: Clip.hardEdge,
            child: _MarqueeScroll(text: text, color: color),
          ),
        );
      },
    );
  }
}

class _MarqueeScroll extends StatefulWidget {
  final String text;
  final Color color;

  const _MarqueeScroll({required this.text, required this.color});

  @override
  State<_MarqueeScroll> createState() => _MarqueeScrollState();
}

class _MarqueeScrollState extends State<_MarqueeScroll>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _unitWidth = 0;
  double _boxWidth = 0;
  bool _needsScroll = false;
  bool _initialized = false;
  static const double _gap = 60.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
  }

  @override
  void didUpdateWidget(covariant _MarqueeScroll old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _initialized = false;
      _ctrl.stop();
      _ctrl.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _tryStart() {
    if (_initialized) return;
    if (!mounted || _boxWidth <= 0) return;

    final tp = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    _unitWidth = 12 + 14 + 6 + tp.width + 12;

    if (_unitWidth > _boxWidth) {
      _needsScroll = true;
      final distance = _unitWidth + _gap;
      _ctrl.duration = Duration(
        milliseconds: (distance / 45 * 1000).round().clamp(4000, 25000),
      );
      _ctrl.repeat();
    } else {
      _needsScroll = false;
    }
    _initialized = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_boxWidth != constraints.maxWidth) {
          _boxWidth = constraints.maxWidth;
          _initialized = false;
          WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
        }

        if (!_needsScroll) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: widget.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.text,
                    style: TextStyle(fontSize: 12, color: widget.color, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }

        final distance = _unitWidth + _gap;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final offset = -distance * _ctrl.value;
            return ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: AlignmentDirectional.centerStart,
                child: Transform.translate(
                  offset: Offset(offset, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildUnit(),
                      SizedBox(width: _gap),
                      _buildUnit(),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnit() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: widget.color),
          const SizedBox(width: 6),
          Text(widget.text, style: TextStyle(fontSize: 12, color: widget.color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
