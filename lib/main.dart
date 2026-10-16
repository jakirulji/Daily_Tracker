import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
 
String dk(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
 
const palette = [0xFF5C6BC0, 0xFF26A69A, 0xFFEF5350, 0xFFFFA726, 0xFF8D6E63, 0xFFAB47BC, 0xFF42A5F5, 0xFF66BB6A];
 
List<Map> defSubjects() => [
      {'n': 'Work', 'c': palette[0]},
      {'n': 'Personal', 'c': palette[1]},
      {'n': 'Health', 'c': palette[2]},
    ];
 
List<Map> defModes() => [
      {'n': 'Classic', 'f': 25, 'b': 5},
      {'n': 'Deep', 'f': 50, 'b': 10},
      {'n': 'Marathon', 'f': 90, 'b': 15},
    ];
 
List<Map> defProfiles() => [
      {'n': 'Study', 't': 'tracker', 'd': {'subjects': [{'n': 'Math', 'c': palette[0]}, {'n': 'English', 'c': palette[1]}, {'n': 'Science', 'c': palette[2]}]}},
      {'n': 'Prayer', 't': 'prayer', 'd': {}},
      {'n': 'Other', 't': 'tracker', 'd': {}},
    ];
 
class Store extends ChangeNotifier {
  late SharedPreferences p;
  List<Map> profiles = [], subjects = [], tasks = [], modes = [], prayers = [];
  Map logs = {}, notes = {}, pdone = {};
  double goal = 4;
  String exam = '', examDate = '', cel = '', faith = '', sel = dk(DateTime.now());
  bool dark = false, amoled = false;
  int seed = 0xFF5C6BC0, mi = 0, cur = 0, tab = 0;
 
  bool get tracker => profiles[cur]['t'] != 'prayer';
  String get pname => profiles[cur]['n'];
 
  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    final j = p.getString('data');
    if (j == null || !apply(j)) {
      profiles = defProfiles();
      cur = 0;
      loadP(profiles[0]['d']);
    }
  }
 
  Map get pdata => {'subjects': subjects, 'tasks': tasks, 'logs': logs, 'notes': notes, 'goal': goal, 'exam': exam, 'examDate': examDate, 'cel': cel, 'modes': modes, 'mi': mi, 'faith': faith, 'prayers': prayers, 'pdone': pdone};
 
  void loadP(Map m) {
    subjects = m['subjects'] == null ? defSubjects() : List<Map>.from(m['subjects']);
    if (subjects.isEmpty) subjects = defSubjects();
    tasks = List<Map>.from(m['tasks'] ?? []);
    logs = Map.from(m['logs'] ?? {});
    notes = Map.from(m['notes'] ?? {});
    goal = ((m['goal'] ?? 4) as num).toDouble().clamp(1.0, 12.0).toDouble();
    exam = m['exam'] ?? '';
    examDate = m['examDate'] ?? '';
    cel = m['cel'] ?? '';
    modes = m['modes'] == null ? defModes() : List<Map>.from(m['modes']);
    if (modes.isEmpty) modes = defModes();
    mi = ((m['mi'] ?? 0) as int) % modes.length;
    faith = m['faith'] ?? '';
    prayers = List<Map>.from(m['prayers'] ?? []);
    pdone = Map.from(m['pdone'] ?? {});
  }
 
  String get json {
    profiles[cur]['d'] = pdata;
    return jsonEncode({'profiles': profiles, 'cur': cur, 'dark': dark, 'amoled': amoled, 'seed': seed});
  }
 
  void _load(String j) {
    final m = jsonDecode(j) as Map;
    final ps = m['profiles'] != null
        ? List<Map>.from(m['profiles'])
        : <Map>[
            {'n': 'Study', 't': 'tracker', 'd': m},
            {'n': 'Prayer', 't': 'prayer', 'd': {'faith': m['faith'], 'prayers': m['prayers'], 'pdone': m['pdone']}},
            {'n': 'Other', 't': 'tracker', 'd': {}},
          ];
    if (ps.isEmpty) throw 'empty';
    profiles = ps;
    cur = ((m['cur'] ?? 0) as int).clamp(0, ps.length - 1).toInt();
    dark = m['dark'] ?? false;
    amoled = m['amoled'] ?? false;
    seed = m['seed'] ?? seed;
    tab = 0;
    loadP(profiles[cur]['d'] ?? {});
  }
 
  bool apply(String j) {
    final old = profiles.isEmpty ? null : json;
    try {
      _load(j);
      return true;
    } catch (_) {
      if (old != null) {
        try { _load(old); } catch (_) {}
      }
      return false;
    }
  }
 
  void save({bool q = false}) {
    p.setString('data', json);
    if (!q) notifyListeners();
  }
 
  void pick(String k) { sel = k; notifyListeners(); }
  void goTab(int v) { tab = v; notifyListeners(); }
 
  void switchTo(int i) {
    profiles[cur]['d'] = pdata;
    cur = i;
    tab = 0;
    loadP(profiles[cur]['d'] ?? {});
    save();
  }
 
  void addProfile(String n, String t) {
    profiles[cur]['d'] = pdata;
    profiles.add({'n': n, 't': t, 'd': {}});
    cur = profiles.length - 1;
    tab = 0;
    loadP({});
    save();
  }
 
  void removeProfile(int i) {
    profiles[cur]['d'] = pdata;
    profiles.removeAt(i);
    if (i < cur) cur--;
    cur = cur.clamp(0, profiles.length - 1).toInt();
    tab = 0;
    loadP(profiles[cur]['d'] ?? {});
    save();
  }
 
  void renameProfile(int i, String n) { profiles[i]['n'] = n; save(); }
 
  void setFaith(String f) {
    faith = f;
    prayers = [for (final n in faiths[f]!) {'n': n}];
    save();
  }
 
  bool pd(String d, String n) => ((pdone[d] as List?) ?? []).contains(n);
 
  void ptoggle(String d, String n) {
    final l = List.from((pdone[d] as List?) ?? []);
    if (l.contains(n)) { l.remove(n); } else { l.add(n); }
    pdone[d] = l;
    save();
  }
 
  int pcount(String d) => prayers.where((p) => pd(d, p['n'])).length;
 
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
          title: 'Daily Tracker',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Color(st.seed), useMaterial3: true, brightness: st.dark ? Brightness.dark : Brightness.light, scaffoldBackgroundColor: st.dark && st.amoled ? Colors.black : null),
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
                st.tasks.add({'t': t.text.trim(), 's': s, 'd': st.sel, 'tm': tm.text.trim(), 'x': false});
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
 
