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

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (_, __) => MaterialApp(
          title: 'Daily Tracker',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Color(st.seed), useMaterial3: true, brightness: st.dark ? Brightness.dark : Brightness.light, scaffoldBackgroundColor: st.dark && st.amoled ? Colors.black : null),
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
