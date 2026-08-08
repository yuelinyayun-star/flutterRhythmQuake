import 'package:flutter/material.dart';

import '../../models/unified_quake_data.dart';
import '../../models/volcano_event_data.dart';

UnifiedQuakeData? selectVolcanoSidebarEvent(
  List<UnifiedQuakeData> events,
  int currentIndex,
) {
  if (currentIndex >= 0 &&
      currentIndex < events.length &&
      events[currentIndex].isVolcanoEvent) {
    return events[currentIndex];
  }

  UnifiedQuakeData? selected;
  DateTime? selectedTime;
  for (final event in events) {
    if (!event.isVolcanoEvent) continue;
    final eventTime = event.arrivedAt ?? event.reportTime ?? event.originTime;
    if (selected == null ||
        (eventTime != null &&
            (selectedTime == null || eventTime.isAfter(selectedTime)))) {
      selected = event;
      selectedTime = eventTime;
    }
  }
  return selected;
}

/// Sidebar page for an active WHEWS/JMA volcano bulletin.
///
/// Empty fields are omitted. Ashfall polygon coordinates remain in the model
/// for the map layer; the compact sidebar reports only the polygon count.
class VolcanoSidebarPanel extends StatelessWidget {
  final UnifiedQuakeData event;
  final double Function(double) scale;

  const VolcanoSidebarPanel({
    super.key,
    required this.event,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final volcano = event.volcanoEvent;
    if (volcano == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.local_fire_department,
              color: const Color(0xFFFF7043),
              size: scale(14),
            ),
            SizedBox(width: scale(4)),
            Expanded(
              child: Text(
                _headerTitle(volcano),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: scale(12),
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
        if (_headerDetail(volcano).isNotEmpty) ...[
          SizedBox(height: scale(2)),
          Text(
            _headerDetail(volcano),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: scale(9.5),
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
        SizedBox(height: scale(4)),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in _basicRows(volcano))
                  _VolcanoDataRow(row: row, scale: scale),
                for (final section in _textSections(volcano))
                  _VolcanoTextSection(section: section, scale: scale),
                if (_plumeRows(volcano).isNotEmpty)
                  _VolcanoSection(
                    title: '喷烟',
                    scale: scale,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final row in _plumeRows(volcano))
                          _VolcanoDataRow(row: row, scale: scale),
                      ],
                    ),
                  ),
                if (volcano.winds.isNotEmpty)
                  _WindSection(volcano: volcano, scale: scale),
                if (volcano.ashfallWindows.isNotEmpty)
                  _AshfallSection(volcano: volcano, scale: scale),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _headerTitle(VolcanoEventData volcano) {
    final kindName = volcano.kindName.trim();
    return kindName.isEmpty ? '日本气象厅火山情报' : kindName;
  }

  String _headerDetail(VolcanoEventData volcano) {
    return [
      volcano.kindCode.trim(),
      volcano.infoTypeName.trim(),
      '日本气象厅 · WHEWS',
    ].where((value) => value.isNotEmpty).join(' · ');
  }

  List<_VolcanoData> _basicRows(VolcanoEventData volcano) {
    final rows = <_VolcanoData>[];
    void add(String label, String value) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) rows.add(_VolcanoData(label, normalized));
    }

    add('事件 ID', event.eventId);
    add('电文标题', volcano.title);
    add('日文类型', volcano.infoKind);
    if (volcano.updates > 0) add('报数', '第 ${volcano.updates} 报');
    add('火山', volcano.volcanoName);
    add('火山代码', volcano.volcanoCode);
    add('火口', volcano.craterName);
    if (volcano.hasMapLocation) {
      add(
        '经纬度',
        '${_number(volcano.latitude!)}°N, ${_number(volcano.longitude!)}°E',
      );
    }
    if (_finite(volcano.elevation)) {
      add('海拔', '${_number(volcano.elevation!)} m');
    }
    if (volcano.reportTime != null) {
      add('发报时刻', '${_dateTime(volcano.reportTime!)} JST');
    }
    if (volcano.targetTime != null) {
      add('现象时刻', '${_dateTime(volcano.targetTime!)} JST');
    }
    add('发布机关', volcano.publishingOffice);
    return rows;
  }

  List<_VolcanoText> _textSections(VolcanoEventData volcano) {
    return [
      _VolcanoText('概要', volcano.headline.trim()),
      _VolcanoText('活动情况', volcano.activity.trim()),
      _VolcanoText('观测补充', volcano.observation.trim()),
      _VolcanoText('防灾事项', volcano.prevention.trim()),
      _VolcanoText('下次发布', volcano.nextAdvisory.trim()),
    ].where((section) => section.value.isNotEmpty).toList(growable: false);
  }

  List<_VolcanoData> _plumeRows(VolcanoEventData volcano) {
    return [
      if (volcano.plumeDirection.trim().isNotEmpty)
        _VolcanoData('方向', volcano.plumeDirection.trim()),
      if (_finite(volcano.plumeHeight))
        _VolcanoData('火口上高度', '${_number(volcano.plumeHeight!)} m'),
      if (_finite(volcano.plumeHeightSea))
        _VolcanoData('海拔高度', '${_number(volcano.plumeHeightSea!)} FT'),
    ];
  }

  static bool _finite(double? value) => value != null && value.isFinite;

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  static String _dateTime(DateTime value) {
    final display = value.isUtc
        ? value.toUtc().add(const Duration(hours: 9))
        : value;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${display.year}-${two(display.month)}-${two(display.day)} '
        '${two(display.hour)}:${two(display.minute)}:${two(display.second)}';
  }
}