Future<bool> confirm(BuildContext c, String msg) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    ) ??
    false;
 
void addProfile(BuildContext c) {
  final t = TextEditingController();
  var type = 'tracker';
  showDialog(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('New profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: t, autofocus: true, decoration: const InputDecoration(labelText: 'Name (e.g. Work, Gym)')),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'tracker', label: Text('Tracker')), ButtonSegment(value: 'prayer', label: Text('Prayer'))],
            selected: {type},
            onSelectionChanged: (v) => set(() => type = v.first),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (t.text.trim().isNotEmpty) st.addProfile(t.text.trim(), type);
              Navigator.pop(d);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}
 
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});
  @override
  Widget build(BuildContext c) => Drawer(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: st,
            builder: (c, _) => ListView(children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('Profiles', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              for (var i = 0; i < st.profiles.length; i++)
                ListTile(
                  leading: Icon(st.profiles[i]['t'] == 'prayer' ? Icons.self_improvement : Icons.checklist),
                  title: Text(st.profiles[i]['n']),
                  selected: i == st.cur,
                  onTap: () { st.switchTo(i); Navigator.pop(c); },
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'del') {
                        if (st.profiles.length > 1 && await confirm(c, 'Delete "${st.profiles[i]['n']}" and all its data?')) st.removeProfile(i);
                      } else {
                        final n = await ask(c, 'New name');
                        if (n != null && n.isNotEmpty) st.renameProfile(i, n);
                      }
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'ren', child: Text('Rename')), PopupMenuItem(value: 'del', child: Text('Delete'))],
                  ),
                ),
              const Divider(),
              ListTile(leading: const Icon(Icons.add), title: const Text('Add profile'), onTap: () { Navigator.pop(c); addProfile(c); }),
            ]),
          ),
        ),
      );
}
 
