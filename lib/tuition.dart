import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'persist.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'store.dart' show dk;

// =====================================================================
// Tuition Tracker (separate section inside the app)
// Student map keys:
//   n=name, sal=monthly salary, cls=classes per month, days=[weekday 1..7 (Mon=1)],
//   since='yyyy-MM-dd' (start date), att={'yyyy-MM-dd': 'p'|'l'}  p=taught, l=student leave,
//   px=[{'for': missed class date, 'on': date actually taught}]
// Saved in SharedPreferences (phone storage) under key 'tuition_data'.
// =====================================================================

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']; // index = weekday - 1
const _order = [7, 1, 2, 3, 4, 5, 6]; // Sunday first

String _fd(String k) {
  final d = DateTime.parse(k);
  return '${d.day} ${_mon[d.month - 1]}';
}

String _fdw(String k) {
  final d = DateTime.parse(k);
  return '${_wd[d.weekday - 1]} ${d.day} ${_mon[d.month - 1]} ${d.year}';
}

String _money(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<bool> _ok(BuildContext c, String msg, [String label = 'Confirm']) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(label)),
        ],
      ),
    ) ??
    false;

// ---------- student helpers ----------
Map _att(Map s) => s['att'] as Map;
List _px(Map s) => s['px'] as List;
List _days(Map s) => s['days'] as List;
bool _sched(Map s, DateTime d) => _days(s).contains(d.weekday);
String? _mark(Map s, String k) => _att(s)[k] as String?;

Map? _pxOn(Map s, String k) {
  for (final x in _px(s)) {
    if (x['on'] == k) return x as Map;
  }
  return null;
}

Map? _pxFor(Map s, String k) {
  for (final x in _px(s)) {
    if (x['for'] == k) return x as Map;
  }
  return null;
}

class TStat {
  int taught = 0, proxy = 0, leave = 0, missed = 0, cls = 0;
  double amount = 0;
  int get payable => taught + proxy + leave;
  int get payableCapped => payable > cls ? cls : payable;
}

/// Month statistics. Payable days = taught + proxy (counted in the month of the
/// ORIGINAL missed class) + student-leave days. Capped at classes-per-month.
TStat statOf(Map s, int y, int m) {
  final r = TStat();
  r.cls = (s['cls'] as num).toInt();
  final today = dk(DateTime.now());
  final since = s['since'] as String;
  final n = DateTime(y, m + 1, 0).day;
  for (var i = 1; i <= n; i++) {
    final d = DateTime(y, m, i), k = dk(d), mk = _mark(s, k);
    if (mk == 'p') {
      r.taught++;
    } else if (mk == 'l') {
      r.leave++;
    } else if (_pxFor(s, k) != null) {
      r.proxy++;
    } else if (_sched(s, d) && k.compareTo(today) < 0 && k.compareTo(since) >= 0) {
      r.missed++;
    }
  }
  r.amount = r.cls > 0 ? (s['sal'] as num).toDouble() / r.cls * r.payableCapped : 0;
  return r;
}

// ---------- store ----------
class TStore extends ChangeNotifier {
  SharedPreferences? _p;
  List<Map> students = [];
  int sel = 0;
  Future<void> _saveQueue = Future<void>.value();

  Map? get cur => students.isEmpty ? null : students[sel.clamp(0, students.length - 1).toInt()];

  Future<void> load() async {
    final j = await Persist.read('tuition_data');
    if (j != null) {
      try {
        apply(j);
      } catch (_) {
        await Persist.keepBad('tuition_data', j);
      }
    }
  }

  /// Throws if the text is not a valid tuition backup.
  void apply(String j) {
    final m = jsonDecode(j) as Map;
    if (m['students'] is! List) throw 'bad';
    final l = [for (final e in (m['students'] as List)) _norm(Map.from(e as Map))];
    students = l;
    sel = 0;
  }

