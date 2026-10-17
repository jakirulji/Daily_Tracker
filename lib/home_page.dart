import 'package:flutter/material.dart';
import 'store.dart';
import 'tuition.dart';
import 'exam_page.dart';
import 'ui.dart';
import 'attention.dart';

class HomeDashboardPage extends StatelessWidget {
  const HomeDashboardPage({super.key});

  String _duration(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  Map? _profileData(String type) {
    final i = st.profiles.indexWhere((p) => p['t'] == type);
    return i < 0 ? null : st.dataOf(i);
  }

  int _minutes(Map data, String day) {
    final logs = data['logs'] as Map? ?? {};
    final values = logs[day] as Map? ?? {};
    return values.values.fold<int>(0, (sum, value) => sum + (value as num).toInt());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListenableBuilder(
          listenable: tst,
          builder: (context, __) {
            final now = DateTime.now();
            final today = dk(now);
            final cs = Theme.of(context).colorScheme;
            final study = _profileData('tracker');
            final prayer = _profileData('prayer');

            final tasks = study == null
                ? <Map>[]
                : List<Map>.from(study['tasks'] ?? []).where((e) => occurs(e, today)).toList();
            final completed = study == null
                ? 0
                : tasks.where((e) => isDone(e, today)).length;
            final focusMinutes = study == null ? 0 : _minutes(study, today);
            final goal = study == null ? 240 : (((study['goal'] ?? 4) as num) * 60).round();
            final focusProgress = goal <= 0 ? 0.0 : (focusMinutes / goal).clamp(0.0, 1.0).toDouble();
            final prayerItems = List<Map>.from(prayer?['prayers'] ?? []);
            final prayerDone = prayerItems.where((p) {
              final done = prayer?['pdone'] as Map? ?? {};
              return ((done[today] as List?) ?? []).contains(p['n']);
            }).length;
            final students = tst.students;
            final scheduled = students.where((s) {
              final days = s['days'] as List? ?? [];
              return days.contains(now.weekday) && today.compareTo((s['since'] ?? today).toString()) >= 0;
            }).toList();
            final taught = scheduled.where((s) => ((s['att'] as Map?) ?? {})[today] == 'p').length;
            final leave = scheduled.where((s) => ((s['att'] as Map?) ?? {})[today] == 'l').length;
            final monthDue = students.fold<double>(0, (sum, s) =>
                sum + statOf(s, now.year, now.month).amount);
            final trackerIndex = st.profiles.indexWhere((p) => p['t'] != 'prayer');
            final examProfile = trackerIndex;
            final examData = examProfile < 0 ? <Map>[] : List<Map>.from(st.dataOf(examProfile)['exams'] ?? []);
            final todayDate = DateTime(now.year, now.month, now.day);
            DateTime? nextDateFor(Map group) {
              final subjects = List<Map>.from(group['subjects'] ?? []);
              final dates = subjects.map((s) => DateTime.tryParse((s['date'] ?? group['endDate'] ?? group['date'] ?? '').toString())).whereType<DateTime>().where((d) => !DateTime(d.year,d.month,d.day).isBefore(todayDate)).toList()..sort();
              if (dates.isNotEmpty) return dates.first;
              return DateTime.tryParse((group['endDate'] ?? group['date'] ?? '').toString());
            }
            final upcomingExams = examData.where((e) {
              if (e['done'] == true) return false;
              final d = nextDateFor(e);
              return d != null && !DateTime(d.year,d.month,d.day).isBefore(todayDate);
            }).toList()..sort((a,b) => nextDateFor(a)!.compareTo(nextDateFor(b)!));
            final nextExam = upcomingExams.isEmpty ? null : upcomingExams.first;
            final prayerIndex = st.profiles.indexWhere((p) => p['t'] == 'prayer');

            void openTracker(int tab) {
              if (trackerIndex < 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a study profile first.')));
                return;
              }
              if (st.cur != trackerIndex) st.switchTo(trackerIndex);
              if (tab == 1) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const ProfileTrackerScreen(isPrayer: false),
                ));
              } else {
                st.goTab(tab);
              }
            }

            void openPrayer() {
              if (prayerIndex < 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a prayer profile first.')));
                return;
              }
              if (st.cur != prayerIndex) st.switchTo(prayerIndex);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const ProfileTrackerScreen(isPrayer: true),
              ));
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(21),
                  decoration: BoxDecoration(
                    // Fixed deeper tones keep white text readable with every theme seed.
                    gradient: LinearGradient(
                      colors: Theme.of(context).brightness == Brightness.dark
                          ? const [Color(0xFF34205F), Color(0xFF542B55)]
                          : const [Color(0xFF49318A), Color(0xFF8A315F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(now.hour < 12 ? 'Good morning 👋' : now.hour < 17 ? 'Good afternoon 👋' : 'Good evening 👋',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 5),
                          Text('${now.day} ${_month(now.month)} ${now.year}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                        ])),
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 27),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      const Text('YOUR DAY, AT A GLANCE', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _heroMetric('${completed}/${tasks.length}', 'Tasks done')),
                        Container(width: 1, height: 38, color: Colors.white54),
                        Expanded(child: _heroMetric(_duration(focusMinutes), 'Focus today')),
                        Container(width: 1, height: 38, color: Colors.white24),
                        Expanded(child: _heroMetric('${prayerDone}/${prayerItems.length}', 'Prayer routine')),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const AttentionCard(),
                const SizedBox(height: 16),
                _examHighlight(context, nextExam, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamPage()))),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: Text('Today’s priorities', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                  Text(today, style: TextStyle(color: cs.outline, fontSize: 12)),
                ]),
                const SizedBox(height: 10),
                _sectionCard(
                  context,
                  icon: Icons.menu_book_rounded,
                  color: cs.primary,
                  title: 'Study tracker',
                  subtitle: study == null ? 'Set up a study profile to track your day.' : '${tasks.length - completed} task(s) remaining · ${_duration(focusMinutes)} focused',
                  trailing: study == null ? 'Set up' : '${(focusProgress * 100).round()}%',
                  progress: study == null ? null : focusProgress,
                  actionLabel: 'Open study plan',
                  onTap: () => openTracker(1),
                ),
                const SizedBox(height: 10),
                _sectionCard(
                  context,
                  icon: Icons.self_improvement_rounded,
                  color: const Color(0xFF6558D3),
                  title: 'Prayer tracker',
                  subtitle: prayer == null
                      ? 'Add a prayer profile to see daily progress.'
                      : prayerItems.isEmpty ? 'Choose your daily prayer routine.' : '$prayerDone of ${prayerItems.length} completed today',
                  trailing: prayer == null || prayerItems.isEmpty ? 'Open' : '${(prayerDone * 100 / prayerItems.length).round()}%',
                  progress: prayer == null || prayerItems.isEmpty ? null : prayerDone / prayerItems.length,
                  actionLabel: 'Open prayer routine',
                  onTap: openPrayer,
                ),
                const SizedBox(height: 10),
                _sectionCard(
                  context,
                  icon: Icons.school_rounded,
                  color: const Color(0xFF0D9488),
                  title: 'Tuition tracker',
                  subtitle: students.isEmpty
                      ? 'No students added yet.'
                      : '${scheduled.length} scheduled today · $taught taught · $leave leave',
                  trailing: '৳${monthDue.toStringAsFixed(0)}',
                  progress: null,
                  actionLabel: 'Manage students & attendance',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TuitionHome())),
                ),
                const SizedBox(height: 20),
                Text('Quick actions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _quickAction(context, Icons.play_arrow_rounded, 'Start focus', () => openTracker(2))),
                  const SizedBox(width: 10),
                  Expanded(child: _quickAction(context, Icons.checklist_rounded, 'View tasks', () => openTracker(1))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _quickAction(context, Icons.spa_rounded, 'Prayer routine', openPrayer)),
                  const SizedBox(width: 10),
                  Expanded(child: _quickAction(context, Icons.event_available_rounded, 'Tuition today', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TuitionHome())))),
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb_outline_rounded, color: cs.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('A small step is still progress', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        tasks.isEmpty && prayerItems.isEmpty && students.isEmpty
                            ? 'Start by adding a task, setting a prayer routine, or adding a tuition student.'
                            : 'Pick one important task and give it your full attention. You can update each tracker whenever you need.',
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.4, fontSize: 12),
                      ),
                    ])),
                  ]),
                ),
              ],
            );
          },
        ),
      );


  Widget _examHighlight(BuildContext context, Map? exam, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final subjects = List<Map>.from(exam?['subjects'] ?? []);
    final groupDate = exam == null ? null : DateTime.tryParse('${exam['endDate'] ?? exam['date'] ?? ''}');
    final todayDate = DateTime(now.year, now.month, now.day);
    final subjectDates = subjects.map((s) => DateTime.tryParse((s['date'] ?? exam?['endDate'] ?? exam?['date'] ?? '').toString())).whereType<DateTime>().where((d) => !DateTime(d.year,d.month,d.day).isBefore(todayDate)).toList()..sort();
    final date = subjectDates.isNotEmpty ? subjectDates.first : groupDate;
    final days = date == null ? null : DateTime(date.year, date.month, date.day).difference(todayDate).inDays;
    final topics = subjects.fold<int>(0, (sum, s) => sum + List<Map>.from(s['topics'] ?? []).length);
    final done = subjects.fold<int>(0, (sum, s) => sum + List<Map>.from(s['topics'] ?? []).where((t) => t['done'] == true).length);
    return Card(
      elevation: 0,
      color: cs.tertiaryContainer.withOpacity(.65),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23), side: BorderSide(color: cs.tertiary.withOpacity(.3))),
      child: InkWell(borderRadius: BorderRadius.circular(23), onTap: onTap, child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.event_available_rounded, color: cs.onTertiaryContainer), const SizedBox(width: 9), Expanded(child: Text('EXAM COUNTDOWN', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11))),
            if (exam != null) Text(days == 0 ? 'TODAY' : days == 1 ? 'TOMORROW' : '$days DAYS LEFT', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w900, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          Text(exam == null ? 'Your next exam group' : '${exam['title']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onTertiaryContainer)),
          const SizedBox(height: 5),
          Text(exam == null ? 'Add an exam group and track each subject inside Exam Count.' : 'Next: ${date == null ? 'Date not set' : date.day.toString().padLeft(2,'0') + '/' + date.month.toString().padLeft(2,'0') + '/' + date.year.toString()}  •  ${subjects.length} subject(s)', style: TextStyle(color: cs.onTertiaryContainer.withOpacity(.85), fontSize: 12)),
          if (exam != null) ...[
            const SizedBox(height: 13),
            Row(children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: topics == 0 ? 0 : done / topics, minHeight: 7, backgroundColor: cs.onTertiaryContainer.withOpacity(.12), color: cs.tertiary))), const SizedBox(width: 10), Text('$done/$topics · ${topics == 0 ? 0 : (done * 100 / topics).round()}%', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w800, fontSize: 11))]),
          ],
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text(exam == null ? 'Add exam group' : 'Open Exam Count for details', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w800)), const SizedBox(width: 5), Icon(Icons.arrow_forward_rounded, color: cs.onTertiaryContainer, size: 18)]),
        ]),
      )),
    );
  }

  static String _month(int m) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  Widget _heroMetric(String value, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String trailing,
    required double? progress,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21), side: BorderSide(color: cs.outlineVariant.withOpacity(.7))),
      child: InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.35)),
              ])),
              const SizedBox(width: 8),
              Text(trailing, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
            ]),
            if (progress != null) ...[
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0).toDouble(), minHeight: 6, backgroundColor: color.withOpacity(.12), color: color)),
            ],
            const SizedBox(height: 11),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(actionLabel, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 16, color: color),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _quickAction(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 19),
        const SizedBox(width: 7),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
