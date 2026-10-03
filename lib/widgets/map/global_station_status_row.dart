import 'package:flutter/material.dart';
import '../../services/sources/fdsn_source_catalog.dart';
import '../../services/sources/fdsn_source_status.dart';

Color globalStationStatusColor(FdsnSourceStatus status) {
  switch (status.state) {
    case FdsnSourceConnectionState.failed:
      return const Color(0xFFFF5252);
    case FdsnSourceConnectionState.connecting:
      return const Color(0xFFFFD54F);
    case FdsnSourceConnectionState.idle:
      return const Color(0xFFAAAAAA);
    case FdsnSourceConnectionState.streaming:
      const stops = [
        Color(0xFF45D483),
        Color(0xFFFFD54F),
        Color(0xFFFF9B45),
        Color(0xFFFF5252),
      ];
      final position = status.delayScore * (stops.length - 1);
      final index = position.floor().clamp(0, stops.length - 2);
      return Color.lerp(stops[index], stops[index + 1], position - index)!;
  }
}

String globalStationStatusDescription(FdsnSourceStatus status) {
  final state = switch (status.state) {
    FdsnSourceConnectionState.connecting => '连接中／等待数据',
    FdsnSourceConnectionState.streaming => '正在接收数据',
    FdsnSourceConnectionState.failed => '连接或订阅失败',
    FdsnSourceConnectionState.idle => '没有分配测站',
  };
  return '${status.source}：$state\n'
      '有效连接 ${status.linked} 站／已订阅 ${status.selected} 站\n'
      '≤30 秒 ${status.timely} 站；30–180 秒 ${status.delayed} 站\n'
      '>180 秒 ${status.stale} 站；未收到有效数据 ${status.missing} 站';
}

class GlobalStationStatusRow extends StatelessWidget {
  const GlobalStationStatusRow({
    super.key,
    required this.statuses,
    required this.style,
    this.spacing = 10,
    this.runSpacing = 2,
  });

  final List<FdsnSourceStatus> statuses;
  final TextStyle style;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    final bySource = {for (final status in statuses) status.source: status};
    return Wrap(
      key: const ValueKey('global-station-statuses'),
      spacing: spacing,
      runSpacing: runSpacing,
      children: [
        for (final source in FdsnSourceCatalog.sources)
          if (bySource[source.name] case final status?)
            Tooltip(
              message: globalStationStatusDescription(status),
              child: Text(
                '${status.source}(${status.linked})',
                semanticsLabel: '${status.source} ${status.linked}站',
                key: ValueKey('global-station-${status.source}'),
                style: style.copyWith(color: globalStationStatusColor(status)),
              ),
            ),
      ],
    );
  }
}
