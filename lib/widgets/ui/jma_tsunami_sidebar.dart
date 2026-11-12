import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/jma_tsunami_list.dart';
import '../../models/tsunami_message.dart';
import '../../services/native_jma_tsunami.dart';
import 'ui_scale.dart';

/// One shared viewport page for JMA regions and their tide stations.
/// Rust owns association/order/page boundaries; Dart measures and draws text.
class JmaTsunamiSidebar extends StatefulWidget {
  const JmaTsunamiSidebar({
    super.key,
    required this.groups,
    required this.scale,
    required this.maxHeight,
    this.sourceMessage,
  });

  /// Reuse the existing measured text layout; NMEFC data preparation stays native.
  const JmaTsunamiSidebar.nmefc({
    super.key,
    required TsunamiMessage message,
    required this.scale,
    required this.maxHeight,
  }) : groups = const [],
       sourceMessage = message;
  const JmaTsunamiSidebar.international({
    super.key,
    required TsunamiMessage message,
    required this.scale,
    required this.maxHeight,
  }) : groups = const [],
       sourceMessage = message;
  final List<JmaTsunamiListGroup> groups;
  final TsunamiMessage? sourceMessage;
  final double scale, maxHeight;
  @override
  State<JmaTsunamiSidebar> createState() => _JmaTsunamiSidebarState();
}

