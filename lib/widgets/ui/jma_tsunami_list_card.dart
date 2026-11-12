import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/jma_tsunami_list.dart';
import '../../models/tsunami_message.dart';
import '../../services/native_jma_tsunami.dart';

/// Two aligned region blocks per line. Native code supplies page boundaries;
/// this widget owns text measurement, UI page state and the display timer.
class JmaTsunamiListCard extends StatefulWidget {
  const JmaTsunamiListCard({
    super.key,
    required this.group,
    required this.scale,
  });
  final JmaTsunamiListGroup group;
  final double scale;
  @override
  State<JmaTsunamiListCard> createState() => _JmaTsunamiListCardState();
}

class _JmaTsunamiListCardState extends State<JmaTsunamiListCard>
    with WidgetsBindingObserver {
  TsunamiMessage get _clock => TsunamiMessage(
    source: TsunamiSource.values.byName(group.source),
    timeZone: group.timeZone,
  );
  JmaTsunamiListGroup get group => widget.group;
  bool get _messageOnly =>
      !group.pinned ||
      (group.source != 'jma' &&
          group.rows.length == 1 &&
          group.timeLabel.isEmpty &&
          group.heightLabel.isEmpty);
  int get _columnsCount => _messageOnly || group.rows.length == 1 ? 1 : 2;
  String get _messageText => !group.pinned
      ? (group.informationText.isEmpty ? group.label : group.informationText)
      : group.rows.single.name;
  String get _eventText => !group.pinned ? group.eventText : '';
  double s(double v) => v * widget.scale;
  Object? _layoutKey;
  Future<_Pages>? _layoutFuture;
  _Pages? _pages;
  Timer? _timer;
  int _page = 0;
  bool _hovering = false, _dialogOpen = false, _inactive = false;
  Color get color => switch (group.className) {
    'purple' => const Color(0xFFB56AFF),
    'red' => const Color(0xFFFF4F4F),
    'orange' => const Color(0xFFFF9A35),
    'green' => const Color(0xFF43B581),
    'yellow' => const Color(0xFFF4D44D),
    'blue' => const Color(0xFF4AA3FF),
    _ => const Color(0xFF9EA9B7),
  };
  TextStyle style(double size, {Color? color, bool bold = false}) => TextStyle(
    fontSize: s(size),
    color: color ?? Colors.white,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    height: 1.2,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inactive = state != AppLifecycleState.resumed;
    _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    final pages = _pages;
    if (!mounted ||
        pages == null ||
        pages.pages.length < 2 ||
        _hovering ||
        _dialogOpen ||
        _inactive ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _timer = Timer.periodic(Duration(milliseconds: pages.intervalMs), (_) {
      if (mounted) setState(() => _page = (_page + 1) % pages.pages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String arrival(JmaTsunamiListRow row) =>
      group.timeLabel.isEmpty &&
          row.arrivalTime.isEmpty &&
          row.arrivalLabel.isEmpty
      ? ''
      : row.arrivalLabel.isNotEmpty
      ? row.arrivalLabel
      : _clock.formatLocalHourMinute(row.arrivalTime);
  String height(JmaTsunamiListRow row) => row.heightTime.isEmpty
      ? row.height
      : _clock.formatLocalHourMinute(row.heightTime);
  String fieldText(JmaTsunamiListField field, {bool fullTime = false}) =>
      field.time.isEmpty && field.text.isEmpty
      ? ''
      : [
          if (field.label.isNotEmpty) field.label,
          if (field.time.isNotEmpty)
            fullTime
                ? _clock.formatLocalTime(field.time)
                : _clock.formatLocalHourMinute(field.time),
          if (field.text.isNotEmpty) field.text,
        ].join(' ');
  String secondary(JmaTsunamiListRow row) => row.secondary
      .map((v) => fieldText(v))
      .where((v) => v.isNotEmpty)
      .join(' · ');
  String detail(JmaTsunamiListRow row) => [
    row.name.isEmpty ? group.label : row.name,
    if (height(row).isNotEmpty)
      '${group.grade == 'observation'
          ? '截至目前最大波高'
          : group.grade == 'stationForecast'
          ? '满潮'
          : group.source == 'jma'
          ? '预计波高'
          : group.heightLabel}：${height(row)}',
    if (row.arrivalTime.isNotEmpty)
      '${group.grade == 'observation' ? '最大波观测' : '预计到达'}：${_clock.formatLocalTime(row.arrivalTime)}',
    if (row.condition.isNotEmpty) row.condition,
    ...row.secondary
        .map((v) => fieldText(v, fullTime: true))
        .where((v) => v.isNotEmpty),
    ...row.details
        .map((v) => fieldText(v, fullTime: true))
        .where((v) => v.isNotEmpty),
  ].join('\n');
  Future<void> showText(String text) async {
    _dialogOpen = true;
    _syncTimer();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(group.caption),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } finally {
      _dialogOpen = false;
      if (mounted) _syncTimer();
    }
  }

  double _measure(
    String value,
    TextStyle style,
    double width, {
    int? maxLines,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: math.max(1, width));
    final h = p.height;
    p.dispose();
    return h;
  }

  void _requestLayout(Object key, double width, String metadata) {
    if (_layoutKey == key) return;
    _layoutKey = key;
    _page = 0;
    _pages = null;
    _timer?.cancel();
    _timer = null;
    final blockWidth = (width - s(10) * (_columnsCount - 1)) / _columnsCount;
    // Same fixed fractions are used in the actual region columns below.
    final compact = group.source != 'jma';
    final nameWidth = math.max(1.0, (blockWidth - s(6)) * (compact ? .4 : .5));
    final arrivalWidth = math.max(
      1.0,
      (blockWidth - s(6)) * (compact ? .25 : .3),
    );
    final heightWidth = math.max(
      1.0,
      (blockWidth - s(6)) * (compact ? .35 : .2),
    );
    final heights = _messageOnly
        ? [
            _measure(_messageText, style(11, bold: true), width, maxLines: 2) +
                (_eventText.isEmpty
                    ? 0
                    : s(3) +
                          _measure(
                            _eventText,
                            style(10, color: Colors.white70),
                            width,
                            maxLines: 1,
                          )),
          ]
        : [
            for (final row in group.rows)
              math.max(
                    _measure(
                      row.name.isEmpty ? group.label : row.name,
                      style(11, bold: true),
                      nameWidth,
                      maxLines: compact ? 2 : null,
                    ),
                    math.max(
                      _measure(
                        arrival(row),
                        style(10, color: Colors.white70),
                        compact ? double.infinity : arrivalWidth,
                      ),
                      _measure(
                        height(row),
                        style(11, color: color, bold: true),
                        compact ? double.infinity : heightWidth,
                      ),
                    ),
                  ) +
                  (secondary(row).isEmpty
                      ? 0
                      : s(2) +
                            _measure(
                              secondary(row),
                              style(9, color: Colors.white60),
                              blockWidth,
                            )),
          ];
    final footerHeight = _measure(
      metadata,
      style(8.5, color: Colors.white38),
      math.max(1, width - (group.rows.length > _columnsCount ? s(38) : 0)),
    );
    final headerStyle = style(8.5, color: Colors.white38);
    final headerHeight = _messageOnly
        ? 0.0
        : math.max(
            s(11),
            math.max(
              _measure(group.nameLabel, headerStyle, nameWidth),
              math.max(
                _measure(group.timeLabel, headerStyle, arrivalWidth),
                _measure(group.heightLabel, headerStyle, heightWidth),
              ),
            ),
          );
    final overhead =
        footerHeight + headerHeight + s(_messageOnly ? 17.4 : 20.4);
    // A single message has no pagination work. Draw it in the standard 1*
    // cell immediately, including while its official bulletin is enriched.
    if (_messageOnly) {
      _pages = _Pages.single(heights.single);
      _layoutFuture = Future.value(_pages);
      return;
    }
    _layoutFuture =
        NativeJmaTsunami.prepareAsync({
          'op': 'paginate',
          'itemHeights': heights,
          'unitHeight': s(76),
          'overhead': overhead,
          'rowGap': s(5),
          'columns': _columnsCount,
          'maxUnits':
              !group.pinned || (group.source != 'jma' && group.rows.length == 1)
              ? 1
              : 2,
        }).then((view) {
          final pages = _Pages.fromMap(view);
          if (mounted && _layoutKey == key) {
            _pages = pages;
            _syncTimer();
          }
          return pages;
        });
  }

  Widget _columns(
    String name,
    String time,
    String height, {
    bool heading = false,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: group.source == 'jma' ? 5 : 8,
        child: Text(
          name,
          maxLines: group.source == 'jma' ? null : 2,
          overflow: group.source == 'jma'
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
          style: style(
            heading ? 8.5 : 11,
            color: heading ? Colors.white38 : null,
            bold: !heading,
          ),
        ),
      ),
      SizedBox(width: s(3)),
      Expanded(
        flex: group.source == 'jma' ? 3 : 5,
        child: _number(
          Text(
            time,
            textAlign: TextAlign.center,
            style: style(
              heading ? 8.5 : 10,
              color: heading ? Colors.white38 : Colors.white70,
            ),
          ),
        ),
      ),
      SizedBox(width: s(3)),
      Expanded(
        flex: group.source == 'jma' ? 2 : 7,
        child: _number(
          Text(
            height,
            textAlign: TextAlign.right,
            style: style(
              heading ? 8.5 : 11,
              color: heading ? Colors.white38 : color,
              bold: !heading,
            ),
          ),
        ),
      ),
    ],
  );
  Widget _number(Text text) => group.source == 'jma'
      ? text
      : FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topRight,
          child: Text(
            text.data ?? '',
            style: text.style,
            maxLines: 1,
            softWrap: false,
          ),
        );
  Widget _region(int index) {
    if (_messageOnly) {
      return GestureDetector(
        onTap: () => showText(
          !group.pinned ? group.headline : detail(group.rows[index]),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _messageText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style(11, color: !group.pinned ? color : null, bold: true),
            ),
            if (_eventText.isNotEmpty) ...[
              SizedBox(height: s(3)),
              Text(
                _eventText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style(10, color: Colors.white70),
              ),
            ],
          ],
        ),
      );
    }
    final row = group.rows[index];
    return GestureDetector(
      onTap: () => showText(detail(row)),
      child: Container(
        key: ValueKey('jma_tsunami_region_${group.grade}_${row.name}'),
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _columns(
              row.name.isEmpty ? group.label : row.name,
              arrival(row),
              height(row),
            ),
            if (secondary(row).isNotEmpty) ...[
              SizedBox(height: s(2)),
              Text(secondary(row), style: style(9, color: Colors.white60)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metadata =
        '${group.reportNumber == null ? '' : '第${group.reportNumber}报 · '}${_clock.formatLocalTime(group.reportTime)}';
    return MouseRegion(
      onEnter: (_) {
        _hovering = true;
        _syncTimer();
      },
      onExit: (_) {
        _hovering = false;
        _syncTimer();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: s(4), vertical: s(2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(left: s(8), top: s(3), bottom: s(4)),
              child: Row(
                children: [
                  Container(
                    width: s(2),
                    height: s(11),
                    color: color.withValues(alpha: .6),
                  ),
                  SizedBox(width: s(6)),
                  Expanded(
                    child: Text(
                      '${group.caption} · ${group.regionCount}${group.countLabel}',
                      style: style(10, color: Colors.white60),
                    ),
                  ),
                  if (group.headline.isNotEmpty)
                    GestureDetector(
                      onTap: () => showText(group.headline),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: s(8)),
                        child: Text(
                          '公告',
                          style: style(10, color: Colors.white54),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = math.max(1.0, constraints.maxWidth - s(22.4));
                final key = (
                  group,
                  width,
                  widget.scale,
                  DefaultTextStyle.of(context).style,
                  MediaQuery.textScalerOf(context),
                  metadata,
                );
                _requestLayout(key, width, metadata);
                return FutureBuilder<_Pages>(
                  future: _layoutFuture,
                  builder: (context, snapshot) {
                    // Never retain old pages while a revised bulletin is being prepared.
                    final pages = _layoutKey == key ? _pages : null;
                    if (snapshot.hasError) {
                      return Text(
                        '海啸列表排版失败',
                        style: style(10, color: Colors.white54),
                      );
                    }
                    if (pages == null) return SizedBox(height: s(76));
                    if (pages.pages.isEmpty) return const SizedBox.shrink();
                    final page = pages.pages[_page];
                    final header = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _columns(
                            group.nameLabel,
                            group.timeLabel,
                            group.heightLabel,
                            heading: true,
                          ),
                        ),
                        if (_columnsCount == 2) ...[
                          SizedBox(width: s(10)),
                          Expanded(
                            child: _columns(
                              group.nameLabel,
                              group.timeLabel,
                              group.heightLabel,
                              heading: true,
                            ),
                          ),
                        ],
                      ],
                    );
                    return Container(
                      key: ValueKey(
                        'jma_tsunami_cell_${group.grade}_${pages.units}',
                      ),
                      height: s(76) * pages.units,
                      padding: EdgeInsets.symmetric(
                        horizontal: s(10),
                        vertical: s(6),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x99151515),
                        borderRadius: BorderRadius.circular(s(6)),
                        border: Border.all(
                          color: color.withValues(alpha: .3),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: width,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (!_messageOnly) ...[
                                        header,
                                        SizedBox(height: s(3)),
                                      ],
                                      for (
                                        var i = 0;
                                        i < page.lines.length;
                                        i++
                                      ) ...[
                                        if (i > 0) SizedBox(height: s(5)),
                                        SizedBox(
                                          height: page.lines[i].height,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _region(
                                                  page.lines[i].indices[0],
                                                ),
                                              ),
                                              if (_columnsCount == 2) ...[
                                                SizedBox(width: s(10)),
                                                if (page
                                                        .lines[i]
                                                        .indices
                                                        .length >
                                                    1)
                                                  Expanded(
                                                    child: _region(
                                                      page.lines[i].indices[1],
                                                    ),
                                                  )
                                                else
                                                  const Spacer(),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: s(3)),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  metadata,
                                  style: style(8.5, color: Colors.white38),
                                ),
                              ),
                              if (pages.pages.length > 1) ...[
                                SizedBox(width: s(6)),
                                SizedBox(
                                  width: s(32),
                                  child: Text(
                                    pages.pages.length > 1
                                        ? '${_page + 1}/${pages.pages.length}'
                                        : '',
                                    key: ValueKey(
                                      'jma_tsunami_page_${group.grade}',
                                    ),
                                    textAlign: TextAlign.right,
                                    style: style(9, color: Colors.white54),
                                  ),
                                ),
                              ] else
                                Text(
                                  '',
                                  key: ValueKey(
                                    'jma_tsunami_page_${group.grade}',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 0,
                                    height: 0,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Pages {
  final int units, intervalMs;
  final List<_Page> pages;
  _Pages.single(double height)
    : units = 1,
      intervalMs = 0,
      pages = [_Page.single(height)];
  _Pages.fromMap(Map map)
    : units = map['units'] as int,
      intervalMs = map['intervalMs'] as int,
      pages = [for (final v in map['pages'] as List) _Page.fromMap(v as Map)];
}

class _Page {
  final List<_Line> lines;
  _Page.single(double height) : lines = [_Line.single(height)];
  _Page.fromMap(Map map)
    : lines = [for (final v in map['lines'] as List) _Line.fromMap(v as Map)];
}

class _Line {
  final List<int> indices;
  final double height;
  _Line.single(this.height) : indices = const [0];
  _Line.fromMap(Map map)
    : indices = (map['indices'] as List).cast<int>(),
      height = (map['height'] as num).toDouble();
}
