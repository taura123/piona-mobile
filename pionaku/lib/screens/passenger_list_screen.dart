import 'dart:async';

import 'package:flutter/material.dart';

import '../services/passenger_scan_store.dart';
import '../services/session_context_store.dart';
import 'scan_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/piona_shell_scaffold.dart';

@immutable
class _FilterState {
  const _FilterState({
    required this.query,
    required this.flight,
    required this.origin,
    required this.destination,
    required this.passengerType,
    required this.category,
    required this.scanPoint,
    required this.status,
    required this.todayOnly,
  });

  final String query;
  final String? flight;
  final String? origin;
  final String? destination;
  final String? passengerType;
  final String? category;
  final String? scanPoint;
  final String? status;
  final bool todayOnly;

  static const Object _keep = Object();

  _FilterState copyWith({
    String? query,
    Object? flight = _keep,
    Object? origin = _keep,
    Object? destination = _keep,
    Object? passengerType = _keep,
    Object? category = _keep,
    Object? scanPoint = _keep,
    Object? status = _keep,
    bool? todayOnly,
  }) {
    return _FilterState(
      query: query ?? this.query,
      flight: flight == _keep ? this.flight : flight as String?,
      origin: origin == _keep ? this.origin : origin as String?,
      destination:
          destination == _keep ? this.destination : destination as String?,
      passengerType: passengerType == _keep
          ? this.passengerType
          : passengerType as String?,
      category: category == _keep ? this.category : category as String?,
      scanPoint: scanPoint == _keep ? this.scanPoint : scanPoint as String?,
      status: status == _keep ? this.status : status as String?,
      todayOnly: todayOnly ?? this.todayOnly,
    );
  }
}

class PassengerListScreen extends StatefulWidget {
  const PassengerListScreen({super.key});

  @override
  State<PassengerListScreen> createState() => _PassengerListScreenState();
}

class _PassengerListScreenState extends State<PassengerListScreen> {
  static const int _refreshSeconds = 5;

  final PassengerScanStore _store = PassengerScanStore.instance;
  final SessionContextStore _session = SessionContextStore.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _countdownTimer;
  int _secondsLeft = _refreshSeconds;
  bool _initialLoading = true;
  bool _syncing = false;
  VoidCallback? _sessionListener;
  _FilterState _filters = const _FilterState(
    query: '',
    flight: null,
    origin: null,
    destination: null,
    passengerType: null,
    category: null,
    scanPoint: null,
    status: null,
    todayOnly: false,
  );

