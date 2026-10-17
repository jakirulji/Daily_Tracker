import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'store.dart';
import 'ui.dart';

/// Attention mode (Phase 1) = Android Do Not Disturb, "Priority only", with
/// calls and alarms allowed. Native side: native/android/AttentionCore.kt.
/// State lives natively; this class mirrors it and notifies the UI.
class Attention extends ChangeNotifier {
  static const _ch = MethodChannel('attention');

  bool access = false, active = false;
  String by = '';
  DateTime? endAt;

  Future<void> refresh() async {
    try {
      final m = Map.from(await _ch.invokeMethod('status') as Map);
      access = m['access'] == true;
      active = m['active'] == true;
      by = (m['by'] ?? '').toString();
      final e = (m['endAt'] as num?)?.toInt() ?? 0;
      endAt = active && e > 0 ? DateTime.fromMillisecondsSinceEpoch(e) : null;
    } catch (_) {
      // Not Android / channel missing: behave as "no access", never crash.
      access = false;
      active = false;
      endAt = null;
    }
    notifyListeners();
  }

  /// Returns "ok", "fallbackN", "failed", or "missing" (native part not in this build).
  Future<String> openAccessSettings() async {
    try {
      return (await _ch.invokeMethod('openAccessSettings')).toString();
    } on MissingPluginException {
      return 'missing';
    } catch (_) {
      return 'failed';
    }
  }

  /// Returns false if DND access has not been granted.
  Future<bool> enable(String owner, DateTime until) async {
    try {
      final r = Map.from(await _ch.invokeMethod('enable', {'by': owner, 'endAt': until.millisecondsSinceEpoch}) as Map);
      await refresh();
      return r['ok'] == true;
    } catch (_) {
      await refresh();
      return false;
    }
  }

  /// owner "pomodoro" only switches off a session that pomodoro started; "manual" always switches off.
  Future<void> disable(String owner) async {
    try {
      await _ch.invokeMethod('disable', {'by': owner == 'manual' ? 'force' : owner});
    } catch (_) {}
    await refresh();
  }

  String get left {
    final e = endAt;
    if (e == null) return '';
    final s = e.difference(DateTime.now()).inSeconds;
    if (s <= 0) return '0:00';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${x.toString().padLeft(2, '0')}' : '$m:${x.toString().padLeft(2, '0')}';
  }
}

final att = Attention();

/// Opens the DND access screen; if it cannot open the exact page, tells the user how to find it.
Future<void> openDndAccess(BuildContext c) async {
  final r = await att.openAccessSettings();
  if (r == 'ok' || !c.mounted) return;
  final msg = r == 'missing'
      ? 'The Attention mode part is missing from this build.\n\nMake sure the native/ folder and the updated .github/workflows/build.yml are uploaded, run Build APK again, and reinstall.'
      : 'Could not open that exact screen on this phone.\n\nOpen phone Settings and search for "Do Not Disturb access" (or Apps > Special app access > Do Not Disturb access), then switch on Daily Tracker.';
  await showDialog(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Open it manually'),
      content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
    ),
  );
}

/// Grants DND access if needed, then asks how long, then turns the mode on.
Future<void> startAttention(BuildContext c) async {
  if (!att.access) {
    final go = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Allow Do Not Disturb access'),
        content: const Text('Attention mode silences distracting notifications using Android\'s Do Not Disturb. '
            'Android needs your permission once.\n\nOn the next screen, find Daily Tracker and switch it on, then come back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Open settings')),
        ],
      ),
    );
    if (go == true && c.mounted) await openDndAccess(c);
    return;
  }
  final mins = await _askMinutes(c);
  if (mins == null || !c.mounted) return;
  st.attMin = mins;
  st.save(q: true);
  final ok = await att.enable('manual', DateTime.now().add(Duration(minutes: mins)));
  if (c.mounted) snack(c, ok ? 'Attention mode on for $mins min. Calls and alarms still ring.' : 'Could not turn on Attention mode');
}

Future<void> stopAttention(BuildContext c) async {
  await att.disable('manual');
  if (c.mounted) snack(c, 'Attention mode off');
}

Future<int?> _askMinutes(BuildContext c) {
  int sel = st.attMin;
  final custom = TextEditingController();
  return showDialog<int>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('Focus for how long?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in const [30, 60, 90, 120, 180])
              ChoiceChip(
                label: Text(m < 60 ? '$m min' : '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60}m'}'),
                selected: sel == m && custom.text.isEmpty,
                onSelected: (_) => set(() { sel = m; custom.clear(); }),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: custom,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Or custom (minutes)'),
            onChanged: (_) => set(() {}),
          ),
          const SizedBox(height: 10),
          const Text('Attention mode always ends automatically at this time, even if the app is closed.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = custom.text.trim().isEmpty ? sel : int.tryParse(custom.text.trim());
              if (v == null || v < 1) return;
              Navigator.pop(d, v.clamp(1, 720).toInt());
            },
            child: const Text('Start'),
          ),
        ],
      ),
    ),
  );
}

/// Card for the Home dashboard: shows state, start / stop.
class AttentionCard extends StatefulWidget {
  const AttentionCard({super.key});
  @override
  State<AttentionCard> createState() => _AC();
}

class _AC extends State<AttentionCard> with WidgetsBindingObserver {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    att.refresh();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (att.active) {
        if (att.endAt != null && DateTime.now().isAfter(att.endAt!)) {
          att.refresh();
        } else {
          setState(() {});
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) att.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: att,
        builder: (c, _) {
          final cs = Theme.of(c).colorScheme;
          final on = att.active;
          return Card(
            margin: EdgeInsets.zero,
            color: on ? cs.primaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(on ? Icons.do_not_disturb_on_rounded : Icons.do_not_disturb_off_outlined, size: 30, color: cs.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Attention mode', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      on
                          ? 'On · ${att.left} left · calls & alarms allowed'
                          : (att.access ? 'Silence distracting notifications while you focus' : 'Tap Start to give permission'),
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                on
                    ? OutlinedButton(onPressed: () => stopAttention(c), child: const Text('Stop'))
                    : FilledButton(onPressed: () => startAttention(c), child: const Text('Start')),
              ]),
            ),
          );
        },
      );
}

/// Settings tile group for Attention mode (used in settings_page.dart).
class AttentionSettings extends StatefulWidget {
  const AttentionSettings({super.key});
  @override
  State<AttentionSettings> createState() => _AS();
}

class _AS extends State<AttentionSettings> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    att.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) att.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: Listenable.merge([st, att]),
        builder: (c, _) => Column(children: [
          ListTile(
            leading: Icon(att.access ? Icons.check_circle_outline : Icons.lock_open_outlined),
            title: const Text('Do Not Disturb access'),
            subtitle: Text(att.access ? 'Granted' : 'Not granted. Tap to allow (needed for Attention mode)'),
            onTap: att.access ? null : () => openDndAccess(c),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.timer_outlined),
            title: const Text('Start Attention mode with Pomodoro focus'),
            subtitle: const Text('Turns on when a focus session starts. Off when you pause, reset or it finishes.'),
            value: st.attAuto,
            onChanged: (v) async {
              if (v && !att.access) {
                await startAttention(c);
                return;
              }
              st.attAuto = v;
              st.save();
            },
          ),
          if (st.attAuto)
            SwitchListTile(
              secondary: const Icon(Icons.coffee_outlined),
              title: const Text('Keep it on during breaks'),
              subtitle: const Text('Off: Attention mode ends when the focus session ends.'),
              value: st.attBreak,
              onChanged: (v) { st.attBreak = v; st.save(); },
            ),
        ]),
      );
}
