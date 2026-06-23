import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/scan_point_store.dart';
import '../services/session_context_store.dart';
import '../services/users_api.dart';
import '../services/user_store.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen>
    with SingleTickerProviderStateMixin {
  final ScanPointStore _scanPointStore = ScanPointStore.instance;
  final SessionContextStore _session = SessionContextStore.instance;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final t = _session.jwtToken?.trim();
    _scanPointStore.loadOnce(bearerToken: (t != null && t.isNotEmpty) ? t : null);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : AppTheme.shellScaffoldLight;
    final surface = isDark ? const Color(0xFF141C2E) : Colors.white;
    final border = AppTheme.borderColor(context);
    final secondary = AppTheme.textSecondaryColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Management'),
        backgroundColor: isDark ? AppTheme.primaryBlueDark : AppTheme.primaryBlue,
        foregroundColor: Colors.white,
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Management',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pengaturan dan administrasi data.',
                        style: TextStyle(
                          fontSize: 13,
                          color: secondary,
                          height: 1.25,
                        ),
                      ),
                    ],
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
                    Tab(text: 'Scan Points'),
                    Tab(text: 'User Management'),
                  ],
                ),
                Divider(height: 1, thickness: 1, color: border),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: const [
                      _ScanPointsTab(),
                      _UserManagementTab(),
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

class _UserManagementTab extends StatefulWidget {
  const _UserManagementTab();

  @override
  State<_UserManagementTab> createState() => _UserManagementTabState();
}

enum _TopToastType { success, error }

class _TopToast extends StatelessWidget {
  const _TopToast({
    required this.message,
    required this.type,
    required this.onClose,
  });

  final String message;
  final _TopToastType type;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxWidth = mq.size.width - 24;
    final toastWidth = maxWidth > 520 ? 520.0 : maxWidth;
    final topOffset = kToolbarHeight + 12;

    final bg = switch (type) {
      _TopToastType.success => AppTheme.validGreen,
      _TopToastType.error => AppTheme.invalidRed,
    };
    final icon = switch (type) {
      _TopToastType.success => Icons.check_circle_rounded,
      _TopToastType.error => Icons.warning_amber_rounded,
    };

    return SafeArea(
      top: true,
      bottom: false,
      child: IgnorePointer(
        ignoring: false,
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: topOffset),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * -12),
                    child: child,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints.tightFor(width: toastWidth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: onClose,
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanPointsTab extends StatefulWidget {
  const _ScanPointsTab();

  @override
  State<_ScanPointsTab> createState() => _ScanPointsTabState();
}

class _UserManagementTabState extends State<_UserManagementTab> {
  final UserStore _store = UserStore.instance;
  final SessionContextStore _session = SessionContextStore.instance;

  OverlayEntry? _toastEntry;
  Timer? _toastTimer;
  Timer? _refreshTimer;

  String? _backendBearer() {
    final t = _session.jwtToken?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  Future<void> _reloadUsersFromBackendIfPossible() async {
    final token = _backendBearer();
    if (token == null) {
      await _store.loadOnce();
      return;
    }
    await _store.loadOnce(bearerToken: token, force: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reloadUsersFromBackendIfPossible();
    });

    // Lightweight "real-time" refresh: periodically pull latest users,
    // including createdAt / lastLoginAt and status updates.
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _reloadUsersFromBackendIfPossible();
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _showTopToast({
    required String message,
    required _TopToastType type,
    Duration duration = const Duration(seconds: 2),
  }) {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) => _TopToast(
        message: message,
        type: type,
        onClose: () {
          _toastTimer?.cancel();
          _toastEntry?.remove();
          _toastEntry = null;
        },
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);

    _toastTimer = Timer(duration, () {
      entry.remove();
      if (identical(_toastEntry, entry)) {
        _toastEntry = null;
      }
    });
  }

  String _fmtDate(DateTime dt) => '${dt.month}/${dt.day}/${dt.year}';

  String _roleLabel(UserRole r) {
    return switch (r) {
      UserRole.admin => 'Admin',
      UserRole.it => 'IT',
      UserRole.scan => 'Scan',
      UserRole.view => 'View',
    };
  }

  Color _roleTint(UserRole r) {
    return switch (r) {
      UserRole.admin => const Color(0xFFEF4444),
      UserRole.it => const Color(0xFF8B5CF6),
      UserRole.scan => AppTheme.primaryBlue,
      UserRole.view => const Color(0xFF10B981),
    };
  }

  /// Avoid disposing dialog [TextEditingController]s in the same turn as
  /// [Navigator.pop] — the route may still be animating and [TextField]s
  /// still hold inherited dependencies.
  void _disposeUserFormControllersAfterDialogClose(
    TextEditingController usernameCtrl,
    TextEditingController passwordCtrl,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        usernameCtrl.dispose();
        passwordCtrl.dispose();
      });
    });
  }

  Future<void> _openUserDialog({UserRecord? editing}) async {
    if (!_session.canManageUsers) {
      _showTopToast(
        message: 'Only Admin or IT can manage users.',
        type: _TopToastType.error,
      );
      return;
    }
    final usernameCtrl = TextEditingController(text: editing?.username ?? '');
    final passwordCtrl = TextEditingController();
    UserRole role = editing?.role ?? UserRole.scan;
    UserStatus status = editing?.status ?? UserStatus.active;

    InputDecoration userMgmtInputDecoration(BuildContext ctx) {
      final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: AppTheme.borderColor(ctx)),
      );
      return InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Theme.of(ctx).brightness == Brightness.dark
            ? AppTheme.darkSurfaceElevated.withValues(alpha: 0.65)
            : const Color(0xFFF7F8FA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:
              const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
        ),
      );
    }

    Widget fieldLabel(BuildContext ctx, String text) {
      return Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondaryColor(ctx),
          ),
        ),
      );
    }

    final bool? saved;
    if (editing == null) {
      saved = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          bool obscurePassword = true;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Widget usernameBlock() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fieldLabel(context, 'Username'),
                    TextField(
                      controller: usernameCtrl,
                      decoration: userMgmtInputDecoration(context).copyWith(
                        hintText: 'Enter username',
                      ),
                    ),
                  ],
                );
              }

              Widget passwordBlock() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fieldLabel(context, 'Password'),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: obscurePassword,
                      decoration: userMgmtInputDecoration(context).copyWith(
                        hintText: 'Enter password',
                        suffixIcon: IconButton(
                          tooltip: obscurePassword ? 'Show' : 'Hide',
                          onPressed: () => setDialogState(
                            () => obscurePassword = !obscurePassword,
                          ),
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppTheme.textSecondaryColor(context),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              Widget roleDropdown() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fieldLabel(context, 'Role'),
                    DropdownButtonFormField<UserRole>(
                      value: role,
                      items: UserRole.values
                          .map(
                            (r) => DropdownMenuItem<UserRole>(
                              value: r,
                              child: Text(_roleLabel(r)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => role = v);
                      },
                      decoration: userMgmtInputDecoration(context),
                    ),
                  ],
                );
              }

              Widget statusDropdown() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fieldLabel(context, 'Status'),
                    DropdownButtonFormField<UserStatus>(
                      value: status,
                      items: const [
                        DropdownMenuItem(
                          value: UserStatus.active,
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: UserStatus.inactive,
                          child: Text('Inactive'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => status = v);
                      },
                      decoration: userMgmtInputDecoration(context),
                    ),
                  ],
                );
              }

              final primaryBtnStyle = ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              );

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.borderColor(context)
                          .withValues(alpha: 0.85),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                'Add New User',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimaryColor(context),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              icon: const Icon(Icons.close_rounded),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, c) {
                            final narrow = c.maxWidth < 440;
                            if (narrow) {
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  usernameBlock(),
                                  const SizedBox(height: 16),
                                  passwordBlock(),
                                  const SizedBox(height: 16),
                                  roleDropdown(),
                                  const SizedBox(height: 16),
                                  statusDropdown(),
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      usernameBlock(),
                                      const SizedBox(height: 16),
                                      roleDropdown(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      passwordBlock(),
                                      const SizedBox(height: 16),
                                      statusDropdown(),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final u = usernameCtrl.text.trim();
                                  final p = passwordCtrl.text.trim();
                                  if (u.isEmpty) {
                                    _showTopToast(
                                      message: 'Username is required.',
                                      type: _TopToastType.error,
                                    );
                                    return;
                                  }
                                  if (p.isEmpty) {
                                    _showTopToast(
                                      message: 'Password is required.',
                                      type: _TopToastType.error,
                                    );
                                    return;
                                  }
                                  if (p.length < 6) {
                                    _showTopToast(
                                      message:
                                          'Password must be at least 6 characters.',
                                      type: _TopToastType.error,
                                    );
                                    return;
                                  }
                                  Navigator.of(dialogContext).pop(true);
                                },
                                icon: const Icon(Icons.check_rounded, size: 20),
                                label: const Text(
                                  'Create User',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: primaryBtnStyle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                icon: const Icon(Icons.close_rounded, size: 20),
                                label: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: primaryBtnStyle,
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
    } else {
      final secondary = AppTheme.textSecondaryColor(context);
      saved = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          Widget dropdownField<T>({
            required String label,
            required T value,
            required List<DropdownMenuItem<T>> items,
            required void Function(T? v) onChanged,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fieldLabel(context, label),
                DropdownButtonFormField<T>(
                  value: value,
                  items: items,
                  onChanged: onChanged,
                  decoration: const InputDecoration(),
                ),
              ],
            );
          }

          Widget usernameField() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fieldLabel(context, 'Username'),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(hintText: 'e.g. scanner'),
                ),
              ],
            );
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                scrollable: true,
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                titlePadding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit User',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      usernameField(),
                      const SizedBox(height: 12),
                      dropdownField<UserRole>(
                        label: 'Role',
                        value: role,
                        items: UserRole.values
                            .map(
                              (r) => DropdownMenuItem<UserRole>(
                                value: r,
                                child: Text(_roleLabel(r)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() => role = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      dropdownField<UserStatus>(
                        label: 'Status',
                        value: status,
                        items: const [
                          DropdownMenuItem(
                            value: UserStatus.active,
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: UserStatus.inactive,
                            child: Text('Inactive'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() => status = v);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Changes will be saved when you click Save.',
                        style: TextStyle(
                          fontSize: 12,
                          color: secondary.withValues(alpha: 0.95),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity:
                                  const VisualDensity(vertical: -1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity:
                                  const VisualDensity(vertical: -1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
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
          );
        },
      );
    }

    final username = usernameCtrl.text.trim();
    final passwordForAdd = passwordCtrl.text.trim();

    // [showDialog]'s Future can complete before the route's exit animation
    // finishes. Disposing [TextEditingController]s immediately breaks
    // [TextField] while it still depends on [InheritedWidget]s → framework
    // assertion '_dependents.isEmpty' (see flutter framework.dart ~6268).
    _disposeUserFormControllersAfterDialogClose(
      usernameCtrl,
      passwordCtrl,
    );

    if (!mounted) return;
    if (saved != true) return;

    if (username.isEmpty) {
      _showTopToast(message: 'Username is required.', type: _TopToastType.error);
      return;
    }

    if (editing == null) {
      if (!_session.canManageUsers) {
        _showTopToast(
          message: 'Only Admin or IT can add users.',
          type: _TopToastType.error,
        );
        return;
      }
      final bearer = _backendBearer();
      if (bearer == null) {
        _showTopToast(
          message: 'Session token missing. Please login again.',
          type: _TopToastType.error,
        );
        return;
      }
      if (passwordForAdd.isEmpty) {
        _showTopToast(
          message: 'Password is required.',
          type: _TopToastType.error,
        );
        return;
      }
      if (passwordForAdd.length < 6) {
        _showTopToast(
          message: 'Password must be at least 6 characters.',
          type: _TopToastType.error,
        );
        return;
      }
      try {
        await _store.add(
          username: username,
          role: role,
          status: status,
          password: passwordForAdd,
          bearerToken: bearer,
        );
      } on UsersApiException catch (e) {
        if (!mounted) return;
        _showTopToast(message: e.message, type: _TopToastType.error);
        return;
      } catch (_) {
        if (!mounted) return;
        _showTopToast(
          message: 'Failed to create user. Please try again.',
          type: _TopToastType.error,
        );
        return;
      }
      if (!mounted) return;
      _showTopToast(
        message: 'User added successfully.',
        type: _TopToastType.success,
      );
    } else {
      if (!_session.canManageUsers) {
        _showTopToast(
          message: 'Only Admin or IT can update users.',
          type: _TopToastType.error,
        );
        return;
      }
      final bearer = _backendBearer();
      if (bearer == null) {
        _showTopToast(
          message: 'Session token missing. Please login again.',
          type: _TopToastType.error,
        );
        return;
      }
      try {
        await _store.update(
          id: editing.id,
          username: username,
          role: role,
          status: status,
          bearerToken: bearer,
        );
      } on UsersApiException catch (e) {
        if (!mounted) return;
        _showTopToast(message: e.message, type: _TopToastType.error);
        return;
      } catch (_) {
        if (!mounted) return;
        _showTopToast(
          message: 'Failed to update user. Please try again.',
          type: _TopToastType.error,
        );
        return;
      }
      if (!mounted) return;
      _showTopToast(
        message: 'User updated successfully.',
        type: _TopToastType.success,
      );
    }
  }

  Future<void> _confirmDelete(UserRecord r) async {
    if (!_session.canManageUsers) {
      _showTopToast(
        message: 'Only Admin or IT can delete users.',
        type: _TopToastType.error,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final secondary = AppTheme.textSecondaryColor(context);
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Delete User',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Text(
              'Are you sure you want to delete "${r.username}"?\n'
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: secondary,
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.invalidRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (ok != true) return;
    final bearer = _backendBearer();
    if (bearer == null) {
      _showTopToast(
        message: 'Session token missing. Please login again.',
        type: _TopToastType.error,
      );
      return;
    }
    try {
      await _store.remove(id: r.id, bearerToken: bearer);
    } on UsersApiException catch (e) {
      if (!mounted) return;
      _showTopToast(message: e.message, type: _TopToastType.error);
      return;
    } catch (_) {
      if (!mounted) return;
      _showTopToast(
        message: 'Failed to delete user. Please try again.',
        type: _TopToastType.error,
      );
      return;
    }
    if (!mounted) return;
    _showTopToast(
      message: 'User deleted successfully.',
      type: _TopToastType.success,
    );
  }

  Widget _pill({
    required BuildContext context,
    required String label,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: tint,
        ),
      ),
    );
  }

  Widget _statusBadge(BuildContext context, UserStatus s) {
    final color = s == UserStatus.active ? const Color(0xFF10B981) : secondary(context);
    final label = s == UserStatus.active ? 'Active' : 'Inactive';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Color secondary(BuildContext context) => AppTheme.textSecondaryColor(context);

  Widget _actionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color tint,
    required VoidCallback? onTap,
  }) {
    final border = AppTheme.borderColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border.withValues(alpha: 0.8)),
            color: tint.withValues(alpha: 0.06),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = AppTheme.borderColor(context);
    final secondary = AppTheme.textSecondaryColor(context);

    return AnimatedBuilder(
      animation: Listenable.merge([_store, _session]),
      builder: (context, _) {
        final items = _store.records;
        final canManageUsers = _session.canManageUsers;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User Management',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage system users, roles, and access permissions.',
                          style: TextStyle(fontSize: 12.5, color: secondary),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: canManageUsers ? () => _openUserDialog() : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'Add User',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(130, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _store.isLoading && !_store.isLoaded
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Loading users...',
                              style: TextStyle(fontSize: 13, color: secondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  : items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No users yet. Click "Add User" to create one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: secondary.withValues(alpha: 0.95),
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, c) {
                            if (c.maxWidth >= 820) {
                              return _UserTable(
                                isDark: isDark,
                                canManageUsers: canManageUsers,
                                rows: items,
                                fmtDate: _fmtDate,
                                roleLabel: _roleLabel,
                                roleTint: _roleTint,
                                pillBuilder: _pill,
                                statusBuilder: _statusBadge,
                                actionButton: _actionButton,
                                onEdit: (r) => _openUserDialog(editing: r),
                                onDelete: _confirmDelete,
                              );
                            }
                            return _UserCardList(
                              canManageUsers: canManageUsers,
                              rows: items,
                              fmtDate: _fmtDate,
                              roleLabel: _roleLabel,
                              roleTint: _roleTint,
                              pillBuilder: _pill,
                              statusBuilder: _statusBadge,
                              actionButton: _actionButton,
                              onEdit: (r) => _openUserDialog(editing: r),
                              onDelete: _confirmDelete,
                            );
                          },
                        ),
            ),
            Divider(height: 1, color: border.withValues(alpha: 0.9)),
          ],
        );
      },
    );
  }
}

