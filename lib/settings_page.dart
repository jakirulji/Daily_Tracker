import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'store.dart';
import 'notify.dart';
import 'ui.dart';
import 'exam_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> exportFile(BuildContext c) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/daily_tracker_backup_${dk(DateTime.now())}.json');
      await f.writeAsString(st.json);
      await Share.shareXFiles([XFile(f.path)], subject: 'Daily Tracker backup');
    } catch (_) {
      if (c.mounted) snack(c, 'Could not create backup file');
    }
  }

  Future<void> importFile(BuildContext c) async {
    try {
      final r = await FilePicker.platform.pickFiles(withData: true);
      if (r == null || r.files.isEmpty || !c.mounted) return;
      final f = r.files.single;
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      if (!c.mounted) return;
      if (!await confirm(c, 'Replace all current data with this backup?', 'Replace')) return;
      final ok = st.apply(utf8.decode(bytes));
      if (ok) st.save();
      if (c.mounted) snack(c, ok ? 'Restored!' : 'Invalid backup file');
    } catch (_) {
      if (c.mounted) snack(c, 'Could not read that file');
    }
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: st,
        builder: (c, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.palette_outlined, color: Theme.of(c).colorScheme.primary, size: 26),
                  const SizedBox(width: 10),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Appearance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Text('Choose a look that feels right for you'),
                  ])),
                ]),
                const SizedBox(height: 16),
                for (final option in [
                  ('premium', 'Premium & Minimal', 'Navy and violet accents, calm surfaces', Icons.auto_awesome_rounded),
                  ('colorful', 'Modern & Colorful', 'Choose your own accent colour', Icons.color_lens_rounded),
                  ('glass', 'Soft Glass UI', 'Airy teal tones, softer rounded cards', Icons.blur_on_rounded),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () { st.themeStyle = option.$1; st.save(); },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: st.themeStyle == option.$1 ? Theme.of(c).colorScheme.primary : Theme.of(c).colorScheme.outlineVariant,
                            width: st.themeStyle == option.$1 ? 2 : 1,
                          ),
                          color: st.themeStyle == option.$1 ? Theme.of(c).colorScheme.primaryContainer.withOpacity(0.45) : Colors.transparent,
                        ),
                        child: Row(children: [
                          Icon(option.$4, color: Theme.of(c).colorScheme.primary, size: 25),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(option.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(option.$3, style: Theme.of(c).textTheme.bodySmall),
                          ])),
                          if (st.themeStyle == option.$1) Icon(Icons.check_circle_rounded, color: Theme.of(c).colorScheme.primary),
                        ]),
                      ),
                    ),
                  ),
                if (st.themeStyle == 'colorful') ...[
                  const SizedBox(height: 4),
                  const Text('Accent colour', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final p in palette)
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () { st.seed = p; st.save(); },
                        child: CircleAvatar(
                          radius: 19,
                          backgroundColor: Color(p),
                          child: st.seed == p ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                        ),
                      ),
                  ]),
                ],
              ]),
            ),
          ),
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark mode'),
                subtitle: const Text('Use a darker colour scheme'),
                value: st.dark,
                onChanged: (v) { st.dark = v; st.save(); },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                secondary: const Icon(Icons.nightlight_round),
                title: const Text('AMOLED black'),
                subtitle: const Text('Pure black background (requires dark mode)'),
                value: st.amoled,
                onChanged: st.dark ? (v) { st.amoled = v; st.save(); } : null,
              ),
            ]),
          ),
          if (st.tracker) ...[
            ListTile(
              title: Text('Daily goal: ${st.goal} h'),
              subtitle: Slider(min: 1, max: 12, divisions: 22, value: st.goal, onChanged: (v) { st.goal = v; st.save(); }),
            ),
            ListTile(
              leading: const Icon(Icons.event_note_rounded),
              title: const Text('Exam Tracker'),
              subtitle: const Text('Exam routine, syllabus, countdown & reminders'),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const ExamPage())),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Test notification'),
            subtitle: const Text('Fires in 5 seconds. Close the app to check it works'),
            onTap: () async {
              await Notif.askPermission();
              await Notif.test();
              if (c.mounted) snack(c, 'Notification coming in 5 seconds…');
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Export backup file'),
            subtitle: const Text('Share a .json file to Drive, Telegram, email…'),
            onTap: () => exportFile(c),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import backup file'),
            subtitle: const Text('Pick a .json backup (replaces current data)'),
            onTap: () => importFile(c),
          ),
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('Backup (copy data)'),
            subtitle: const Text('Paste it in Telegram/Notes/Email to keep it safe'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: st.json));
              if (c.mounted) snack(c, 'Backup copied. Now paste it somewhere safe.');
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Restore from backup text'),
            subtitle: const Text('Paste your backup text (replaces current data)'),
            onTap: () async {
              final t = await ask(c, 'Paste backup here');
              if (t == null || t.isEmpty || !c.mounted) return;
              final ok = st.apply(t);
              if (ok) st.save();
              if (c.mounted) snack(c, ok ? 'Restored!' : 'Invalid backup text');
            },
          ),
          if (st.tracker) ...[
            const Divider(),
            for (final m in st.modes)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(m['n']),
                subtitle: Text('${m['f']} min focus / ${m['b']} min break'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: st.modes.length > 1 ? () { st.modes.remove(m); if (st.mi >= st.modes.length) st.mi = 0; st.save(); } : null,
                ),
              ),
            const Divider(),
            for (final s in st.subjects)
              ListTile(
                leading: CircleAvatar(radius: 10, backgroundColor: Color(s['c'])),
                title: Text(s['n']),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: st.subjects.length > 1 ? () => st.removeSubject(s) : null,
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
              onPressed: () async {
                final n = await ask(c, 'Category name');
                if (n == null || n.isEmpty) return;
                st.subjects.add({'n': n, 'c': palette[st.subjects.length % palette.length]});
                st.save();
              },
            ),
          ],
        ]),
      );
}
