import 'package:flutter/material.dart';
import 'store.dart';
import 'ui.dart';

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
                controlAffinity: ListTileControlAffinity.leading,
                value: st.pd(today, p['n']),
                title: Text(p['n']),
                subtitle: p['rt'] == null ? null : Text('⏰ Reminder ${p['rt']}'),
                secondary: PopupMenuButton<String>(
                  icon: Icon(p['rt'] == null ? Icons.alarm_add : Icons.alarm_on, color: p['rt'] == null ? cs.outline : cs.primary),
                  onSelected: (v) async {
                    if (v == 'set') {
                      final r = await pickTime(c, p['rt']);
                      if (r != null) { p['rt'] = r; st.save(); }
                    } else if (v == 'clr') {
                      p['rt'] = null;
                      st.save();
                    } else {
                      st.prayers.remove(p);
                      st.save();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'set', child: Text('Set reminder time')),
                    if (p['rt'] != null) const PopupMenuItem(value: 'clr', child: Text('Remove reminder')),
                    const PopupMenuItem(value: 'del', child: Text('Delete')),
                  ],
                ),
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
