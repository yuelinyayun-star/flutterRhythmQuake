import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

enum MobileSection { seismic, weather, settings }

/// Keeps the existing map and its subscriptions mounted across page switches.
class MobileSectionHost extends StatefulWidget {
  const MobileSectionHost({
    super.key,
    required this.seismic,
    required this.settingsBuilder,
    this.weather,
    this.onSectionChanged,
  });

  final Widget seismic;
  final Widget Function(VoidCallback onBack) settingsBuilder;
  final Widget? weather;
  final ValueChanged<MobileSection>? onSectionChanged;

  @override
  State<MobileSectionHost> createState() => _MobileSectionHostState();
}

class _MobileSectionHostState extends State<MobileSectionHost> {
  MobileSection _section = MobileSection.seismic;
  bool _settingsCreated = false;

  void _select(MobileSection section) {
    if (_section == section) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _section = section;
      _settingsCreated |= section == MobileSection.settings;
    });
    widget.onSectionChanged?.call(section);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _section == MobileSection.seismic,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(MobileSection.seismic);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage:
                _section == MobileSection.settings ||
                (_section == MobileSection.weather && widget.weather == null),
            child: ExcludeFocus(
              excluding: _section == MobileSection.settings,
              child: widget.seismic,
            ),
          ),
          if (_section == MobileSection.weather)
            widget.weather ??
                const ColoredBox(
                  key: ValueKey('mobile-weather-reserved'),
                  color: Color(0xFF020208),
                ),
          if (_settingsCreated)
            Offstage(
              offstage: _section != MobileSection.settings,
              child: ExcludeFocus(
                excluding: _section != MobileSection.settings,
                child: widget.settingsBuilder(
                  () => _select(MobileSection.seismic),
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 12,
            right: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0x8016191D),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x38FFFFFF)),
                  ),
                  child: Row(
                    children: [
                      for (final (section, label) in const [
                        (MobileSection.seismic, '地震·火山'),
                        (MobileSection.weather, '气象'),
                        (MobileSection.settings, '设置'),
                      ])
                        Expanded(
                          child: Semantics(
                            selected: _section == section,
                            child: TextButton(
                              key: ValueKey('mobile-section-${section.name}'),
                              onPressed: () => _select(section),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                foregroundColor: _section == section
                                    ? const Color(0xFFE6F4FF)
                                    : Colors.white70,
                                backgroundColor: _section == section
                                    ? const Color(0x2082B1FF)
                                    : Colors.transparent,
                                side: _section == section
                                    ? const BorderSide(color: Color(0x5CB5DCFF))
                                    : BorderSide.none,
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  shadows: _section == section
                                      ? const [
                                          Shadow(
                                            color: Color(0x70A2D2FF),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Only positions existing modules. Empty space remains available to the map.
class MobileSeismicOverlays extends StatelessWidget {
  const MobileSeismicOverlays({
    super.key,
    required this.stations,
    required this.sidebar,
    required this.events,
  });
  final Widget stations;
  final Widget sidebar;
  final Widget events;

  Widget _buildSidebar(double width, double height) {
    const scale = .85;
    final contentWidth = math.min(width, 145 / scale);
    return SizedBox(
      key: const ValueKey('mobile-sidebar-frame'),
      width: contentWidth * scale,
      height: height * scale,
      child: FittedBox(
        alignment: Alignment.topRight,
        child: SizedBox(width: contentWidth, height: height, child: sidebar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 74,
        12,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600 && constraints.maxHeight < 420) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 76, child: stations),
                const SizedBox(width: 12),
                Expanded(child: events),
                const SizedBox(width: 12),
                Align(
                  alignment: Alignment.topRight,
                  widthFactor: 1,
                  child: _buildSidebar(200, constraints.maxHeight),
                ),
              ],
            );
          }
          final topHeight = math.min(
            constraints.maxHeight * .58,
            (constraints.maxHeight * .43).clamp(264.0, 324.0),
          );
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 76, child: stations),
                    const Spacer(),
                    _buildSidebar(
                      math.min(218, math.max(0, constraints.maxWidth - 108)),
                      topHeight,
                    ),
                  ],
                ),
              ),
              Positioned.fill(child: events),
            ],
          );
        },
      ),
    );
  }
}

