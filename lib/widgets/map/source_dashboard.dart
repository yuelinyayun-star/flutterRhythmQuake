import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../models/source_status.dart';

class SourceDashboard extends StatelessWidget {
  const SourceDashboard({super.key});

  static const double _refWidth = 1280.0;

  double _scale(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    return (w / _refWidth).clamp(0.7, 1.0);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50 + _s(12 + 140, context),
      right: 20,
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
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(_s(6, context)),
              border: Border.all(color: Colors.white10, width: _s(0.8, context)),
            ),
            child: Consumer<QuakeProvider>(
              builder: (context, provider, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: provider.sourceStatuses.entries
                      .where((e) => e.key != 'CENC' && e.key != 'S-net')
                      .map((entry) {
                    return _buildStatusRow(context, entry.key, entry.value);
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, String name, SourceStatus status) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: _s(2, context)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(context: context, status: status),
          SizedBox(width: _s(6, context)),
          Text(
            name,
            style: TextStyle(fontFamily: 'JetBrainsMono',
              color: Colors.white70,
              fontSize: _s(10, context),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: _s(4, context)),
          Text(
            _getStatusText(status),
            style: TextStyle(
              color: _getStatusColor(status).withOpacity(0.8),
              fontSize: _s(8, context),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(SourceStatus status) {
    switch (status) {
      case SourceStatus.connected: return "ONLINE";
      case SourceStatus.connecting: return "CONNECTING";
      case SourceStatus.disconnected: return "OFFLINE";
      case SourceStatus.error: return "ERROR";
      case SourceStatus.synchronizing: return "SYNCING";
    }
  }

  Color _getStatusColor(SourceStatus status) {
    switch (status) {
      case SourceStatus.connected: return const Color(0xFF00FF00);
      case SourceStatus.connecting: return const Color(0xFFFFD700);
      case SourceStatus.error: return const Color(0xFFFF4500);
      case SourceStatus.disconnected: return Colors.grey;
      case SourceStatus.synchronizing: return Colors.blueAccent;
    }
  }
}

class _StatusDot extends StatefulWidget {
  final BuildContext context;
  final SourceStatus status;
  const _StatusDot({required this.context, required this.status});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const double _refWidth = 1280.0;

  double _scale() {
    final w = MediaQuery.of(widget.context).size.width;
    return (w / _refWidth).clamp(0.7, 1.0);
  }

  double _s(double v) => v * _scale();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color color = _getStatusColor(widget.status);

    bool shouldAnimate = widget.status == SourceStatus.connecting || 
                        widget.status == SourceStatus.error ||
                        widget.status == SourceStatus.synchronizing;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: _s(6),
          height: _s(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(shouldAnimate ? _controller.value : 1.0),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: shouldAnimate ? _s(3) * _controller.value : _s(1.5),
                spreadRadius: _s(0.5),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(SourceStatus status) {
    switch (status) {
      case SourceStatus.connected: return const Color(0xFF00FF00);
      case SourceStatus.connecting: return const Color(0xFFFFD700);
      case SourceStatus.error: return const Color(0xFFFF4500);
      case SourceStatus.disconnected: return Colors.grey;
      case SourceStatus.synchronizing: return Colors.blueAccent;
    }
  }
}