class _UserTable extends StatelessWidget {
  const _UserTable({
    required this.isDark,
    required this.canManageUsers,
    required this.rows,
    required this.fmtDate,
    required this.roleLabel,
    required this.roleTint,
    required this.pillBuilder,
    required this.statusBuilder,
    required this.actionButton,
    required this.onEdit,
    required this.onDelete,
  });

  final bool isDark;
  final bool canManageUsers;
  final List<UserRecord> rows;
  final String Function(DateTime) fmtDate;
  final String Function(UserRole) roleLabel;
  final Color Function(UserRole) roleTint;
  final Widget Function({
    required BuildContext context,
    required String label,
    required Color tint,
  }) pillBuilder;
  final Widget Function(BuildContext context, UserStatus s) statusBuilder;
  final Widget Function({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color tint,
    required VoidCallback? onTap,
  }) actionButton;
  final void Function(UserRecord r) onEdit;
  final void Function(UserRecord r) onDelete;

  @override
  Widget build(BuildContext context) {
    final headerBg = isDark ? const Color(0xFF141C2E) : const Color(0xFFF7F9FC);
    final border = AppTheme.borderColor(context);

    Widget headerCell(String text, {double w = 140}) {
      return SizedBox(
        width: w,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppTheme.textSecondaryColor(context),
          ),
        ),
      );
    }

    Widget cell(Widget child, {double w = 140}) {
      return SizedBox(width: w, child: child);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1060,
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
                        headerCell('Username', w: 220),
                        headerCell('Role', w: 120),
                        headerCell('Status', w: 140),
                        headerCell('Created', w: 140),
                        headerCell('Last Login', w: 160),
                        headerCell('Actions', w: 220),
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
                        final tint = roleTint(r.role);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              cell(
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: tint.withValues(alpha: 0.12),
                                      foregroundColor: tint,
                                      child: Text(
                                        r.username.isEmpty
                                            ? '?'
                                            : r.username
                                                .trim()
                                                .substring(0, 1)
                                                .toUpperCase(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        r.username,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textPrimaryColor(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                w: 220,
                              ),
                              cell(
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: pillBuilder(
                                    context: context,
                                    label: roleLabel(r.role),
                                    tint: tint,
                                  ),
                                ),
                                w: 120,
                              ),
                              cell(statusBuilder(context, r.status), w: 140),
                              cell(
                                Text(
                                  fmtDate(r.createdAt),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppTheme.textSecondaryColor(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                w: 140,
                              ),
                              cell(
                                Text(
                                  r.lastLoginAt == null
                                      ? '-'
                                      : fmtDate(r.lastLoginAt!),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppTheme.textSecondaryColor(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                w: 160,
                              ),
                              cell(
                                Row(
                                  children: [
                                    actionButton(
                                      context: context,
                                      icon: Icons.edit_rounded,
                                      label: 'Edit',
                                      tint: AppTheme.primaryBlue,
                                      onTap:
                                          canManageUsers ? () => onEdit(r) : null,
                                    ),
                                    const SizedBox(width: 10),
                                    actionButton(
                                      context: context,
                                      icon: Icons.delete_outline_rounded,
                                      label: 'Delete',
                                      tint: AppTheme.invalidRed,
                                      onTap:
                                          canManageUsers ? () => onDelete(r) : null,
                                    ),
                                  ],
                                ),
                                w: 220,
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

class _UserCardList extends StatelessWidget {
  const _UserCardList({
    required this.canManageUsers,
    required this.rows,
    required this.fmtDate,
    required this.roleLabel,
    required this.roleTint,
    required this.pillBuilder,
    required this.statusBuilder,
    required this.actionButton,
    required this.onEdit,
    required this.onDelete,
  });

  final bool canManageUsers;
  final List<UserRecord> rows;
  final String Function(DateTime) fmtDate;
  final String Function(UserRole) roleLabel;
  final Color Function(UserRole) roleTint;
  final Widget Function({
    required BuildContext context,
    required String label,
    required Color tint,
  }) pillBuilder;
  final Widget Function(BuildContext context, UserStatus s) statusBuilder;
  final Widget Function({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color tint,
    required VoidCallback? onTap,
  }) actionButton;
  final void Function(UserRecord r) onEdit;
  final void Function(UserRecord r) onDelete;

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderColor(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = rows[i];
        final tint = roleTint(r.role);
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
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: tint.withValues(alpha: 0.12),
                      foregroundColor: tint,
                      child: Text(
                        r.username.isEmpty
                            ? '?'
                            : r.username
                                .trim()
                                .substring(0, 1)
                                .toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                    ),
                    pillBuilder(
                      context: context,
                      label: roleLabel(r.role),
                      tint: tint,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: statusBuilder(context, r.status)),
                    Text(
                      'Created: ${fmtDate(r.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Last login: ${r.lastLoginAt == null ? '-' : fmtDate(r.lastLoginAt!)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: actionButton(
                        context: context,
                        icon: Icons.edit_rounded,
                        label: 'Edit',
                        tint: AppTheme.primaryBlue,
                        onTap: canManageUsers ? () => onEdit(r) : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: actionButton(
                        context: context,
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        tint: AppTheme.invalidRed,
                        onTap: canManageUsers ? () => onDelete(r) : null,
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

class _ScanPointsTabState extends State<_ScanPointsTab> {
  final ScanPointStore _store = ScanPointStore.instance;
  final SessionContextStore _session = SessionContextStore.instance;

  OverlayEntry? _toastEntry;
  Timer? _toastTimer;
  Timer? _refreshTimer;

  String? _backendBearer() {
    final t = _session.jwtToken?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  Future<void> _reloadScanPointsFromBackendIfPossible() async {
    final token = _backendBearer();
    if (token == null) return;
    await _store.loadOnce(bearerToken: token, force: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reloadScanPointsFromBackendIfPossible();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _reloadScanPointsFromBackendIfPossible();
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _showTopToast({
    required String message,
    required _TopToastType type,
    Duration duration = const Duration(seconds: 2),
  }) {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (ctx) => _TopToast(
        message: message,
        type: type,
        onClose: () {
          _toastTimer?.cancel();
          _toastEntry?.remove();
          _toastEntry = null;
        },
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);

    _toastTimer = Timer(duration, () {
      entry.remove();
      if (identical(_toastEntry, entry)) {
        _toastEntry = null;
      }
    });
  }

  Widget _dialogActionBar({
    required BuildContext context,
    required VoidCallback onCancel,
    required String primaryLabel,
    required VoidCallback onPrimary,
    required Color primaryBg,
  }) {
    const labelStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      height: 1.15,
    );

    final cancelBtn = SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onCancel,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(vertical: -1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Center(child: Text('Cancel', style: labelStyle)),
      ),
    );

    final primaryBtn = SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPrimary,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBg,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(vertical: -1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Center(child: Text(primaryLabel, style: labelStyle)),
      ),
    );

    return Row(
      children: [
        Expanded(child: cancelBtn),
        const SizedBox(width: 12),
        Expanded(child: primaryBtn),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondaryColor(context),
        ),
      ),
    );
  }

  Widget _nameField({
    required BuildContext context,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, 'Name'),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. Concordia',
          ),
        ),
      ],
    );
  }

  Widget _actionIconButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color tint,
  }) {
    final border = AppTheme.borderColor(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border.withValues(alpha: 0.85)),
            color: tint.withValues(alpha: 0.08),
          ),
          child: Icon(icon, size: 18, color: tint),
        ),
      ),
    );
  }

  Future<void> _openAddDialog({ScanPointRecord? editing}) async {
    if (!_session.isIt) {
      _showTopToast(
        message: 'Only IT can manage scan points.',
        type: _TopToastType.error,
      );
      return;
    }
    final nameCtrl = TextEditingController(text: editing?.name ?? '');

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final secondary = AppTheme.textSecondaryColor(context);
        final title = editing == null ? 'Add New Scan Point' : 'Edit Scan Point';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimaryColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _nameField(context: context, controller: nameCtrl),
                    const SizedBox(height: 8),
                    Text(
                      'Status scan point otomatis aktif saat ada user login di scan point tersebut.',
                      style: TextStyle(
                        fontSize: 12,
                        color: secondary.withValues(alpha: 0.95),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                _dialogActionBar(
                  context: context,
                  onCancel: () => Navigator.of(context).pop(false),
                  primaryLabel: 'Save',
                  onPrimary: () => Navigator.of(context).pop(true),
                  primaryBg: AppTheme.primaryBlue,
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (saved != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _showTopToast(
        message: 'Scan point name is required.',
        type: _TopToastType.error,
      );
      return;
    }

    if (editing == null) {
      final bearer = _backendBearer();
      if (bearer == null) {
        _showTopToast(
          message: 'Session token missing. Please login again.',
          type: _TopToastType.error,
        );
        return;
      }
      await _store.add(name: name, bearerToken: bearer);
      if (!mounted) return;
      _showTopToast(
        message: 'Scan point added successfully.',
        type: _TopToastType.success,
      );
    } else {
      final bearer = _backendBearer();
      if (bearer == null) {
        _showTopToast(
          message: 'Session token missing. Please login again.',
          type: _TopToastType.error,
        );
        return;
      }
      await _store.update(
        id: editing.id,
        name: name,
        bearerToken: bearer,
      );
      if (!mounted) return;
      _showTopToast(
        message: 'Scan point updated successfully.',
        type: _TopToastType.success,
      );
    }
  }

  Future<void> _confirmDelete(ScanPointRecord r) async {
    if (!_session.isIt) {
      _showTopToast(
        message: 'Only IT can manage scan points.',
        type: _TopToastType.error,
      );
      return;
    }

    if (r.activeSessions > 0) {
      _showTopToast(
        message: 'Scan point is currently active on ${r.activeSessions} device(s).',
        type: _TopToastType.error,
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final secondary = AppTheme.textSecondaryColor(context);
        return AlertDialog(
          scrollable: true,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Hapus Scan Point',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: Text(
              'Yakin ingin menghapus "${r.name}"?\n'
              'Aksi ini tidak bisa dibatalkan.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: secondary,
              ),
            ),
          ),
          actions: [
            _dialogActionBar(
              context: context,
              onCancel: () => Navigator.of(context).pop(false),
              primaryLabel: 'Delete',
              onPrimary: () => Navigator.of(context).pop(true),
              primaryBg: AppTheme.invalidRed,
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (ok != true) return;
    final bearer = _backendBearer();
    if (bearer == null) {
      _showTopToast(
        message: 'Session token missing. Please login again.',
        type: _TopToastType.error,
      );
      return;
    }
    await _store.remove(id: r.id, bearerToken: bearer);
    if (!mounted) return;
    _showTopToast(
      message: 'Scan point deleted successfully.',
      type: _TopToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = AppTheme.borderColor(context);
    final secondary = AppTheme.textSecondaryColor(context);

    return AnimatedBuilder(
      animation: Listenable.merge([_store, _session]),
      builder: (context, _) {
        final items = _store.records;
        final canManage = _session.isIt;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan Points Management',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add/change scan point status.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: canManage ? () => _openAddDialog() : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'Add Scan Point',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(160, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _store.isLoading && !_store.isLoaded
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Memuat scan points...',
                              style: TextStyle(
                                fontSize: 13,
                                color: secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Belum ada scan point. Klik "Add Scan Point" untuk menambah.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: secondary.withValues(alpha: 0.95),
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, c) {
                            if (c.maxWidth >= 760) {
                              return _ScanPointTable(
                                isDark: isDark,
                                rows: items,
                                onEdit: (r) => _openAddDialog(editing: r),
                                onDelete: _confirmDelete,
                                actionBuilder: _actionIconButton,
                              );
                            }
                            return _ScanPointCardList(
                              rows: items,
                              onEdit: (r) => _openAddDialog(editing: r),
                              onDelete: _confirmDelete,
                              actionBuilder: _actionIconButton,
                            );
                          },
                        ),
            ),
            Divider(height: 1, color: border.withValues(alpha: 0.9)),
          ],
        );
      },
    );
  }
}

class _ScanPointTable extends StatelessWidget {
  const _ScanPointTable({
    required this.isDark,
    required this.rows,
    required this.onEdit,
    required this.onDelete,
    required this.actionBuilder,
  });

  final bool isDark;
  final List<ScanPointRecord> rows;
  final void Function(ScanPointRecord r) onEdit;
  final void Function(ScanPointRecord r) onDelete;
  final Widget Function({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color tint,
  }) actionBuilder;

  @override
  Widget build(BuildContext context) {
    final headerBg = isDark ? const Color(0xFF141C2E) : const Color(0xFFF7F9FC);
    final border = AppTheme.borderColor(context);

    Widget headerCell(String text, {double w = 160}) {
      return SizedBox(
        width: w,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppTheme.textSecondaryColor(context),
          ),
        ),
      );
    }

    Widget cell(Widget child, {double w = 160}) {
      return SizedBox(width: w, child: child);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              headerCell('Name', w: 340),
              headerCell('Status', w: 160),
              headerCell('Actions', w: 140),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
            itemCount: rows.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: border),
            itemBuilder: (context, i) {
              final r = rows[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    cell(
                      Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.textPrimaryColor(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      w: 340,
                    ),
                    cell(_StatusPill(status: r.status), w: 160),
                    cell(
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            actionBuilder(
                              context: context,
                              icon: Icons.edit_rounded,
                              tooltip: 'Edit',
                              onPressed: () => onEdit(r),
                              tint: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 8),
                            actionBuilder(
                              context: context,
                              icon: Icons.delete_outline_rounded,
                              tooltip: 'Delete',
                              onPressed: () => onDelete(r),
                              tint: AppTheme.invalidRed,
                            ),
                          ],
                        ),
                      ),
                      w: 140,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ScanPointCardList extends StatelessWidget {
  const _ScanPointCardList({
    required this.rows,
    required this.onEdit,
    required this.onDelete,
    required this.actionBuilder,
  });

  final List<ScanPointRecord> rows;
  final void Function(ScanPointRecord r) onEdit;
  final void Function(ScanPointRecord r) onDelete;
  final Widget Function({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color tint,
  }) actionBuilder;

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderColor(context);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = rows[i];
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
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StatusPill(status: r.status),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    actionBuilder(
                      context: context,
                      icon: Icons.edit_rounded,
                      tooltip: 'Edit',
                      onPressed: () => onEdit(r),
                      tint: AppTheme.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    actionBuilder(
                      context: context,
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      onPressed: () => onDelete(r),
                      tint: AppTheme.invalidRed,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ScanPointStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (status) {
      ScanPointStatus.active => (
          AppTheme.validGreenLight,
          AppTheme.validGreen,
          AppTheme.validGreen.withValues(alpha: 0.30),
        ),
      ScanPointStatus.inactive => (
          AppTheme.invalidRedLight,
          AppTheme.invalidRed,
          AppTheme.invalidRed.withValues(alpha: 0.30),
        ),
    };

    final label = status == ScanPointStatus.active ? 'Active' : 'Inactive';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