class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final tr = st.tracker;
          final List<Widget> pages = tr ? const [TodayPage(), TimerPage(), StatsPage(), SettingsPage()] : const [PrayerPage(), SettingsPage()];
          final idx = st.tab >= pages.length ? 0 : st.tab;
          return Scaffold(
            appBar: AppBar(title: Text(st.pname)),
            drawer: const AppDrawer(),
            body: SafeArea(child: IndexedStack(key: ValueKey(st.cur), index: idx, children: pages)),
            floatingActionButton: tr && idx == 0 ? FloatingActionButton(onPressed: () => addTask(c), child: const Icon(Icons.add)) : null,
            bottomNavigationBar: NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: st.goTab,
              destinations: tr
                  ? const [
                      NavigationDestination(icon: Icon(Icons.checklist), label: 'Today'),
                      NavigationDestination(icon: Icon(Icons.timer), label: 'Timer'),
                      NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
                      NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
                    ]
                  : const [
                      NavigationDestination(icon: Icon(Icons.self_improvement), label: 'Prayer'),
                      NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
                    ],
            ),
          );
        },
      );
}
 
class Confetti extends StatefulWidget {
  const Confetti({super.key});
  @override
  State<Confetti> createState() => _CF();
}
 
class _CF extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController a = AnimationController(vsync: this, duration: const Duration(seconds: 3))..forward();
  final r = Random();
  late final ps = List.generate(50, (_) => [r.nextDouble(), r.nextDouble() * .5, 0.5 + r.nextDouble(), r.nextInt(palette.length)]);
  @override
  void dispose() { a.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) => IgnorePointer(child: AnimatedBuilder(animation: a, builder: (_, __) => CustomPaint(size: Size.infinite, painter: _CP(ps, a.value))));
}
 
