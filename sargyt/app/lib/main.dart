import 'package:flutter/material.dart';
import 'state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/profile_screen.dart';

const brand = Color(0xFF0A8F5A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(App(state: state, child: const SargytApp()));
}

class SargytApp extends StatelessWidget {
  const SargytApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    return MaterialApp(
      title: 'SARGYT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: brand,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, surfaceTintColor: Colors.white),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      home: s.loggedIn ? const RootTabs() : const LoginScreen(),
    );
  }
}

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});
  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    return Scaffold(
      body: IndexedStack(index: tab, children: [const HomeScreen(), OrdersScreen(key: ValueKey(tab == 1)), const ProfileScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        backgroundColor: Colors.white,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.storefront_outlined), label: s.t('home')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), label: s.t('orders')),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: s.t('profile')),
        ],
      ),
    );
  }
}
