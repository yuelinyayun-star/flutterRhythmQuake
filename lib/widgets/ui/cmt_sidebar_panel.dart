import 'package:flutter/material.dart';

import '../../core/utils/cmt_fault_type.dart';
import '../../core/utils/quake_time.dart';
import '../../models/cmt_solution_metadata.dart';
import '../../models/quake_message.dart';
import '../map/fssn_cmt_layer.dart';
import 'ui_scale.dart';

/// Sidebar page for the active CMT solution.
///
/// It only renders values that are already present on [event]. In particular,
/// [CmtSolutionMetadata.rawMomentTensor] keeps the source coordinate basis for
/// display while [CmtBeachball] continues to use the map's canonical input.
class CmtSidebarPanel extends StatelessWidget {
  final QuakeMessage event;
  final double Function(double) scale;

  const CmtSidebarPanel({super.key, required this.event, required this.scale});

  @override
  Widget build(BuildContext context) {
    final metadata = event.cmtMetadata;
    final rows = _rows(metadata);
    final renderableBeachball = CmtBeachball.hasRenderableMechanism(
      momentTensor: event.momentTensor,
      nodalPlane: event.nodalPlane1,
      nodalPlane2: event.nodalPlane2,
    );
    final faultType = CmtFaultTypeClassifier.label(
      CmtFaultTypeClassifier.fromNodalPlane(event.nodalPlane1),
    );

    final phone = UiScale.isPhone(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          event.source.displayName,
          maxLines: phone ? null : 1,
          overflow: phone ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: scale(12),
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        SizedBox(height: scale(4)),
        if (phone)
          for (final row in rows) _CmtRawDataRow(row: row, scale: scale)
        else
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in rows)
                    _CmtRawDataRow(row: row, scale: scale),
                ],
              ),
            ),
          ),
        if (renderableBeachball) ...[
          Padding(
            padding: EdgeInsets.only(top: scale(5), bottom: scale(3)),
            child: Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Center(
            child: CmtBeachball(
              diameter: scale(76),
              momentTensor: event.momentTensor,
              nodalPlane: event.nodalPlane1,
              nodalPlane2: event.nodalPlane2,
            ),
          ),
          SizedBox(height: scale(3)),
        ],
        Center(
          child: Text(
            '断层类型：$faultType（仅供参考）',
            maxLines: UiScale.isPhone(context) ? null : 1,
            overflow: UiScale.isPhone(context)
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            textAlign: UiScale.isPhone(context)
                ? TextAlign.center
                : TextAlign.start,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: scale(10.5),
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
    return phone ? SingleChildScrollView(child: content) : content;
  }

  List<_CmtRawData> _rows(CmtSolutionMetadata? metadata) {
    final originTime = QuakeTime.displayClock(event);
    final rows = <_CmtRawData>[
      _CmtRawData('事件 ID', event.eventId),
      _CmtRawData(
        '发震时刻',
        '${_dateTimeText(originTime)} (${QuakeTime.zoneLabel(event)})',
      ),
      if (event.location.trim().isNotEmpty) _CmtRawData('位置', event.location),
      _CmtRawData('纬度', event.latitude.toString()),
      _CmtRawData('经度', event.longitude.toString()),
      if (event.depth >= 0) _CmtRawData('震源深度', '${event.depth} km'),
      if (event.magnitude >= 0) _CmtRawData('震级', 'M${event.magnitude}'),
      if (event.centroidDepth != null && event.centroidDepth! >= 0)
        _CmtRawData('矩心深度', '${event.centroidDepth} km'),
      if (event.nodalPlane1?.trim().isNotEmpty == true)
        _CmtRawData('节面 1 (走向/倾角/滑动角)', event.nodalPlane1!.trim()),
      if (event.nodalPlane2?.trim().isNotEmpty == true)
        _CmtRawData('节面 2 (走向/倾角/滑动角)', event.nodalPlane2!.trim()),
    ];
    if (metadata == null) return rows;

    if (metadata.centroidTime?.trim().isNotEmpty == true) {
      rows.add(_CmtRawData('矩心时刻', metadata.centroidTime!.trim()));
    }
    if (metadata.centroidLatitude != null) {
      rows.add(_CmtRawData('矩心纬度', metadata.centroidLatitude.toString()));
    }
    if (metadata.centroidLongitude != null) {
      rows.add(_CmtRawData('矩心经度', metadata.centroidLongitude.toString()));
    }
    final scalarMoment = _scalarMomentText(metadata);
    if (scalarMoment != null) rows.add(_CmtRawData('标量矩', scalarMoment));
    if (metadata.momentTensorConvention?.trim().isNotEmpty == true) {
      rows.add(
        _CmtRawData(
          '张量坐标',
          metadata.momentTensorConvention!.trim().toUpperCase(),
        ),
      );
    }
    metadata.rawMomentTensor?.forEach((component, value) {
      rows.add(_CmtRawData(_tensorComponentLabel(component), value));
    });
    if (metadata.varianceReduction != null) {
      rows.add(_CmtRawData('方差减少率', metadata.varianceReduction.toString()));
    }
    if (metadata.stationCount != null) {
      rows.add(_CmtRawData('台站数', metadata.stationCount.toString()));
    }
    if (metadata.nonDoubleCoupleRatio != null) {
      rows.add(_CmtRawData('非双力偶比例', metadata.nonDoubleCoupleRatio.toString()));
    }
    if (metadata.doubleCoupleRatio != null) {
      rows.add(_CmtRawData('双力偶比例', metadata.doubleCoupleRatio.toString()));
    }
    return rows;
  }

  String? _scalarMomentText(CmtSolutionMetadata metadata) {
    final value = metadata.scalarMoment?.trim();
    if (value == null || value.isEmpty) return null;
    final exponent = metadata.scalarMomentExponent;
    final unit = metadata.scalarMomentUnit?.trim();
    final exponentText = exponent == null ? '' : ' × 10^$exponent';
    final unitText = unit == null || unit.isEmpty ? '' : ' $unit';
    return '$value$exponentText$unitText';
  }

  String _tensorComponentLabel(String component) {
    final normalized = component.trim();
    if (normalized.length < 2) return normalized;
    return 'M${normalized.substring(1)}';
  }

  String _dateTimeText(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute:$second';
  }
}

class _CmtRawData {
  final String label;
  final String value;

  const _CmtRawData(this.label, this.value);
}

class _CmtRawDataRow extends StatelessWidget {
  final _CmtRawData row;
  final double Function(double) scale;

  const _CmtRawDataRow({required this.row, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: scale(2)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${row.label}：${UiScale.isPhone(context) ? '\n' : ''}',
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
