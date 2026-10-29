import 'package:flutter/material.dart';
import 'services/api.dart';
import 'services/l10n.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/help_screen.dart';
import 'screens/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.init();
  runApp(const BilimApp());
}

/// Rebuilds the whole app when language or auth changes.
final appState = ValueNotifier<int>(0);
void refreshApp() => appState.value++;

class BilimApp extends StatelessWidget {
  const BilimApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F7B5F); // Turkmen green
    return ValueListenableBuilder(
      valueListenable: appState,
      builder: (_, __, ___) => MaterialApp(
        title: 'Bilim',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
        home: Api.I.token == null ? const LoginScreen() : const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final l = Api.I.lang;
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: tab, children: const [HomeScreen(), HelpScreen(), ProfileScreen()]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.school_outlined), selectedIcon: const Icon(Icons.school), label: tr('home', l)),
          NavigationDestination(icon: const Icon(Icons.support_agent_outlined), selectedIcon: const Icon(Icons.support_agent), label: tr('help', l)),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('profile', l)),
        ],
      ),
    );
  }
}