  Map _norm(Map s) {
    s['att'] = Map.from((s['att'] as Map?) ?? {});
    s['px'] = [for (final x in (s['px'] as List? ?? [])) Map.from(x as Map)];
    s['days'] = [for (final x in (s['days'] as List? ?? [])) (x as num).toInt()];
    s['n'] = (s['n'] ?? 'Student').toString();
    s['sal'] = (s['sal'] as num?) ?? 0;
    s['cls'] = (s['cls'] as num?) ?? 1;
    s['since'] = (s['since'] ?? dk(DateTime.now())).toString();
    return s;
  }

  String get json => jsonEncode({'v': 1, 'students': students});

  Future<void> save() {
    // Serialize writes and initialize storage if a save happens before load completes.
    String? snapshot;
    try {
      snapshot = json;
    } catch (e) {
      Persist.lastError = 'could not encode tuition data: $e';
    }
    if (snapshot != null) {
      final data = snapshot;
      _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
        await Persist.write('tuition_data', data);
      });
    }
    notifyListeners();
    return _saveQueue;
  }

  void select(int i) {
    sel = i;
    notifyListeners();
  }

  void addStudent(Map s) {
    students.add(_norm(s));
    sel = students.length - 1;
    save();
  }

  void removeStudent(Map s) {
    students.remove(s);
    sel = 0;
    save();
  }

  void setMark(Map s, String k, String? v) {
    if (v == null) {
      _att(s).remove(k);
    } else {
      _att(s)[k] = v;
    }
    save();
  }

  void addProxy(Map s, String f, String o) {
    _px(s).add({'for': f, 'on': o});
    save();
  }

  void removeProxy(Map s, Map x) {
    _px(s).remove(x);
    save();
  }
}

final tst = TStore();

// ---------- shared widgets ----------
Widget _monthBar(DateTime m, void Function(int) go) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(onPressed: () => go(-1), icon: const Icon(Icons.chevron_left)),
      Text('${_mon[m.month - 1]} ${m.year}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      IconButton(onPressed: () => go(1), icon: const Icon(Icons.chevron_right)),
    ]);

Widget _studentPick(Map? cur, void Function(Map) on) => DropdownButton<Map>(
      isExpanded: true,
      value: cur,
      hint: const Text('Select student'),
      items: [for (final s in tst.students) DropdownMenuItem<Map>(value: s, child: Text(s['n'].toString()))],
      onChanged: (v) {
        if (v != null) on(v);
      },
    );

Widget _row(String a, String b, {bool bold = false}) {
  final st = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 16 : 14);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a, style: st), Text(b, style: st)]),
  );
}

/// Date picker that only allows dates passing [ok] (and never in the future).
Future<DateTime?> _pickDate(BuildContext c, bool Function(DateTime) ok, String help) {
  final now = DateTime.now(), last = DateTime(now.year, now.month, now.day);
  DateTime? init;
  for (var i = 0; i < 800; i++) {
    final d = DateTime(last.year, last.month, last.day - i);
    if (ok(d)) {
      init = d;
      break;
    }
  }
  if (init == null) {
    _snack(c, 'No date available to choose');
    return Future.value(null);
  }
  return showDatePicker(
    context: c,
    initialDate: init,
    firstDate: DateTime(2020),
    lastDate: last,
    helpText: help,
    selectableDayPredicate: ok,
  );
}

// =====================================================================
// Home: calendar + side menu
// =====================================================================
class TuitionHome extends StatefulWidget {
  const TuitionHome({super.key});
  @override
  State<TuitionHome> createState() => _THState();
}

