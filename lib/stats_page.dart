import 'package:flutter/material.dart';
import 'store.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  Widget _statValue(String value, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      );

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
          var taskTotal = 0, taskDone = 0;
          for (final d in days) {
            final k = dk(d);
            for (final e in st.tasksOn(k)) {
              taskTotal++;
              if (isDone(e, k)) taskDone++;
            }
          }
          final mon = DateTime(now.year, now.month, now.day - (now.weekday - 1) - 77);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('YOUR STUDY JOURNEY', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                const SizedBox(height: 8),
                const Text('Progress, not perfection.', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _statValue('${tot ~/ 60}h ${tot % 60}m', 'Focused this week')),
                  Container(width: 1, height: 42, color: Colors.white24),
                  Expanded(child: _statValue('$taskDone/$taskTotal', 'Tasks completed')),
                  Container(width: 1, height: 42, color: Colors.white24),
                  Expanded(child: _statValue('${st.streak} days', 'Current streak')),
                ]),
              ]),
            ),
            const SizedBox(height: 22),
            Text('Last 7 days', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Daily focus time · hours', style: TextStyle(color: cs.outline, fontSize: 12)),
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
            Text('Weekly breakdown', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Total: ${tot ~/ 60}h ${tot % 60}m  •  Tasks done: $taskDone/$taskTotal'),
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
            Text('Consistency map', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text('Last 12 weeks · darker means closer to your daily goal', style: TextStyle(fontSize: 12, color: cs.outline)),
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
