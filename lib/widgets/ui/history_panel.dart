import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../core/calculator.dart';
import '../../models/eew_event_group.dart';
import '../../core/utils/quake_time.dart';
import '../../models/unified_quake_data.dart';
import 'unified_intensity_format.dart';

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<QuakeProvider>();
    return ValueListenableBuilder<int>(
      valueListenable: provider.historyListenable,
      builder: (context, _, child) {
        final groups = provider.eewHistory;

        if (groups.isEmpty) {
          return const Center(
            child: Text("暂无历史记录", style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            return _EewEventGroupCard(
              key: ValueKey(groups[index].eventId),
              group: groups[index],
            );
          },
        );
      },
    );
  }
}

class _EewEventGroupCard extends StatefulWidget {
  final EewEventGroup group;

  const _EewEventGroupCard({super.key, required this.group});

  @override
  State<_EewEventGroupCard> createState() => _EewEventGroupCardState();
}

class _EewEventGroupCardState extends State<_EewEventGroupCard> {
  static const double _badgeSize = 42;
  bool _expanded = false;

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

  @override
  Widget build(BuildContext context) {
    final latest = widget.group.latest;
    final color = _colorFromClass(latest.className);
    final reports = widget.group.reports;
    final hasMultiple = reports.length > 1;

    return Material(
      color: Colors.grey[900]?.withOpacity(0.8),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          final dest = LatLng(latest.lat ?? 0, latest.lng ?? 0);
          if (QuakeCalculator.isUsableMapCoordinate(
            dest.latitude,
            dest.longitude,
          )) {
            final mapState = context.read<MapStateProvider>();
            mapState.pauseAutoZoom();
            mapState.animatedMove(dest, 7.0);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMainRow(latest, color, hasMultiple),
              if (hasMultiple) ...[
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${widget.group.latestReportNumber}报',
                          style: TextStyle(
                            color: color.withOpacity(0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: color.withOpacity(0.6),
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded) _buildReportList(reports, color),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainRow(UnifiedQuakeData event, Color color, bool hasMultiple) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildBadge(event, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.titleText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        softWrap: true,
                      ),
                    ),
                    if (event.reportNumText.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          event.reportNumText,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatInfo(event),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (event.apiTypeLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.apiTypeLabel,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.location_searching, color: Colors.white24, size: 18),
        ],
      ),
    );
  }

  Widget _buildBadge(UnifiedQuakeData event, Color color) {
    if (event.useShindo) {
      final text = event.maxIntensity;
      final hasSub =
          text.length > 1 && (text.contains('弱') || text.contains('強'));
      final mainChar = hasSub ? text.substring(0, 1) : text;
      final subChar = hasSub ? text.substring(1) : '';

      return Container(
        width: _badgeSize,
        height: _badgeSize,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: subChar.isEmpty
                  ? Text(
                      mainChar,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mainChar,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: color,
                            height: 1,
                          ),
                        ),
                        Text(
                          subChar,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: color,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
            ),
            Text(
              '震度',
              style: TextStyle(
                fontSize: 6,
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
        ? unifiedRomanIntensityLabel(event.maxIntensity)
        : event.maxIntensity;

    return Container(
      width: _badgeSize,
      height: _badgeSize,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
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
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1,
              ),
            ),
          ),
          Text(
            '烈度',
            style: TextStyle(
              fontSize: 6,
              fontWeight: FontWeight.w500,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportList(List<UnifiedQuakeData> reports, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: Colors.white10),
          ...reports.map((report) => _buildReportRow(report, color)),
        ],
      ),
    );
  }

  Widget _buildReportRow(UnifiedQuakeData report, Color groupColor) {
    final reportColor = _colorFromClass(report.className);

    return InkWell(
      onTap: () {
        final dest = LatLng(report.lat ?? 0, report.lng ?? 0);
        if (QuakeCalculator.isUsableMapCoordinate(
          dest.latitude,
          dest.longitude,
        )) {
          final mapState = context.read<MapStateProvider>();
          mapState.pauseAutoZoom();
          mapState.animatedMove(dest, 7.0);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBadge(report, reportColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      if (report.reportNumText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: groupColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            report.reportNumText,
                            style: TextStyle(
                              color: groupColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (report.isFinal) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '最終',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (report.isCanceled) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '取消',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (report.isWarn) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '警報',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isInvestigatingHypocenter(report.hypocenter)
                        ? '震源 調査中'
                        : report.hypocenter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatInfo(report),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  if (report.apiTypeLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      report.apiTypeLabel,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.location_searching,
              color: Colors.white24,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _formatInfo(UnifiedQuakeData event) {
    final hypocenterInvestigating = _isInvestigatingHypocenter(
      event.hypocenter,
    );
    final magnitudeInvestigating = event.magnitude < 0;
    if (hypocenterInvestigating && magnitudeInvestigating) {
      return '震源 調査中  規模 調査中';
    }
    if (event.isAssumption) return '${event.hypocenter}  仮定震源要素';
    final magStr = !magnitudeInvestigating
        ? 'M${event.magnitude.toStringAsFixed(1)}'
        : '規模 調査中';
    final depthStr = event.depthText.isNotEmpty
        ? event.depthText
        : (event.depth >= 0 ? '深${event.depth.round()}km' : '深度 --');
    final timeStr = QuakeTime.formatUnifiedOriginClock(
      event,
      includeSeconds: false,
    );
    final locationText = hypocenterInvestigating ? '' : event.hypocenter;
    return [
      timeStr,
      magStr,
      depthStr,
      locationText,
    ].where((item) => item.isNotEmpty).join('  ');
  }

  bool _isInvestigatingHypocenter(String value) {
    final text = value.trim();
    return text.isEmpty ||
        text.contains('調査中') ||
        text.contains('调查中') ||
        text == '不明' ||
        text == '不詳' ||
        text.toLowerCase() == 'unknown';
  }
}