class _CP extends CustomPainter {
  final List ps;
  final double t;
  _CP(this.ps, this.t);
  @override
  void paint(Canvas c, Size s) {
    for (final p in ps) {
      final y = p[1] * s.height * .3 + t * s.height * p[2];
      c.drawCircle(Offset(p[0] * s.width + sin(t * 8 + p[0] * 9) * 20, y), 5, Paint()..color = Color(palette[p[3].toInt()]).withOpacity(1 - t));
    }
  }
  @override
  bool shouldRepaint(_CP o) => true;
}
 
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});
 
  Widget tile(Map e) => Dismissible(
        key: ObjectKey(e),
        background: Container(color: Colors.green, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), child: const Icon(Icons.check, color: Colors.white)),
        secondaryBackground: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) { e['x'] = e['x'] != true; st.save(); return false; }
          return true;
        },
        onDismissed: (_) { st.tasks.remove(e); st.save(); },
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 6, color: st.col(e['s'])),
              Expanded(
                child: ListTile(
                  title: Text(e['t'], style: TextStyle(decoration: e['x'] == true ? TextDecoration.lineThrough : null)),
                  subtitle: Text(e['tm'] == '' ? e['s'] : '${e['s']}  •  ${e['tm']}', style: TextStyle(color: st.col(e['s']))),
                  trailing: Checkbox(value: e['x'] == true, onChanged: (v) { e['x'] = v; st.save(); }),
                ),
              ),
            ]),
          ),
        ),
      );
 
  Widget head(String s) => Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)));
 
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final now = DateTime.now(), today = dk(now), sel = st.sel, cs = Theme.of(c).colorScheme;
          final todays = st.tasks.where((e) => e['d'] == sel).toList();
          final List<Map> old = sel != today ? <Map>[] : st.tasks.where((e) => (e['d'] as String).compareTo(today) < 0 && e['x'] != true).toList();
          final m = st.minutes(today), g = (st.goal * 60).round(), h = now.hour;
          final v = (m / g).clamp(0.0, 1.0).toDouble();
          final left = st.examDate == '' ? 0 : DateTime.parse(st.examDate).difference(DateTime.parse(today)).inDays;
          final show = m >= g && st.cel != today;
          if (show) WidgetsBinding.instance.addPostFrameCallback((_) { st.cel = today; st.save(q: true); });
          final dn = todays.where((e) => e['x'] == true).length;
          final badge = st.streak >= 30 ? '🏆' : st.streak >= 7 ? '🥇' : st.streak >= 3 ? '🥉' : '';
          const w = TextStyle(color: Colors.white);
          return Stack(children: [
            ListView(padding: const EdgeInsets.all(12), children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.tertiary]), borderRadius: BorderRadius.circular(24)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h < 12 ? 'Good morning 👋' : h < 17 ? 'Good afternoon 👋' : 'Good evening 👋', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('$today  •  Goal ${st.goal}h', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 8),
                      Text('🔥 ${st.streak} day streak $badge', style: w),
                      if (st.examDate != '') Text('📅 ${st.exam}: $left days left', style: w),
                    ]),
                  ),
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: v), duration: const Duration(milliseconds: 700), builder: (_, x, __) => CircularProgressIndicator(value: x, strokeWidth: 9, color: Colors.white, backgroundColor: Colors.white24))),
                      Text('${m ~/ 60}h ${m % 60}m', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var i = -3; i <= 3; i++)
                  Builder(builder: (_) {
                    final d = now.add(Duration(days: i)), k = dk(d);
                    return GestureDetector(
                      onTap: () => st.pick(k),
                      child: Container(
                        width: 44,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(color: k == sel ? cs.primaryContainer : null, borderRadius: BorderRadius.circular(14), border: k == today ? Border.all(color: cs.primary) : null),
                        child: Column(children: [
                          Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1], style: const TextStyle(fontSize: 12)),
                          Text('${d.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Icon(Icons.circle, size: 6, color: st.minutes(k) > 0 ? cs.primary : Colors.transparent),
                        ]),
                      ),
                    );
                  }),
              ]),
              if (old.isNotEmpty) ...[head('Carry-over (pending)'), ...old.map(tile)],
              head('${sel == today ? 'Today' : sel}  $dn/${todays.length}'),
              if (todays.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Column(children: [Icon(Icons.auto_stories, size: 60, color: cs.outline), const SizedBox(height: 8), const Text('No tasks yet. Tap + to add ✨')])),
              ...todays.map(tile),
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey(sel),
                initialValue: st.notes[sel] ?? '',
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reflection (ki korlam, ki baki)', border: OutlineInputBorder()),
                onChanged: (v) { st.notes[sel] = v; st.save(q: true); },
              ),
              const SizedBox(height: 80),
            ]),
            if (show) const Positioned.fill(child: Confetti()),
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
  int done = 0;
  Timer? t;
  Map get md => st.modes[st.mi];
  int get total => ((brk ? md['b'] : md['f']) as int) * 60;
  late int left = total;
  String get who => st.subjects.any((e) => e['n'] == sub) ? sub! : st.subjects[0]['n'];
 
  void tick(Timer _) {
    setState(() => left--);
    if (left <= 0) {
      HapticFeedback.heavyImpact();
      if (!brk) { st.addLog(who, md['f']); done++; }
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
 
  void pick(int i) { stop(); st.mi = i; st.save(q: true); setState(() { brk = false; left = total; }); }
 
  void addMode() {
    final n = TextEditingController(), f = TextEditingController(text: '30'), b = TextEditingController(text: '5');
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Custom timer'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: f, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Focus (minutes)')),
          TextField(controller: b, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Break (minutes)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final fm = int.tryParse(f.text) ?? 0, bm = int.tryParse(b.text) ?? 0;
              if (fm > 0 && bm > 0) {
                st.modes.add({'n': n.text.trim().isEmpty ? 'Custom' : n.text.trim(), 'f': fm.clamp(1, 240), 'b': bm.clamp(1, 60)});
                pick(st.modes.length - 1);
              }
              Navigator.pop(d);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
 
  @override
  void dispose() { t?.cancel(); super.dispose(); }
 
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          if (left > total) left = total;
          final n = done == 0 ? 0 : (done - 1) % 4 + 1, col = st.col(who);
          return ListView(padding: const EdgeInsets.all(24), children: [
            Wrap(spacing: 8, children: [
              for (var i = 0; i < st.modes.length; i++)
                ChoiceChip(label: Text('${st.modes[i]['n']} ${st.modes[i]['f']}/${st.modes[i]['b']}'), selected: i == st.mi, onSelected: (_) => pick(i)),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Custom'), onPressed: addMode),
            ]),
            const SizedBox(height: 12),
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Select category'),
              value: st.subjects.any((e) => e['n'] == sub) ? sub : null,
              items: [for (final e in st.subjects) DropdownMenuItem<String>(value: e['n'], child: Text(e['n']))],
              onChanged: (v) => setState(() => sub = v),
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: left / total, strokeWidth: 12, color: col, backgroundColor: col.withOpacity(.15))),
                  Text('${(left ~/ 60).toString().padLeft(2, '0')}:${(left % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Center(child: Text(brk ? 'Break (${md['b']} min)' : 'Focus (${md['f']} min)')),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 4; i++) Padding(padding: const EdgeInsets.all(3), child: Icon(i < n ? Icons.circle : Icons.circle_outlined, size: 12)),
            ]),
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
              FilledButton.icon(onPressed: toggle, icon: Icon(run ? Icons.pause : Icons.play_arrow), label: Text(run ? 'Pause' : 'Start')),
              OutlinedButton(onPressed: reset, child: const Text('Reset & log')),
              TextButton(onPressed: swap, child: Text(brk ? 'Focus' : 'Break')),
            ]),
          ]);
        },
      );
}
 
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final now = DateTime.now(), cs = Theme.of(c).colorScheme;
          final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
          final mins = [for (final d in days) st.minutes(dk(d))];
          final mx = mins.fold<int>(60, (a, b) => a > b ? a : b);
          final best = mins.fold<int>(0, (a, b) => a > b ? a : b);
          final by = <String, int>{};
          for (final d in days) {
            ((st.logs[dk(d)] as Map?) ?? {}).forEach((k, v) => by[k as String] = (by[k] ?? 0) + (v as num).toInt());
          }
          final tot = by.values.fold<int>(0, (a, b) => a + b);
          final prev = [for (var i = 13; i >= 7; i--) st.minutes(dk(now.subtract(Duration(days: i))))].fold<int>(0, (a, b) => a + b);
          final keys = days.map(dk).toSet();
          final wt = st.tasks.where((e) => keys.contains(e['d'])).toList();
          final done = wt.where((e) => e['x'] == true).length;
          final mon = DateTime(now.year, now.month, now.day - (now.weekday - 1) - 77);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Last 7 days (hours)', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                for (var i = 0; i < 7; i++)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text((mins[i] / 60).toStringAsFixed(1), style: const TextStyle(fontSize: 11)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Column(children: [
                        for (final en in ((st.logs[dk(days[i])] as Map?) ?? {}).entries) Container(width: 22, height: 110 * (en.value as num) / mx, color: st.col(en.key)),
                      ]),
                    ),
                    Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][days[i].weekday - 1]),
                  ]),
              ]),
            ),
            const SizedBox(height: 20),
            Text('Weekly summary', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Total: ${tot ~/ 60}h ${tot % 60}m  •  Tasks done: $done/${wt.length}'),
            Text('Best day: ${(best / 60).toStringAsFixed(1)}h  •  vs last week: ${tot >= prev ? '+' : '-'}${((tot - prev).abs() / 60).toStringAsFixed(1)}h'),
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
            const SizedBox(height: 20),
            Text('Last 12 weeks', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var w = 0; w < 12; w++)
                  Column(children: [
                    for (var d = 0; d < 7; d++)
                      Builder(builder: (_) {
                        final day = DateTime(mon.year, mon.month, mon.day + w * 7 + d), x = (st.minutes(dk(day)) / (st.goal * 60)).clamp(0.0, 1.0).toDouble();
                        return Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: day.isAfter(now) ? Colors.transparent : x == 0 ? cs.outlineVariant.withOpacity(.4) : cs.primary.withOpacity(.25 + .75 * x)),
                        );
                      }),
                  ]),
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
          SwitchListTile(title: const Text('AMOLED black (needs dark mode)'), value: st.amoled, onChanged: st.dark ? (v) { st.amoled = v; st.save(); } : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(spacing: 10, children: [
              for (final p in palette)
                GestureDetector(
                  onTap: () { st.seed = p; st.save(); },
                  child: CircleAvatar(radius: 16, backgroundColor: Color(p), child: st.seed == p ? const Icon(Icons.check, color: Colors.white, size: 18) : null),
                ),
            ]),
          ),
          if (st.tracker) ...[
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
          ],
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
          if (st.tracker) ...[
          const Divider(),
          for (final m in st.modes)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(m['n']),
              subtitle: Text('${m['f']} min focus / ${m['b']} min break'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: st.modes.length > 1 ? () { st.modes.remove(m); if (st.mi >= st.modes.length) st.mi = 0; st.save(); } : null,
              ),
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
            label: const Text('Add category'),
            onPressed: () async {
              final n = await ask(c, 'Category name');
              if (n == null || n.isEmpty) return;
              st.subjects.add({'n': n, 'c': palette[st.subjects.length % palette.length]});
              st.save();
            },
          ),
          ],
        ]),
      );
}
 
