import 'package:flutter/material.dart';

import '../../models/jma_lpgm_bulletin.dart';

/// Sidebar page for an official JMA VXSE62 long-period observation bulletin.
class JmaLpgmSidebarPanel extends StatelessWidget {
  const JmaLpgmSidebarPanel({
    super.key,
    required this.bulletin,
    required this.scale,
  });

  final JmaLpgmBulletin bulletin;
  final double Function(double) scale;

  @override
  Widget build(BuildContext context) {
    final maxRegions = bulletin.regionsAtMaxClass();
    final stations = bulletin.topStations(limit: 6);
    final category = jmaLpgmCategoryLabel(bulletin.lgCategory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: scale(18),
              height: scale(18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: jmaLpgmClassColor(bulletin.maxLgInt),
                borderRadius: BorderRadius.circular(scale(3)),
              ),
              child: Text(
                '${bulletin.maxLgInt}',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: scale(11),
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            SizedBox(width: scale(6)),
            Expanded(
              child: Text(
                '长周期地震动观测情报',
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
        SizedBox(height: scale(2)),
        Text(
          [
            'JMA · VXSE62',
            if (bulletin.serial > 1) '第 ${bulletin.serial} 报',
            if (bulletin.infoType.isNotEmpty) bulletin.infoType,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: scale(9.5),
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        SizedBox(height: scale(4)),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in _basicRows())
                  _LpgmDataRow(row: row, scale: scale),
                if (bulletin.headline.isNotEmpty)
                  _LpgmTextSection(
                    label: '概要',
                    value: bulletin.headline,
                    scale: scale,
                  ),
                if (category.isNotEmpty)
                  _LpgmDataRow(row: _LpgmData('类别', category), scale: scale),
                if (maxRegions.isNotEmpty)
                  _LpgmTextSection(
                    label: '最大阶级地区',
                    value: maxRegions.map((region) => region.name).join('、'),
                    scale: scale,
                  ),
                if (stations.isNotEmpty)
                  _LpgmSection(
                    title: '测站',
                    scale: scale,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final station in stations)
                          Padding(
                            padding: EdgeInsets.only(bottom: scale(2)),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${station.lgInt}  ',
                                    style: TextStyle(
                                      color: jmaLpgmClassColor(station.lgInt),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  TextSpan(text: station.name),
                                  if (station.intensity.isNotEmpty)
                                    TextSpan(text: '  震度${station.intensity}'),
                                  if (station.sva != null)
                                    TextSpan(
                                      text:
                                          '  ${station.sva!.toStringAsFixed(1)}',
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: scale(10.3),
                                height: 1.2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_LpgmData> _basicRows() {
    final rows = <_LpgmData>[];
    void add(String label, String value) {
      if (value.trim().isNotEmpty) rows.add(_LpgmData(label, value.trim()));
    }

    add('最大阶级', '${bulletin.maxLgInt}');
    if (bulletin.maxInt.isNotEmpty) add('最大震度', bulletin.maxInt);
    if (bulletin.magnitude != null) {
      add('震级', 'M${_number(bulletin.magnitude!)}');
    }
    add('震中', bulletin.hypocenter);
    if (bulletin.depthKm != null) {
      add('深度', '${_number(bulletin.depthKm!)} km');
    }
    if (bulletin.originTime != null) {
      add('发震时刻', '${_dateTime(bulletin.originTime!)} JST');
    }
    return rows;
  }

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

class _LpgmSection extends StatelessWidget {
  const _LpgmSection({
    required this.title,
    required this.child,
    required this.scale,
  });

  final String title;
  final Widget child;
  final double Function(double) scale;

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
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: scale(9.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: scale(3)),
          child,
        ],
      ),
    );
  }
}

class _LpgmTextSection extends StatelessWidget {
  const _LpgmTextSection({
    required this.label,
    required this.value,
    required this.scale,
  });

  final String label;
  final String value;
  final double Function(double) scale;

  @override
  Widget build(BuildContext context) {
    return _LpgmSection(
      title: label,
      scale: scale,
      child: Text(
        value,
        style: TextStyle(
          color: Colors.white,
          fontSize: scale(10.3),
          height: 1.25,
        ),
      ),
    );
  }
}

class _LpgmData {
  const _LpgmData(this.label, this.value);

  final String label;
  final String value;
}

class _LpgmDataRow extends StatelessWidget {
  const _LpgmDataRow({required this.row, required this.scale});

  final _LpgmData row;
  final double Function(double) scale;

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
