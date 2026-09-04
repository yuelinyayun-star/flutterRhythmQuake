import 'package:flutter/material.dart';

import '../../models/jma_megaquake_advisory.dart';

/// Sidebar page for JMA Nankai Trough / Hokkaido-Sanriku subsequent-quake
/// advisories (VYSE50 / VYSE51 / VYSE60).
class JmaMegaquakeSidebarPanel extends StatelessWidget {
  const JmaMegaquakeSidebarPanel({
    super.key,
    required this.advisory,
    required this.scale,
  });

  final JmaMegaquakeAdvisory advisory;
  final double Function(double) scale;

  @override
  Widget build(BuildContext context) {
    final color = jmaMegaquakeKeywordColor(advisory.keyword);
    final keyword = advisory.keywordLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (keyword.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: scale(5),
                  vertical: scale(2),
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(scale(3)),
                ),
                child: Text(
                  keyword,
                  style: TextStyle(
                    color: advisory.keyword == JmaMegaquakeKeyword.investigating
                        ? Colors.black
                        : Colors.white,
                    fontSize: scale(9.5),
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
              SizedBox(width: scale(6)),
            ],
            Expanded(
              child: Text(
                advisory.displayTitle,
                maxLines: 2,
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
          advisory.sourceLabel,
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
                  _MegaquakeDataRow(row: row, scale: scale),
                if (advisory.headline.isNotEmpty)
                  _MegaquakeTextSection(value: advisory.headline, scale: scale),
                if (advisory.bodyText.isNotEmpty &&
                    advisory.bodyText != advisory.headline)
                  _MegaquakeTextSection(value: advisory.bodyText, scale: scale),
                if (advisory.nextAdvisory.isNotEmpty)
                  _MegaquakeTextSection(
                    value: advisory.nextAdvisory,
                    scale: scale,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_MegaquakeData> _basicRows() {
    final rows = <_MegaquakeData>[];
    void add(String label, String value) {
      if (value.trim().isNotEmpty) {
        rows.add(_MegaquakeData(label, value.trim()));
      }
    }

    if (advisory.reportTime != null) {
      add('发表时刻', '${_dateTime(advisory.reportTime!)} JST');
    }
    return rows;
  }

  static String _dateTime(DateTime value) {
    final display = value.isUtc
        ? value.toUtc().add(const Duration(hours: 9))
        : value;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${display.year}-${two(display.month)}-${two(display.day)} '
        '${two(display.hour)}:${two(display.minute)}';
  }
}

class _MegaquakeTextSection extends StatelessWidget {
  const _MegaquakeTextSection({required this.value, required this.scale});

  final String value;
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
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: scale(10.3),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _MegaquakeData {
  const _MegaquakeData(this.label, this.value);

  final String label;
  final String value;
}

class _MegaquakeDataRow extends StatelessWidget {
  const _MegaquakeDataRow({required this.row, required this.scale});

  final _MegaquakeData row;
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
