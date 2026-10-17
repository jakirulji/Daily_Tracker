import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notify.dart';

String dk(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const palette = [0xFF5C6BC0, 0xFF26A69A, 0xFFEF5350, 0xFFFFA726, 0xFF8D6E63, 0xFFAB47BC, 0xFF42A5F5, 0xFF66BB6A];

const Map<String, List<String>> faiths = {
  'Islam': ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'],
  'Hinduism': ['Morning Puja', 'Noon Sandhya', 'Evening Aarti'],
  'Buddhism': ['Morning Chanting', 'Evening Chanting', 'Meditation'],
  'Christianity': ['Morning Prayer', 'Evening Prayer', 'Night Prayer'],
  'Sikhism': ['Morning Nitnem', 'Rehras Sahib', 'Kirtan Sohila'],
  'Other (add my own)': [],
};

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

// ---------- Task helpers (work on a raw task map) ----------
// Task keys: t=title, s=subject, d=start date, tm=time text, x=done (one-off),
// rp=repeat ('none'|'daily'|'weekly'), xd=list of done dates (repeating), rt=reminder 'HH:mm'

bool recurring(Map e) => (e['rp'] ?? 'none') != 'none';

bool occurs(Map e, String d) {
  final s = e['d'] as String;
  if (d.compareTo(s) < 0) return false;
  switch (e['rp'] ?? 'none') {
    case 'daily':
      return true;
    case 'weekly':
      return DateTime.parse(d).weekday == DateTime.parse(s).weekday;
    default:
      return d == s;
  }
}

bool isDone(Map e, String d) => recurring(e) ? ((e['xd'] as List?) ?? []).contains(d) : e['x'] == true;

void setDone(Map e, String d, bool v) {
  if (recurring(e)) {
    final l = List.from((e['xd'] as List?) ?? []);
    l.remove(d);
    if (v) l.add(d);
    e['xd'] = l;
  } else {
    e['x'] = v;
  }
}

class Store extends ChangeNotifier {
  SharedPreferences? p;
  List<Map> profiles = [], subjects = [], tasks = [], modes = [], prayers = [], exams = [];
  Map logs = {}, notes = {}, pdone = {}, oldCol = {};
  double goal = 4;
  String exam = '', examDate = '', cel = '', faith = '', sel = dk(DateTime.now());
  bool dark = false, amoled = false;
  int seed = 0xFF5C6BC0, mi = 0, cur = 0, tab = 0;
  Timer? _rs;
  Future<void> _saveQueue = Future<void>.value();

  bool get tracker => profiles[cur]['t'] != 'prayer';
  String get pname => profiles[cur]['n'];

  // Usable defaults from the very first frame, so the UI never builds with an empty profile list.
  Store() {
    profiles = defProfiles();
    loadP(profiles[0]['d']);
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    p = sp;
    final j = sp.getString('data');
    if (j == null || !apply(j)) {
      profiles = defProfiles();
      cur = 0;
      loadP(profiles[0]['d']);
    }
    notifyListeners();
  }

  Map get pdata => {'subjects': subjects, 'tasks': tasks, 'logs': logs, 'notes': notes, 'goal': goal, 'exam': exam, 'examDate': examDate, 'cel': cel, 'modes': modes, 'mi': mi, 'faith': faith, 'prayers': prayers, 'pdone': pdone, 'oldCol': oldCol, 'exams': exams};

  // Data of any profile (current one comes from live fields)
  Map dataOf(int i) => i == cur ? pdata : (profiles[i]['d'] as Map? ?? {});

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
    exams = List<Map>.from(m['exams'] ?? []);
    oldCol = Map.from(m['oldCol'] ?? {});
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

  void _resched() {
    _rs?.cancel();
    _rs = Timer(const Duration(milliseconds: 600), () => Notif.rescheduleAll(this));
  }

  Future<void> save({bool q = false}) {
    // Capture a snapshot now and serialize writes so rapid edits cannot race.
    final snapshot = json;
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      try {
        final prefs = p ?? await SharedPreferences.getInstance();
        p = prefs;
        await prefs.setString('data', snapshot);
      } catch (_) {
        // A later save may retry if storage initialization temporarily fails.
      }
    });
    if (!q) {
      notifyListeners();
      _resched();
    }
    return _saveQueue;
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

  List<Map> tasksOn(String d) => tasks.where((e) => occurs(e, d)).toList();

  // A day counts for the streak if you logged focus time OR finished a task
  bool active(String d) => minutes(d) > 0 || tasksOn(d).any((e) => isDone(e, d));

  int get streak {
    var d = DateTime.now();
    if (!active(dk(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (active(dk(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  // Deleted categories keep their colour so old tasks/logs don't turn grey
  void removeSubject(Map s) {
    oldCol[s['n']] = s['c'];
    subjects.remove(s);
    save();
  }

  Color col(String s) {
    for (final e in subjects) {
      if (e['n'] == s) return Color(e['c']);
    }
    return Color((oldCol[s] as int?) ?? 0xFF9E9E9E);
  }
}

final st = Store();
