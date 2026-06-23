import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_theme_scope.dart';
import 'screens/login_screen.dart';
import 'services/session_context_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionContextStore.instance.restoreFromSecureStorage();

  void launchApp() {
    // Always start from LoginScreen; session is not persisted across app restarts.
    runApp(const PionaMobileApp(initialHome: LoginScreen()));
  }

  final dsn =
      const String.fromEnvironment('PIONA_SENTRY_DSN', defaultValue: '').trim();
  if (dsn.isEmpty) {
    launchApp();
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      options.tracesSampleRate = 0.15;
      options.environment = const String.fromEnvironment(
        'PIONA_SENTRY_ENV',
        defaultValue: 'development',
      );
    },
    appRunner: launchApp,
  );
}

class PionaMobileApp extends StatefulWidget {
  const PionaMobileApp({super.key, required this.initialHome});

  final Widget initialHome;

  @override
  State<PionaMobileApp> createState() => _PionaMobileAppState();
}

class _PionaMobileAppState extends State<PionaMobileApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      themeMode: _themeMode,
      setThemeMode: _setThemeMode,
      child: MaterialApp(
        title: 'PIONA Mobile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('id'),
          Locale('en'),
        ],
        localeResolutionCallback: (locale, supported) {
          if (locale != null) {
            for (final s in supported) {
              if (s.languageCode == locale.languageCode) {
                return s;
              }
            }
          }
          return const Locale('id');
        },
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          SystemChrome.setSystemUIOverlayStyle(
            SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  dark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor:
                  dark ? AppTheme.darkBackground : AppTheme.shellScaffoldLight,
              systemNavigationBarIconBrightness:
                  dark ? Brightness.light : Brightness.dark,
            ),
          );
          return child ?? const SizedBox.shrink();
        },
        home: widget.initialHome,
      ),
    );
  }
}
