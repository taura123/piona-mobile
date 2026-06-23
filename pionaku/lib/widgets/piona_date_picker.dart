import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const List<String> _kWeekdayShort = [
  'Su',
  'Mo',
  'Tu',
  'We',
  'Th',
  'Fr',
  'Sa',
];

const List<String> _kMonthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _kMonthLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// PIONA calendar UI: clean white panel, blue selection + black border,
/// Clear / Today footer, month-year drill-down from header.
Future<DateTime?> showPionaDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final i = _clampDate(initialDate, firstDate, lastDate);
  return showDialog<DateTime?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade400, width: 1),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: PionaCalendarViewport(
            selectedDate: i,
            firstDate: _dateOnly(firstDate),
            lastDate: _dateOnly(lastDate),
            showFooter: true,
            onClear: () => Navigator.of(ctx).pop(),
            onDayCommitted: (d) => Navigator.of(ctx).pop(d),
          ),
        ),
      );
    },
  );
}

DateTime _clampDate(DateTime d, DateTime first, DateTime last) {
  final x = _dateOnly(d);
  final f = _dateOnly(first);
  final l = _dateOnly(last);
  if (x.isBefore(f)) return f;
  if (x.isAfter(l)) return l;
  return x;
}

/// Calendar body: header (month/year + arrows), grid or month-year picker,
/// optional Clear | Today row.
class PionaCalendarViewport extends StatefulWidget {
  const PionaCalendarViewport({
    super.key,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDayCommitted,
    this.showFooter = false,
    this.onClear,
  });

  final DateTime selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;

  /// Called when user taps a valid day (dialog mode: pop after this).
  final ValueChanged<DateTime> onDayCommitted;

  final bool showFooter;
  final VoidCallback? onClear;

  @override
  State<PionaCalendarViewport> createState() => _PionaCalendarViewportState();
}

enum _CalMode { dayGrid, monthYear }

class _PionaCalendarViewportState extends State<PionaCalendarViewport> {
  late DateTime _displayedMonth;
  late DateTime _selected;
  _CalMode _mode = _CalMode.dayGrid;
  int? _expandedYear;

  @override
  void initState() {
    super.initState();
    _selected = _dateOnly(widget.selectedDate);
    _displayedMonth = DateTime(_selected.year, _selected.month);
  }

