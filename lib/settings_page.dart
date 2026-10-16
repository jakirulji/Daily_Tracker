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
        builder: (c, _) => ListView(children: [
          SwitchListTile(title: const Text('Dark mode'), value: st.dark, onChanged: (v) { st.dark = v; st.save(); }),
          SwitchListTile(title: const Text('AMOLED black (needs dark mode)'), value: st.amoled, onChanged: st.dark ? (v) { st.amoled = v; st.save(); } : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(spacing: 10, children: [
              for (final p in palette)
                GestureDetector(
                  onTap: () { st.seed = p; st.save(); },
                  child: CircleAvatar(radius: 16, backgroundColor: Color(p), child: st.seed == p ? const Icon(Icons.check, color: Colors.white, size: 18) : null),
                ),
            ]),
          ),
          if (st.tracker) ...[
            ListTile(
              title: Text('Daily goal: ${st.goal} h'),
              subtitle: Slider(min: 1, max: 12, divisions: 22, value: st.goal, onChanged: (v) { st.goal = v; st.save(); }),
            ),
            ListTile(
              title: Text(st.exam == '' ? 'Set exam countdown' : '${st.exam} – ${st.examDate}'),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final n = await ask(c, 'Exam name');
                if (n == null || n.isEmpty || !c.mounted) return;
                final d = await showDatePicker(context: c, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime(2100));
                if (d == null) return;
                st.exam = n;
                st.examDate = dk(d);
                st.save();
              },
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
