import 'package:flutter/material.dart';
import '../../services/weather_playback_controller.dart';

class MobileWeatherPlaybackControls extends StatefulWidget {
  const MobileWeatherPlaybackControls({super.key, required this.controller});
  final WeatherPlaybackController controller;
  @override
  State<MobileWeatherPlaybackControls> createState() => _ControlsState();
}

class _ControlsState extends State<MobileWeatherPlaybackControls> {
  double? _drag;
  String _clock(DateTime t) {
    final v = t.toUtc().add(const Duration(hours: 8));
    return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, n = c.entries.length;
      if (!c.supported)
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '当前图层仅显示实时数据',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('weather-playback-play'),
                tooltip: c.playing ? '暂停' : '播放实况动画',
                onPressed: c.playing || !c.loading ? c.toggle : null,
                icon: Icon(
                  c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: n > 1
                    ? Slider(
                        key: const ValueKey('weather-playback-slider'),
                        min: 0,
                        max: (n - 1).toDouble(),
                        divisions: n - 1,
                        value: (_drag ?? c.index.toDouble())
                            .clamp(0, n - 1)
                            .toDouble(),
                        onChangeStart: (_) {
                          c.pause();
                        },
                        onChanged: (v) => setState(() => _drag = v),
                        onChangeEnd: (v) {
                          setState(() => _drag = null);
                          c.seek(v.round());
                        },
                      )
                    : Text(
                        c.loading ? '正在获取历史实况…' : '播放最近实况',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
              ),
              if (c.loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              TextButton(
                key: const ValueKey('weather-playback-live'),
                onPressed: c.live,
                child: Text(
                  c.frame.value == null ? '实时' : '回到实时',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              IconButton(
                tooltip: '刷新历史帧',
                visualDensity: VisualDensity.compact,
                onPressed: c.loading ? null : c.load,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Colors.white70,
                  size: 19,
                ),
              ),
            ],
          ),
          if (n > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _clock(c.timeAt(0)),
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
                Text(
                  '${c.index + 1}/$n 帧 · 实况',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
                Text(
                  _clock(c.timeAt(n - 1)),
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          if (c.error != null)
            Text(
              c.error!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
        ],
      );
    },
  );
}