  @override
  void initState() {
    super.initState();
    _sessionListener = () {
      if (!mounted) return;
      _syncFromBackend(replace: true);
      setState(() {});
    };
    _session.addListener(_sessionListener!);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text;
      setState(() => _filters = _filters.copyWith(query: q));
    });
    Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _initialLoading = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromBackend(replace: true);
    });
    _startCountdown();
  }

  @override
  void dispose() {
    final l = _sessionListener;
    if (l != null) {
      _session.removeListener(l);
      _sessionListener = null;
    }
    _countdownTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _secondsLeft = _refreshSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft -= 1;
        if (_secondsLeft <= 0) {
          _secondsLeft = _refreshSeconds;
          _store.refreshTick();
          _syncFromBackend();
        }
      });
    });
  }

  Future<void> _syncFromBackend({bool replace = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final shouldUpdate = mounted;
    try {
      final ac = _session.originCode.trim();
      await _store.loadFromBackend(
        airportCode: _session.allAirports ? null : (ac.isEmpty ? null : ac),
        since: replace ? null : _store.lastRefreshedAt,
        replace: replace,
      );
    } finally {
      if (shouldUpdate && mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _openFiltersSheet({
    required BuildContext context,
    required List<String> flightOpts,
    required List<String> originOpts,
    required List<String> destOpts,
    required List<String> typeOpts,
    required List<String> categoryOpts,
    required List<String> scanPointOpts,
    required List<String> statusOpts,
  }) async {
    final before = _filters;
    final updated = await showModalBottomSheet<_FilterState>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.paddingOf(context).bottom;
        final sheetBg = AppTheme.surface(context);
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, bottom + 12),
            child: Container(
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
              child: _FilterSheetContent(
                initial: before,
                flightOpts: flightOpts,
                originOpts: originOpts,
                destOpts: destOpts,
                typeOpts: typeOpts,
                categoryOpts: categoryOpts,
                scanPointOpts: scanPointOpts,
                statusOpts: statusOpts,
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (updated == null) return;
    setState(() => _filters = updated);
  }

  List<_ActiveChip> _activeChips(_FilterState f) {
    final chips = <_ActiveChip>[];
    if (f.todayOnly) {
      chips.add(
        _ActiveChip(
          label: "Today's Data",
          onClear: () =>
              setState(() => _filters = _filters.copyWith(todayOnly: false)),
        ),
      );
    }

    void add(
      String name,
      String? value,
      _FilterState Function() clear,
    ) {
      if (value == null || value.trim().isEmpty) return;
      chips.add(
        _ActiveChip(
          label: '$name: $value',
          onClear: () => setState(() => _filters = clear()),
        ),
      );
    }

    add('Flight', f.flight, () => _filters.copyWith(flight: null));
    add('Origin', f.origin, () => _filters.copyWith(origin: null));
    add(
      'Destination',
      f.destination,
      () => _filters.copyWith(destination: null),
    );
    add('Type', f.passengerType, () => _filters.copyWith(passengerType: null));
    add('Category', f.category, () => _filters.copyWith(category: null));
    add('Scan Point', f.scanPoint, () => _filters.copyWith(scanPoint: null));
    add('Status', f.status, () => _filters.copyWith(status: null));
    return chips;
  }

  List<PassengerScanRecord> _applyFilters(
    List<PassengerScanRecord> input,
    _FilterState f,
  ) {
    final today = DateTime.now();
    return input.where((r) {
      if (f.todayOnly && !_isSameDay(r.scannedAt, today)) return false;

      if (f.flight != null && r.flight != f.flight) return false;
      if (f.origin != null && r.origin != f.origin) return false;
      if (f.destination != null && r.destination != f.destination) return false;
      if (f.passengerType != null && r.passengerType != f.passengerType) {
        return false;
      }
      if (f.category != null && r.category != f.category) return false;
      if (f.scanPoint != null && r.scanPoint != f.scanPoint) return false;
      if (f.status != null && _statusLabel(r.status) != f.status) return false;

      final q = f.query.trim().toLowerCase();
      if (q.isEmpty) return true;
      final hay = <String>[
        r.passengerName,
        r.pnrOrCode,
        r.flight,
        r.origin,
        r.destination,
        r.scanPoint,
        r.category,
        r.passengerType,
        _statusLabel(r.status),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList(growable: false);
  }

  List<String> _uniqueSorted(
    Iterable<String> values, {
    bool keepNA = true,
  }) {
    final set = <String>{};
    for (final v in values) {
      final t = v.trim();
      if (t.isEmpty) continue;
      if (!keepNA && t == 'N/A') continue;
      set.add(t);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _optionsFor(
    List<PassengerScanRecord> all,
    _FilterState f,
    _FilterState Function(_FilterState base) overrideThisField,
    String Function(PassengerScanRecord r) getter,
  ) {
    final base = overrideThisField(f);
    final filtered = _applyFilters(all, base);
    return _uniqueSorted(filtered.map(getter));
  }

  static String _statusLabel(ParseStatus s) {
    return switch (s) {
      ParseStatus.complete => 'Valid (Lengkap)',
      ParseStatus.partial => 'Valid (Tidak Lengkap)',
      ParseStatus.failed => 'Invalid',
    };
  }

  String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PionaShellScaffold(
      currentNav: PionaNavItem.passengerList,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.background(context)
          : AppTheme.shellScaffoldLight,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: BackButton(
          color: Colors.white,
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            pionaNavigateToNavItem(context, PionaNavItem.home);
          },
        ),
        title: const Text('Passenger List'),
        backgroundColor:
            isDark ? AppTheme.primaryBlueDark : AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          final sessionAirport = _session.originCode.trim();
          final all = _store.records.where((r) {
            if (_session.allAirports) return true;
            if (sessionAirport.isEmpty) return true;
            return r.airportCode.trim() == sessionAirport;
          }).toList(growable: false);
          final results = _applyFilters(all, _filters);
          final lastUpdated = _store.lastRefreshedAt;
          final activeChips = _activeChips(_filters);

          final flightOpts = _optionsFor(
            all,
            _filters,
            (base) => base.copyWith(flight: null),
            (r) => r.flight,
          );
          final originOpts = _optionsFor(
            all,
            _filters,
            (base) => base.copyWith(origin: null),
            (r) => r.origin,
          );
          final destOpts = _optionsFor(
            all,
            _filters,
            (base) => base.copyWith(destination: null),
            (r) => r.destination,
          );
          final typeOpts = _optionsFor(
            all,
            _filters,
            (base) => base.copyWith(passengerType: null),
            (r) => r.passengerType,
          );
          final categoryOpts = _optionsFor(
            all,
            _filters,
            (base) => base.copyWith(category: null),
            (r) => r.category,
          );
          final scanPointOpts = _optionsFor(
            all,
            _filters,
            (base) => base.copyWith(scanPoint: null),
            (r) => r.scanPoint,
          );
          final statusOpts = _optionsFor(
            all,
            _filters,
            (base) => base.copyWith(status: null),
            (r) => _statusLabel(r.status),
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Auto refresh tiap $_refreshSeconds detik',
                          style: TextStyle(
                            color: AppTheme.textSecondaryColor(context),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Refresh in: $_secondsLeft',
                          style: TextStyle(
                            color: AppTheme.textSecondaryColor(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Last updated: ${_fmtDateTime(lastUpdated)}',
                          style: TextStyle(
                            color: AppTheme.textSecondaryColor(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search by Name or PNR/Code...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _filters.query.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => _searchCtrl.clear(),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _filters = _filters.copyWith(
                                todayOnly: !_filters.todayOnly,
                              );
                            }),
                            icon: Icon(
                              Icons.today_rounded,
                              color: _filters.todayOnly
                                  ? AppTheme.primaryBlue
                                  : AppTheme.textSecondaryColor(context),
                              size: 18,
                            ),
                            label: Text(
                              "Today's Data",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _filters.todayOnly
                                    ? AppTheme.primaryBlue
                                    : AppTheme.textPrimaryColor(context),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _filters.todayOnly
                                    ? AppTheme.primaryBlue
                                    : AppTheme.borderColor(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: _filters.todayOnly
                                  ? AppTheme.primaryBlue.withValues(alpha: 0.06)
                                  : null,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () => _openFiltersSheet(
                              context: context,
                              flightOpts: flightOpts,
                              originOpts: originOpts,
                              destOpts: destOpts,
                              typeOpts: typeOpts,
                              categoryOpts: categoryOpts,
                              scanPointOpts: scanPointOpts,
                              statusOpts: statusOpts,
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            label: const Text(
                              'Filter',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(120, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        if (activeChips.isNotEmpty ||
                            _filters.query.trim().isNotEmpty)
                          SizedBox(
                            height: 44,
                            child: TextButton.icon(
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _filters = const _FilterState(
                                  query: '',
                                  flight: null,
                                  origin: null,
                                  destination: null,
                                  passengerType: null,
                                  category: null,
                                  scanPoint: null,
                                  status: null,
                                  todayOnly: false,
                                );
                              }),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text(
                                'Reset',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (activeChips.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final c in activeChips) ...[
                              _ActiveFilterChip(chip: c),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Total records: ${results.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondaryColor(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Max tampil: 200',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _initialLoading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Memuat data...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        AppTheme.textSecondaryColor(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : results.isEmpty
                          ? _EmptyState(
                              key: const ValueKey('empty'),
                              isDark: isDark,
                              todayOnly: _filters.todayOnly,
                            )
                          : LayoutBuilder(
                              key: const ValueKey('data'),
                              builder: (context, c) {
                                final rows =
                                    results.take(200).toList(growable: false);
                                final navPadding = PionaFloatingNavBar.reserveBottomPadding(context);
                                if (c.maxWidth < 900) {
                                  return _PassengerCardList(
                                    rows: rows,
                                    fmtDateTime: _fmtDateTime,
                                    bottomPadding: navPadding,
                                  );
                                }
                                return _PassengerTable(
                                  isDark: isDark,
                                  rows: rows,
                                  fmtDateTime: _fmtDateTime,
                                );
                              },
                            ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey<String?>(
        value == null ? 'all:$label' : '$label:$value',
      ),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All'),
        ),
        ...options.map(
          (o) => DropdownMenuItem<String?>(
            value: o,
            child: Text(o, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.isDark,
    required this.todayOnly,
  });

  final bool isDark;
  final bool todayOnly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assignment_rounded,
              size: 48,
              color:
                  AppTheme.textSecondaryColor(context).withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              'No passengers found${todayOnly ? ' for today' : ''}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimaryColor(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              todayOnly
                  ? 'Aktifkan kembali data semua tanggal atau lakukan scan hari ini.'
                  : 'Lakukan scan dari menu Scan Normal / Scan Transit untuk menambah data.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondaryColor(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassengerTable extends StatelessWidget {
  const _PassengerTable({
    required this.isDark,
    required this.rows,
    required this.fmtDateTime,
  });

  final bool isDark;
  final List<PassengerScanRecord> rows;
  final String Function(DateTime) fmtDateTime;

  @override
  Widget build(BuildContext context) {
    final headerBg = isDark ? const Color(0xFF141C2E) : const Color(0xFFF7F9FC);
    final border = AppTheme.borderColor(context);

    Widget headerCell(String text, {double w = 120}) {
      return SizedBox(
        width: w,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondaryColor(context),
          ),
        ),
      );
    }

    Widget cell(String text, {double w = 120, bool mono = false}) {
      return SizedBox(
        width: w,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textPrimaryColor(context),
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1040,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: headerBg,
                      border: Border(bottom: BorderSide(color: border)),
                    ),
                    child: Row(
                      children: [
                        headerCell('Name', w: 220),
                        headerCell('Flight', w: 90),
                        headerCell('Origin', w: 80),
                        headerCell('Destination', w: 100),
                        headerCell('Flight Date', w: 120),
                        headerCell('Seat', w: 70),
                        headerCell('Type', w: 120),
                        headerCell('Category', w: 110),
                        headerCell('PNR/Code', w: 140),
                        headerCell('Scanned At', w: 170),
                        headerCell('Scan Point', w: 120),
                        headerCell('Status', w: 160),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: border),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              cell(r.passengerName, w: 220),
                              cell(r.flight, w: 90, mono: true),
                              cell(r.origin, w: 80, mono: true),
                              cell(r.destination, w: 100, mono: true),
                              cell(r.boardingDate, w: 120, mono: true),
                              cell(r.seat, w: 70, mono: true),
                              cell(r.passengerType, w: 120),
                              cell(r.category, w: 110),
                              cell(r.pnrOrCode, w: 140, mono: true),
                              cell(
                                fmtDateTime(r.scannedAt),
                                w: 170,
                                mono: true,
                              ),
                              cell(r.scanPoint, w: 120),
                              cell(
                                switch (r.status) {
                                  ParseStatus.complete => 'Valid (Lengkap)',
                                  ParseStatus.partial =>
                                    'Valid (Tidak Lengkap)',
                                  ParseStatus.failed => 'Invalid',
                                },
                                w: 160,
                              ),
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
    );
  }
}

@immutable
class _ActiveChip {
  const _ActiveChip({
    required this.label,
    required this.onClear,
  });

  final String label;
  final VoidCallback onClear;
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    required this.chip,
  });

  final _ActiveChip chip;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        chip.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimaryColor(context),
        ),
      ),
      onDeleted: chip.onClear,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: AppTheme.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );
  }
}

class _FilterSheetContent extends StatefulWidget {
  const _FilterSheetContent({
    required this.initial,
    required this.flightOpts,
    required this.originOpts,
    required this.destOpts,
    required this.typeOpts,
    required this.categoryOpts,
    required this.scanPointOpts,
    required this.statusOpts,
  });

  final _FilterState initial;
  final List<String> flightOpts;
  final List<String> originOpts;
  final List<String> destOpts;
  final List<String> typeOpts;
  final List<String> categoryOpts;
  final List<String> scanPointOpts;
  final List<String> statusOpts;

  @override
  State<_FilterSheetContent> createState() => _FilterSheetContentState();
}

class _FilterSheetContentState extends State<_FilterSheetContent> {
  late _FilterState _local = widget.initial;

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: border.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filter',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FilterGroupTitle(
                    title: 'Route & Flight',
                    icon: Icons.flight_takeoff_rounded,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Flight',
                    value: _local.flight,
                    options: widget.flightOpts,
                    onChanged: (v) =>
                        setState(() => _local = _local.copyWith(flight: v)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterDropdown(
                          label: 'Origin',
                          value: _local.origin,
                          options: widget.originOpts,
                          onChanged: (v) => setState(
                            () => _local = _local.copyWith(origin: v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilterDropdown(
                          label: 'Destination',
                          value: _local.destination,
                          options: widget.destOpts,
                          onChanged: (v) => setState(
                            () => _local = _local.copyWith(destination: v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _FilterGroupTitle(
                    title: 'Passenger & Scan',
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterDropdown(
                          label: 'Passenger Type',
                          value: _local.passengerType,
                          options: widget.typeOpts,
                          onChanged: (v) => setState(
                            () => _local = _local.copyWith(passengerType: v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilterDropdown(
                          label: 'Category',
                          value: _local.category,
                          options: widget.categoryOpts,
                          onChanged: (v) => setState(
                            () => _local = _local.copyWith(category: v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Scan Point',
                    value: _local.scanPoint,
                    options: widget.scanPointOpts,
                    onChanged: (v) => setState(
                      () => _local = _local.copyWith(scanPoint: v),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Status',
                    value: _local.status,
                    options: widget.statusOpts,
                    onChanged: (v) =>
                        setState(() => _local = _local.copyWith(status: v)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.today_rounded,
                          size: 18,
                          color: AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Today's Data",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimaryColor(context),
                            ),
                          ),
                        ),
                        Switch(
                          value: _local.todayOnly,
                          onChanged: (v) => setState(
                            () => _local = _local.copyWith(todayOnly: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _local = const _FilterState(
                      query: '',
                      flight: null,
                      origin: null,
                      destination: null,
                      passengerType: null,
                      category: null,
                      scanPoint: null,
                      status: null,
                      todayOnly: false,
                    );
                  }),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Reset Filter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_local),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterGroupTitle extends StatelessWidget {
  const _FilterGroupTitle({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimaryColor(context),
          ),
        ),
      ],
    );
  }
}

class _PassengerCardList extends StatelessWidget {
  const _PassengerCardList({
    required this.rows,
    required this.fmtDateTime,
    this.bottomPadding = 16.0,
  });

  final List<PassengerScanRecord> rows;
  final String Function(DateTime) fmtDateTime;
  final double bottomPadding;

  Color _statusColor(ParseStatus s) {
    return switch (s) {
      ParseStatus.complete => AppTheme.validGreen,
      ParseStatus.partial => const Color(0xFFF59E0B),
      ParseStatus.failed => AppTheme.invalidRed,
    };
  }

  String _statusLabel(ParseStatus s) {
    return switch (s) {
      ParseStatus.complete => 'VALID (Lengkap)',
      ParseStatus.partial => 'VALID (Tidak Lengkap)',
      ParseStatus.failed => 'INVALID',
    };
  }

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderColor(context);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = rows[i];
        final statusColor = _statusColor(r.status);
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.passengerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel(r.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _MetaPill(label: 'Flight', value: r.flight),
                    _MetaPill(
                      label: 'Route',
                      value: '${r.origin}-${r.destination}',
                    ),
                    _MetaPill(label: 'Type', value: r.passengerType),
                    _MetaPill(label: 'Category', value: r.category),
                    _MetaPill(label: 'Scan Point', value: r.scanPoint),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PNR/Code: ${r.pnrOrCode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondaryColor(context),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Text(
                      fmtDateTime(r.scannedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimaryColor(context),
        ),
      ),
    );
  }
}
