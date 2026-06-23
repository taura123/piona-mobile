import 'package:flutter/material.dart';

/// Scope untuk akses tema app (light/dark) dari child widget.
class AppThemeScope extends InheritedWidget {
  const AppThemeScope({
    super.key,
    required this.themeMode,
    required this.setThemeMode,
    required super.child,
  });

  final ThemeMode themeMode;
  final void Function(ThemeMode) setThemeMode;

  static AppThemeScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) {
    return themeMode != oldWidget.themeMode;
  }
}