class _JmaTsunamiSidebarState extends State<JmaTsunamiSidebar>
    with WidgetsBindingObserver {
  static const _jmaClock = TsunamiMessage(source: TsunamiSource.jma);
  TsunamiMessage get _clock => widget.sourceMessage ?? _jmaClock;
  late Future<_View> _viewFuture;
  Future<_Layout>? _layoutFuture;
  _Layout? _layout;
  Object? _layoutKey;
  Timer? _timer;
  int _page = 0;
  bool _hovering = false, _dialog = false, _inactive = false;
  PageStorageBucket? _pageBucket;
  String get _storageId =>
      'tsunami_sidebar_${widget.sourceMessage?.source.name ?? 'jma'}';
  int get _reportSignature => Object.hash(widget.sourceMessage, widget.groups);
  double s(double value) => value * widget.scale;
  TextStyle style(
    double size, {
    Color color = Colors.white,
    bool bold = false,
  }) => TextStyle(
    fontSize: s(size),
    height: 1.2,
    color: color,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _load() {
    _timer?.cancel();
    _layout = null;
    _layoutKey = null;
    _page = 0;
    _viewFuture = NativeJmaTsunami.prepareAsync(
      widget.sourceMessage != null
          ? {
              'op': widget.sourceMessage!.source == TsunamiSource.nmefc
                  ? 'nmefcSidebar'
                  : 'internationalSidebar',
              'message': widget.sourceMessage!.toMap(),
            }
          : {
              'op': 'sidebar',
              'groups': [for (final group in widget.groups) group.toMap()],
            },
    ).then(_View.fromMap);
  }

  @override
  void didUpdateWidget(covariant JmaTsunamiSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.groups, oldWidget.groups) ||
        !identical(widget.sourceMessage, oldWidget.sourceMessage)) {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageBucket = PageStorage.maybeOf(context);
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
    final layout = _layout;
    if (!mounted ||
        layout == null ||
        layout.pages.length < 2 ||
        _hovering ||
        _dialog ||
        _inactive ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _timer = Timer.periodic(Duration(milliseconds: layout.intervalMs), (_) {
      if (mounted) setState(() => _page = (_page + 1) % layout.pages.length);
    });
  }

  @override
  void dispose() {
    final layout = _layout;
    if (layout != null && layout.pages.isNotEmpty) {
      _pageBucket?.writeState(context, (
        _reportSignature,
        (_page + 1) % layout.pages.length,
      ), identifier: _storageId);
    }
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Color color(String name) => switch (name) {
    'purple' => const Color(0xFFB56AFF),
    'red' => const Color(0xFFFF4F4F),
    'yellow' => const Color(0xFFF4D44D),
    'orange' => const Color(0xFFFF9A35),
    'green' => const Color(0xFF43B581),
    'gray' => const Color(0xFF9EA9B7),
    _ => const Color(0xFF4AA3FF),
  };
  String arrival(JmaTsunamiListRow row) => row.arrivalLabel.isEmpty
      ? _clock.formatLocalHourMinute(row.arrivalTime)
      : row.arrivalLabel;
  String field(JmaTsunamiListField value, {bool full = false}) =>
      value.time.isEmpty && value.text.isEmpty
      ? ''
      : [
          if (value.label.isNotEmpty) value.label,
          if (value.time.isNotEmpty)
            full
                ? _clock.formatLocalTime(value.time)
                : _clock.formatLocalHourMinute(value.time),
          if (value.text.isNotEmpty) value.text,
        ].join(' ');
  // Match the old sidebar's aligned text columns, without per-station cards.
  List<_TextLine> itemColumns(_Cell cell) => [
    _TextLine(cell.region, style(11, color: color(cell.className), bold: true)),
    _TextLine(
      cell.observation?.height ?? (widget.sourceMessage == null ? '未知' : '—'),
      style(11, color: color('blue'), bold: true),
    ),
    _TextLine(
      (widget.sourceMessage != null ? cell.forecast?.height : null) ??
          cell.regionForecast?.height ??
          (widget.sourceMessage == null ? '未知' : '—'),
      style(11, color: color(cell.className), bold: true),
    ),
  ];
  bool bulletinOnly(_Cell cell) =>
      widget.sourceMessage != null &&
      cell.forecast == null &&
      cell.observation == null &&
      cell.regionForecast == null;
  List<_TextLine> columnHeadings(_View view) => [
    for (final text in view.headings)
      _TextLine(text, style(8.5, color: Colors.white38)),
  ];
  List<double> columnWidths(double width) => [
    (width - s(6)) * (widget.sourceMessage == null ? .6 : .45),
    (width - s(6)) * (widget.sourceMessage == null ? .2 : .275),
    (width - s(6)) * (widget.sourceMessage == null ? .2 : .275),
  ];
  double rowHeight(List<_TextLine> values, double width) {
    final widths = columnWidths(width);
    return [
      for (var i = 0; i < 3; i++)
        measure(
          values[i],
          widget.sourceMessage != null && i > 0 ? double.infinity : widths[i],
          maxLines: widget.sourceMessage != null && i == 0 ? 2 : null,
        ),
    ].reduce(math.max);
  }

  String detail(_Cell cell) => [
    cell.region,
    if (cell.gradeLabel.isNotEmpty) cell.gradeLabel,
    if (cell.regionForecast case final row?)
      '区域预计${widget.sourceMessage == null ? '波高' : '波幅'} ${row.height} · ${arrival(row)}',
    if (cell.stationName.isNotEmpty) cell.stationName,
    if (cell.observation case final row?)
      '${widget.sourceMessage == null ? '截至目前最大波高' : cell.observedLabel} ${row.height} · ${arrival(row)}',
    if (cell.forecast case final row?) ...[
      '${cell.forecastLabel} ${widget.sourceMessage == null ? '' : row.height} · ${arrival(row)}',
      if (row.heightTime.isNotEmpty)
        '满潮 ${_clock.formatLocalHourMinute(row.heightTime)}',
    ],
  ].join('\n');

  String metadata(_View view) => view.bulletins
      .map(
        (b) =>
            '${b.label}${b.number == null ? '' : ' 第${b.number}报'} · ${_clock.formatLocalTime(b.time)}',
      )
      .join('\n');
  double measure(_TextLine line, double width, {int? maxLines}) {
    final painter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: DefaultTextStyle.of(context).style.merge(line.style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: math.max(1, width));
    // Match the paragraph's enclosing pixel bounds before native page fitting.
    final height = painter.height.ceilToDouble();
    painter.dispose();
    return height;
  }

  void requestLayout(
    Object key,
    _View view,
    double width,
    int columns,
    String footer,
  ) {
    if (_layoutKey == key) return;
    _layoutKey = key;
    _layout = null;
    _page = 0;
    _timer?.cancel();
    final cellWidth = (width - s(8) * (columns - 1)) / columns;
    final itemHeights = [
      for (final cell in view.cells)
        if (bulletinOnly(cell))
          measure(
            _TextLine(
              cell.region,
              style(11, color: color(cell.className), bold: true),
            ),
            cellWidth,
            maxLines: 2,
          )
        else
          rowHeight(itemColumns(cell), cellWidth),
    ];
    final heading = measure(
      _TextLine(
        widget.sourceMessage == null
            ? '${view.caption} · ${view.regionCount}地区 · ${view.stationCount}站'
            : '${view.caption}\n${view.regionCount}地区 · ${view.stationCount}站',
        widget.sourceMessage == null
            ? style(10, color: Colors.white60)
            : style(12, bold: true),
      ),
      math.max(1, width - (view.hasHeadlines ? s(36) : 0)),
    );
    final footerHeight = math.max(
      measure(
        _TextLine(footer, style(8.5, color: Colors.white38)),
        math.max(1, width - s(42)),
      ),
      measure(
        _TextLine(
          '${view.cells.length}/${view.cells.length}',
          style(9, color: Colors.white38),
        ),
        s(32),
      ),
    );
    final overhead =
        heading +
        rowHeight(columnHeadings(view), cellWidth) +
        footerHeight +
        s(25);
    _layoutFuture =
        NativeJmaTsunami.prepareAsync({
          'op': 'sidebarPaginate',
          'itemHeights': itemHeights,
          'columns': columns,
          'maxHeight': widget.maxHeight,
          'overhead': overhead,
          'rowGap': s(6),
        }).then((result) {
          final layout = _Layout.fromMap(result);
          if (mounted && _layoutKey == key) {
            _layout = layout;
            final saved = _pageBucket?.readState(
              context,
              identifier: _storageId,
            );
            if (saved is (int, int) &&
                saved.$1 == _reportSignature &&
                layout.pages.isNotEmpty) {
              _page = saved.$2 % layout.pages.length;
            }
            _syncTimer();
          }
          return layout;
        });
  }

  Future<void> showDetails(_Cell cell) async {
    _dialog = true;
    _syncTimer();
    try {
      final details = [
        for (final row in [
          cell.regionForecast,
          cell.forecast,
          cell.observation,
        ])
          if (row != null) ...[
            if (row.arrivalTime.isNotEmpty)
              _clock.formatLocalTime(row.arrivalTime),
            if (row.heightTime.isNotEmpty)
              '满潮 ${_clock.formatLocalTime(row.heightTime)}',
            for (final value in row.secondary)
              if (field(value, full: true).isNotEmpty) field(value, full: true),
            for (final value in row.details)
              if (field(value, full: true).isNotEmpty) field(value, full: true),
          ],
      ];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            cell.stationName.isEmpty || cell.stationName == cell.region
                ? cell.region
                : '${cell.region} · ${cell.stationName}',
          ),
          content: SingleChildScrollView(
            child: SelectableText([detail(cell), ...details].join('\n')),
          ),
          actions: [
            if (widget.sourceMessage?.htmlUrl.isNotEmpty == true)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(widget.sourceMessage!.htmlUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('官方原文'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } finally {
      _dialog = false;
      if (mounted) _syncTimer();
    }
  }

  Future<void> showBulletins(_View view) async {
    _dialog = true;
    _syncTimer();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(view.caption),
          content: SingleChildScrollView(
            child: SelectableText(
              [
                for (final bulletin in view.bulletins)
                  '${bulletin.label}${bulletin.number == null ? '' : ' 第${bulletin.number}报'} · ${_clock.formatLocalTime(bulletin.time)}\n${bulletin.headline}\n\n${bulletin.rawText}',
              ].join('\n\n'),
            ),
          ),
          actions: [
            if (widget.sourceMessage?.htmlUrl.isNotEmpty == true)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(widget.sourceMessage!.htmlUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('官方原文'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } finally {
      _dialog = false;
      if (mounted) _syncTimer();
    }
  }

  Widget textColumns(List<_TextLine> values) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) SizedBox(width: s(3)),
        Expanded(
          flex: widget.sourceMessage == null
              ? (i == 0 ? 6 : 2)
              : (i == 0 ? 18 : 11),
          child: widget.sourceMessage != null && i > 0
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topRight,
                  child: Text(
                    values[i].text,
                    style: values[i].style,
                    maxLines: 1,
                    softWrap: false,
                  ),
                )
              : Text(
                  values[i].text,
                  style: values[i].style,
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  maxLines: widget.sourceMessage != null ? 2 : null,
                  overflow: widget.sourceMessage != null
                      ? TextOverflow.ellipsis
                      : TextOverflow.clip,
                ),
        ),
      ],
    ],
  );

  Widget cell(_Cell cell) => GestureDetector(
    onTap: () => showDetails(cell),
    child: Container(
      key: ValueKey('jma_tsunami_cell_${cell.grade}_sidebar_${cell.key}'),
      color: Colors.transparent,
      child: bulletinOnly(cell)
          ? Text(
              cell.region,
              style: style(11, color: color(cell.className), bold: true),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : textColumns(itemColumns(cell)),
    ),
  );
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _hovering = true;
      _syncTimer();
    },
    onExit: (_) {
      _hovering = false;
      _syncTimer();
    },
    child: FutureBuilder<_View>(
      future: _viewFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('海啸列表排版失败');
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final view = snapshot.data!;
        if (view.cells.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(1.0, constraints.maxWidth - s(8));
            final columns =
                UiScale.isPhone(context) ||
                    (widget.sourceMessage != null && view.cells.length == 1)
                ? 1
                : 2;
            final footer = metadata(view);
            final key = (
              view,
              width,
              columns,
              widget.scale,
              widget.maxHeight,
              MediaQuery.textScalerOf(context),
              DefaultTextStyle.of(context).style,
              footer,
            );
            requestLayout(key, view, width, columns, footer);
            return FutureBuilder<_Layout>(
              future: _layoutFuture,
              builder: (context, layoutSnapshot) {
                if (layoutSnapshot.hasError) return const Text('海啸列表排版失败');
                final layout = _layoutKey == key ? _layout : null;
                if (layout == null || layout.pages.isEmpty) {
                  return const SizedBox.shrink();
                }
                return SingleChildScrollView(
                  primary: false,
                  child: SizedBox(
                    key: const ValueKey('jma_tsunami_sidebar_viewport'),
                    height: layout.height,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(s(4), s(4), s(4), s(4)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.sourceMessage == null
                                      ? '${view.caption} · ${view.regionCount}地区 · ${view.stationCount}站'
                                      : '${view.caption}\n${view.regionCount}地区 · ${view.stationCount}站',
                                  style: widget.sourceMessage == null
                                      ? style(10, color: Colors.white60)
                                      : style(12, bold: true),
                                ),
                              ),
                              if (view.hasHeadlines)
                                SizedBox(
                                  width: s(36),
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'jma_tsunami_sidebar_bulletin',
                                    ),
                                    onTap: () => showBulletins(view),
                                    child: Text(
                                      widget.sourceMessage == null
                                          ? '公告'
                                          : '报文',
                                      textAlign: TextAlign.right,
                                      style: style(10, color: Colors.white54),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: s(6)),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: textColumns(columnHeadings(view)),
                              ),
                              if (layout.columns == 2) ...[
                                SizedBox(width: s(8)),
                                Expanded(
                                  child: textColumns(columnHeadings(view)),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: s(3)),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final line in layout.pages[_page])
                                    Padding(
                                      padding: EdgeInsets.only(bottom: s(6)),
                                      child: SizedBox(
                                        height: line.height,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          key: ValueKey(
                                            'jma_tsunami_sidebar_line_${line.indices.first}',
                                          ),
                                          children: [
                                            Expanded(
                                              child: cell(
                                                view.cells[line.indices.first],
                                              ),
                                            ),
                                            if (layout.columns == 2) ...[
                                              SizedBox(width: s(8)),
                                              if (line.indices.length == 2)
                                                Expanded(
                                                  child: cell(
                                                    view.cells[line
                                                        .indices
                                                        .last],
                                                  ),
                                                )
                                              else
                                                const Spacer(),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: s(2)),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  footer,
                                  style: style(8.5, color: Colors.white38),
                                ),
                              ),
                              SizedBox(width: s(10)),
                              SizedBox(
                                width: s(32),
                                child: Text(
                                  '${_page + 1}/${layout.pages.length}',
                                  key: const ValueKey(
                                    'jma_tsunami_sidebar_page',
                                  ),
                                  textAlign: TextAlign.right,
                                  style: style(9, color: Colors.white38),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}

class _TextLine {
  const _TextLine(this.text, this.style);
  final String text;
  final TextStyle style;
}

class _Cell {
  final String observedLabel, forecastLabel;
  final String key, region, grade, gradeLabel, className, stationName;
  final JmaTsunamiListRow? regionForecast, forecast, observation;
  _Cell.fromMap(Map map)
    : observedLabel = map['observedLabel'] as String? ?? '截至目前最大波幅',
      forecastLabel = map['forecastLabel'] as String? ?? '预计到达',
      key = map['key'] as String,
      region = map['region'] as String,
      grade = map['grade'] as String,
      gradeLabel = map['gradeLabel'] as String,
      className = map['className'] as String,
      stationName = map['stationName'] as String,
      regionForecast = _row(map['regionForecast']),
      forecast = _row(map['forecast']),
      observation = _row(map['observation']);
  static JmaTsunamiListRow? _row(dynamic value) =>
      value is Map ? JmaTsunamiListRow.fromMap(value) : null;
}

class _Bulletin {
  final String label, time, headline, rawText;
  final int? number;
  _Bulletin.fromMap(Map map)
    : rawText = map['rawText'] as String? ?? '',
      label = map['label'] as String,
      time = map['reportTime'] as String,
      headline = map['headline'] as String? ?? '',
      number = map['reportNumber'] as int?;
}

class _View {
  final List<String> headings;
  final String caption;
  final int regionCount, stationCount;
  final List<_Cell> cells;
  final List<_Bulletin> bulletins;
  bool get hasHeadlines => bulletins.any((value) => value.headline.isNotEmpty);
  _View.fromMap(Map map)
    : headings =
          (map['columnHeadings'] as List?)?.cast<String>() ??
          const ['地区', '实测', '预计'],
      caption = map['caption'] as String,
      regionCount = map['regionCount'] as int,
      stationCount = map['stationCount'] as int,
      cells = [for (final v in map['cells'] as List) _Cell.fromMap(v as Map)],
      bulletins = [
        for (final v in map['bulletins'] as List) _Bulletin.fromMap(v as Map),
      ];
}

class _Layout {
  final int columns, intervalMs;
  final double height;
  final List<List<_Line>> pages;
  _Layout.fromMap(Map map)
    : columns = map['columns'] as int,
      intervalMs = map['intervalMs'] as int,
      height = (map['height'] as num).toDouble(),
      pages = [
        for (final page in map['pages'] as List)
          [
            for (final line in page['lines'] as List)
              _Line.fromMap(line as Map),
          ],
      ];
}

class _Line {
  final List<int> indices;
  final double height;
  _Line.fromMap(Map map)
    : indices = (map['indices'] as List).cast<int>(),
      height = (map['height'] as num).toDouble();
}
