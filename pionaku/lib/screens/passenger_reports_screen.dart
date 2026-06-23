import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../services/passenger_scan_store.dart';
import '../services/passenger_scans_api.dart';
import '../services/reports_exporter.dart';
import '../screens/scan_screen.dart' show ParseStatus;
import '../utils/passenger_recap.dart';
import '../services/session_context_store.dart';

/// Reports (UI shell).
///
/// Recap is driven by Passenger List data (PassengerScanStore).
class PassengerReportsScreen extends StatefulWidget {
  const PassengerReportsScreen({super.key});

  @override
  State<PassengerReportsScreen> createState() => _PassengerReportsScreenState();
}

class _FlightRecapRow {
  const _FlightRecapRow({
    required this.flight,
    required this.totalPassengers,
    required this.totalBaggageDisplay,
    required this.status,
  });

  final String flight;
  final int totalPassengers;
  final String totalBaggageDisplay;
  final String status;
}

class _PassengerReportsScreenState extends State<PassengerReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final PassengerScanStore _store = PassengerScanStore.instance;
  final PassengerScansApi _api = PassengerScansApi();
  final SessionContextStore _session = SessionContextStore.instance;
  Timer? _refreshTimer;
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );
  bool _isFiltered = false;
  DateTimeRange? _filteredRange;
  List<_FlightRecapRow> _dataRecap = const [];
  String? _selectedFlightForList;
  bool _filtering = false;
  final Set<String> _selectedAirports = <String>{};
  List<String> _airportOptions = const [];
  List<PassengerScanRecord> _effectiveRecords() {
    final records = _store.records;
    if (!_session.allAirports) {
      final ac = _session.originCode.trim();
      if (ac.isEmpty) return records;
      return records
          .where((r) => r.airportCode.trim() == ac)
          .toList(growable: false);
    }
    if (_selectedAirports.isEmpty) return records;
    final selected = _selectedAirports.map((s) => s.trim()).toSet();
    return records
        .where((r) => selected.contains(r.airportCode.trim()))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _store.loadFromBackend(
        airportCodes: _session.allAirports
            ? (_selectedAirports.isEmpty
                ? null
                : _selectedAirports.toList(growable: false))
            : null,
        airportCode: _session.allAirports ? null : _session.originCode.trim(),
        since: _store.lastRefreshedAt,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAirportOptions();
      _store.loadFromBackend(
        airportCodes: _session.allAirports
            ? (_selectedAirports.isEmpty
                ? null
                : _selectedAirports.toList(growable: false))
            : null,
        airportCode: _session.allAirports ? null : _session.originCode.trim(),
        replace: true,
      );
    });
  }

  Future<void> _refreshAirportOptions() async {
    final token = _session.jwtToken?.trim();
    if (token == null || token.isEmpty) return;
    try {
      final items = await _api.listAirports(bearerToken: token);
      if (!mounted) return;
      setState(() => _airportOptions = items);
    } catch (_) {
      // Best-effort: keep existing options.
    }
  }

  Future<void> _openAirportPicker() async {
    final opts = _airportOptions;
    final before = Set<String>.from(_selectedAirports);

    final result = await showModalBottomSheet<
        ({Set<String> selected})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.paddingOf(context).bottom;
        final sheetBg = AppTheme.surface(context);
        final localSelected = Set<String>.from(before);
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, bottom + 12),
            child: StatefulBuilder(
              builder: (context, setLocal) {
                return Container(
                  decoration: BoxDecoration(
                    color: sheetBg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Row(
                          children: [
                            Text(
                              'Airports',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimaryColor(context),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(null),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 6),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop((
                                selected: localSelected,
                              )),
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: AppTheme.borderColor(context)),
                      if (!_session.allAirports) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'All Airports sedang OFF (mengikuti toggle di Home). Reports akan menampilkan bandara login saja.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondaryColor(context),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Pilih 1 atau lebih bandara',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondaryColor(context),
                              ),
                            ),
                          ),
                        ),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: opts.length,
                            itemBuilder: (context, i) {
                              final code = opts[i];
                              final checked = localSelected.contains(code);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: (v) {
                                  setLocal(() {
                                    if (v == true) {
                                      localSelected.add(code);
                                    } else {
                                      localSelected.remove(code);
                                    }
                                  });
                                },
                                title: Text(code),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (result == null) return;
    setState(() {
      _selectedAirports
        ..clear()
        ..addAll(result.selected);
    });
    await _store.loadFromBackend(
      airportCodes: _session.allAirports
          ? (_selectedAirports.isEmpty
              ? null
              : _selectedAirports.toList(growable: false))
          : null,
      airportCode: _session.allAirports ? null : _session.originCode.trim(),
      replace: true,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedRange,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      currentDate: now,
      saveText: 'Pilih',
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() => _selectedRange = picked);
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  String _fmtIsoDay(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static bool _recordMatchesRange(
    PassengerScanRecord r,
    DateTimeRange range,
  ) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final parsedBoarding = parseBoardingDateString(r.boardingDate);

    bool inRange(DateTime d) {
      final dd = DateTime(d.year, d.month, d.day);
      return (dd.isAtSameMomentAs(start) || dd.isAfter(start)) &&
          (dd.isAtSameMomentAs(end) || dd.isBefore(end));
    }

    final byBoarding = parsedBoarding != null && inRange(parsedBoarding);
    final byScannedAt = inRange(r.scannedAt);
    return byBoarding || byScannedAt;
  }

  Future<void> _onFilter() async {
    final range = _selectedRange;
    setState(() => _filtering = true);
    try {
      final days = _expandCalendarDays(range);
      for (var i = 0; i < days.length; i += 1) {
        final d = days[i];
        await _store.loadFromBackend(
          date: _fmtIsoDay(d),
          airportCodes: _session.allAirports
              ? (_selectedAirports.isEmpty
                  ? null
                  : _selectedAirports.toList(growable: false))
              : null,
          airportCode: _session.allAirports ? null : _session.originCode.trim(),
          replace: i == 0,
        );
      }

      final next = _buildRecapRowsForRange(_effectiveRecords(), range);
      if (!mounted) return;
      setState(() {
        _isFiltered = true;
        _filteredRange = range;
        _dataRecap = next;
        _selectedFlightForList = null;
      });
    } finally {
      if (mounted) {
        setState(() => _filtering = false);
      }
    }
  }

  static List<DateTime> _expandCalendarDays(DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final out = <DateTime>[];
    var cur = start;
    while (!cur.isAfter(end)) {
      out.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return out;
  }

  List<_FlightRecapRow> _buildRecapRowsForRange(
    List<PassengerScanRecord> records,
    DateTimeRange range,
  ) {
    final filtered =
        records.where((r) => _recordMatchesRange(r, range)).toList();
    if (filtered.isEmpty) return const [];

    final byFlight = <String, List<PassengerScanRecord>>{};
    for (final r in filtered) {
      final flight = r.flight.trim().isEmpty ? 'N/A' : r.flight.trim();
      byFlight.putIfAbsent(flight, () => <PassengerScanRecord>[]).add(r);
    }

    final keys = byFlight.keys.toList()..sort();
    final out = <_FlightRecapRow>[];
    for (final k in keys) {
      final list = byFlight[k]!;
      final total = list.length;

      // Total baggage is not available in current scan record model.
      const baggageDisplay = '—';

      final hasInvalid = list.any((r) => r.status == ParseStatus.failed);
      final hasPartial = list.any((r) => r.status == ParseStatus.partial);
      final status =
          hasInvalid ? 'Has Invalid' : (hasPartial ? 'Partial' : 'Complete');

      out.add(
        _FlightRecapRow(
          flight: k,
          totalPassengers: total,
          totalBaggageDisplay: baggageDisplay,
          status: status,
        ),
      );
    }

    return out;
  }

  Future<void> _downloadXlsx() async {
    final range = _filteredRange ?? _selectedRange;
    try {
      await ReportsExporter.shareXlsx(
          range: range, scanRecords: _effectiveRecords());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export XLSX gagal: $e')),
      );
    }
  }

  Future<void> _downloadPdf() async {
    final range = _filteredRange ?? _selectedRange;
    try {
      await ReportsExporter.sharePdf(
        range: range,
        scanRecords: _effectiveRecords(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export PDF gagal: $e')),
      );
    }
  }

  String _fmtRange(DateTimeRange r) {
    return '${_fmtDate(r.start)} - ${_fmtDate(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : AppTheme.shellScaffoldLight;
    final surface = isDark ? const Color(0xFF141C2E) : Colors.white;
    final border = AppTheme.borderColor(context);
    final secondary = AppTheme.textSecondaryColor(context);
    final primaryText = AppTheme.textPrimaryColor(context);
    final subtleBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFFAFAFA);
    final activeRange = _filteredRange ?? _selectedRange;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor:
            isDark ? AppTheme.primaryBlueDark : AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _session.allAirports ? _openAirportPicker : null,
            icon: const Icon(Icons.public_rounded),
            tooltip: 'Airports',
          ),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 420;
                      final headerText = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reports',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: primaryText,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'View summaries and detailed passenger lists.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: secondary,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AnimatedBuilder(
                                  animation: _session,
                                  builder: (context, _) {
                                    final on = _session.allAirports;
                                    final scopeLabel = on
                                        ? 'All Airports'
                                        : (_session.originCode.trim().isEmpty
                                            ? 'Login Airport'
                                            : _session.originCode.trim());
                                    final pickedLabel = _selectedAirports.isEmpty
                                        ? 'All'
                                        : '${_selectedAirports.length} selected';

                                    Widget pill({
                                      required Widget child,
                                      VoidCallback? onTap,
                                    }) {
                                      final w = Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: subtleBg,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(color: border),
                                        ),
                                        child: child,
                                      );
                                      if (onTap == null) return w;
                                      return InkWell(
                                        onTap: onTap,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        child: w,
                                      );
                                    }

                                    final scopePill = pill(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.public_rounded,
                                            size: 14,
                                            color: AppTheme.primaryBlue,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            scopeLabel,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: primaryText,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Transform.scale(
                                            scale: 0.78,
                                            child: Switch.adaptive(
                                              value: on,
                                              onChanged: (v) async {
                                                _session.setAllAirports(v);
                                                if (!_session.allAirports) {
                                                  setState(
                                                      _selectedAirports.clear);
                                                }
                                                await _store.loadFromBackend(
                                                  airportCodes:
                                                      _session.allAirports
                                                          ? (_selectedAirports
                                                                  .isEmpty
                                                              ? null
                                                              : _selectedAirports
                                                                  .toList(
                                                                      growable:
                                                                          false))
                                                          : null,
                                                  airportCode: _session
                                                          .allAirports
                                                      ? null
                                                      : _session.originCode
                                                          .trim(),
                                                  replace: true,
                                                );
                                              },
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    final pickerPill = pill(
                                      onTap: on ? _openAirportPicker : null,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.filter_alt_rounded,
                                            size: 14,
                                            color: on
                                                ? AppTheme.primaryBlue
                                                : secondary,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            on ? 'Airports: $pickedLabel' : 'Airports filter',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  on ? primaryText : secondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    return Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        scopePill,
                                        pickerPill,
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryBlue.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withValues(
                                  alpha: 0.22,
                                ),
                              ),
                            ),
                            child: Text(
                              _isFiltered ? 'Filtered' : 'Not filtered',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: primaryText,
                              ),
                            ),
                          ),
                        ],
                      );

                      final dateField = Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _pickRange,
                          borderRadius: BorderRadius.circular(10),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: border),
                              color: subtleBg,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Text(
                                  _fmtRange(_selectedRange),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: primaryText,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                  color: secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      final filterBtn = ElevatedButton(
                        onPressed: _filtering ? null : _onFilter,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: narrow ? 14 : 12,
                          ),
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_filtering)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            else
                              const Icon(
                                Icons.filter_alt_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _filtering ? 'Syncing...' : 'Filter',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );

                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            headerText,
                            const SizedBox(height: 14),
                            dateField,
                            const SizedBox(height: 10),
                            SizedBox(width: double.infinity, child: filterBtn),
                            if (_filtering) ...[
                              const SizedBox(height: 10),
                              LinearProgressIndicator(
                                minHeight: 3,
                                color: AppTheme.primaryBlue,
                                backgroundColor: AppTheme.primaryBlue
                                    .withValues(alpha: 0.18),
                              ),
                            ] else if (_isFiltered) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Range: ${_fmtRange(activeRange)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          headerText,
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(child: dateField),
                              const SizedBox(width: 10),
                              SizedBox(width: 150, child: filterBtn),
                            ],
                          ),
                          if (_filtering) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              minHeight: 3,
                              color: AppTheme.primaryBlue,
                              backgroundColor:
                                  AppTheme.primaryBlue.withValues(alpha: 0.18),
                            ),
                          ] else if (_isFiltered) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Range: ${_fmtRange(activeRange)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primaryBlue,
                  unselectedLabelColor: secondary,
                  indicatorColor: AppTheme.primaryBlue,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(text: 'Recap'),
                    Tab(text: 'List'),
                  ],
                ),
                Divider(height: 1, thickness: 1, color: border),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      Builder(
                        builder: (context) {
                          final exportEnabled =
                              _isFiltered && _dataRecap.isNotEmpty;
                          return _RecapTable(
                            border: border,
                            isDark: isDark,
                            exportEnabled: exportEnabled,
                            onDownloadXlsx:
                                exportEnabled ? () => _downloadXlsx() : null,
                            onDownloadPdf:
                                exportEnabled ? () => _downloadPdf() : null,
                            secondary: secondary,
                            rows: _dataRecap,
                            emptyMessage: _isFiltered
                                ? 'No recap data for the selected range.'
                                : 'Silakan pilih rentang tanggal dan tekan tombol filter untuk menampilkan data.',
                            onTapFlight: (flight) {
                              if (!_isFiltered || _filteredRange == null) {
                                return;
                              }
                              setState(() => _selectedFlightForList = flight);
                              _tabController.animateTo(1);
                            },
                          );
                        },
                      ),
                      _ReportsListTab(
                        isFiltered: _isFiltered,
                        filterRange: _filteredRange ?? _selectedRange,
                        selectedFlight: _selectedFlightForList,
                        onClearFlight: () =>
                            setState(() => _selectedFlightForList = null),
                        secondary: secondary,
                        border: border,
                        isDark: isDark,
                        records: _effectiveRecords(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecapTable extends StatelessWidget {
  const _RecapTable({
    required this.border,
    required this.isDark,
    required this.secondary,
    required this.exportEnabled,
    required this.onDownloadXlsx,
    required this.onDownloadPdf,
    required this.rows,
    required this.emptyMessage,
    required this.onTapFlight,
  });

  final Color border;
  final bool isDark;
  final Color secondary;
  final bool exportEnabled;
  final VoidCallback? onDownloadXlsx;
  final VoidCallback? onDownloadPdf;
  final List<_FlightRecapRow> rows;
  final String emptyMessage;
  final ValueChanged<String> onTapFlight;

  static const _headerBgLight = Color(0xFFF1F3F5);
  static const _headerBgDark = Color(0xFF1E293B);

  static const double _wFlight = 130;
  static const double _wPax = 132;
  static const double _wBag = 112;
  static const double _wStatus = 110;
  static const double _hPad = 12; // left/right padding inside table rows

  static const double _tableWidth =
      (_hPad * 2) + _wFlight + _wPax + _wBag + _wStatus;

  @override
  Widget build(BuildContext context) {
    final headerBg = isDark ? _headerBgDark : _headerBgLight;
    final headerFg = AppTheme.textPrimaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onDownloadXlsx,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor:
                        const Color(0xFF16A34A).withValues(alpha: 0.45),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.85),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Download XLSX',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onDownloadPdf,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor:
                        const Color(0xFFDC2626).withValues(alpha: 0.45),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.85),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Download PDF',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: secondary.withValues(alpha: 0.95),
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, c) {
                    final h = c.maxHeight;
                    final hCtrl = ScrollController();
                    return Scrollbar(
                      controller: hCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: hCtrl,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: SizedBox(
                          width: _tableWidth,
                          height: h,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: headerBg,
                                  border: Border(
                                    bottom: BorderSide(color: border),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _hPad,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    _hCell('Flight Number', _wFlight, headerFg),
                                    _hCell('Total Penumpang', _wPax, headerFg),
                                    _hCell('Total Bagasi', _wBag, headerFg),
                                    _hCell('Status', _wStatus, headerFg),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: border.withValues(alpha: 0.65),
                                  ),
                                  itemBuilder: (context, i) {
                                    final r = rows[i];
                                    final base = TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimaryColor(context),
                                      fontWeight: FontWeight.w600,
                                    );
                                    final rowBg =
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(0xFF141C2E)
                                            : Colors.white;
                                    return Material(
                                      color: rowBg,
                                      child: InkWell(
                                        onTap: () => onTapFlight(r.flight),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: _hPad,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              _dCell(
                                                r.flight,
                                                _wFlight,
                                                base,
                                                mono: true,
                                              ),
                                              _dCell(
                                                '${r.totalPassengers}',
                                                _wPax,
                                                base.copyWith(
                                                  color: AppTheme.primaryBlue,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                mono: true,
                                              ),
                                              _dCell(
                                                r.totalBaggageDisplay,
                                                _wBag,
                                                base,
                                                mono: true,
                                              ),
                                              _dCell(
                                                r.status,
                                                _wStatus,
                                                base.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
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

  static Widget _hCell(String label, double w, Color fg) {
    return SizedBox(
      width: w,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  static Widget _dCell(
    String text,
    double w,
    TextStyle style, {
    bool mono = false,
  }) {
    return SizedBox(
      width: w,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: mono
            ? style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 13) - 0.5,
              )
            : style,
      ),
    );
  }
}

class _ReportsListTab extends StatelessWidget {
  const _ReportsListTab({
    required this.isFiltered,
    required this.filterRange,
    required this.selectedFlight,
    required this.onClearFlight,
    required this.secondary,
    required this.border,
    required this.isDark,
    required this.records,
  });

  final bool isFiltered;
  final DateTimeRange filterRange;
  final String? selectedFlight;
  final VoidCallback onClearFlight;
  final Color secondary;
  final Color border;
  final bool isDark;
  final List<PassengerScanRecord> records;

  static const _headerBgLight = Color(0xFFF1F3F5);
  static const _headerBgDark = Color(0xFF1E293B);

  static const double _hPad = 12;
  static const double _wName = 190;
  static const double _wPnr = 120;
  static const double _wSeat = 70;
  static const double _wType = 90;
  static const double _wCategory = 95;
  static const double _wScanPoint = 120;

  static const double _tableWidth =
      (_hPad * 2) + _wName + _wPnr + _wSeat + _wType + _wCategory + _wScanPoint;

  @override
  Widget build(BuildContext context) {
    final headerBg = isDark ? _headerBgDark : _headerBgLight;
    final headerFg = AppTheme.textPrimaryColor(context);

    final filtered = records
        .where((r) => _PassengerReportsScreenState._recordMatchesRange(
              r,
              filterRange,
            ))
        .where((r) => selectedFlight == null || r.flight == selectedFlight)
        .toList(growable: false);

    if (!isFiltered) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'Silakan pilih rentang tanggal dan tekan tombol filter untuk menampilkan data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: secondary.withValues(alpha: 0.9),
              height: 1.45,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedFlight != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    'Flight: $selectedFlight',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimaryColor(context),
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: onClearFlight,
                  child: const Text('Clear'),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final h = c.maxHeight;
              final hCtrl = ScrollController();
              return Scrollbar(
                controller: hCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: hCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: _tableWidth,
                    height: h,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: headerBg,
                            border: Border(
                              bottom: BorderSide(color: border),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: _hPad,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              _hCell('Name', _wName, headerFg),
                              _hCell('PNR', _wPnr, headerFg),
                              _hCell('Seat', _wSeat, headerFg),
                              _hCell('Type', _wType, headerFg),
                              _hCell('Category', _wCategory, headerFg),
                              _hCell('Scan Point', _wScanPoint, headerFg),
                            ],
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: Text(
                                      'No passengers found for the selected date and flight.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color:
                                            secondary.withValues(alpha: 0.95),
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: EdgeInsets.zero,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: border.withValues(alpha: 0.65),
                                  ),
                                  itemBuilder: (context, i) {
                                    final r = filtered[i];
                                    final base = TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimaryColor(context),
                                      fontWeight: FontWeight.w600,
                                    );
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: _hPad,
                                        vertical: 12,
                                      ),
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? const Color(0xFF141C2E)
                                          : Colors.white,
                                      child: Row(
                                        children: [
                                          _dCell(r.passengerName, _wName, base),
                                          _dCell(
                                            r.pnrOrCode,
                                            _wPnr,
                                            base,
                                            mono: true,
                                          ),
                                          _dCell(r.seat, _wSeat, base,
                                              mono: true),
                                          _dCell(r.passengerType, _wType, base),
                                          _dCell(r.category, _wCategory, base),
                                          _dCell(
                                              r.scanPoint, _wScanPoint, base),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
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

  static Widget _hCell(String label, double w, Color fg) {
    return SizedBox(
      width: w,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  static Widget _dCell(
    String text,
    double w,
    TextStyle style, {
    bool mono = false,
  }) {
    return SizedBox(
      width: w,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: mono
            ? style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 13) - 0.5,
              )
            : style,
      ),
    );
  }
}
