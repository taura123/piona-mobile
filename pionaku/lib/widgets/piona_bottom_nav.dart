import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum PionaNavItem {
  home,
  scanTransit,
  scanNormal,
  passengerList,
  manualEntry,
}

@immutable
class PionaFloatingNavBar extends StatelessWidget {
  const PionaFloatingNavBar({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final PionaNavItem current;
  final void Function(PionaNavItem item) onSelect;

  static const double _navHeight = 66.0;
  static const double _fabSize = 56.0;
  static const double _fabOverlap = 18.0;
  static const double _bottomGap = 8.0;

  /// Space to pad scrollable body content so it stays above the floating bar
  /// (use with [Scaffold.extendBody]).
  static double reserveBottomPadding(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return _navHeight + (_fabSize / 2) + _fabOverlap + bottomInset + _bottomGap;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final border = AppTheme.borderColor(context);
    const active = AppTheme.primaryBlue;
    final inactive = AppTheme.textSecondaryColor(context);
    final pillBg = active.withValues(alpha: isDark ? 0.20 : 0.10);

    const sideMargin = 16.0;

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final totalHeight =
        _navHeight + (_fabSize / 2) + _fabOverlap + bottomInset + _bottomGap;

    return Material(
      type: MaterialType.transparency,
      elevation: 0,
      shadowColor: Colors.transparent,
      color: Colors.transparent,
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              left: sideMargin,
              right: sideMargin,
              bottom: bottomInset + _bottomGap,
              child: Container(
                height: _navHeight,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(
                    color: border.withValues(alpha: isDark ? 0.85 : 0.65),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: active.withValues(alpha: isDark ? 0.12 : 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _NavItem(
                          label: 'Home',
                          icon: Icons.home_rounded,
                          active: current == PionaNavItem.home,
                          activeColor: active,
                          inactiveColor: inactive,
                          pillBg: pillBg,
                          onTap: () => onSelect(PionaNavItem.home),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          label: 'Transit',
                          icon: Icons.transfer_within_a_station_rounded,
                          active: current == PionaNavItem.scanTransit,
                          activeColor: active,
                          inactiveColor: inactive,
                          pillBg: pillBg,
                          onTap: () => onSelect(PionaNavItem.scanTransit),
                        ),
                      ),
                      const SizedBox(width: _fabSize),
                      Expanded(
                        child: _NavItem(
                          label: 'List',
                          icon: Icons.people_alt_rounded,
                          active: current == PionaNavItem.passengerList,
                          activeColor: active,
                          inactiveColor: inactive,
                          pillBg: pillBg,
                          onTap: () => onSelect(PionaNavItem.passengerList),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          label: 'Manual Entry',
                          icon: Icons.edit_note_rounded,
                          active: current == PionaNavItem.manualEntry,
                          activeColor: active,
                          inactiveColor: inactive,
                          pillBg: pillBg,
                          onTap: () => onSelect(PionaNavItem.manualEntry),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: bottomInset +
                  _bottomGap +
                  _navHeight -
                  (_fabSize / 2) -
                  _fabOverlap,
              child: _CenterFab(
                active: current == PionaNavItem.scanNormal,
                onTap: () => onSelect(PionaNavItem.scanNormal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.pillBg,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final Color pillBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? activeColor : inactiveColor;
    final textColor = active ? activeColor : inactiveColor;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? pillBg : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  scale: active ? 1.05 : 1.0,
                  child: Icon(icon, size: 22, color: iconColor),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: textColor,
                    height: 1.0,
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

class _CenterFab extends StatefulWidget {
  const _CenterFab({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  State<_CenterFab> createState() => _CenterFabState();
}

class _CenterFabState extends State<_CenterFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const c1 = Color(0xFF2B5CE6);
    const c2 = Color(0xFF0A6EA8);
    final shadowA = widget.active ? 0.22 : 0.16;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        scale: _pressed ? 0.94 : 1.0,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c1, c2],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A3DBF).withValues(alpha: shadowA),
                blurRadius: 14,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
