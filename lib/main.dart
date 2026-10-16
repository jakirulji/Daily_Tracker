import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

String dk(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const palette = [0xFF5C6BC0, 0xFF26A69A, 0xFFEF5350, 0xFFFFA726, 0xFF8D6E63, 0xFFAB47BC, 0xFF42A5F5, 0xFF66BB6A];

class Store extends ChangeNotifier {
  late SharedPreferences p;
  List<Map> subjects = [], tasks = [];
  Map logs = {}, notes = {};
  double goal = 4;
  String exam = '', examDate = '';
  bool dark = false;

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    final j = p.getString('data');
    if (j != null) apply(j);
    if (subjects.isEmpty) {
      subjects = [
        {'n': 'Math', 'c': palette[0]},
        {'n': 'English', 'c': palette[1]},
        {'n': 'Science', 'c': palette[2]},
      ];
    }
  }

  String get json => jsonEncode({'subjects': subjects, 'tasks': tasks, 'logs': logs, 'notes': notes, 'goal': goal, 'exam': exam, 'examDate': examDate, 'dark': dark});

  bool apply(String j) {
    try {
      final m = jsonDecode(j);
      final s = List<Map>.from(m['subjects']), t = List<Map>.from(m['tasks']);
      final l = Map.from(m['logs']), n = Map.from(m['notes']);
      final g = (m['goal'] as num).toDouble().clamp(1.0, 12.0).toDouble();
      final e = m['exam'] as String, ed = m['examDate'] as String, d = m['dark'] as bool;
      if (s.isEmpty) return false;
      subjects = s; tasks = t; logs = l; notes = n; goal = g; exam = e; examDate = ed; dark = d;
      return true;
    } catch (_) {
      return false;
    }
  }

  void save({bool q = false}) {
    p.setString('data', jsonEncode({'subjects': subjects, 'tasks': tasks, 'logs': logs, 'notes': notes, 'goal': goal, 'exam': exam, 'examDate': examDate, 'dark': dark}));
    if (!q) notifyListeners();
  }

  int minutes(String d) {
    final l = logs[d] as Map?;
    return l == null ? 0 : l.values.fold<int>(0, (a, b) => a + (b as num).toInt());
  }

  void addLog(String s, int m) {
    final l = logs.putIfAbsent(dk(DateTime.now()), () => {}) as Map;
    l[s] = (l[s] ?? 0) + m;
    save();
  }

  int get streak {
    var d = DateTime.now();
    if (minutes(dk(d)) == 0) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (minutes(dk(d)) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  Color col(String s) => Color(subjects.firstWhere((e) => e['n'] == s, orElse: () => {'c': 0xFF9E9E9E})['c']);
}

final st = Store();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await st.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (_, __) => MaterialApp(
          title: 'Study Planner',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true, brightness: st.dark ? Brightness.dark : Brightness.light),
          home: const Home(),
        ),
      );
}