class MobileEventListLayout extends StatefulWidget {
  const MobileEventListLayout({
    super.key,
    required this.alert,
    required this.divider,
    required this.list,
    required this.actions,
  });
  final Widget alert;
  final Widget divider;
  final Widget list;
  final Widget actions;

  @override
  State<MobileEventListLayout> createState() => _MobileEventListLayoutState();
}

class _MobileEventListLayoutState extends State<MobileEventListLayout> {
  double _listHeight = 0;
  final _metrics = _EventListMetrics();

  void _resize(double value) => setState(() {
    _listHeight = value.clamp(0.0, _metrics.maxListHeight);
  });

  @override
  Widget build(BuildContext context) {
    final expanded = _listHeight > 0;
    void toggle() =>
        _resize(expanded ? 0 : math.min(200, _metrics.maxListHeight));
    return CustomMultiChildLayout(
      delegate: _EventListLayoutDelegate(
        listHeight: _listHeight,
        metrics: _metrics,
      ),
      children: [
        LayoutId(id: _EventListSlot.actions, child: widget.actions),
        LayoutId(
          id: _EventListSlot.alert,
          child: SingleChildScrollView(
            key: const PageStorageKey('mobile-unified-events'),
            child: widget.alert,
          ),
        ),
        LayoutId(
          id: _EventListSlot.grip,
          child: Semantics(
            button: true,
            label: expanded ? '收起地震列表' : '展开地震列表',
            onTap: toggle,
            child: GestureDetector(
              key: const ValueKey('mobile-list-grip'),
              behavior: HitTestBehavior.opaque,
              onTap: toggle,
              onVerticalDragUpdate: (details) => _resize(
                _listHeight.clamp(0.0, _metrics.maxListHeight) -
                    details.delta.dy,
              ),
              child: Center(child: widget.divider),
            ),
          ),
        ),
        LayoutId(
          id: _EventListSlot.list,
          child: SizedBox(
            key: const ValueKey('mobile-list-viewport'),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final visible = constraints.maxHeight > 0;
                final layoutHeight = math.max(180.0, constraints.maxHeight);
                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: layoutHeight,
                    maxHeight: layoutHeight,
                    child: ExcludeFocus(
                      excluding: !visible,
                      child: ExcludeSemantics(
                        excluding: !visible,
                        child: IgnorePointer(
                          ignoring: !visible,
                          child: widget.list,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

enum _EventListSlot { actions, alert, grip, list }

class _EventListMetrics {
  double maxListHeight = 0;
}

class _EventListLayoutDelegate extends MultiChildLayoutDelegate {
  _EventListLayoutDelegate({required this.listHeight, required this.metrics});
  final double listHeight;
  final _EventListMetrics metrics;

  @override
  void performLayout(Size size) {
    final actions = layoutChild(
      _EventListSlot.actions,
      BoxConstraints.loose(size),
    );
    final gap = math.min(8.0, math.max(0.0, size.height - actions.height));
    final gripHeight = math.min(
      28.0,
      math.max(0.0, size.height - actions.height - gap),
    );
    final available = math.max(
      0.0,
      size.height - actions.height - gap - gripHeight,
    );
    // Measure the original UI first. Only the list consumes the remaining space.
    final alert = layoutChild(
      _EventListSlot.alert,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: available,
      ),
    );
    metrics.maxListHeight = math.max(0.0, available - alert.height);
    final height = listHeight.clamp(0.0, metrics.maxListHeight);
    layoutChild(
      _EventListSlot.grip,
      BoxConstraints.tight(Size(size.width, gripHeight)),
    );
    layoutChild(
      _EventListSlot.list,
      BoxConstraints.tight(Size(size.width, height)),
    );
    final alertTop = size.height - height - gripHeight - alert.height;
    positionChild(
      _EventListSlot.actions,
      Offset(size.width - actions.width, alertTop - gap - actions.height),
    );
    positionChild(_EventListSlot.alert, Offset(0, alertTop));
    positionChild(_EventListSlot.grip, Offset(0, alertTop + alert.height));
    positionChild(_EventListSlot.list, Offset(0, size.height - height));
  }

  @override
  bool shouldRelayout(covariant _EventListLayoutDelegate oldDelegate) => true;
}
