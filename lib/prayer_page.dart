import 'package:flutter/material.dart';
import 'store.dart';
import 'ui.dart';

class PrayerPage extends StatelessWidget {
  const PrayerPage({super.key});

  static const Color _navy = Color(0xFF172554);
  static const Color _violet = Color(0xFF6558D3);
  static const Color _mint = Color(0xFF39C6A5);

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) {
          final cs = Theme.of(c).colorScheme;
          if (st.faith == '') {
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_navy, _violet],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.self_improvement_rounded, color: Colors.white, size: 34),
                      SizedBox(height: 16),
                      Text('Make space for what matters.', style: TextStyle(color: Colors.white, fontSize: 24, height: 1.15, fontWeight: FontWeight.w800)),
                      SizedBox(height: 8),
                      Text('Choose a prayer tradition to personalise your daily checklist. You can add, edit or remove items later.', style: TextStyle(color: Color(0xFFE5E7FF), fontSize: 13, height: 1.45)),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text('CHOOSE YOUR PRACTICE', style: TextStyle(fontSize: 11, letterSpacing: 1.15, fontWeight: FontWeight.w800, color: cs.outline)),
                const SizedBox(height: 10),
                for (final f in faiths.keys)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19), side: BorderSide(color: cs.outlineVariant.withOpacity(.7))),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      leading: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: _violet.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
                        child: Icon(_faithIcon(f), color: _violet),
                      ),
                      title: Text(f, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(faiths[f]!.isEmpty ? 'Create your own routine' : '${faiths[f]!.length} suggested daily practices'),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () => st.setFaith(f),
                    ),
                  ),
              ],
            );
          }

          final now = DateTime.now();
          final today = dk(now);
          final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
          final n = st.prayers.length;
          final dn = st.pcount(today);
          var wk = 0;
          for (final d in days) {
            wk += st.pcount(dk(d));
          }
          bool full(DateTime d) => n > 0 && st.pcount(dk(d)) == n;
          var d0 = now;
          if (!full(d0)) d0 = d0.subtract(const Duration(days: 1));
          var streak = 0;
          while (full(d0)) {
            streak++;
            d0 = d0.subtract(const Duration(days: 1));
          }
          final progress = n == 0 ? 0.0 : (dn / n).clamp(0.0, 1.0);
          final percent = (progress * 100).round();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(21),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_navy, Color(0xFF37358A), _violet],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(27),
                  boxShadow: [BoxShadow(color: _violet.withOpacity(.20), blurRadius: 22, offset: const Offset(0, 9))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.13), borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.spa_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('DAILY PRAYER', style: TextStyle(color: Color(0xFFD8D7FF), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      const SizedBox(height: 4),
                      Text(st.faith, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    ])),
                    PopupMenuButton<String>(
                      tooltip: 'Prayer settings',
                      iconColor: Colors.white,
                      onSelected: (v) {
                        if (v == 'faith') {
                          st.faith = '';
                          st.save();
                        } else if (v == 'add') {
                          _addPrayer(c);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'add', child: Text('Add prayer')),
                        PopupMenuItem(value: 'faith', child: Text('Change tradition')),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 22),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_dateLabel(now), style: const TextStyle(color: Color(0xFFE1E0FF), fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      Text('$dn of $n completed', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -.4)),
                    ])),
                    SizedBox(
                      width: 67, height: 67,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox.expand(child: CircularProgressIndicator(
                          value: progress, strokeWidth: 6,
                          backgroundColor: Colors.white.withOpacity(.16),
                          valueColor: const AlwaysStoppedAnimation<Color>(_mint),
                          strokeCap: StrokeCap.round,
                        )),
                        Text('$percent%', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 17),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white.withOpacity(.14), valueColor: const AlwaysStoppedAnimation<Color>(_mint)),
                  ),
                  const SizedBox(height: 11),
                  Text(n > 0 && dn == n ? 'Beautiful work — you completed today’s routine.' : 'One step at a time. Keep going at your own pace.', style: const TextStyle(color: Color(0xFFE1E0FF), fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _metricCard(cs, Icons.local_fire_department_rounded, '$streak days', 'Full-day streak', const Color(0xFFFFA45B))),
                const SizedBox(width: 10),
                Expanded(child: _metricCard(cs, Icons.date_range_rounded, '$wk / ${n * 7}', 'This week', const Color(0xFF52BDA3))),
              ]),
              const SizedBox(height: 23),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Today’s routine', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.45, color: cs.onSurface)),
                  const SizedBox(height: 3),
                  Text('Tap an item when you’ve completed it', style: TextStyle(fontSize: 12, color: cs.outline)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: _violet.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                  child: Text('$dn/$n done', style: const TextStyle(color: _violet, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 11),
              if (st.prayers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: cs.outlineVariant)),
                  child: const Column(children: [
                    Icon(Icons.checklist_rounded, size: 34, color: _violet),
                    SizedBox(height: 9),
                    Text('Your routine is empty', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Add a prayer or practice to get started.', textAlign: TextAlign.center),
                  ]),
                ),
              for (var i = 0; i < st.prayers.length; i++)
                _prayerTile(c, cs, st.prayers[i], i, today),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _addPrayer(c),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add a prayer or practice'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(49),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: BorderSide(color: _violet.withOpacity(.45)),
                  foregroundColor: _violet,
                ),
              ),
              const SizedBox(height: 25),
              Row(children: [
                const Icon(Icons.calendar_month_rounded, color: _violet, size: 21),
                const SizedBox(width: 8),
                Expanded(child: Text('Last 7 days', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: cs.onSurface))),
                Text('Tap a circle to edit', style: TextStyle(fontSize: 11, color: cs.outline)),
              ]),
              const SizedBox(height: 5),
              Text('Your consistency at a glance', style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 15, 12, 14),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(23), border: Border.all(color: cs.outlineVariant.withOpacity(.7))),
                child: Column(children: [
                  Row(children: [
                    const SizedBox(width: 84),
                    for (final d in days)
                      Expanded(child: Center(child: Text(_weekday(d), style: TextStyle(fontSize: 10, fontWeight: d.day == now.day && d.month == now.month ? FontWeight.w900 : FontWeight.w600, color: d.day == now.day && d.month == now.month ? _violet : cs.outline)))),
                  ]),
                  const SizedBox(height: 11),
                  for (final p in st.prayers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        SizedBox(width: 84, child: Text(p['n'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                        for (final d in days)
                          Expanded(child: Center(child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => st.ptoggle(dk(d), p['n'].toString()),
                            child: Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: st.pd(dk(d), p['n'].toString()) ? _mint : cs.surfaceContainerHighest,
                                border: Border.all(color: st.pd(dk(d), p['n'].toString()) ? _mint : cs.outlineVariant),
                              ),
                              child: Icon(st.pd(dk(d), p['n'].toString()) ? Icons.check_rounded : Icons.remove, size: 14, color: st.pd(dk(d), p['n'].toString()) ? Colors.white : cs.outline.withOpacity(.55)),
                            ),
                          ))),
                      ]),
                    ),
                  if (st.prayers.isEmpty) Text('Add items above to start tracking your week.', style: TextStyle(color: cs.outline, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 14),
            ],
          );
        },
      );

  static IconData _faithIcon(String faith) {
    switch (faith) {
      case 'Islam': return Icons.nightlight_round;
      case 'Hinduism': return Icons.local_florist_rounded;
      case 'Buddhism': return Icons.self_improvement_rounded;
      case 'Christianity': return Icons.church_rounded;
      case 'Sikhism': return Icons.wb_sunny_rounded;
      default: return Icons.favorite_rounded;
    }
  }

  static String _dateLabel(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  static String _weekday(DateTime d) {
    const days = ['M','T','W','T','F','S','S'];
    return days[d.weekday - 1];
  }

  Widget _metricCard(ColorScheme cs, IconData icon, String value, String label, Color accent) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: accent.withOpacity(.14), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 2),
            Text(label, maxLines: 2, style: TextStyle(fontSize: 10, color: cs.outline, height: 1.2)),
          ])),
        ]),
      );

  Widget _prayerTile(BuildContext c, ColorScheme cs, Map p, int i, String today) {
    final done = st.pd(today, p['n'].toString());
    final time = p['rt'];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: done ? _mint.withOpacity(.09) : cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: done ? _mint.withOpacity(.55) : cs.outlineVariant.withOpacity(.75)),
      ),
      child: Row(children: [
        const SizedBox(width: 13),
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: done ? _mint.withOpacity(.17) : _violet.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
          child: Icon(done ? Icons.check_rounded : Icons.spa_outlined, color: done ? const Color(0xFF168B70) : _violet, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => st.ptoggle(today, p['n'].toString()),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['n'].toString(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, decoration: done ? TextDecoration.lineThrough : TextDecoration.none, color: done ? cs.outline : cs.onSurface)),
              const SizedBox(height: 4),
              Text(time == null ? (done ? 'Completed today' : 'Tap to mark complete') : 'Reminder · $time', style: TextStyle(fontSize: 11, color: cs.outline)),
            ]),
          ),
        )),
        if (time != null) const Icon(Icons.notifications_active_rounded, size: 17, color: _violet),
        PopupMenuButton<String>(
          tooltip: 'Prayer options',
          icon: Icon(Icons.more_vert_rounded, color: cs.outline),
          onSelected: (v) async {
            if (v == 'set') {
              final r = await pickTime(c, time);
              if (r != null) { p['rt'] = r; st.save(); }
            } else if (v == 'clr') {
              p['rt'] = null;
              st.save();
            } else if (v == 'rename') {
              final name = await ask(c, 'Prayer name');
              if (name != null && name.trim().isNotEmpty && name.trim() != p['n'].toString()) {
                final old = p['n'].toString();
                for (final entry in st.pdone.values) {
                  if (entry is List && entry.contains(old)) {
                    entry.remove(old);
                    entry.add(name.trim());
                  }
                }
                p['n'] = name.trim();
                st.save();
              }
            } else if (v == 'del') {
              st.prayers.remove(p);
              st.save();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'set', child: Text('Set reminder time')),
            if (time != null) const PopupMenuItem(value: 'clr', child: Text('Remove reminder')),
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(value: 'del', child: Text('Delete')),
          ],
        ),
        const SizedBox(width: 3),
      ]),
    );
  }

  Future<void> _addPrayer(BuildContext c) async {
    final name = await ask(c, 'Prayer name');
    if (name == null || name.trim().isEmpty) return;
    if (st.prayers.any((p) => p['n'].toString().toLowerCase() == name.trim().toLowerCase())) return;
    st.prayers.add({'n': name.trim()});
    st.save();
  }
}