class _THState extends State<TuitionHome> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  void go(BuildContext c, Widget p) {
    Navigator.pop(c); // close drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => p));
  }

  Future<void> export() async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/tuition_backup_${dk(DateTime.now())}.json');
      await f.writeAsString(tst.json);
      await Share.shareXFiles([XFile(f.path)], subject: 'Tuition Tracker backup');
    } catch (_) {
      if (mounted) _snack(context, 'Could not create backup file');
    }
  }

  Future<void> restore() async {
    try {
      final r = await FilePicker.platform.pickFiles(withData: true);
      if (r == null || r.files.isEmpty || !mounted) return;
      final f = r.files.single;
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      if (!mounted) return;
      if (!await _ok(context, 'Replace all tuition data with this backup?', 'Replace')) return;
      tst.apply(utf8.decode(bytes));
      tst.save();
      if (mounted) _snack(context, 'Restored!');
    } catch (_) {
      if (mounted) _snack(context, 'Invalid tuition backup file');
    }
  }

  /// Calendar tap: only a scheduled, still-blank date can be marked. Once marked it is locked.
  Future<void> tap(Map s, DateTime d) async {
    final k = dk(d);
    if (!_sched(s, d) || _mark(s, k) != null || _pxFor(s, k) != null || _pxOn(s, k) != null) return;
    final r = await showDialog<String>(
      context: context,
      builder: (x) => SimpleDialog(
        title: Text(_fdw(k)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(x, 'p'),
            child: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 12), Text('Taught')]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(x, 'l'),
            child: const Row(children: [Icon(Icons.event_busy, color: Colors.orange), SizedBox(width: 12), Text('Student leave (still paid)')]),
          ),
        ],
      ),
    );
    if (r != null) tst.setMark(s, k, r);
  }

  Widget cell(Map s, DateTime? d, ColorScheme cs) {
    if (d == null) return const Expanded(child: SizedBox(height: 48));
    final k = dk(d), mk = _mark(s, k), pf = _pxFor(s, k), po = _pxOn(s, k);
    final today = dk(DateTime.now()), sc = _sched(s, d);
    Color? fill, border;
    var txt = cs.onSurface;
    String? tag;
    if (mk == 'p') {
      fill = Colors.green;
      txt = Colors.white;
      tag = '✓';
    } else if (mk == 'l') {
      fill = Colors.orange;
      txt = Colors.white;
      tag = 'L';
    } else if (po != null) {
      fill = Colors.blue;
      txt = Colors.white;
      tag = 'P';
    } else if (pf != null) {
      border = Colors.blue;
      tag = '↪';
    } else if (sc) {
      final missed = k.compareTo(today) < 0 && k.compareTo(s['since'] as String) >= 0;
      border = missed ? Colors.red : cs.primary;
    } else {
      txt = cs.outline.withOpacity(.6);
    }
    final bc = border;
    return Expanded(
      child: GestureDetector(
        onTap: () => tap(s, d),
        child: Container(
          height: 48,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: bc == null ? null : Border.all(color: bc, width: 1.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${d.day}', style: TextStyle(color: txt, fontWeight: FontWeight.bold)),
            if (tag != null) Text(tag, style: TextStyle(color: fill == null ? bc : txt, fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  Widget legend(Color c, String t, {bool outline = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: outline ? null : c, border: outline ? Border.all(color: c, width: 1.5) : null, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);

  Widget calendar(Map s, ColorScheme cs) {
    final first = DateTime(month.year, month.month, 1);
    final n = DateTime(month.year, month.month + 1, 0).day;
    final off = first.weekday % 7; // Sunday = 0
    final rows = ((off + n) / 7).ceil();
    DateTime? at(int i) => (i >= 1 && i <= n) ? DateTime(month.year, month.month, i) : null;
    return Column(children: [
      Row(children: [
        for (final w in _order) Expanded(child: Center(child: Text(_wd[w - 1], style: TextStyle(fontSize: 12, color: cs.outline)))),
      ]),
      const SizedBox(height: 4),
      for (var r = 0; r < rows; r++)
        Row(children: [
          for (var c0 = 0; c0 < 7; c0++) cell(s, at(r * 7 + c0 - off + 1), cs),
        ]),
    ]);
  }

  Widget summary(Map s) {
    final t = statOf(s, month.year, month.month);
    final pre = dk(DateTime(month.year, month.month, 1)).substring(0, 8);
    final pxs = _px(s).where((x) => (x['for'] as String).startsWith(pre)).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['n']} — ${_mon[month.month - 1]} summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _row('Taught', '${t.taught}'),
          _row('Proxy classes', '${t.proxy}'),
          _row('Student leave (paid)', '${t.leave}'),
          _row('Missed (unpaid)', '${t.missed}'),
          _row('Payable days', '${t.payableCapped} / ${t.cls}'),
          const Divider(),
          _row('Due', _money(t.amount), bold: true),
          for (final x in pxs) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Proxy for ${_fd(x['for'])} → taught ${_fd(x['on'])}', style: const TextStyle(fontSize: 12, color: Colors.blue))),
        ]),
      ),
    );
  }

  Widget _studentMonthlyBar(Map student, DateTime month, bool selected, ColorScheme cs, VoidCallback onTap) {
    final t = statOf(student, month.year, month.month);
    final amount = (student['sal'] as num).toDouble();
    final progress = amount <= 0 ? 0.0 : (t.amount / amount).clamp(0.0, 1.0);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      color: selected ? cs.primaryContainer.withOpacity(.58) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? cs.primary.withOpacity(.55) : cs.outlineVariant.withOpacity(.65)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: selected ? cs.primary : cs.secondaryContainer,
                child: Text(student['n'].toString().trim().isEmpty ? '?' : student['n'].toString().trim()[0].toUpperCase(),
                  style: TextStyle(color: selected ? cs.onPrimary : cs.onSecondaryContainer, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(student['n'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text('${t.taught} taught · ${t.proxy} proxy · ${t.leave} leave', style: TextStyle(fontSize: 11, color: cs.outline)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('৳${_money(t.amount)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cs.primary)),
                Text('of ৳${_money(amount)}', style: TextStyle(fontSize: 11, color: cs.outline)),
              ]),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                color: selected ? cs.primary : const Color(0xFF35A879),
              ),
            ),
            const SizedBox(height: 7),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${t.payableCapped}/${t.cls} payable days', style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w600)),
              Text(selected ? 'Selected' : 'View calendar', style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget menuTile(BuildContext c, IconData i, String t, Widget page) => ListTile(leading: Icon(i), title: Text(t), onTap: () => go(c, page));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: tst,
        builder: (c, _) {
          final s = tst.cur, cs = Theme.of(c).colorScheme;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Tuition Tracker', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.3)),
              centerTitle: false,
              actions: [
                IconButton(
                  tooltip: 'Add student',
                  onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const StudentsPage())),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
            drawer: Drawer(
              child: SafeArea(
                child: ListView(children: [
                  const Padding(padding: EdgeInsets.all(16), child: Text('Tuition Menu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  menuTile(c, Icons.person_add, 'Add Student', const StudentsPage()),
                  menuTile(c, Icons.payments, 'Salary', const SalaryPage()),
                  menuTile(c, Icons.event_available, 'Taught dates & total', const DatesPage(taught: true)),
                  menuTile(c, Icons.event_busy, 'Student leave dates & total', const DatesPage(taught: false)),
                  menuTile(c, Icons.edit_calendar, 'Edit Attendance', const EditAttPage()),
                  menuTile(c, Icons.swap_horiz, 'Add Proxy Class', const ProxyPage()),
                  const Divider(),
                  ListTile(leading: const Icon(Icons.ios_share), title: const Text('Backup (export)'), onTap: () { Navigator.pop(c); export(); }),
                  ListTile(leading: const Icon(Icons.restore), title: const Text('Restore backup'), onTap: () { Navigator.pop(c); restore(); }),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: const Text('Back to Daily Tracker'),
                    onTap: () {
                      final nav = Navigator.of(context);
                      nav.pop(); // drawer
                      nav.pop(); // tuition screen
                    },
                  ),
                ]),
              ),
            ),
            body: s == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.school, size: 64, color: cs.outline),
                      const SizedBox(height: 8),
                      const Text('No students yet'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const StudentsPage())),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Add Student'),
                      ),
                    ]),
                  )
                : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF252A67), Color(0xFF5557C8), Color(0xFF7775E8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF4F46C8).withOpacity(.20), blurRadius: 22, offset: const Offset(0, 9)),
                        ],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(15)),
                            child: const Icon(Icons.school_rounded, color: Colors.white, size: 25),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('TUITION OVERVIEW', style: TextStyle(color: Color(0xFFD9DBFF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.25)),
                            SizedBox(height: 3),
                            Text('Your teaching, organised.', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(13)),
                            child: Text('${tst.students.length} students', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        Text('${_mon[month.month - 1]} ${month.year}', style: const TextStyle(color: Color(0xFFE1E2FF), fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        Text('৳${_money(statOf(s, month.year, month.month).amount)}', style: const TextStyle(color: Colors.white, fontSize: 31, height: 1.1, fontWeight: FontWeight.w900, letterSpacing: -.7)),
                        const SizedBox(height: 4),
                        const Text('Estimated payable salary for selected student', style: TextStyle(color: Color(0xFFE1E2FF), fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('STUDENT PROFILES', style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      Text('${tst.students.length} total', style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: tst.students.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final student = tst.students[i];
                          final selected = student == s;
                          return ChoiceChip(
                            avatar: CircleAvatar(
                              radius: 12,
                              backgroundColor: selected ? Colors.white.withOpacity(.18) : cs.primaryContainer,
                              child: Text(student['n'].toString().trim().isEmpty ? '?' : student['n'].toString().trim()[0].toUpperCase(),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? Colors.white : cs.onPrimaryContainer)),
                            ),
                            label: Text(student['n'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                            selected: selected,
                            showCheckmark: false,
                            selectedColor: const Color(0xFF4F46C8),
                            backgroundColor: cs.surface,
                            side: BorderSide(color: selected ? const Color(0xFF4F46C8) : cs.outlineVariant),
                            labelStyle: TextStyle(color: selected ? Colors.white : cs.onSurface, fontWeight: FontWeight.w700),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            onSelected: (_) => tst.select(i),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: cs.outlineVariant.withOpacity(.65))),
                      child: Column(children: [
                        Row(children: [
                          const Icon(Icons.calendar_month_rounded, size: 20, color: Color(0xFF5557C8)),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Attendance calendar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                          _monthBar(month, (d) => setState(() => month = DateTime(month.year, month.month + d))),
                        ]),
                        const SizedBox(height: 10),
                        calendar(s, cs),
                        const SizedBox(height: 12),
                        Wrap(spacing: 12, runSpacing: 9, children: [
                          legend(const Color(0xFF239B68), 'Taught'),
                          legend(const Color(0xFFE69A32), 'Student leave'),
                          legend(const Color(0xFF4775E8), 'Proxy day'),
                          legend(const Color(0xFF4775E8), 'Covered by proxy', outline: true),
                          legend(cs.primary, 'Tap to mark', outline: true),
                          legend(const Color(0xFFD9534F), 'Missed', outline: true),
                        ]),
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerLeft, child: Text('Marked dates are locked. To change, use Menu → Edit Attendance.', style: TextStyle(fontSize: 11, color: cs.outline))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('MONTHLY STUDENT SUMMARY', style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    for (final student in tst.students)
                      _studentMonthlyBar(student, month, student == s, cs, () => tst.select(tst.students.indexOf(student))),
                    const SizedBox(height: 12),
                    summary(s),
                  ]),
          );
        },
      );
}

// =====================================================================
// Add / edit / delete students
// =====================================================================
void studentDialog(BuildContext c, {Map? s}) {
  final n = TextEditingController(text: s?['n']?.toString() ?? '');
  final sal = TextEditingController(text: s == null ? '' : _money(s['sal'] as num));
  final cls = TextEditingController(text: s == null ? '12' : '${s['cls']}');
  final days = <int>{if (s != null) ...List<int>.from(_days(s))};
  String since = (s?['since'] ?? dk(DateTime.now())).toString();
  String err = '';
  showDialog(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text(s == null ? 'Add Student' : 'Edit Student'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Student name')),
            TextField(controller: sal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly salary')),
            TextField(controller: cls, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Classes per month')),
            const SizedBox(height: 12),
            const Text('Teaching days'),
            Wrap(spacing: 6, children: [
              for (final w in _order)
                FilterChip(
                  label: Text(_wd[w - 1]),
                  selected: days.contains(w),
                  onSelected: (v) => setS(() {
                    if (v) {
                      days.add(w);
                    } else {
                      days.remove(w);
                    }
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await showDatePicker(context: d, initialDate: DateTime.parse(since), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (p != null) setS(() => since = dk(p));
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Start date: ${_fdw(since)}'),
            ),
            const Text('Days before the start date are never counted as missed.', style: TextStyle(fontSize: 11)),
            if (err != '') Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: Colors.red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final sv = double.tryParse(sal.text.trim()), cv = int.tryParse(cls.text.trim());
              if (n.text.trim().isEmpty || sv == null || sv < 0 || cv == null || cv < 1 || days.isEmpty) {
                setS(() => err = 'Enter name, salary, classes per month and at least one teaching day.');
                return;
              }
              final dl = [for (final w in _order) if (days.contains(w)) w];
              if (s == null) {
                tst.addStudent({'n': n.text.trim(), 'sal': sv, 'cls': cv, 'days': dl, 'since': since, 'att': {}, 'px': []});
              } else {
                s['n'] = n.text.trim();
                s['sal'] = sv;
                s['cls'] = cv;
                s['days'] = dl;
                s['since'] = since;
                tst.save();
              }
              Navigator.pop(d);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

class StudentsPage extends StatelessWidget {
  const StudentsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: tst,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: const Text('Students')),
          floatingActionButton: FloatingActionButton.extended(onPressed: () => studentDialog(c), icon: const Icon(Icons.person_add), label: const Text('Add Student')),
          body: tst.students.isEmpty
              ? const Center(child: Text('No students yet. Tap Add Student.'))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final s in tst.students)
                    Card(
                      child: ListTile(
                        title: Text(s['n'].toString()),
                        subtitle: Text('${_money(s['sal'] as num)} / month  •  ${s['cls']} classes\n${[for (final w in _order) if (_days(s).contains(w)) _wd[w - 1]].join(', ')}'),
                        isThreeLine: true,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.edit), onPressed: () => studentDialog(c, s: s)),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              if (await _ok(c, 'Delete ${s['n']} and all attendance records?', 'Delete')) tst.removeStudent(s);
                            },
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 80),
                ]),
        ),
      );
}

// =====================================================================
// Salary
// =====================================================================
class SalaryPage extends StatefulWidget {
  const SalaryPage({super.key});
  @override
  State<SalaryPage> createState() => _SalaryState();
}

class _SalaryState extends State<SalaryPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: tst,
        builder: (c, _) {
          var total = 0.0;
          final cards = <Widget>[];
          for (final s in tst.students) {
            final t = statOf(s, month.year, month.month);
            total += t.amount;
            cards.add(Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['n'].toString(), style: Theme.of(c).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  _row('Classes per month', '${t.cls}'),
                  _row('Monthly salary', _money(s['sal'] as num)),
                  _row('Taught', '${t.taught}'),
                  _row('Proxy classes', '${t.proxy}'),
                  _row('Student leave (paid)', '${t.leave}'),
                  _row('Missed (unpaid)', '${t.missed}'),
                  _row('Payable days', '${t.payableCapped}'),
                  const Divider(),
                  _row('Amount due', _money(t.amount), bold: true),
                ]),
              ),
            ));
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Salary')),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              _monthBar(month, (d) => setState(() => month = DateTime(month.year, month.month + d))),
              const Text('Payable days = Taught + Proxy + Student leave. Formula: salary ÷ classes × payable days.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              if (cards.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No students yet'))),
              ...cards,
              if (cards.isNotEmpty)
                Card(
                  color: Theme.of(c).colorScheme.primaryContainer,
                  child: Padding(padding: const EdgeInsets.all(14), child: _row('Total this month', _money(total), bold: true)),
                ),
            ]),
          );
        },
      );
}

