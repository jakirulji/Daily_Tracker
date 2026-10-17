import 'package:flutter/material.dart';
import 'store.dart';
import 'ui.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  Widget tile(BuildContext c, Map e, String d) {
    final done = isDone(e, d);
    final parts = <String>[
      e['s'],
      if ((e['tm'] ?? '') != '') e['tm'],
      if (e['rt'] != null) '⏰ ${e['rt']}',
      if (recurring(e)) (e['rp'] == 'daily' ? '🔁 daily' : '🔁 weekly'),
    ];
    return Dismissible(
      key: ObjectKey(e),
      background: Container(color: Colors.green, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), child: const Icon(Icons.check, color: Colors.white)),
      secondaryBackground: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          setDone(e, d, !isDone(e, d));
          st.save();
          return false;
        }
        return recurring(e) ? await confirm(c, 'Delete this repeating task and all its repeats?') : true;
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
                onTap: () => taskDialog(c, e: e),
                title: Text(e['t'], style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
                subtitle: Text(parts.join('  •  '), style: TextStyle(color: st.col(e['s']))),
                trailing: Checkbox(value: done, onChanged: (v) { setDone(e, d, v == true); st.save(); }),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget head(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 9),
        child: Text(s, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.25)),
      );

  Widget _quickMetric(IconData icon, String value, String label, Color color) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
        ]),
      );

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final now = DateTime.now(), today = dk(now), sel = st.sel, cs = Theme.of(c).colorScheme;
          final todays = st.tasksOn(sel);
          final List<Map> old = sel != today ? <Map>[] : st.tasks.where((e) => !recurring(e) && (e['d'] as String).compareTo(today) < 0 && e['x'] != true).toList();
          final m = st.minutes(today), g = (st.goal * 60).round(), h = now.hour;
          final v = (m / g).clamp(0.0, 1.0).toDouble();
          final left = st.examDate == '' ? 0 : DateTime.parse(st.examDate).difference(DateTime.parse(today)).inDays;
          final show = m >= g && st.cel != today;
          if (show) WidgetsBinding.instance.addPostFrameCallback((_) { st.cel = today; st.save(q: true); });
          final dn = todays.where((e) => isDone(e, sel)).length;
          final streak = st.streak;
          final badge = streak >= 30 ? '🏆' : streak >= 7 ? '🥇' : streak >= 3 ? '🥉' : '';
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
                      Text('🔥 $streak day streak $badge', style: w),
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
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                color: cs.surfaceContainerLow,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Expanded(child: _quickMetric(Icons.check_circle_outline_rounded, '${dn}/${todays.length}', 'Tasks done', cs.primary)),
                    Container(width: 1, height: 38, color: cs.outlineVariant),
                    Expanded(child: _quickMetric(Icons.pending_actions_rounded, '${todays.length - dn}', 'Remaining', cs.tertiary)),
                    Container(width: 1, height: 38, color: cs.outlineVariant),
                    Expanded(child: _quickMetric(Icons.bolt_rounded, '${(v * 100).round()}%', 'Focus goal', cs.secondary)),
                  ]),
                ),
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
                          Icon(Icons.circle, size: 6, color: st.active(k) ? cs.primary : Colors.transparent),
                        ]),
                      ),
                    );
                  }),
              ]),
              if (old.isNotEmpty) ...[head('Carry-over (pending)'), ...old.map((e) => tile(c, e, e['d']))],
              head('${sel == today ? 'Today' : sel}  $dn/${todays.length}'),
              if (todays.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Column(children: [Icon(Icons.auto_stories, size: 60, color: cs.outline), const SizedBox(height: 8), const Text('No tasks yet. Tap + to add ✨')])),
              ...todays.map((e) => tile(c, e, sel)),
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