Future<String?> ask(BuildContext c, String title) {
  final t = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: t, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, t.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

void addTask(BuildContext c) {
  final t = TextEditingController(), tm = TextEditingController();
  String s = st.subjects[0]['n'];
  showDialog(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('New task'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: t, autofocus: true, decoration: const InputDecoration(labelText: 'Task')),
          DropdownButton<String>(
            isExpanded: true,
            value: s,
            items: [for (final e in st.subjects) DropdownMenuItem<String>(value: e['n'], child: Text(e['n']))],
            onChanged: (v) => set(() => s = v!),
          ),
          TextField(controller: tm, decoration: const InputDecoration(labelText: 'Time (e.g. 6:00-7:00 PM)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (t.text.trim().isNotEmpty) {
                st.tasks.add({'t': t.text.trim(), 's': s, 'd': dk(DateTime.now()), 'tm': tm.text.trim(), 'x': false});
                st.save();
              }
              Navigator.pop(d);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(child: IndexedStack(index: i, children: const [TodayPage(), TimerPage(), StatsPage(), SettingsPage()])),
        floatingActionButton: i == 0 ? FloatingActionButton(onPressed: () => addTask(c), child: const Icon(Icons.add)) : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.checklist), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.timer), label: 'Timer'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  Widget tile(Map e) => ListTile(
        leading: Checkbox(value: e['x'] == true, onChanged: (v) { e['x'] = v; st.save(); }),
        title: Text(e['t'], style: TextStyle(decoration: e['x'] == true ? TextDecoration.lineThrough : null)),
        subtitle: Text(e['tm'] == '' ? e['s'] : '${e['s']}  •  ${e['tm']}', style: TextStyle(color: st.col(e['s']))),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { st.tasks.remove(e); st.save(); }),
      );

  Widget head(String s) => Padding(padding: const EdgeInsets.fromLTRB(8, 16, 8, 4), child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)));

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final today = dk(DateTime.now());
          final todays = st.tasks.where((e) => e['d'] == today).toList();
          final old = st.tasks.where((e) => (e['d'] as String).compareTo(today) < 0 && e['x'] != true).toList();
          final m = st.minutes(today), g = (st.goal * 60).round();
          final left = st.examDate == '' ? 0 : DateTime.parse(st.examDate).difference(DateTime.parse(today)).inDays;
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Today: ${m ~/ 60}h ${m % 60}m / ${st.goal}h', style: Theme.of(c).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: (m / g).clamp(0.0, 1.0).toDouble(), minHeight: 10, borderRadius: BorderRadius.circular(8)),
                  const SizedBox(height: 8),
                  Text('🔥 Streak: ${st.streak} day(s)'),
                  if (st.examDate != '') Text('📅 ${st.exam}: $left days left'),
                ]),
              ),
            ),
            if (old.isNotEmpty) ...[head('Carry-over (pending)'), ...old.map(tile)],
            head('Today'),
            if (todays.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No tasks yet. Tap + to add.')),
            ...todays.map(tile),
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey(today),
              initialValue: st.notes[today] ?? '',
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reflection (ki bujhlam, ki baki)', border: OutlineInputBorder()),
              onChanged: (v) { st.notes[today] = v; st.save(q: true); },
            ),
            const SizedBox(height: 70),
          ]);
        },
      );
}

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});
  @override
  State<TimerPage> createState() => _TP();
}

class _TP extends State<TimerPage> {
  String? sub;
  bool brk = false, run = false;
  int left = 1500;
  Timer? t;
  int get total => brk ? 300 : 1500;
  String get who => st.subjects.any((e) => e['n'] == sub) ? sub! : st.subjects[0]['n'];

  void tick(Timer _) {
    setState(() => left--);
    if (left <= 0) {
      if (!brk) st.addLog(who, 25);
      stop();
      setState(() { brk = !brk; left = total; });
    }
  }

  void stop() { t?.cancel(); run = false; }
  void toggle() {
    if (run) { stop(); } else { run = true; t = Timer.periodic(const Duration(seconds: 1), tick); }
    setState(() {});
  }

  void reset() {
    final el = total - left;
    if (!brk && el >= 60) st.addLog(who, el ~/ 60);
    stop();
    setState(() => left = total);
  }

  void swap() { stop(); setState(() { brk = !brk; left = total; }); }