// =====================================================================
// Taught dates / Student-leave dates (with totals)
// =====================================================================
class DatesPage extends StatefulWidget {
  final bool taught;
  const DatesPage({super.key, required this.taught});
  @override
  State<DatesPage> createState() => _DatesState();
}

class _DatesState extends State<DatesPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: tst,
        builder: (c, _) {
          final pre = dk(DateTime(month.year, month.month, 1)).substring(0, 8);
          final want = widget.taught ? 'p' : 'l';
          final cards = <Widget>[];
          for (final s in tst.students) {
            final ents = <MapEntry<String, String>>[];
            _att(s).forEach((k, v) {
              if (k.toString().startsWith(pre) && v == want) ents.add(MapEntry(k.toString(), _fdw(k.toString())));
            });
            if (widget.taught) {
              for (final x in _px(s)) {
                if ((x['for'] as String).startsWith(pre)) ents.add(MapEntry(x['on'] as String, '${_fdw(x['on'] as String)}  (proxy for ${_fd(x['for'] as String)})'));
              }
            }
            ents.sort((a, b) => a.key.compareTo(b.key));
            cards.add(Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['n']}  —  Total: ${ents.length} days', style: Theme.of(c).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (ents.isEmpty) const Text('None') else Wrap(spacing: 6, runSpacing: 6, children: [for (final e in ents) Chip(label: Text(e.value, style: const TextStyle(fontSize: 12)))]),
                ]),
              ),
            ));
          }
          return Scaffold(
            appBar: AppBar(title: Text(widget.taught ? 'Taught dates & total' : 'Student leave dates & total')),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              _monthBar(month, (d) => setState(() => month = DateTime(month.year, month.month + d))),
              if (cards.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No students yet'))),
              ...cards,
            ]),
          );
        },
      );
}

