import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  app.init();
  runApp(const DostApp());
}

class DostApp extends StatefulWidget {
  const DostApp({super.key});

  @override
  State<DostApp> createState() => _DostAppState();
}

class _DostAppState extends State<DostApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) app.reconnectNow();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'Dost',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: app.themeMode,
        home: const Root(),
      ),
    );
  }
}

/// Decides which screen to show: splash → welcome/login → profile setup → home.
class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final Widget screen;
        if (!app.ready) {
          screen = const SplashScreen(key: ValueKey('splash'));
        } else if (!app.loggedIn) {
          // not const: rebuild texts when the language changes
          screen = WelcomeScreen(key: const ValueKey('welcome'));
        } else if (app.needsProfile) {
          screen = ProfileSetupScreen(key: const ValueKey('profile'));
        } else {
          screen = HomeScreen(key: const ValueKey('home'));
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
          ),
          child: screen,
        );
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          builder: (_, v, c) => Transform.scale(scale: v, child: c),
          child: const DostLogo(size: 110),
        ),
      ),
    );
  }
}