  @override
  void didUpdateWidget(PionaCalendarViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _selected = _dateOnly(widget.selectedDate);
      _displayedMonth = DateTime(_selected.year, _selected.month);
    }
  }

  void _goPrevMonth() {
    if (!_canGoPrev) return;
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
  }

  void _goNextMonth() {
    if (!_canGoNext) return;
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
  }

  bool get _canGoPrev {
    final dm = _displayedMonth.year * 12 + _displayedMonth.month;
    final fm = widget.firstDate.year * 12 + widget.firstDate.month;
    return dm > fm;
  }

  bool get _canGoNext {
    final dm = _displayedMonth.year * 12 + _displayedMonth.month;
    final lm = widget.lastDate.year * 12 + widget.lastDate.month;
    return dm < lm;
  }

  void _goToday() {
    final n = DateTime.now();
    final t = _dateOnly(n);
    final c = _clampDate(t, widget.firstDate, widget.lastDate);
    setState(() {
      _selected = c;
      _displayedMonth = DateTime(c.year, c.month);
      _mode = _CalMode.dayGrid;
    });
  }

  void _onDayTap(DateTime day) {
    final d = _dateOnly(day);
    if (d.isBefore(widget.firstDate) || d.isAfter(widget.lastDate)) return;
    setState(() => _selected = d);
    widget.onDayCommitted(d);
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppTheme.primaryBlue;
    final fg = const Color(0xFF1A1A1A);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gapBelowHeader = 8.0;
        final maxH = constraints.maxHeight;
        final tightHeight = constraints.hasBoundedHeight &&
            maxH.isFinite &&
            maxH < 400;

        Widget calendarBody() => _mode == _CalMode.dayGrid
            ? _buildDayGrid(fg, blue)
            : _buildMonthYearPicker(fg, blue);

        final footer = <Widget>[
          if (widget.showFooter) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (widget.onClear != null)
                    TextButton(
                      onPressed: widget.onClear,
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: blue,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _goToday,
                    child: Text(
                      'Today',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ];

        if (tightHeight) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(fg, blue),
                const SizedBox(height: gapBelowHeader),
                Expanded(child: calendarBody()),
                ...footer,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(fg, blue),
              const SizedBox(height: gapBelowHeader),
              SizedBox(
                height: _mode == _CalMode.dayGrid ? 240 : 260,
                child: calendarBody(),
              ),
              ...footer,
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Color fg, Color blue) {
    final label =
        '${_kMonthLong[_displayedMonth.month - 1]} ${_displayedMonth.year}';
    return Row(
      children: [
        InkWell(
          onTap: () => setState(() {
            _mode = _CalMode.monthYear;
            _expandedYear ??= _displayedMonth.year;
          }),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                Icon(Icons.arrow_drop_down_rounded, color: fg, size: 22),
              ],
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(32, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _canGoPrev ? _goPrevMonth : null,
          icon: Icon(
            Icons.arrow_upward_rounded,
            size: 20,
            color: _canGoPrev ? fg : fg.withValues(alpha: 0.25),
          ),
        ),
        IconButton(
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(32, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _canGoNext ? _goNextMonth : null,
          icon: Icon(
            Icons.arrow_downward_rounded,
            size: 20,
            color: _canGoNext ? fg : fg.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }

  Widget _buildDayGrid(Color fg, Color blue) {
    final y = _displayedMonth.year;
    final m = _displayedMonth.month;
    final first = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final leading = first.weekday % 7;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: _kWeekdayShort
              .map(
                (w) => Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              final dayNum = index - leading + 1;
              DateTime cellDate;
              bool inCurrentMonth;

              if (index < leading) {
                final prevLast = DateTime(y, m, 0).day;
                final d = prevLast - (leading - index - 1);
                cellDate = DateTime(y, m - 1, d);
                inCurrentMonth = false;
              } else if (dayNum <= daysInMonth) {
                cellDate = DateTime(y, m, dayNum);
                inCurrentMonth = true;
              } else {
                final over = dayNum - daysInMonth;
                cellDate = DateTime(y, m + 1, over);
                inCurrentMonth = false;
              }

              final cd = _dateOnly(cellDate);
              final enabled =
                  !cd.isBefore(widget.firstDate) && !cd.isAfter(widget.lastDate);
              final sel = _sameDay(cd, _selected);
              final muted = !inCurrentMonth;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled && inCurrentMonth ? () => _onDayTap(cd) : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: sel
                          ? BoxDecoration(
                              color: blue,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.black,
                                width: 2.5,
                              ),
                            )
                          : null,
                      child: Text(
                        '${cd.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: sel
                              ? Colors.white
                              : muted
                                  ? fg.withValues(alpha: 0.38)
                                  : enabled
                                      ? fg
                                      : fg.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthYearPicker(Color fg, Color blue) {
    final y0 = widget.firstDate.year;
    final y1 = widget.lastDate.year;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _mode = _CalMode.dayGrid),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text(
                  '${_kMonthLong[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg.withValues(alpha: 0.75),
                  ),
                ),
                Icon(Icons.arrow_drop_down_rounded, color: fg, size: 20),
              ],
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              itemCount: y1 - y0 + 1,
              itemBuilder: (context, i) {
                final year = y0 + i;
                final expanded = _expandedYear == year;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => setState(() {
                        _expandedYear = expanded ? null : year;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 8,
                        ),
                        color: Colors.grey.shade200,
                        child: Text(
                          '$year',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                    ),
                    if (expanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 2.2,
                          ),
                          itemCount: 12,
                          itemBuilder: (context, mi) {
                            final month = mi + 1;
                            final label = _kMonthShort[mi];
                            final firstOfMonth = DateTime(year, month, 1);
                            final lastOfMonth = DateTime(year, month + 1, 0);
                            final inRange = !lastOfMonth.isBefore(
                                  widget.firstDate,
                                ) &&
                                !firstOfMonth.isAfter(widget.lastDate);
                            final sel = year == _selected.year &&
                                month == _selected.month;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: inRange
                                    ? () {
                                        setState(() {
                                          _displayedMonth =
                                              DateTime(year, month);
                                          _mode = _CalMode.dayGrid;
                                          final d = _clampDate(
                                            DateTime(
                                              year,
                                              month,
                                              _selected.day
                                                  .clamp(
                                                    1,
                                                    DateTime(year, month + 1, 0)
                                                        .day,
                                                  ),
                                            ),
                                            widget.firstDate,
                                            widget.lastDate,
                                          );
                                          _selected = d;
                                        });
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: sel ? blue : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: sel
                                          ? Colors.black
                                          : Colors.grey.shade300,
                                      width: sel ? 2.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: sel
                                          ? Colors.white
                                          : inRange
                                              ? fg
                                              : fg.withValues(alpha: 0.35),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
