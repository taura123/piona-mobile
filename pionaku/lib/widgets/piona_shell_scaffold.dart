import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/manual_entry_screen.dart';
import '../screens/passenger_list_screen.dart';
import '../screens/scan_screen.dart';
import '../theme/app_theme.dart';
import 'piona_bottom_nav.dart';

export 'piona_bottom_nav.dart';

Route<void> pionaRouteForNavItem(PionaNavItem item) {
  return switch (item) {
    PionaNavItem.home =>
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    PionaNavItem.scanNormal => MaterialPageRoute<void>(
        builder: (_) => const ScanScreen(mode: ScanMode.normal),
      ),
    PionaNavItem.scanTransit => MaterialPageRoute<void>(
        builder: (_) => const ScanScreen(mode: ScanMode.transit),
      ),
    PionaNavItem.passengerList => MaterialPageRoute<void>(
        builder: (_) => const PassengerListScreen(),
      ),
    PionaNavItem.manualEntry => MaterialPageRoute<void>(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final bg = isDark
              ? const Color(0xFF0D1117)
              : AppTheme.shellScaffoldLight;
          return PionaShellScaffold(
            currentNav: PionaNavItem.manualEntry,
            backgroundColor: bg,
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
              title: const Text('Manual Entry'),
              backgroundColor:
                  isDark ? AppTheme.primaryBlueDark : AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: const ManualEntryScreen(asShellBody: true),
          );
        },
      ),
  };
}

void pionaNavigateToNavItem(BuildContext context, PionaNavItem item) {
  Navigator.of(context).pushReplacement(pionaRouteForNavItem(item));
}

/// Shared [Scaffold] shell: floating navbar, [extendBody], and one place for tab routing.
@immutable
class PionaShellScaffold extends StatelessWidget {
  const PionaShellScaffold({
    super.key,
    required this.currentNav,
    required this.body,
    this.appBar,
    this.backgroundColor,
    this.extendBody = true,
    this.resizeToAvoidBottomInset,
    this.floatingActionButton,
  });

  final PionaNavItem currentNav;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;
  final bool extendBody;
  final bool? resizeToAvoidBottomInset;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: extendBody,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset ?? true,
      backgroundColor: backgroundColor,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: PionaFloatingNavBar(
        current: currentNav,
        onSelect: (navItem) => pionaNavigateToNavItem(context, navItem),
      ),
    );
  }
}