const Map<String, List<String>> faiths = {
  'Islam': ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'],
  'Hinduism': ['Morning Puja', 'Noon Sandhya', 'Evening Aarti'],
  'Buddhism': ['Morning Chanting', 'Evening Chanting', 'Meditation'],
  'Christianity': ['Morning Prayer', 'Evening Prayer', 'Night Prayer'],
  'Sikhism': ['Morning Nitnem', 'Rehras Sahib', 'Kirtan Sohila'],
  'Other (add my own)': [],
};
 
class PrayerPage extends StatelessWidget {
  const PrayerPage({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          if (st.faith == '') {
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('Select your religion', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Common daily prayers will be added. You can edit, delete or add your own anytime.'),
              const SizedBox(height: 12),
              for (final f in faiths.keys) Card(child: ListTile(title: Text(f), trailing: const Icon(Icons.chevron_right), onTap: () => st.setFaith(f))),
            ]);
          }
          final now = DateTime.now(), today = dk(now), cs = Theme.of(c).colorScheme;
          final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
          final n = st.prayers.length, dn = st.pcount(today);
          var wk = 0, ps = 0, d0 = now;
          for (final d in days) { wk += st.pcount(dk(d)); }
          bool full(DateTime d) => n > 0 && st.pcount(dk(d)) == n;
          if (!full(d0)) d0 = d0.subtract(const Duration(days: 1));
          while (full(d0)) { ps++; d0 = d0.subtract(const Duration(days: 1)); }
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${st.faith}  •  Today $dn/$n', style: Theme.of(c).textTheme.titleMedium)),
                    TextButton(onPressed: () { st.faith = ''; st.save(); }, child: const Text('Change')),
                  ]),
                  LinearProgressIndicator(value: n == 0 ? 0.0 : dn / n, minHeight: 10, borderRadius: BorderRadius.circular(8)),
                  const SizedBox(height: 8),
                  Text('🔥 Full-day streak: $ps  •  This week: $wk/${n * 7}'),
                ]),
              ),
            ),
            for (final p in st.prayers)
              CheckboxListTile(
                value: st.pd(today, p['n']),
                title: Text(p['n']),
                secondary: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { st.prayers.remove(p); st.save(); }),
                onChanged: (_) => st.ptoggle(today, p['n']),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add extra prayer'),
              onPressed: () async {
                final s = await ask(c, 'Prayer name');
                if (s == null || s.isEmpty) return;
                st.prayers.add({'n': s});
                st.save();
              },
            ),
            const Divider(),
            Text('Last 7 days (tap to edit)', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: SizedBox()),
              for (final d in days) SizedBox(width: 30, child: Center(child: Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1], style: const TextStyle(fontSize: 12)))),
            ]),
            for (final p in st.prayers)
              Row(children: [
                Expanded(child: Text(p['n'], overflow: TextOverflow.ellipsis)),
                for (final d in days)
                  GestureDetector(
                    onTap: () => st.ptoggle(dk(d), p['n']),
                    child: Padding(padding: const EdgeInsets.all(5), child: Icon(st.pd(dk(d), p['n']) ? Icons.check_circle : Icons.circle_outlined, size: 20, color: st.pd(dk(d), p['n']) ? cs.primary : cs.outline)),
                  ),
              ]),
            const SizedBox(height: 20),
          ]);
        },
      );
}