  @override
  void dispose() { t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Select subject'),
                value: st.subjects.any((e) => e['n'] == sub) ? sub : null,
                items: [for (final e in st.subjects) DropdownMenuItem<String>(value: e['n'], child: Text(e['n']))],
                onChanged: (v) => setState(() => sub = v),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: left / total, strokeWidth: 10)),
                  Text('${(left ~/ 60).toString().padLeft(2, '0')}:${(left % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(height: 8),
              Text(brk ? 'Break (5 min)' : 'Focus (25 min)'),
              const SizedBox(height: 24),
              Wrap(spacing: 8, children: [
                FilledButton.icon(onPressed: toggle, icon: Icon(run ? Icons.pause : Icons.play_arrow), label: Text(run ? 'Pause' : 'Start')),
                OutlinedButton(onPressed: reset, child: const Text('Reset & log')),
                TextButton(onPressed: swap, child: Text(brk ? 'Focus' : 'Break')),
              ]),
            ]),
          ),
        ),
      );
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final days = [for (var i = 6; i >= 0; i--) DateTime.now().subtract(Duration(days: i))];
          final mins = [for (final d in days) st.minutes(dk(d))];
          final mx = mins.fold<int>(60, (a, b) => a > b ? a : b);
          final by = <String, int>{};
          for (final d in days) {
            ((st.logs[dk(d)] as Map?) ?? {}).forEach((k, v) => by[k as String] = (by[k] ?? 0) + (v as num).toInt());
          }
          final tot = by.values.fold<int>(0, (a, b) => a + b);
          final keys = days.map(dk).toSet();
          final wt = st.tasks.where((e) => keys.contains(e['d'])).toList();
          final done = wt.where((e) => e['x'] == true).length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Last 7 days (hours)', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                for (var i = 0; i < 7; i++)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text((mins[i] / 60).toStringAsFixed(1), style: const TextStyle(fontSize: 11)),
                    Container(width: 22, height: 110 * mins[i] / mx, decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary, borderRadius: BorderRadius.circular(4))),
                    Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][days[i].weekday - 1]),
                  ]),
              ]),
            ),
            const SizedBox(height: 20),
            Text('Weekly summary', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Total: ${tot ~/ 60}h ${tot % 60}m  •  Tasks done: $done/${wt.length}'),
            const SizedBox(height: 12),
            for (final e in by.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e.key}  ${e.value ~/ 60}h ${e.value % 60}m'),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: e.value / tot, color: st.col(e.key), minHeight: 8, borderRadius: BorderRadius.circular(8)),
                ]),
              ),
          ]);
        },
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) => ListView(children: [
          SwitchListTile(title: const Text('Dark mode'), value: st.dark, onChanged: (v) { st.dark = v; st.save(); }),
          ListTile(
            title: Text('Daily goal: ${st.goal} h'),
            subtitle: Slider(min: 1, max: 12, divisions: 22, value: st.goal, onChanged: (v) { st.goal = v; st.save(); }),
          ),
          ListTile(
            title: Text(st.exam == '' ? 'Set exam countdown' : '${st.exam} – ${st.examDate}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final n = await ask(c, 'Exam name');
              if (n == null || n.isEmpty || !c.mounted) return;
              final d = await showDatePicker(context: c, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime(2100));
              if (d == null) return;
              st.exam = n;
              st.examDate = dk(d);
              st.save();
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('Backup (copy data)'),
            subtitle: const Text('Paste it in Telegram/Notes/Email to keep it safe'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: st.json));
              if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Backup copied. Now paste it somewhere safe.')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Restore from backup'),
            subtitle: const Text('Paste your backup text (replaces current data)'),
            onTap: () async {
              final t = await ask(c, 'Paste backup here');
              if (t == null || t.isEmpty || !c.mounted) return;
              final ok = st.apply(t);
              if (ok) st.save();
              if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(ok ? 'Restored!' : 'Invalid backup text')));
            },
          ),
          const Divider(),
          for (final s in st.subjects)
            ListTile(
              leading: CircleAvatar(radius: 10, backgroundColor: Color(s['c'])),
              title: Text(s['n']),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: st.subjects.length > 1 ? () { st.subjects.remove(s); st.save(); } : null,
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add subject'),
            onPressed: () async {
              final n = await ask(c, 'Subject name');
              if (n == null || n.isEmpty) return;
              st.subjects.add({'n': n, 'c': palette[st.subjects.length % palette.length]});
              st.save();
            },
          ),
        ]),
      );
}
