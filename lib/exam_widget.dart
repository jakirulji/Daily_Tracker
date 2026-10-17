import 'package:home_widget/home_widget.dart';
import 'store.dart';

/// Keeps Android launcher widgets in sync with the exam data stored by Daily Tracker.
class ExamWidgetSync {
  static Future<void> update() async {
    try {
      final profileIndex = st.profiles.indexWhere((p) => p['t'] != 'prayer');
      final exams = profileIndex < 0
          ? <Map>[]
          : List<Map>.from(st.dataOf(profileIndex)['exams'] ?? []);
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);

      DateTime? dateOf(Map exam) {
        final groupDate = (exam['endDate'] ?? exam['date'] ?? '').toString();
        final dates = List<Map>.from(exam['subjects'] ?? [])
            .map((s) => DateTime.tryParse((s['date'] ?? groupDate).toString()))
            .whereType<DateTime>()
            .map((d) => DateTime(d.year, d.month, d.day))
            .where((d) => !d.isBefore(todayOnly))
            .toList()
          ..sort();
        if (dates.isNotEmpty) return dates.first;
        final group = DateTime.tryParse(groupDate);
        if (group == null) return null;
        final normalized = DateTime(group.year, group.month, group.day);
        return normalized.isBefore(todayOnly) ? null : normalized;
      }

      final upcoming = exams.where((e) => e['done'] != true && dateOf(e) != null).toList()
        ..sort((a, b) => dateOf(a)!.compareTo(dateOf(b)!));
      if (upcoming.isEmpty) {
        await HomeWidget.saveWidgetData<String>('exam_title', 'No upcoming exams');
        await HomeWidget.saveWidgetData<String>('exam_days', 'Add an exam in Daily Tracker');
        await HomeWidget.saveWidgetData<int>('exam_progress', 0);
        await HomeWidget.saveWidgetData<String>('exam_progress_label', 'No syllabus yet');
        for (var i = 0; i < 3; i++) {
          await HomeWidget.saveWidgetData<String>('subject_$i', '');
          await HomeWidget.saveWidgetData<int>('subject_progress_$i', 0);
        }
      } else {
        final exam = upcoming.first;
        final subjects = List<Map>.from(exam['subjects'] ?? []);
        final total = subjects.fold<int>(0, (sum, s) => sum + List<Map>.from(s['topics'] ?? []).length);
        final done = subjects.fold<int>(0, (sum, s) => sum + List<Map>.from(s['topics'] ?? []).where((t) => t['done'] == true).length);
        final days = dateOf(exam)!.difference(todayOnly).inDays;
        final countdown = days == 0 ? 'Exam is today' : days == 1 ? '1 day left' : '$days days left';
        await HomeWidget.saveWidgetData<String>('exam_title', (exam['title'] ?? 'Upcoming exam').toString());
        await HomeWidget.saveWidgetData<String>('exam_days', countdown);
        await HomeWidget.saveWidgetData<int>('exam_progress', total == 0 ? 0 : (done * 100 / total).round());
        await HomeWidget.saveWidgetData<String>('exam_progress_label', '$done / $total topics prepared');
        for (var i = 0; i < 3; i++) {
          if (i < subjects.length) {
            final subject = subjects[i];
            final topics = List<Map>.from(subject['topics'] ?? []);
            final completed = topics.where((t) => t['done'] == true).length;
            await HomeWidget.saveWidgetData<String>('subject_$i', (subject['name'] ?? 'Subject').toString());
            await HomeWidget.saveWidgetData<int>('subject_progress_$i', topics.isEmpty ? 0 : (completed * 100 / topics.length).round());
          } else {
            await HomeWidget.saveWidgetData<String>('subject_$i', '');
            await HomeWidget.saveWidgetData<int>('subject_progress_$i', 0);
          }
        }
      }
      await HomeWidget.updateWidget(androidName: 'ExamCompactWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'ExamDetailedWidgetProvider');
    } catch (_) {
      // Widget refresh must never prevent the main app from opening or saving.
    }
  }
}
