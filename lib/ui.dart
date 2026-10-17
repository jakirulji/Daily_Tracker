import 'dart:math';
import 'package:flutter/material.dart';
import 'store.dart';
import 'tuition.dart';
import 'exam_page.dart';

void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

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

Future<bool> confirm(BuildContext c, String msg, [String okLabel = 'Delete']) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(okLabel)),
        ],
      ),
    ) ??
    false;

/// Returns 'HH:mm' or null if cancelled.
Future<String?> pickTime(BuildContext c, String? cur) async {
  var init = TimeOfDay.now();
  if (cur != null) {
    final x = cur.split(':');
    if (x.length == 2) init = TimeOfDay(hour: int.tryParse(x[0]) ?? 8, minute: int.tryParse(x[1]) ?? 0);
  }
  final t = await showTimePicker(context: c, initialTime: init);
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Add (e == null) or edit a task.
void taskDialog(BuildContext c, {Map? e}) {
  final t = TextEditingController(text: e?['t'] ?? ''), tm = TextEditingController(text: e?['tm'] ?? '');
  String s = (e != null && st.subjects.any((x) => x['n'] == e['s'])) ? e['s'] : st.subjects[0]['n'];
  String? rt = e?['rt'];
  String rp = e?['rp'] ?? 'none';
  showDialog(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(e == null ? 'New task' : 'Edit task'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, autofocus: e == null, decoration: const InputDecoration(labelText: 'Task')),
            DropdownButton<String>(
              isExpanded: true,
              value: s,
              items: [for (final x in st.subjects) DropdownMenuItem<String>(value: x['n'], child: Text(x['n']))],
              onChanged: (v) => set(() => s = v!),
            ),
            TextField(controller: tm, decoration: const InputDecoration(labelText: 'Time (e.g. 6:00-7:00 PM)')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.alarm),
                  label: Text(rt == null ? 'Reminder: off' : 'Reminder: $rt'),
                  onPressed: () async {
                    final r = await pickTime(d, rt);
                    if (r != null) set(() => rt = r);
                  },
                ),
              ),
              if (rt != null) IconButton(icon: const Icon(Icons.close), onPressed: () => set(() => rt = null)),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'none', label: Text('Once')),
                ButtonSegment(value: 'daily', label: Text('Daily')),
                ButtonSegment(value: 'weekly', label: Text('Weekly')),
              ],
              selected: {rp},
              onSelectionChanged: (v) => set(() => rp = v.first),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (t.text.trim().isNotEmpty) {
                final Map m = e ?? <dynamic, dynamic>{'d': st.sel, 'x': false};
                m['t'] = t.text.trim();
                m['s'] = s;
                m['tm'] = tm.text.trim();
                m['rt'] = rt;
                m['rp'] = rp;
                if (e == null) st.tasks.add(m);
                st.save();
              }
              Navigator.pop(d);
            },
            child: Text(e == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

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
                  onTap: () {
                    st.switchTo(i);
                    // Open the selected profile's actual tracker screen instead of
                    // returning to the same-looking dashboard, which felt like no action.
                    st.goTab(1); // Prayer page for prayer profiles; task tracker for others.
                    Navigator.pop(c);
                  },
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
              ListTile(
                leading: const Icon(Icons.event_note_rounded),
                title: const Text('Exam Tracker'),
                subtitle: const Text('Exam routine, syllabus & countdown'),
                onTap: () { Navigator.pop(c); Navigator.push(c, MaterialPageRoute(builder: (_) => const ExamPage())); },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.school),
                title: const Text('Tuition Tracker'),
                subtitle: const Text('Students, attendance & salary'),
                onTap: () {
                  final nav = Navigator.of(c);
                  nav.pop();
                  nav.push(MaterialPageRoute(builder: (_) => const TuitionHome()));
                },
              ),
              const Divider(),
              ListTile(leading: const Icon(Icons.add), title: const Text('Add profile'), onTap: () { Navigator.pop(c); addProfile(c); }),
            ]),
          ),
        ),
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
