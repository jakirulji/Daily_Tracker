import 'dart:async';
import 'package:flutter/material.dart';
import 'exam_widget.dart';
import 'store.dart';
import 'notify.dart';
import 'ui.dart';
import 'home_page.dart';
import 'today_page.dart';
import 'timer_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';
import 'prayer_page.dart';
import 'tuition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Saved data is read before the first frame (fast). The Store also has safe defaults,
  // so even if this fails or times out the app still opens.
  try {
    await st.load().timeout(const Duration(seconds: 5));
  } catch (_) {}
  runApp(const App());
  unawaited(_initializeApp());
}

Future<void> _initializeApp() async {
  // Never hold the native splash screen while plugins or local storage initialize.
  try {
    await tst.load().timeout(const Duration(seconds: 8));
  } catch (_) {
    // Tuition data is optional for the main app.
  }

  try {
    await Notif.init().timeout(const Duration(seconds: 8));
  } catch (_) {
    // Notifications are optional; the app must still open without them.
  }

  unawaited(Notif.askPermission());
  try {
    await ExamWidgetSync.update().timeout(const Duration(seconds: 5));
  } catch (_) {}
  try {
    await Notif.rescheduleAll(st).timeout(const Duration(seconds: 8));
  } catch (_) {}
}

ThemeData _buildAppTheme({required bool dark, required bool amoled, required String style, required int customSeed}) {
  final seed = switch (style) {
    'premium' => const Color(0xFF6750A4),
    'glass' => const Color(0xFF168F91),
    _ => Color(customSeed),
  };
  final brightness = dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    surface: dark ? (amoled ? Colors.black : const Color(0xFF171923)) : switch (style) {
      'premium' => const Color(0xFFF7F6FC),
      'glass' => const Color(0xFFF0FAFA),
      _ => const Color(0xFFF6F7FB),
    },
  );
  final background = dark
      ? (amoled ? Colors.black : const Color(0xFF11131B))
      : switch (style) {
          'premium' => const Color(0xFFF7F6FC),
          'glass' => const Color(0xFFF0FAFA),
          _ => const Color(0xFFF6F7FB),
        };
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: scheme.onSurface, fontSize: 21, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardTheme(
      color: dark ? scheme.surface : Colors.white,
      elevation: style == 'glass' ? 1 : 0,
      shadowColor: scheme.primary.withOpacity(0.08),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style == 'glass' ? 24 : 20),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(style == 'glass' ? 0.55 : 0.35)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withOpacity(0.6), thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerHighest.withOpacity(0.45) : scheme.surfaceContainerHighest.withOpacity(0.45),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.55))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? scheme.surface : Colors.white,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (_, __) => MaterialApp(
          title: 'Daily Tracker',
          debugShowCheckedModeBanner: false,
          theme: _buildAppTheme(dark: st.dark, amoled: st.amoled, style: st.themeStyle, customSeed: st.seed),
          home: const Home(),
        ),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Notif.askPermission());
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final tr = st.tracker;
          final List<Widget> pages = tr
              ? const [HomeDashboardPage(), TodayPage(), TimerPage(), StatsPage(), SettingsPage()]
              : const [HomeDashboardPage(), PrayerPage(), SettingsPage()];
          final idx = st.tab >= pages.length ? 0 : st.tab;
          return Scaffold(
            appBar: AppBar(title: Text(st.tab == 0 ? 'Daily Tracker' : st.pname)),
            drawer: const AppDrawer(),
            body: SafeArea(child: IndexedStack(key: ValueKey(st.cur), index: idx, children: pages)),
            floatingActionButton: tr && idx == 1 ? FloatingActionButton(onPressed: () => taskDialog(c), child: const Icon(Icons.add)) : null,
            bottomNavigationBar: NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: st.goTab,
              destinations: tr
                  ? const [
                      NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Home'),
                      NavigationDestination(icon: Icon(Icons.checklist), label: 'Study'),
                      NavigationDestination(icon: Icon(Icons.timer), label: 'Timer'),
                      NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
                      NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
                    ]
                  : const [
                      NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Home'),
                      NavigationDestination(icon: Icon(Icons.self_improvement), label: 'Prayer'),
                      NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
                    ],
            ),
          );
        },
      );
}
