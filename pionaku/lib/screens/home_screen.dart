import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../app_theme_scope.dart';
import '../theme/app_theme.dart';
import '../services/passenger_scan_store.dart';
import '../services/api_errors.dart';
import '../services/session_context_store.dart';
import '../services/session_api.dart';
import 'manual_entry_screen.dart';
import 'management_screen.dart';
import 'passenger_list_screen.dart';
import 'passenger_reports_screen.dart';
import 'profile_screen.dart';
import 'scan_screen.dart';
import 'login_screen.dart';
import '../widgets/piona_date_picker.dart';
import '../widgets/piona_shell_scaffold.dart';

import 'home_design_tokens.dart';
import 'home_models.dart';

part 'home_widgets.part.dart';

const Animation<Offset> _kZeroOffsetAnim =
    AlwaysStoppedAnimation<Offset>(Offset.zero);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.userInfo});
  final HomeUserInfo? userInfo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const HomeUserInfo _defaultUser = HomeUserInfo();
  final SessionApi _sessionApi = SessionApi();
  VoidCallback? _sessionListener;
  Timer? _scanSyncTimer;
  final SessionContextStore _session = SessionContextStore.instance;

  Timer? _timeTimer;
  DateTime _currentTime = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  int? _selectedHourlyIndex;

  AnimationController? _entranceController;
  AnimationController? _pulseController;
  AnimationController? _shimmerController;
  List<Animation<double>> _staggeredFades = [];
  List<Animation<Offset>> _staggeredSlides = [];

  int _totalPassengers = 0;
  int _activeFlights = 0;
  int _adultPassengers = 0;
  int _infantPassengers = 0;
  int _normalPassengers = 0;
  int _transitPassengers = 0;
  final Set<String> _activeFlightKeys = <String>{};

  final Map<String, HomeInsightFlightRoute> _flightRoutesByKey = {};
  final Map<String, int> _scanPointCounts = {};
  final Map<String, int> _hourlyCounts = {};

  HomeUserInfo get _user => widget.userInfo ?? _defaultUser;

  /// Role from [SessionContextStore] after login (Admin / Officer).
  String get _sessionRoleLabel {
    final raw = SessionContextStore.instance.role.trim();
    return switch (raw.toLowerCase()) {
      'admin' => 'Admin',
      'it' => 'IT',
      'officer' => 'Scan',
      'scan' || 'scanner' => 'Scan',
      'view' || 'viewer' => 'View',
      _ => raw.isNotEmpty ? raw : _user.role,
    };
  }

  Animation<double> _fade(int i) => _staggeredFades.length > i
      ? _staggeredFades[i]
      : kAlwaysCompleteAnimation;
  Animation<Offset> _slide(int i) =>
      _staggeredSlides.length > i ? _staggeredSlides[i] : _kZeroOffsetAnim;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _selectedDate = _currentTime;

    _sessionListener = () {
      if (!mounted) return;
      if (SessionContextStore.instance.isLoggedIn) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    };
    SessionContextStore.instance.addListener(_sessionListener!);

    _timeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() => _currentTime = DateTime.now());
      },
    );

    final entrance = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    final pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    final shimmer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();

    _staggeredFades = List.generate(7, (i) {
      final s = i * 0.10, e = (s + 0.45).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: entrance, curve: Interval(s, e, curve: Curves.easeOut)));
    });
    _staggeredSlides = List.generate(7, (i) {
      final s = i * 0.10, e = (s + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero)
          .animate(CurvedAnimation(
              parent: entrance,
              curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });

    _entranceController = entrance;
    _pulseController = pulse;
    _shimmerController = shimmer;
    entrance.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncScansForSelectedDate(replace: true);
    });

    // Keep session alive so scan point "active" is real-time across devices.
    SessionContextStore.instance.startHeartbeat(
      ping: (token) async {
        try {
          await _sessionApi.ping(bearerToken: token);
        } on UnauthorizedException {
          SessionContextStore.instance.clearSession();
        }
      },
    );

    _scanSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _syncScansForSelectedDate(replace: false);
    });
  }

  String _fmtIsoDay(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _syncScansForSelectedDate({required bool replace}) async {
    final d = _selectedDate;
    final sessionAirport = _session.originCode.trim();
    await PassengerScanStore.instance.loadFromBackend(
      date: _fmtIsoDay(d),
      airportCode:
          _session.allAirports ? null : (sessionAirport.isEmpty ? null : sessionAirport),
      since: replace ? null : PassengerScanStore.instance.lastRefreshedAt,
      replace: replace,
    );
    if (!mounted) return;
    setState(_hydrateInsightsFromStore);
  }

  /// Rebuild KPI / insight maps from [PassengerScanStore] (e.g. after opening
  /// Home via navbar following a scan that replaced this route).
  void _hydrateInsightsFromStore() {
    final records = PassengerScanStore.instance.records;
    _flightRoutesByKey.clear();
    _scanPointCounts.clear();
    _hourlyCounts.clear();
    _activeFlightKeys.clear();
    _totalPassengers = 0;
    _activeFlights = 0;
    _adultPassengers = 0;
    _infantPassengers = 0;
    _normalPassengers = 0;
    _transitPassengers = 0;

    final sd = _selectedDate;
    for (final r in records) {
      // Store timestamps are parsed from backend (UTC). Always bucket & compare
      // using local time so the UI matches WIB on device.
      final t = r.scannedAt.toLocal();
      final sdLocal = DateTime(sd.year, sd.month, sd.day);
      final tLocalDay = DateTime(t.year, t.month, t.day);
      if (tLocalDay != sdLocal) {
        continue;
      }

      _totalPassengers += 1;
      final flight = r.flight;
      if (flight != 'N/A') {
        _activeFlightKeys.add(flight);
      }

      final origin = r.origin;
      final destination = r.destination;
      final route = (origin.isEmpty ||
              origin == 'N/A' ||
              destination.isEmpty ||
              destination == 'N/A')
          ? 'N/A'
          : '$origin-$destination';
      final key = '$flight|$route';
      final prev = _flightRoutesByKey[key];
      _flightRoutesByKey[key] = HomeInsightFlightRoute(
        flight: flight,
        passengers: (prev?.passengers ?? 0) + 1,
        route: route,
        changePercent: 0.0,
      );

      final sp = r.scanPoint.trim();
      final scanPoint = (sp.isEmpty || sp == 'N/A') ? _user.airportName : sp;
      _scanPointCounts[scanPoint] = (_scanPointCounts[scanPoint] ?? 0) + 1;

      final hourLabel = '${t.hour.toString().padLeft(2, '0')}:00';
      _hourlyCounts[hourLabel] = (_hourlyCounts[hourLabel] ?? 0) + 1;

      final c = r.passengerType.trim().toLowerCase();
      final isInfant = c.contains('inf');
      if (isInfant) {
        _infantPassengers += 1;
      } else {
        _adultPassengers += 1;
      }

      if (r.category == 'Transit') {
        _transitPassengers += 1;
      } else {
        _normalPassengers += 1;
      }
    }
    _activeFlights = _activeFlightKeys.length;
  }

  @override
  void dispose() {
    final l = _sessionListener;
    if (l != null) {
      SessionContextStore.instance.removeListener(l);
      _sessionListener = null;
    }
    _scanSyncTimer?.cancel();
    _timeTimer?.cancel();
    _entranceController?.dispose();
    _pulseController?.dispose();
    _shimmerController?.dispose();
    super.dispose();
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String get _greeting {
    final h = _currentTime.hour;
    if (h < 12) return 'Selamat Pagi';
    if (h < 15) return 'Selamat Siang';
    if (h < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  String get _timeStr => '${_currentTime.hour.toString().padLeft(2, '0')}:'
      '${_currentTime.minute.toString().padLeft(2, '0')}:'
      '${_currentTime.second.toString().padLeft(2, '0')}';

  String get _dateStr {
    const days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu'
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    final d = _selectedDate;
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PionaShellScaffold(
      currentNav: PionaNavItem.home,
      // Light: same gray as Scan so extendBody + floating nav match Transit screen.
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : AppTheme.shellScaffoldLight,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroHeader(context, isDark),
              _buildScrollBody(context, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ Hero header (top bar + greeting + kpi all in one gradient container) â”€â”€

  Widget _buildHeroHeader(BuildContext context, bool isDark) {
    return AnimatedBuilder(
      animation: _entranceController ?? kAlwaysCompleteAnimation,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF0A1628),
                      Color(0xFF0D2347),
                      Color(0xFF061020)
                    ]
                  : const [
                      Color(0xFF1A3A7A),
                      Color(0xFF2557C7),
                      Color(0xFF1040A8)
                    ],
            ),
          ),
          child: Stack(
            children: [
              // Decorative orbs
              _buildOrbs(isDark),
              // Diagonal accent line
              Positioned.fill(child: _DiagonalAccent()),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBar(context, isDark),
                    const SizedBox(height: 18),
                    FadeTransition(
                        opacity: _fade(0),
                        child: SlideTransition(
                            position: _slide(0),
                            child: _buildGreetingRow(context, isDark))),
                    const SizedBox(height: 12),
                    FadeTransition(
                        opacity: _fade(1),
                        child: SlideTransition(
                            position: _slide(1),
                            child: _buildDateTimeChip(context, isDark))),
                    const SizedBox(height: 16),
                    FadeTransition(
                        opacity: _fade(2),
                        child: SlideTransition(
                            position: _slide(2),
                            child: _buildQuickStatsRow(context, isDark))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrbs(bool isDark) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(children: [
          Positioned(
              top: -50,
              right: -30,
              child: _Orb(180, isDark ? const Color(0xFF3D7FFF) : Colors.white,
                  isDark ? 0.06 : 0.07)),
          Positioned(
              top: 60,
              left: -50,
              child: _Orb(120, isDark ? const Color(0xFF00C8E8) : Colors.white,
                  isDark ? 0.04 : 0.05)),
          Positioned(
              bottom: 0,
              right: 80,
              child: _Orb(70, const Color(0xFF3D7FFF), 0.08)),
          Positioned(
              bottom: 20,
              left: 120,
              child: _Orb(40, const Color(0xFF00C8E8), 0.10)),
        ]),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark) {
    final appTheme = AppThemeScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HomeTopBrandProfile(
          onTap: () => _openProfile(context),
        ),
        const Spacer(),
        // Live indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: HomeDesignTokens.accentGreen.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: HomeDesignTokens.accentGreen.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(color: HomeDesignTokens.accentGreen, size: 6),
              const SizedBox(width: 5),
              Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: HomeDesignTokens.accentGreen,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        AnimatedBuilder(
          animation: PassengerScanStore.instance,
          builder: (context, _) {
            final pending = PassengerScanStore.instance.pendingSyncCount;
            final lastErr = PassengerScanStore.instance.lastPostErrorMessage;
            if (pending <= 0 && (lastErr == null || lastErr.trim().isEmpty)) {
              return const SizedBox.shrink();
            }
            final hasError = lastErr != null && lastErr.trim().isNotEmpty;
            final color = hasError ? Colors.red.shade300 : HomeDesignTokens.accentAmber;
            final label = pending > 0 ? 'SYNC $pending' : 'SYNC';
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  final msg = PassengerScanStore.instance
                      .consumeLastPostErrorMessage();
                  if (msg == null || msg.trim().isEmpty) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasError
                            ? Icons.cloud_off_rounded
                            : Icons.cloud_upload_rounded,
                        size: 14,
                        color: color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // Dark mode toggle
        _IconBtn(
          icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          onTap: () {
            if (appTheme != null) {
              appTheme.setThemeMode(appTheme.themeMode == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light);
            }
          },
        ),
      ],
    );
  }

  Widget _buildGreetingRow(BuildContext context, bool isDark) {
    final session = SessionContextStore.instance;
    final displayUserId = session.displayUserId.trim();
    final displayName =
        displayUserId.isEmpty ? _user.displayName : displayUserId;
    final airportCode = session.originCode.trim().isEmpty
        ? _user.airportCode
        : session.originCode.trim();
    final scanPoint = session.scanPoint.trim().isEmpty
        ? _user.airportName
        : session.scanPoint.trim();
    final roleAt = '$_sessionRoleLabel · $airportCode / $scanPoint';

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: HomeDesignTokens.accentAmber.withOpacity(0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: HomeDesignTokens.accentAmber.withOpacity(0.3)),
              ),
              child: Text(_greeting,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: HomeDesignTokens.accentAmber,
                      letterSpacing: 0.4)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(displayName,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.1)),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: HomeDesignTokens.accentCyan),
            ),
            const SizedBox(width: 6),
            Text(roleAt,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.65),
                    fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
      const SizedBox(width: 12),
      // Clock card
      GestureDetector(
        onTap: () => _openProfile(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12)
            ],
          ),
          child: Column(children: [
            Text(_timeStr,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                    letterSpacing: 1.5)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: HomeDesignTokens.accentCyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('WIB',
                  style: TextStyle(
                      fontSize: 9,
                      color: HomeDesignTokens.accentCyan,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildDateTimeChip(BuildContext context, bool isDark) {
    final baseBg = Colors.white.withOpacity(0.08);
    final baseBorder = Colors.white.withOpacity(0.15);

    Widget pill({
      required Widget child,
      VoidCallback? onTap,
    }) {
      final content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: baseBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: baseBorder),
        ),
        child: child,
      );
      if (onTap == null) return content;
      return GestureDetector(onTap: onTap, child: content);
    }

    final dateChip = pill(
      onTap: () => _pickDate(context),
      child: Row(children: [
        Icon(Icons.calendar_today_rounded,
            size: 13, color: Colors.white.withOpacity(0.7)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _dateStr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Icon(Icons.expand_more_rounded,
            size: 16, color: Colors.white.withOpacity(0.6)),
      ]),
    );

    final allAirportsChip = pill(
      child: Row(children: [
        Icon(Icons.public_rounded,
            size: 14, color: Colors.white.withOpacity(0.75)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'All Airports',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Transform.scale(
          scale: 0.85,
          child: Switch.adaptive(
            value: _session.allAirports,
            onChanged: (v) {
              _session.setAllAirports(v);
              _syncScansForSelectedDate(replace: true);
            },
            activeColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ]),
    );

    return Row(
      children: [
        Expanded(child: dateChip),
        const SizedBox(width: 10),
        Expanded(child: allAirportsChip),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showPionaDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _selectedHourlyIndex = null;
        _totalPassengers = 0;
        _activeFlights = 0;
        _adultPassengers = 0;
        _infantPassengers = 0;
        _normalPassengers = 0;
        _transitPassengers = 0;
        _activeFlightKeys.clear();
        _flightRoutesByKey.clear();
        _scanPointCounts.clear();
        _hourlyCounts.clear();
      });
      _syncScansForSelectedDate(replace: true);
    }
  }

  Widget _buildQuickStatsRow(BuildContext context, bool isDark) {
    final cards = [
      _KpiData('Total Passengers', '$_totalPassengers', 'yesterday · 0', null,
          Icons.groups_rounded, HomeDesignTokens.accentAmber, KpiTrend.flat, 0),
      _KpiData('Active Flights', '$_activeFlights', 'yesterday · 0', null,
          Icons.flight_takeoff_rounded, HomeDesignTokens.accentPink, KpiTrend.flat, 0),
      _KpiData(
          'Passenger Type',
          '$_adultPassengers / $_infantPassengers',
          'Adult / Infant',
          'yesterday · 0/0',
          Icons.badge_rounded,
          HomeDesignTokens.accentGreen,
          KpiTrend.flat,
          0),
      _KpiData(
          'Passenger Category',
          '$_normalPassengers / $_transitPassengers',
          'Normal / Transit',
          'yesterday · 0/0',
          Icons.swap_horiz_rounded,
          HomeDesignTokens.accentPurple,
          KpiTrend.flat,
          0),
    ];
    return Column(children: [
      Row(children: [
        Expanded(
            child: _KpiCard(
                data: cards[0], isDark: isDark, shimmer: _shimmerController)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiCard(
                data: cards[1], isDark: isDark, shimmer: _shimmerController)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: _KpiCard(
                data: cards[2], isDark: isDark, shimmer: _shimmerController)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiCard(
                data: cards[3], isDark: isDark, shimmer: _shimmerController)),
      ]),
    ]);
  }

  /// Passenger List, Manual Entry, Reports, Management â€” under â€œAll Passenger
  /// Summaryâ€; wide layouts use a 2Ã—2 grid to reduce vertical stacking.
  Widget _buildAllPassengerSummaryCards(BuildContext context) {
    final pulse = _pulseController;
    if (pulse == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final passengerList = _ScanCard(
          title: 'Passenger List',
          subtitle: 'Daftar penumpang hasil scan',
          icon: Icons.people_alt_rounded,
          gradientColors: const [Color(0xFF1B4FD6), Color(0xFF3F6ED2)],
          accentColor: HomeDesignTokens.accentBlue,
          pulseController: pulse,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PassengerListScreen(),
            ),
          ),
        );
        final manual = _ScanCard(
          title: 'Manual Entry',
          subtitle: 'Menambahkan data boarding pass secara manual',
          icon: Icons.edit_note_rounded,
          gradientColors: const [Color(0xFF6366F1), Color(0xFF4338CA)],
          accentColor: HomeDesignTokens.accentPurple,
          pulseController: pulse,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ManualEntryScreen(),
            ),
          ),
        );
        final reports = _ScanCard(
          title: 'Reports',
          subtitle: 'Ringkasan dan daftar penumpang per tanggal',
          icon: Icons.assessment_rounded,
          gradientColors: const [Color(0xFF0D9488), Color(0xFF0F766E)],
          accentColor: HomeDesignTokens.accentGreen,
          pulseController: pulse,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PassengerReportsScreen(),
            ),
          ),
        );
        final management = _ScanCard(
          title: 'Management',
          subtitle: 'Pengaturan dan administrasi data',
          icon: Icons.manage_accounts_rounded,
          gradientColors: const [Color(0xFF1E40AF), Color(0xFF0EA5E9)],
          accentColor: HomeDesignTokens.accentCyan,
          pulseController: pulse,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ManagementScreen(),
            ),
          ),
        );

        final wide = constraints.maxWidth >= 560;
        if (wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: passengerList),
                  const SizedBox(width: gap),
                  Expanded(child: manual),
                ],
              ),
              const SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: reports),
                  const SizedBox(width: gap),
                  Expanded(child: management),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            passengerList,
            const SizedBox(height: gap),
            manual,
            const SizedBox(height: gap),
            reports,
            const SizedBox(height: gap),
            management,
          ],
        );
      },
    );
  }

  // â”€â”€ Scroll body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildScrollBody(BuildContext context, bool isDark) {
    final surface = isDark ? const Color(0xFF0B1220) : Colors.white;
    final navReserve = PionaFloatingNavBar.reserveBottomPadding(context);
    final bottomPad = navReserve + 12;

    return Container(
      // Keep background transparent so the rounded top corners reveal the blue
      // hero header behind (no â€œwhite lineâ€ behind the overlay card).
      color: Colors.transparent,
      child: Transform.translate(
        // Slight overlap so it reads like an overlay card, but not too tight
        // against the KPI header area.
        offset: const Offset(0, -8),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(26),
              topRight: Radius.circular(26),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                blurRadius: 22,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 36, 18, bottomPad),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // â”€â”€ Scan section â”€â”€
                  FadeTransition(
                      opacity: _fade(3),
                      child: SlideTransition(
                        position: _slide(3),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(
                                  label: 'Scan Boarding Pass',
                                  icon: Icons.qr_code_scanner_rounded,
                                  isDark: isDark),
                              const SizedBox(height: 14),
                              if (_pulseController != null) ...[
                                _ScanCard(
                                  title: 'Scan Normal',
                                  subtitle:
                                      'Boarding pass penerbangan langsung',
                                  icon: Icons.flight_rounded,
                                  gradientColors: const [
                                    Color(0xFF3F6ED2),
                                    Color(0xFF3359B0)
                                  ],
                                  accentColor: HomeDesignTokens.accentBlue,
                                  pulseController: _pulseController!,
                                  onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => ScanScreen(
                                              mode: ScanMode.normal,
                                              scanPointFallback:
                                                  SessionContextStore
                                                          .instance.scanPoint
                                                          .trim()
                                                          .isEmpty
                                                      ? _user.airportName
                                                      : SessionContextStore
                                                          .instance.scanPoint
                                                          .trim(),
                                              onScanSuccess:
                                                  _ingestScanToInsights))),
                                ),
                                const SizedBox(height: 12),
                                _ScanCard(
                                  title: 'Scan Transit',
                                  subtitle: 'Boarding pass penumpang transit',
                                  icon: Icons.transfer_within_a_station_rounded,
                                  gradientColors: const [
                                    Color(0xFF0A6EA8),
                                    Color(0xFF0A4F7A)
                                  ],
                                  accentColor: HomeDesignTokens.accentCyan,
                                  pulseController: _pulseController!,
                                  onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => ScanScreen(
                                              mode: ScanMode.transit,
                                              scanPointFallback:
                                                  SessionContextStore
                                                          .instance.scanPoint
                                                          .trim()
                                                          .isEmpty
                                                      ? _user.airportName
                                                      : SessionContextStore
                                                          .instance.scanPoint
                                                          .trim(),
                                              onScanSuccess:
                                                  _ingestScanToInsights))),
                                ),
                              ],
                            ]),
                      )),

                  const SizedBox(height: 28),

                  // â”€â”€ All Passenger Summary â”€â”€
                  FadeTransition(
                      opacity: _fade(4),
                      child: SlideTransition(
                        position: _slide(4),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(
                                  label: 'All Passenger Summary',
                                  icon: Icons.groups_rounded,
                                  isDark: isDark),
                              const SizedBox(height: 14),
                              _buildAllPassengerSummaryCards(context),
                            ]),
                      )),

                  const SizedBox(height: 28),

                  // â”€â”€ Insights â”€â”€
                  FadeTransition(
                      opacity: _fade(5),
                      child: SlideTransition(
                        position: _slide(5),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(
                                  label: 'Insights',
                                  icon: Icons.bar_chart_rounded,
                                  isDark: isDark),
                              const SizedBox(height: 16),
                              _buildInsights(context, isDark),
                            ]),
                      )),

                  const SizedBox(height: 24),

                  // â”€â”€ Info card â”€â”€
                  FadeTransition(
                      opacity: _fade(6),
                      child: SlideTransition(
                        position: _slide(6),
                        child: _InfoBanner(isDark: isDark),
                      )),
                ]),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Insights â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _ingestScanToInsights(ScanResultDisplay result, ScanMode mode) {
    if (!mounted) return;
    final now = DateTime.now();

    // [PassengerScanStore] is filled inside [ScanScreen] â€” only update KPI here.

    // Home insights/KPI remain date-scoped to the selected date.
    if (now.year != _selectedDate.year ||
        now.month != _selectedDate.month ||
        now.day != _selectedDate.day) {
      return;
    }

    final origin = result.origin.trim();
    final destination = result.destination.trim();
    final route = (origin.isEmpty || destination.isEmpty)
        ? 'N/A'
        : '$origin-$destination';
    final flight =
        result.airlineCode.trim().isEmpty ? 'N/A' : result.airlineCode.trim();
    final key = '$flight|$route';
    final prev = _flightRoutesByKey[key];
    _flightRoutesByKey[key] = HomeInsightFlightRoute(
        flight: flight,
        passengers: (prev?.passengers ?? 0) + 1,
        route: route,
        changePercent: 0.0);

    final sp = result.gate.trim();
    final scanPoint = (sp.isEmpty || sp == 'N/A') ? _user.airportName : sp;
    _scanPointCounts[scanPoint] = (_scanPointCounts[scanPoint] ?? 0) + 1;

    final hourLabel = '${now.hour.toString().padLeft(2, '0')}:00';
    _hourlyCounts[hourLabel] = (_hourlyCounts[hourLabel] ?? 0) + 1;

    setState(() {
      _totalPassengers += 1;

      if (flight != 'N/A') {
        _activeFlightKeys.add(flight);
        _activeFlights = _activeFlightKeys.length;
      }

      final c = result.criteria.trim().toLowerCase();
      final isInfant = c.contains('inf');
      if (isInfant) {
        _infantPassengers += 1;
      } else {
        _adultPassengers += 1;
      }

      if (mode == ScanMode.transit) {
        _transitPassengers += 1;
      } else {
        _normalPassengers += 1;
      }
    });
  }

  Widget _buildInsights(BuildContext context, bool isDark) {
    final topFlights = _flightRoutesByKey.values.toList()
      ..sort((a, b) => b.passengers.compareTo(a.passengers));

    final scanPointRows = _scanPointCounts.entries
        .map((e) => (scanPoint: e.key, passengers: e.value))
        .toList()
      ..sort((a, b) => b.passengers.compareTo(a.passengers));

    final totalSP = scanPointRows
        .fold<int>(0, (s, x) => s + x.passengers)
        .clamp(1, 1 << 30);

    String wlLabel(double pct) {
      if (pct >= 0.4) return 'Highest';
      if (pct >= 0.25) return 'High';
      if (pct >= 0.12) return 'Medium';
      return 'Low';
    }

    final scanPoints = scanPointRows.map((r) {
      final pct = r.passengers / totalSP;
      return HomeInsightScanPoint(
          scanPoint: r.scanPoint,
          passengers: r.passengers,
          percent: pct,
          workloadLabel: wlLabel(pct));
    }).toList();

    int hourFrom(String l) => int.tryParse(l.split(':').first) ?? 0;
    final flow = _hourlyCounts.entries
        .map((e) =>
            HomeInsightHourlyFlowPoint(hourLabel: e.key, passengers: e.value))
        .toList()
      ..sort((a, b) => hourFrom(a.hourLabel).compareTo(hourFrom(b.hourLabel)));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _InsightPanel(
          isDark: isDark,
          title: 'Top 5 Flights & Routes',
          subtitle: 'By passenger count',
          child: _TopFlightsTable(isDark: isDark, rows: topFlights)),
      const SizedBox(height: 14),
      _InsightPanel(
          isDark: isDark,
          title: 'Scan Point Activity',
          subtitle: 'Workload per gate',
          child: _ScanPointTable(isDark: isDark, rows: scanPoints)),
      const SizedBox(height: 14),
      _InsightPanel(
          isDark: isDark,
          title: 'Passenger Flow / Hour',
          subtitle: 'Tap any bar for detail',
          child: _HourlyFlowChart(
            isDark: isDark,
            points: flow,
            selectedIndex: _selectedHourlyIndex,
            onSelect: (idx) => setState(() => _selectedHourlyIndex = idx),
          )),
    ]);
  }

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      pageBuilder: (context, animation, _) => const ProfileScreen(),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    ));
  }
}

