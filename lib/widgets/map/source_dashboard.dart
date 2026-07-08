import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../models/source_status.dart';
import '../../services/sources/fdsn_motion_service.dart';
import '../../services/sources/global_quake_service.dart';
import '../ui/ui_scale.dart';

class SourceDashboard extends StatelessWidget {
  const SourceDashboard({super.key});

  double _scale(BuildContext c) => UiScale.compact(c);

  double _s(double v, BuildContext c) => v * _scale(c);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: UiScale.topBarHeight(context) + _s(12 + 140, context),
      right: _s(20, context),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_s(6, context)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: _s(8, context),
                vertical: _s(5, context),
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(_s(6, context)),
                border: Border.all(
                  color: Colors.white10,
                  width: _s(0.8, context),
                ),
              ),
              child: Selector<QuakeProvider, int>(
                selector: (context, provider) => Object.hashAll(
                  provider.sourceStatuses.entries.map(
                    (entry) => Object.hash(entry.key, entry.value),
                  ),
                ),
                builder: (context, _, child) {
                  final provider = context.read<QuakeProvider>();
                  final globalQuakeEnabled = GlobalQuakeService().isEnabled;
                  final rows = provider.sourceStatuses.entries
                      .where(
                        (e) =>
                            e.key != 'CENC' &&
                            e.key != 'S-net' &&
                            (e.key != 'GlobalQuake' || globalQuakeEnabled),
                      )
                      .map((entry) {
                        return _buildStatusRow(context, entry.key, entry.value);
                      })
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...rows,
                      ValueListenableBuilder<int>(
                        valueListenable:
                            FdsnMotionService().linkedStationCountNotifier,
                        builder: (context, count, child) {
                          return ValueListenableBuilder<int>(
                            valueListenable:
                                FdsnMotionService().targetStationLimitNotifier,
                            builder: (context, limit, child) {
                              return _buildStationCountRow(
                                context,
                                count,
                                limit,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(
    BuildContext context,
    String name,
    SourceStatus status,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: _s(2, context)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(context: context, status: status),
          SizedBox(width: _s(6, context)),
          Text(
            name,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              color: Colors.white70,
              fontSize: _s(10, context),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: _s(4, context)),
          Text(
            _getStatusText(status),
            style: TextStyle(
              color: _getStatusColor(status).withValues(alpha: 0.8),
              fontSize: _s(8, context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationCountRow(BuildContext context, int count, int limit) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: _s(2, context)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hub_outlined,
            size: _s(8, context),
            color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
          ),
          SizedBox(width: _s(6, context)),
          Text(
            'FDSN',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              color: Colors.white70,
              fontSize: _s(10, context),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: _s(4, context)),
          Text(
            '$count/$limit',
            style: TextStyle(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
              fontSize: _s(8, context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(SourceStatus status) {
    switch (status) {
      case SourceStatus.connected:
        return "ONLINE";
      case SourceStatus.connecting:
        return "CONNECTING";
      case SourceStatus.disconnected:
        return "OFFLINE";
      case SourceStatus.error:
        return "ERROR";
      case SourceStatus.synchronizing:
        return "SYNCING";
    }
  }

  Color _getStatusColor(SourceStatus status) {
    switch (status) {
      case SourceStatus.connected:
        return const Color(0xFF00FF00);
      case SourceStatus.connecting:
        return const Color(0xFFFFD700);
      case SourceStatus.error:
        return const Color(0xFFFF4500);
      case SourceStatus.disconnected:
        return Colors.grey;
      case SourceStatus.synchronizing:
        return Colors.blueAccent;
    }
  }
}

class _StatusDot extends StatelessWidget {
  final BuildContext context;
  final SourceStatus status;
  const _StatusDot({required this.context, required this.status});

  double _scale() => UiScale.compact(context);

  double _s(double v) => v * _scale();

  @override
  Widget build(BuildContext context) {
    return _buildDot(color: _getStatusColor(status));
  }

  Widget _buildDot({required Color color}) {
    return Container(
      width: _s(6),
      height: _s(6),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Color _getStatusColor(SourceStatus status) {
    switch (status) {
      case SourceStatus.connected:
        return const Color(0xFF00FF00);
      case SourceStatus.connecting:
        return const Color(0xFFFFD700);
      case SourceStatus.error:
        return const Color(0xFFFF4500);
      case SourceStatus.disconnected:
        return Colors.grey;
      case SourceStatus.synchronizing:
        return Colors.blueAccent;
    }
  }
}
