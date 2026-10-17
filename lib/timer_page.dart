import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'store.dart';
import 'notify.dart';
import 'ui.dart';
import 'attention.dart';

/// Timer is based on an end timestamp (not a ticking counter), so it stays
/// correct when the app is minimised / screen is off, and a notification is
/// scheduled for the moment it finishes.
class TimerPage extends StatefulWidget {
  const TimerPage({super.key});
  @override
  State<TimerPage> createState() => _TP();
}

class _TP extends State<TimerPage> with WidgetsBindingObserver {
  String? sub;
  bool brk = false, run = false;
  int done = 0;
  Timer? t;
  DateTime? endAt;
  Map get md => st.modes[st.mi];
  int get total => ((brk ? md['b'] : md['f']) as int) * 60;
  late int left = total;
  String get who => st.subjects.any((e) => e['n'] == sub) ? sub! : st.subjects[0]['n'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (st.subjects.isNotEmpty) sub = st.subjects.first['n'] as String;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && run) setState(sync);
  }

  // Recompute remaining time from the end timestamp; finish if it has passed.
  void sync() {
    if (!run || endAt == null) return;
    final r = (endAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    if (r <= 0) {
      finish();
    } else {
      left = r;
    }
  }

  void finish() {
    HapticFeedback.heavyImpact();
    // Keep Attention mode on into the break only if the focus session ended on time
    // (not if the app was closed for a long time), and the user chose that in Settings.
    final onTime = endAt != null && DateTime.now().difference(endAt!).inSeconds < 60;
    final keep = !brk && st.attAuto && st.attBreak && onTime;
    if (!brk) { st.addLog(who, md['f']); done++; }
    stop(keepAtt: keep);
    brk = !brk;
    left = total;
    if (keep) {
      att.enable('pomodoro', DateTime.now().add(Duration(minutes: (md['b'] as num).toInt() + 5)));
    }
  }

  void stop({bool keepAtt = false}) {
    t?.cancel();
    t = null;
    run = false;
    endAt = null;
    Notif.clearTimer();
    // Only switches off Attention mode if pomodoro itself turned it on.
    if (!keepAtt) att.disable('pomodoro');
  }

  // Attention mode ends 3 s before the timer ends, so the "session done" notification can still make a sound.
  // If it should stay on into the break, it runs 5 min past the end (time to press Start on the break).
  DateTime _attUntil() => (!brk && st.attBreak) ? endAt!.add(const Duration(minutes: 5)) : endAt!.subtract(const Duration(seconds: 3));

  Future<void> _attOn() async {
    final ok = await att.enable('pomodoro', _attUntil());
    if (!ok && mounted) snack(context, 'Attention mode could not start. Check Do Not Disturb access in Settings.');
  }

  void tick(Timer _) => setState(sync);

  void toggle() {
    if (run) {
      sync();
      if (run) stop();
    } else {
      run = true;
      endAt = DateTime.now().add(Duration(seconds: left));
      t = Timer.periodic(const Duration(seconds: 1), tick);
      Notif.setTimer(
        brk ? 'Break over ☕' : 'Focus session done 🎉',
        brk ? 'Time to get back to focus.' : '${md['f']} min of focus on $who. Take a break!',
        endAt!,
      );
      if (st.attAuto && (!brk || st.attBreak)) _attOn();
    }
    setState(() {});
  }

  void reset() {
    if (run) sync();
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    t?.cancel();
    if (run) {
      Notif.clearTimer();
      att.disable('pomodoro');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          if (left > total) left = total;
          final n = done == 0 ? 0 : (done - 1) % 4 + 1, col = st.col(who);
          final cs = Theme.of(c).colorScheme;
          return ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 28), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(15)), child: Icon(brk ? Icons.coffee_rounded : Icons.bolt_rounded, color: Colors.white, size: 25)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(brk ? 'RECOVERY TIME' : 'FOCUS SESSION', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                    const SizedBox(height: 4),
                    Text(run ? 'Stay in the zone' : 'Make this session count', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  ])),
                ]),
                const SizedBox(height: 12),
                Text('Choose a subject and a timer mode, then press Start. Your completed focus time is saved to Stats.', style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 18),
            Text('TIMER MODE', style: TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: cs.outline)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < st.modes.length; i++)
                ChoiceChip(label: Text('${st.modes[i]['n']} ${st.modes[i]['f']}/${st.modes[i]['b']}'), selected: i == st.mi, onSelected: (_) => pick(i)),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Custom'), onPressed: addMode),
            ]),
            const SizedBox(height: 18),
            Text('STUDY SUBJECT', style: TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: cs.outline)),
            const SizedBox(height: 4),
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