class _WindSection extends StatelessWidget {
  final VolcanoEventData volcano;
  final double Function(double) scale;

  const _WindSection({required this.volcano, required this.scale});

  @override
  Widget build(BuildContext context) {
    return _VolcanoSection(
      title: '风场',
      scale: scale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (volcano.windTime != null)
            _VolcanoDataRow(
              row: _VolcanoData(
                '风场时刻',
                '${VolcanoSidebarPanel._dateTime(volcano.windTime!)} JST',
              ),
              scale: scale,
            ),
          for (final wind in volcano.winds)
            if (wind.heightFt != null ||
                wind.degree != null ||
                wind.speedKt != null)
              Padding(
                padding: EdgeInsets.only(bottom: scale(2)),
                child: Text(
                  [
                    if (wind.heightFt != null && wind.heightFt!.isFinite)
                      '${VolcanoSidebarPanel._number(wind.heightFt!)} FT',
                    if (wind.degree != null && wind.degree!.isFinite)
                      '${wind.degree!.round().toString().padLeft(3, '0')}°',
                    if (wind.speedKt != null && wind.speedKt!.isFinite)
                      '${VolcanoSidebarPanel._number(wind.speedKt!)} kt',
                  ].join('   '),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: scale(10.3),
                    height: 1.2,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _AshfallSection extends StatelessWidget {
  final VolcanoEventData volcano;
  final double Function(double) scale;

  const _AshfallSection({required this.volcano, required this.scale});

  @override
  Widget build(BuildContext context) {
    return _VolcanoSection(
      title: '降灰预报',
      scale: scale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (
            var windowIndex = 0;
            windowIndex < volcano.ashfallWindows.length;
            windowIndex++
          ) ...[
            if (windowIndex > 0)
              Padding(
                padding: EdgeInsets.symmetric(vertical: scale(3)),
                child: Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            _AshfallWindowView(
              window: volcano.ashfallWindows[windowIndex],
              scale: scale,
            ),
          ],
        ],
      ),
    );
  }
}

class _AshfallWindowView extends StatelessWidget {
  final VolcanoAshfallWindow window;
  final double Function(double) scale;

  const _AshfallWindowView({required this.window, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (window.label.trim().isNotEmpty)
          _VolcanoDataRow(
            row: _VolcanoData('时间窗', window.label.trim()),
            scale: scale,
          ),
        if (window.startTime != null)
          _VolcanoDataRow(
            row: _VolcanoData(
              '开始',
              '${VolcanoSidebarPanel._dateTime(window.startTime!)} JST',
            ),
            scale: scale,
          ),
        if (window.endTime != null)
          _VolcanoDataRow(
            row: _VolcanoData(
              '结束',
              '${VolcanoSidebarPanel._dateTime(window.endTime!)} JST',
            ),
            scale: scale,
          ),
        for (final item in window.items)
          _AshfallItemView(item: item, scale: scale),
      ],
    );
  }
}

class _AshfallItemView extends StatelessWidget {
  final VolcanoAshfallItem item;
  final double Function(double) scale;

  const _AshfallItemView({required this.item, required this.scale});

  @override
  Widget build(BuildContext context) {
    final rows = <_VolcanoData>[
      if (item.phenomenon.trim().isNotEmpty)
        _VolcanoData('现象', item.phenomenon.trim()),
      if (item.areaNames.isNotEmpty)
        _VolcanoData('区域', item.areaNames.join('、')),
      if (item.plumeDirection.trim().isNotEmpty)
        _VolcanoData('方向', item.plumeDirection.trim()),
      if (item.distanceKm != null && item.distanceKm!.isFinite)
        _VolcanoData(
          '距离',
          '${VolcanoSidebarPanel._number(item.distanceKm!)} km',
        ),
      if (item.sizeCm != null && item.sizeCm!.isFinite)
        _VolcanoData('尺寸', '${VolcanoSidebarPanel._number(item.sizeCm!)} cm'),
      if (item.polygons.isNotEmpty)
        _VolcanoData('多边形', '${item.polygons.length} 个'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) _VolcanoDataRow(row: row, scale: scale),
      ],
    );
  }
}

class _VolcanoSection extends StatelessWidget {
  final String title;
  final Widget child;
  final double Function(double) scale;

  const _VolcanoSection({
    required this.title,
    required this.child,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: scale(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          SizedBox(height: scale(4)),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: scale(10.3),
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          SizedBox(height: scale(2)),
          child,
        ],
      ),
    );
  }
}

class _VolcanoTextSection extends StatelessWidget {
  final _VolcanoText section;
  final double Function(double) scale;

  const _VolcanoTextSection({required this.section, required this.scale});

  @override
  Widget build(BuildContext context) {
    return _VolcanoSection(
      title: section.label,
      scale: scale,
      child: Text(
        section.value,
        style: TextStyle(
          color: Colors.white,
          fontSize: scale(10.3),
          height: 1.25,
        ),
      ),
    );
  }
}

class _VolcanoData {
  final String label;
  final String value;

  const _VolcanoData(this.label, this.value);
}

class _VolcanoText {
  final String label;
  final String value;

  const _VolcanoText(this.label, this.value);
}

class _VolcanoDataRow extends StatelessWidget {
  final _VolcanoData row;
  final double Function(double) scale;

  const _VolcanoDataRow({required this.row, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: scale(2)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${row.label}：',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: row.value,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        style: TextStyle(fontSize: scale(10.3), height: 1.2),
      ),
    );
  }
}
