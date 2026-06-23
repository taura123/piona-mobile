import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_theme_scope.dart';
import '../theme/app_theme.dart';
import '../services/session_context_store.dart';
import '../services/users_api.dart';
import '../widgets/piona_shell_scaffold.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  AnimationController? _entranceCtrl;
  List<Animation<double>> _fades = [];
  List<Animation<Offset>> _slides = [];

  final UsersApi _usersApi = UsersApi();

  /// From `GET /me` when online (UUID user id).
  String? _backendUserId;

  /// From `GET /me` — may match [SessionContextStore.displayUserId].
  String? _meUsername;

  /// From `GET /me` — may match [SessionContextStore.role].
  String? _meRole;

  String? _appVersionLabel;

  SessionContextStore get _session => SessionContextStore.instance;

  String _initialsFromUserId(String userId) {
    final s = userId.trim();
    if (s.isEmpty) return 'U';
    final letters = s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (letters.isEmpty) return 'U';
    return letters.substring(0, letters.length >= 2 ? 2 : 1).toUpperCase();
  }

  Animation<double> _fade(int i) =>
      (_fades.length > i) ? _fades[i] : kAlwaysCompleteAnimation;
  Animation<Offset> _slide(int i) => (_slides.length > i)
      ? _slides[i]
      : const AlwaysStoppedAnimation(Offset.zero);

  @override
  void initState() {
    super.initState();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    final fades = List<Animation<double>>.generate(6, (i) {
      final start = (i * 0.10).clamp(0.0, 0.7);
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
            parent: ctrl, curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });

    final slides = List<Animation<Offset>>.generate(6, (i) {
      final start = (i * 0.10).clamp(0.0, 0.7);
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero)
          .animate(
        CurvedAnimation(
            parent: ctrl,
            curve: Interval(start, end, curve: Curves.easeOutCubic)),
      );
    });

    _entranceCtrl = ctrl;
    _fades = fades;
    _slides = slides;
    ctrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPackageInfo());
      unawaited(_syncMeFromBackend());
    });
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel =
            '${info.appName} v${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _appVersionLabel = 'PIONA Mobile');
    }
  }

  Future<void> _syncMeFromBackend() async {
    final token = _session.jwtToken?.trim();
    if (token == null || token.isEmpty) return;
    try {
      final me = await _usersApi.fetchMe(bearerToken: token);
      if (!mounted) return;
      setState(() {
        _backendUserId = me.id;
        _meUsername = me.username;
        _meRole = me.role;
      });
    } catch (_) {
      // Offline or token invalid — UI still uses session store.
    }
  }

  @override
  void dispose() {
    _entranceCtrl?.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        return PionaShellScaffold(
          currentNav: PionaNavItem.home,
          backgroundColor:
              isDark ? const Color(0xFF0D1117) : AppTheme.shellScaffoldLight,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(context, isDark),
                Expanded(
                  child: _buildBody(context, isDark),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Header with avatar ─────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, bool isDark) {
    final appTheme = AppThemeScope.of(context);
    final iconBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.2);
    final userId = (_meUsername ?? _session.displayUserId).trim();
    final airportCode = _session.originCode;
    final scanPoint = _session.scanPoint;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF161D2B), Color(0xFF0D1117)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
              ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background orbs
          _buildOrbs(isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            child: Column(
              children: [
                // Top nav row
                Row(
                  children: [
                    Material(
                      color: iconBg,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.hardEdge,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Profil Petugas',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Dark mode toggle
                    Material(
                      color: iconBg,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.hardEdge,
                      child: InkWell(
                        onTap: () {
                          if (appTheme != null) {
                            final next = appTheme.themeMode == ThemeMode.light
                                ? ThemeMode.dark
                                : ThemeMode.light;
                            appTheme.setThemeMode(next);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Icon(
                            isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Avatar + name
                FadeTransition(
                  opacity: _fade(0),
                  child: SlideTransition(
                    position: _slide(0),
                    child: Column(
                      children: [
                        // Avatar circle
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.35),
                                Colors.white.withValues(alpha: 0.15),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 2.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _initialsFromUserId(userId),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          userId.isEmpty ? '—' : userId,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (_meRole ?? _session.role).trim().isEmpty
                              ? 'Petugas'
                              : (_meRole ?? _session.role).trim(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Role + airport badge row
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            _HeaderBadge(
                              icon: Icons.badge_outlined,
                              label: userId.isEmpty ? '—' : userId,
                              isDark: isDark,
                            ),
                            _HeaderBadge(
                              icon: Icons.flight_rounded,
                              label: airportCode.isEmpty ? '—' : airportCode,
                              isDark: isDark,
                            ),
                            _HeaderBadge(
                              icon: Icons.pin_drop_outlined,
                              label: scanPoint.isEmpty ? '—' : scanPoint,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrbs(bool isDark) {
    final c = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.white.withValues(alpha: 0.06);
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(children: [
          Positioned(top: -50, right: -40, child: _orb(160, c)),
          Positioned(top: 20, left: -60, child: _orb(120, c)),
          Positioned(bottom: -20, right: 60, child: _orb(70, c)),
        ]),
      ),
    );
  }

  Widget _orb(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  // ── Scroll body ────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, bool isDark) {
    final panelColor = isDark ? const Color(0xFF111827) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            40 + PionaFloatingNavBar.reserveBottomPadding(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Gate Assignment card ────────────────────────────────────
              _Animated(
                  fade: _fade(1),
                  slide: _slide(1),
                  child: _buildGateCard(context, isDark)),
              const SizedBox(height: 16),

              // ── Login context card (from login) ─────────────────────────
              _Animated(
                fade: _fade(2),
                slide: _slide(2),
                child: _buildLoginContextCard(context, isDark),
              ),
              const SizedBox(height: 24),

              // ── Logout button ───────────────────────────────────────────
              _Animated(
                  fade: _fade(5),
                  slide: _slide(5),
                  child: _buildLogoutButton(context, isDark)),
              const SizedBox(height: 8),

              // App version
              Center(
                child: Text(
                  _appVersionLabel ?? 'PIONA Mobile',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondaryColor(context)
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Gate Assignment Card ───────────────────────────────────────────────────

  Widget _buildGateCard(BuildContext context, bool isDark) {
    final airportCode = _session.originCode;
    final airportName = _session.airportName;
    final scanPoint = _session.scanPoint;
    return _SectionCard(
      isDark: isDark,
      accentColor: AppTheme.primaryBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.door_sliding_outlined,
            label: 'Penugasan Gate',
            color: AppTheme.primaryBlue,
            context: context,
          ),
          const SizedBox(height: 16),

          // Big gate display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.flight_takeoff_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scanPoint.isEmpty ? '—' : scanPoint,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        airportName.isEmpty
                            ? 'Bandara: ${airportCode.isEmpty ? '—' : airportCode}'
                            : airportName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Airport code badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    airportCode.isEmpty ? '—' : airportCode,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Airport + status row (keep simple)
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.location_on_outlined,
                  label: 'Bandara',
                  value: airportCode.isEmpty ? '—' : airportCode,
                  isDark: isDark,
                  context: context,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoTile(
                  icon: Icons.verified_rounded,
                  label: 'Status',
                  value: 'Aktif Bertugas',
                  isDark: isDark,
                  context: context,
                  valueColor: AppTheme.validGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Login Context Card (from LoginScreen) ──────────────────────────────────

  Widget _buildLoginContextCard(BuildContext context, bool isDark) {
    final userId = (_meUsername ?? _session.displayUserId).trim();
    final airportCode = _session.originCode;
    final airportName = _session.airportName;
    final scanPoint = _session.scanPoint;
    final backendId = _backendUserId?.trim();

    return _SectionCard(
      isDark: isDark,
      accentColor: const Color(0xFF8B5CF6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.person_outline_rounded,
            label: 'Data Login',
            color: const Color(0xFF8B5CF6),
            context: context,
          ),
          const SizedBox(height: 14),
          _ProfileRow(
            icon: Icons.badge_outlined,
            label: 'User ID',
            value: userId.isEmpty ? '—' : userId,
            isDark: isDark,
            context: context,
            onCopy: userId.trim().isEmpty
                ? null
                : () => _copyToClipboard(context, userId),
          ),
          if (backendId != null && backendId.isNotEmpty) ...[
            _Divider(isDark: isDark),
            _ProfileRow(
              icon: Icons.fingerprint_rounded,
              label: 'ID Akun',
              value: backendId,
              isDark: isDark,
              context: context,
              onCopy: () => _copyToClipboard(context, backendId),
            ),
          ],
          _Divider(isDark: isDark),
          _ProfileRow(
            icon: Icons.flight_rounded,
            label: 'Bandara',
            value: airportName.isEmpty
                ? (airportCode.isEmpty ? '—' : airportCode)
                : '$airportCode — $airportName',
            isDark: isDark,
            context: context,
          ),
          _Divider(isDark: isDark),
          _ProfileRow(
            icon: Icons.pin_drop_outlined,
            label: 'Checkpoint',
            value: scanPoint.isEmpty ? '—' : scanPoint,
            isDark: isDark,
            context: context,
          ),
        ],
      ),
    );
  }

  // ── Logout Button ──────────────────────────────────────────────────────────

  Widget _buildLogoutButton(BuildContext context, bool isDark) {
    return Column(
      children: [
        // Logout button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _confirmLogout(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color:
                    AppTheme.invalidRed.withValues(alpha: isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.invalidRed.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded,
                      color: AppTheme.invalidRed, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Keluar dari Akun',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.invalidRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Disalin: $text'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C2333) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.invalidRed.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child:
              Icon(Icons.logout_rounded, color: AppTheme.invalidRed, size: 26),
        ),
        title: const Text(
          'Keluar dari Akun?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Text(
          'Sesi Anda akan diakhiri dan Anda akan diarahkan ke halaman login.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondaryColor(context),
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: AppTheme.borderColor(context)),
                  ),
                  child: const Text('Batal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                          builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.invalidRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Keluar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a child in fade + slide transition.
class _Animated extends StatelessWidget {
  const _Animated({
    required this.fade,
    required this.slide,
    required this.child,
  });

  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
}

/// Consistent card container with left accent stripe.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    required this.isDark,
    required this.accentColor,
  });

  final Widget child;
  final bool isDark;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2333) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(color: accentColor, width: 3.5),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : accentColor.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.label,
    required this.color,
    required this.context,
  });

  final IconData icon;
  final String label;
  final Color color;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimaryColor(context),
            ),
          ),
        ],
      );
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    required this.context,
    this.onCopy,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final BuildContext context;
  final VoidCallback? onCopy;
  final Color? valueColor;

  @override
  Widget build(BuildContext ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: AppTheme.textSecondaryColor(context)
                    .withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondaryColor(context),
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppTheme.textPrimaryColor(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onCopy != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onCopy,
                child: Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: AppTheme.textSecondaryColor(context)
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    required this.context,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final BuildContext context;
  final Color? valueColor;

  @override
  Widget build(BuildContext ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF4F6FB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 13,
                    color: AppTheme.textSecondaryColor(context)
                        .withValues(alpha: 0.7)),
                const SizedBox(width: 5),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                    color: AppTheme.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppTheme.textPrimaryColor(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.06),
      );
}