// =====================================================================
// Edit attendance (the ONLY place where a marked date can be changed)
// =====================================================================
class EditAttPage extends StatefulWidget {
  const EditAttPage({super.key});
  @override
  State<EditAttPage> createState() => _EditAttState();
}

class _EditAttState extends State<EditAttPage> {
  Map? sel;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Map? get s => (sel != null && tst.students.contains(sel)) ? sel : tst.cur;

  static const _lab = {'n': 'Blank', 'p': 'Taught', 'l': 'Student leave'};

  Widget row(Map sd, int i) {
    final d = DateTime(month.year, month.month, i), k = dk(d);
    final mk = _mark(sd, k), pf = _pxFor(sd, k), po = _pxOn(sd, k);
    if (!_sched(sd, d) && mk == null && pf == null && po == null) return const SizedBox.shrink();
    if (pf != null || po != null) {
      return ListTile(
        title: Text(_fdw(k)),
        subtitle: Text(pf != null ? 'Covered by proxy on ${_fd(pf['on'])} (delete the proxy to edit)' : 'Proxy class for ${_fd(po!['for'])}'),
        trailing: const Icon(Icons.lock_outline),
      );
    }
    final cur = mk ?? 'n';
    return ListTile(
      title: Text(_fdw(k)),
      trailing: DropdownButton<String>(
        value: cur,
        items: [for (final e in _lab.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
        onChanged: (v) async {
          if (v == null || v == cur) return;
          if (await _ok(context, 'Change ${_fdw(k)} from ${_lab[cur]} to ${_lab[v]}?')) {
            tst.setMark(sd, k, v == 'n' ? null : v);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: tst,
        builder: (c, _) {
          final sd = s;
          final n = DateTime(month.year, month.month + 1, 0).day;
          return Scaffold(
            appBar: AppBar(title: const Text('Edit Attendance')),
            body: sd == null
                ? const Center(child: Text('No students yet'))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    _studentPick(sd, (v) => setState(() => sel = v)),
                    _monthBar(month, (d) => setState(() => month = DateTime(month.year, month.month + d))),
                    const Text('Changing a date asks for confirmation. Only teaching days (and already marked days) are listed.', style: TextStyle(fontSize: 12)),
                    for (var i = 1; i <= n; i++) row(sd, i),
                  ]),
          );
        },
      );
}

// =====================================================================
// Proxy class: a missed class (date A) taught later on another date (B)
// =====================================================================
class ProxyPage extends StatefulWidget {
  const ProxyPage({super.key});
  @override
  State<ProxyPage> createState() => _ProxyState();
}

class _ProxyState extends State<ProxyPage> {
  Map? sel;
  String? forK, onK;
  Map? get s => (sel != null && tst.students.contains(sel)) ? sel : tst.cur;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: tst,
        builder: (c, _) {
          final sd = s;
          if (sd == null) return Scaffold(appBar: AppBar(title: const Text('Add Proxy Class')), body: const Center(child: Text('No students yet')));
          final list = List<Map>.from(_px(sd).map((e) => e as Map))..sort((a, b) => (b['on'] as String).compareTo(a['on'] as String));
          final f = forK, o = onK;
          return Scaffold(
            appBar: AppBar(title: const Text('Add Proxy Class')),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              _studentPick(sd, (v) => setState(() { sel = v; forK = null; onK = null; })),
              const Text('Use this when you could not teach on a scheduled day and taught it later on another day. It replaces the missed class — it is not paid twice.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_busy),
                label: Text(f == null ? '1. Pick the missed class date' : 'Missed class: ${_fdw(f)}'),
                onPressed: () async {
                  final p = await _pickDate(
                    c,
                    (d) {
                      final k = dk(d);
                      return _sched(sd, d) && _mark(sd, k) == null && _pxFor(sd, k) == null && _pxOn(sd, k) == null && k.compareTo(sd['since'] as String) >= 0;
                    },
                    'Missed class date (blank scheduled days only)',
                  );
                  if (p != null) setState(() { forK = dk(p); onK = null; });
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_available),
                label: Text(o == null ? '2. Pick the day you actually taught' : 'Taught on: ${_fdw(o)}'),
                onPressed: f == null
                    ? null
                    : () async {
                        final p = await _pickDate(
                          c,
                          (d) {
                            final k = dk(d);
                            return _mark(sd, k) == null && _pxFor(sd, k) == null && _pxOn(sd, k) == null && k.compareTo(f) > 0;
                          },
                          'Day you actually taught',
                        );
                        if (p != null) setState(() => onK = dk(p));
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save proxy'),
                onPressed: (f == null || o == null)
                    ? null
                    : () {
                        tst.addProxy(sd, f, o);
                        setState(() { forK = null; onK = null; });
                        _snack(c, 'Proxy saved: ${_fd(o)} covers ${_fd(f)}');
                      },
              ),
              const SizedBox(height: 20),
              Text('Saved proxies', style: Theme.of(c).textTheme.titleMedium),
              if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('None yet')),
              for (final x in list)
                Card(
                  child: ListTile(
                    title: Text('Proxy for ${_fd(x['for'] as String)}'),
                    subtitle: Text('Taught on ${_fdw(x['on'] as String)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        if (await _ok(c, 'Delete this proxy? The missed day becomes blank again.', 'Delete')) tst.removeProxy(sd, x);
                      },
                    ),
                  ),
                ),
            ]),
          );
        },
      );
}
