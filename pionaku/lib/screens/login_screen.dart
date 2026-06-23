import 'package:flutter/material.dart';

import '../services/auth_api.dart';
import '../services/api_errors.dart';
import '../services/scan_points_api.dart';
import '../services/session_api.dart';
import '../services/session_context_store.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Layar login sesuai mockup: header biru #3F6ED2, form putih, fit to page.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Daftar bandara Indonesia di bawah naungan Injourney Airports.
const List<String> _airportOptions = [
  'CGK - Soekarno Hatta International Airport',
  'SRG - Jenderal Ahmad Yani Airport',
  'YIA - Yogyakarta International Airport',
  'SUB - Juanda International Airport',
  'KNO - Kualanamu International Airport',
  'DPS - I Gusti Ngurah Rai International Airport',
  'MDC - Sam Ratulangi International Airport',
  'BTH - Hang Nadim International Airport',
  'PLM - Sultan Mahmud Badaruddin II Airport',
  'UPG - Sultan Hasanuddin International Airport',
];

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isButtonPressed = false;
  bool _isLoading = false;
  String? _selectedAirport;
  String? _selectedCheckpoint;
  String? _openDropdownKey; // 'airport' | 'checkpoint' | null
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final AuthApi _authApi = AuthApi();
  final ScanPointsApi _scanPointsApi = ScanPointsApi();
  final SessionApi _sessionApi = SessionApi();
  List<String> _checkpointOptions = const <String>[];
  bool _loadingCheckpoints = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
    _loadCheckpoints();
  }

  @override
  void dispose() {
    _animController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadCheckpoints() async {
    if (_loadingCheckpoints) return;
    setState(() => _loadingCheckpoints = true);
    try {
      final items = await _scanPointsApi.listPublicScanPoints();
      final names = items
          .map((m) => (m['name'] as String?)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _checkpointOptions = names;
        _loadingCheckpoints = false;
        if (_selectedCheckpoint != null &&
            !_checkpointOptions.contains(_selectedCheckpoint)) {
          _selectedCheckpoint = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkpointOptions = const <String>[];
        _loadingCheckpoints = false;
      });
    }
  }

  Future<bool> _showConfirmLoginSessionDialog({
    required String username,
    required String airportLine,
    required String checkpoint,
  }) async {
    final airportCode =
        SessionContextStore.airportCodeFromOption(airportLine).trim();
    final airportSummary =
        airportCode.isNotEmpty ? airportCode : airportLine;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFC107).withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFF59E0B),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Confirm Login Session',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimaryColor(dialogContext),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please confirm your session details:',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondaryColor(dialogContext),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.borderColor(dialogContext),
                    ),
                  ),
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: AppTheme.textPrimaryColor(dialogContext),
                    ) ??
                        TextStyle(
                          height: 1.45,
                          color: AppTheme.textPrimaryColor(dialogContext),
                        ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Username: ',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: username),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Airport: ',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: airportSummary),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Scan Point: ',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(
                                text: checkpoint.isEmpty ? '—' : checkpoint,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            AppTheme.textPrimaryColor(dialogContext),
                        side: BorderSide(
                          color: AppTheme.borderColor(dialogContext),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Login'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _performLoginAfterConfirm({
    required String airportLine,
    required String checkpoint,
    required String username,
    required String password,
  }) async {
    final airportCode = SessionContextStore.airportCodeFromOption(airportLine);

    try {
      final res = await _authApi.login(
        username: username,
        password: password,
        airportCode: airportCode,
        checkpoint: checkpoint,
      );

      if (!mounted) return;

      SessionContextStore.instance.setFromLogin(
        airportOptionLine: airportLine,
        checkpoint: checkpoint,
        displayUserId: res.username,
        role: res.role,
        jwtToken: res.token,
      );
      SessionContextStore.instance.startHeartbeat(
        ping: (token) async {
          try {
            await _sessionApi.ping(bearerToken: token);
          } on UnauthorizedException {
            SessionContextStore.instance.clearSession();
          }
        },
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isLoading = false);
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Gagal login. Cek koneksi dan coba lagi.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _onLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();

    final airportLine = (_selectedAirport ?? '').trim();
    final checkpoint = (_selectedCheckpoint ?? '').trim();
    final username = _idController.text.trim();
    final password = _passwordController.text;

    final proceed = await _showConfirmLoginSessionDialog(
      username: username,
      airportLine: airportLine,
      checkpoint: checkpoint,
    );
    if (!mounted || !proceed) return;

    setState(() => _isLoading = true);
    await _performLoginAfterConfirm(
      airportLine: airportLine,
      checkpoint: checkpoint,
      username: username,
      password: password,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardOpen = keyboardInset > 0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final headerFraction = isKeyboardOpen ? 0.28 : 0.37;
    final horizontalPadding = screenWidth > 400 ? 28.0 : 20.0;

    return Scaffold(
      backgroundColor: AppTheme.primaryBlue,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final headerHeight = constraints.maxHeight * headerFraction;
            return Stack(
              children: [
                // Full-screen header background
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: headerHeight + 30,
                  child: _buildHeaderBackground(),
                ),
                Column(
                  children: [
                    // ── Header ──────────────────────────────────────────────
                    SizedBox(
                      height: headerHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _PionaLogo(),
                                SizedBox(height: isKeyboardOpen ? 8 : 12),
                                const Text(
                                  'PIONA',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 3,
                                  ),
                                ),
                                SizedBox(height: isKeyboardOpen ? 2 : 4),
                                Text(
                                  'Scanner Boarding Pass Penumpang',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        Colors.white.withValues(alpha: 0.88),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(height: isKeyboardOpen ? 10 : 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 1.5,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Icon(
                                        Icons.flight_takeoff_rounded,
                                        size: 18,
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                      ),
                                    ),
                                    Container(
                                      width: 36,
                                      height: 1.5,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── White Card ───────────────────────────────────────────
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surface(context),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(28),
                            topRight: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 60,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(32),
                            topRight: Radius.circular(32),
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              32,
                              horizontalPadding,
                              bottomPadding + 25,
                            ),
                            child: Form(
                              key: _formKey,
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: SlideTransition(
                                    position: _slideAnimation,
                                    child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Drag handle indicator
                                      Center(
                                        child: Container(
                                          width: 40,
                                          height: 4,
                                          margin:
                                              const EdgeInsets.only(bottom: 20),
                                          decoration: BoxDecoration(
                                            color: AppTheme.borderColor(context),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),

                                      // Title
                                      Text(
                                        'Selamat Datang',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.5,
                                          color:
                                              AppTheme.textPrimaryColor(context),
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Center(
                                        child: Container(
                                          width: 48,
                                          height: 3.5,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                AppTheme.primaryBlue,
                                                AppTheme.primaryBlueDark,
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Masuk untuk melanjutkan',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppTheme.textSecondaryColor(
                                              context),
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 32),

                                      // ID Field
                                      _buildTextField(
                                        context: context,
                                        controller: _idController,
                                        label: 'ID Petugas',
                                        hint: 'Masukkan ID Petugas',
                                        prefixIcon:
                                            Icons.badge_outlined,
                                        keyboardType: TextInputType.text,
                                        textInputAction: TextInputAction.next,
                                        validator: (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return 'ID Petugas wajib diisi';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Password Field
                                      _buildTextField(
                                        context: context,
                                        controller: _passwordController,
                                        label: 'Password',
                                        hint: 'Masukkan Password',
                                        prefixIcon: Icons.lock_outline_rounded,
                                        obscureText: _obscurePassword,
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _onLogin(),
                                        suffixIcon: IconButton(
                                          icon: AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            child: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                      .visibility_off_outlined,
                                              key: ValueKey(_obscurePassword),
                                              color:
                                                  AppTheme.textSecondaryColor(
                                                      context),
                                              size: 20,
                                            ),
                                          ),
                                          onPressed: () {
                                            setState(() => _obscurePassword =
                                                !_obscurePassword);
                                          },
                                        ),
                                        validator: (value) {
                                          if (value == null ||
                                              value.isEmpty) {
                                            return 'Password wajib diisi';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Dropdown Bandara
                                      _buildDropdownDownward(
                                        context: context,
                                        dropdownKey: 'airport',
                                        value: _selectedAirport,
                                        hint: '',
                                        label: 'Bandara',
                                        icon: Icons.flight_rounded,
                                        items: _airportOptions,
                                        onChanged: (value) => setState(
                                          () => _selectedAirport = value,
                                        ),
                                        validator: (value) {
                                          if (value == null ||
                                              value.isEmpty) {
                                            return 'Bandara wajib dipilih';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Dropdown Checkpoint
                                      _buildDropdownDownward(
                                        context: context,
                                        dropdownKey: 'checkpoint',
                                        value: _selectedCheckpoint,
                                        hint: '',
                                        label: 'Checkpoint',
                                        icon: Icons.location_on_outlined,
                                        items: _checkpointOptions.isNotEmpty
                                            ? _checkpointOptions
                                            : const <String>['Concordia'],
                                        onChanged: (value) => setState(
                                          () => _selectedCheckpoint = value,
                                        ),
                                        validator: (value) {
                                          if (value == null ||
                                              value.isEmpty) {
                                            return 'Checkpoint wajib dipilih';
                                          }
                                          return null;
                                        },
                                      ),

                                      const SizedBox(height: 20),

                                      // Login Button
                                      GestureDetector(
                                        onTapDown: (_) => setState(
                                            () => _isButtonPressed = true),
                                        onTapUp: (_) => setState(
                                            () => _isButtonPressed = false),
                                        onTapCancel: () => setState(
                                            () => _isButtonPressed = false),
                                        child: AnimatedScale(
                                          scale: _isButtonPressed ? 0.97 : 1.0,
                                          duration:
                                              const Duration(milliseconds: 120),
                                          curve: Curves.easeInOut,
                                          child: Container(
                                            height: 54,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  AppTheme.primaryBlue,
                                                  AppTheme.primaryBlueDark,
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.primaryBlue
                                                      .withValues(alpha: 0.38),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: _isLoading
                                                    ? null
                                                    : _onLogin,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                splashColor: Colors.white
                                                    .withValues(alpha: 0.15),
                                                child: Center(
                                                  child: _isLoading
                                                      ? const SizedBox(
                                                          width: 22,
                                                          height: 22,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2.5,
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                        Color>(
                                                                    Colors
                                                                        .white),
                                                          ),
                                                        )
                                                      : const Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              'Masuk',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 16,
                                                                color: Colors
                                                                    .white,
                                                                letterSpacing:
                                                                    0.3,
                                                              ),
                                                            ),
                                                            SizedBox(width: 8),
                                                            Icon(
                                                              Icons
                                                                  .arrow_forward_rounded,
                                                              size: 20,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ],
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),

                                      const SizedBox(height: 28),

                                      // Security badge
                                      _buildSecurityBadge(context),
                                    ],
                                  ),
                                ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Reusable themed text field builder.
  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffixIcon,
    void Function(String)? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: TextStyle(
        fontSize: 15,
        color: AppTheme.textPrimaryColor(context),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIcon: Icon(
          prefixIcon,
          color: AppTheme.primaryBlue.withValues(alpha: 0.75),
          size: 20,
        ),
        suffixIcon: suffixIcon,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppTheme.borderColor(context)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.error, width: 2),
        ),
        filled: true,
        fillColor: AppTheme.surface(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(
          color: AppTheme.textSecondaryColor(context),
          fontSize: 14,
        ),
        hintStyle: TextStyle(
          color: AppTheme.textSecondaryColor(context)
              .withValues(alpha: 0.6),
          fontSize: 14,
        ),
      ),
      validator: validator,
    );
  }

  /// Dropdown dengan style selaras card (border radius 12, label, icon).
  Widget _buildDropdownDownward({
    required BuildContext context,
    required String dropdownKey,
    required String? value,
    required String hint,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
    required String? Function(String?)? validator,
  }) {
    return FormField<String>(
      initialValue: value,
      validator: validator,
      builder: (field) {
        final displayValue =
            (value != null && value.isNotEmpty) ? value : null;
        final hasError = field.hasError;
        final isOpen = _openDropdownKey == dropdownKey;

        void toggleOpen() {
          FocusScope.of(context).unfocus();
          setState(() {
            _openDropdownKey = isOpen ? null : dropdownKey;
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: toggleOpen,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  prefixIcon: Icon(
                    icon,
                    color: AppTheme.primaryBlue.withValues(alpha: 0.75),
                    size: 20,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        const BorderRadius.all(Radius.circular(12)),
                    borderSide:
                        BorderSide(color: AppTheme.borderColor(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        const BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(
                      color: hasError
                          ? Theme.of(context).colorScheme.error
                          : AppTheme.primaryBlue,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius:
                        const BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                      width: 1.5,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius:
                        const BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: AppTheme.surface(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  labelStyle: TextStyle(
                    color: AppTheme.textSecondaryColor(context),
                    fontSize: 14,
                  ),
                ),
                isEmpty: displayValue == null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayValue ?? hint,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: displayValue == null
                              ? AppTheme.textSecondaryColor(context)
                                  .withValues(alpha: 0.6)
                              : AppTheme.textPrimaryColor(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textSecondaryColor(context),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: isOpen
                  ? Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasError
                              ? Theme.of(context).colorScheme.error
                              : AppTheme.borderColor(context),
                        ),
                      ),
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: AppTheme.borderColor(context)
                              .withValues(alpha: 0.6),
                        ),
                        itemBuilder: (_, i) {
                          final it = items[i];
                          final selected = it == value;
                          return ListTile(
                            dense: true,
                            visualDensity:
                                const VisualDensity(vertical: -2),
                            title: Text(
                              it,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: AppTheme.textPrimaryColor(context),
                              ),
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: AppTheme.primaryBlue,
                                  )
                                : null,
                            onTap: () {
                              onChanged(it);
                              field.didChange(it);
                              setState(() => _openDropdownKey = null);
                            },
                          );
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  field.errorText ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSecurityBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.securityGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.validGreen.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.validGreen.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.validGreen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_rounded,
                color: AppTheme.validGreen, size: 18),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Data Anda aman dan terlindungi',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
                             gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue,
                AppTheme.primaryBlueDark,
              ],
            ),
          ),
        ),
        // Decorative circles
        Positioned(
          top: -50,
          right: -40,
          child: _circle(140, 0.07),
        ),
        Positioned(
          top: 50,
          left: -50,
          child: _circle(120, 0.05),
        ),
        Positioned(
          bottom: 10,
          right: 30,
          child: _circle(70, 0.05),
        ),
        Positioned(
          bottom: 80,
          left: 20,
          child: _circle(40, 0.06),
        ),
        Positioned(
          top: 20,
          left: MediaQuery.sizeOf(context).width * 0.4,
          child: _circle(55, 0.04),
        ),
      ],
    );
  }

  Widget _circle(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

/// Logo PIONA dari asset.
class _PionaLogo extends StatelessWidget {
  const _PionaLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.contain,
      ),
    );
  }
}