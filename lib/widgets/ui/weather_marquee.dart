import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/event_animation_clock.dart';
import '../../providers/quake_provider.dart';
import 'ui_runtime_flags.dart';
import 'ui_scale.dart';

class WeatherMarquee extends StatelessWidget {
  const WeatherMarquee({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UiRuntimeFlags.weatherMarqueeEnabledNotifier,
      builder: (context, enabled, child) {
        if (!enabled) return const SizedBox.shrink();
        final provider = context.read<QuakeProvider>();
        return ValueListenableBuilder<int>(
          valueListenable: provider.weatherListenable,
          builder: (context, _, child) {
            final alarm = provider.weatherAlarm;
            if (alarm == null) return const SizedBox.shrink();

            final scale = UiScale.main(context);
            double s(double value) => value * scale;
            final text = alarm.marqueeText;
            final color = alarm.levelColor;
            return Container(
              height: s(34),
              width: double.infinity,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(s(6)),
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: s(0.5),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(s(5)),
                clipBehavior: Clip.hardEdge,
                child: _MarqueeScroll(text: text, color: color, scale: scale),
              ),
            );
          },
        );
      },
    );
  }
}

class _MarqueeScroll extends StatefulWidget {
  final String text;
  final Color color;
  final double scale;

  const _MarqueeScroll({
    required this.text,
    required this.color,
    required this.scale,
  });

  @override
  State<_MarqueeScroll> createState() => _MarqueeScrollState();
}

class _MarqueeScrollState extends State<_MarqueeScroll> {
  EventAnimationLease? _clockLease;
  Duration _scrollDuration = Duration.zero;
  DateTime? _lastTickAt;
  double _progress = 0;
  double _unitWidth = 0;
  double _boxWidth = 0;
  bool _needsScroll = false;
  bool _initialized = false;
  static const double _gapBase = 60.0;

  double _s(double value) => value * widget.scale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
  }

  @override
  void didUpdateWidget(covariant _MarqueeScroll old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.scale != widget.scale) {
      _initialized = false;
      _stopScrollClock();
      _progress = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
    }
  }

  @override
  void dispose() {
    _stopScrollClock();
    super.dispose();
  }

  void _tryStart() {
    if (_initialized) return;
    if (!mounted || _boxWidth <= 0) return;

    final tp = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: TextStyle(fontSize: _s(12), fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    _unitWidth = _s(12) + _s(14) + _s(6) + tp.width + _s(12);

    if (_unitWidth > _boxWidth) {
      _needsScroll = true;
      final distance = _unitWidth + _s(_gapBase);
      _scrollDuration = Duration(
        milliseconds: (distance / 45 * 1000).round().clamp(4000, 25000),
      );
      _startScrollClock();
    } else {
      _needsScroll = false;
      _stopScrollClock();
    }
    _initialized = true;
    if (mounted) setState(() {});
  }

  void _startScrollClock() {
    if (_clockLease != null) return;
    _lastTickAt = DateTime.now();
    EventAnimationClock.instance.frame4Fps.addListener(_tickScroll);
    _clockLease = EventAnimationClock.instance.acquire();
  }

  void _stopScrollClock() {
    EventAnimationClock.instance.frame4Fps.removeListener(_tickScroll);
    _clockLease?.dispose();
    _clockLease = null;
    _lastTickAt = null;
  }

  void _tickScroll() {
    if (!mounted || !_needsScroll || _scrollDuration == Duration.zero) {
      return;
    }
    final now = DateTime.now();
    final last = _lastTickAt ?? now;
    _lastTickAt = now;
    final delta =
        now.difference(last).inMicroseconds / _scrollDuration.inMicroseconds;
    setState(() {
      _progress = (_progress + delta) % 1.0;
    });
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
            padding: EdgeInsets.symmetric(horizontal: _s(12), vertical: _s(6)),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: _s(14),
                  color: widget.color,
                ),
                SizedBox(width: _s(6)),
                Expanded(
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      fontSize: _s(12),
                      color: widget.color,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }

        final distance = _unitWidth + _s(_gapBase);
        final offset = -distance * _progress;
        return RepaintBoundary(
          child: ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: AlignmentDirectional.centerStart,
              child: Transform.translate(
                offset: Offset(offset, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUnit(),
                    SizedBox(width: _s(_gapBase)),
                    _buildUnit(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnit() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _s(12), vertical: _s(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: _s(14), color: widget.color),
          SizedBox(width: _s(6)),
          Text(
            widget.text,
            style: TextStyle(
              fontSize: _s(12),
              color: widget.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
