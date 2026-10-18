import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _dwbChannel = MethodChannel('com.dailytracker/dwb');

class _UsageApp {
  final String packageName;
  final String label;
  final int todayMinutes;
  final int yesterdayMinutes;
  const _UsageApp({required this.packageName, required this.label, required this.todayMinutes, required this.yesterdayMinutes});
  factory _UsageApp.fromMap(Map<dynamic, dynamic> m) => _UsageApp(
    packageName: (m['packageName'] ?? '').toString(),
    label: (m['label'] ?? m['packageName'] ?? 'App').toString(),
    todayMinutes: (m['todayMinutes'] as num? ?? 0).toInt(),
    yesterdayMinutes: (m['yesterdayMinutes'] as num? ?? 0).toInt(),
  );
}

class WellbeingPage extends StatefulWidget {
  const WellbeingPage({super.key});
  @override
  State<WellbeingPage> createState() => _WellbeingPageState();
}

class _WellbeingPageState extends State<WellbeingPage> with WidgetsBindingObserver {
  bool _loading = true;
  bool _usageAccess = false;
  bool _overlayAccess = false;
  bool _pauseEnabled = true;
  bool _guiltMode = true;
  bool _overlayReminders = false;
  bool _strictBlockingEnabled = false;
  int _pauseSeconds = 10;
  int _reminderMinutes = 5;
  final Set<String> _pausedPackages = {};
  final Set<String> _blockedPackages = {}; // Strict mode packages
  final Set<String> _gentlePackages = {};
  bool _permissionDialogShowing = false;
  bool _permissionPromptForStrict = false;
  final Map<String, int> _limits = {};
  List<_UsageApp> _apps = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pauseEnabled = p.getBool('dwb.pauseEnabled') ?? true;
      _guiltMode = p.getBool('dwb.guiltMode') ?? true;
      _overlayReminders = p.getBool('dwb.overlayReminders') ?? false;
      _strictBlockingEnabled = p.getBool('dwb.strictBlockingEnabled') ?? false;
      _pauseSeconds = p.getInt('dwb.pauseSeconds') ?? 10;
      _reminderMinutes = p.getInt('dwb.reminderMinutes') ?? 5;
      _pausedPackages
        ..clear()
        ..addAll(p.getStringList('dwb.pausedPackages') ?? const []);
      _blockedPackages
        ..clear()
        ..addAll(p.getStringList('dwb.blockedPackages') ?? const []);
      _gentlePackages
        ..clear()
        ..addAll(p.getStringList('dwb.gentlePackages') ?? const []);
      _gentlePackages.removeAll(_blockedPackages);
      _limits.clear();
      for (final key in p.getKeys().where((k) => k.startsWith('dwb.limit.'))) {
        _limits[key.substring('dwb.limit.'.length)] = p.getInt(key) ?? 30;
      }
    });
    await _syncBlocking();
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('dwb.pauseEnabled', _pauseEnabled);
    await p.setBool('dwb.guiltMode', _guiltMode);
    await p.setBool('dwb.overlayReminders', _overlayReminders);
    await p.setBool('dwb.strictBlockingEnabled', _strictBlockingEnabled);
    await p.setStringList('dwb.blockedPackages', _blockedPackages.toList());
    await p.setStringList('dwb.gentlePackages', _gentlePackages.toList());
    await p.setInt('dwb.pauseSeconds', _pauseSeconds);
    await p.setInt('dwb.reminderMinutes', _reminderMinutes);
    await p.setStringList('dwb.pausedPackages', _pausedPackages.toList());
    for (final entry in _limits.entries) {
      await p.setInt('dwb.limit.${entry.key}', entry.value);
    }
    await _syncBlocking();
  }

  Future<void> _syncBlocking() async {
    try {
      await _dwbChannel.invokeMethod<bool>('configureBlocking', {
        'enabled': _strictBlockingEnabled && _usageAccess && _overlayAccess,
        'selectedPackages': _blockedPackages.toList(),
        'limits': _limits.map((key, value) => MapEntry(key, value)),
      });
    } on PlatformException {
      // Permission or Android service failures are surfaced in the UI on refresh.
    } catch (_) {}
  }

  Future<void> _refresh() async {
    try {
      final access = await _dwbChannel.invokeMethod<bool>('hasUsageAccess') ?? false;
      final overlay = await _dwbChannel.invokeMethod<bool>('hasOverlayPermission') ?? false;
      List<_UsageApp> apps = [];
      if (access) {
        final raw = await _dwbChannel.invokeListMethod<dynamic>('getUsageStats') ?? [];
        apps = raw.whereType<Map>().map(_UsageApp.fromMap).toList();
      }
      if (!mounted) return;
      setState(() { _usageAccess = access; _overlayAccess = overlay; _apps = apps; _loading = false; });
      await _syncBlocking();
      if (!_usageAccess || (_strictBlockingEnabled && !_overlayAccess)) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showPermissionPrompt(); });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read usage data: ${e.message ?? 'Android error'}')));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _showPermissionPrompt() async {
    if (!mounted || _permissionDialogShowing || (_usageAccess && (!_permissionPromptForStrict || _overlayAccess))) return;
    _permissionDialogShowing = true;
    final needUsage = !_usageAccess;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.admin_panel_settings_rounded, size: 38),
        title: Text(needUsage ? 'Enable Usage Access' : 'Enable display over other apps'),
        content: Text(needUsage
          ? 'Daily Tracker needs Usage Access to calculate app screen time and enforce selected limits. In Android Settings, choose Daily Tracker and enable Usage Access.'
          : 'Strict Block needs Display over other apps permission to show its pause screen when a selected app reaches its daily limit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'later'), child: const Text('Not now')),
          FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, needUsage ? 'usage' : 'overlay'), icon: const Icon(Icons.settings_rounded), label: const Text('Open Settings')),
        ],
      ),
    );
    _permissionDialogShowing = false;
    if (!mounted || choice == null || choice == 'later') return;
    if (choice == 'usage') { await _openUsageSettings(); } else { await _openOverlaySettings(); }
  }

  Future<void> _setAppBlockMode(_UsageApp app, String mode) async {
    if (mode == 'strict' && (!_usageAccess || !_overlayAccess)) {
      _permissionPromptForStrict = true;
      await _showPermissionPrompt();
      await _refresh();
      if (!_usageAccess || !_overlayAccess) { _permissionPromptForStrict = false; return; }
      _permissionPromptForStrict = false;
    }
    setState(() {
      _blockedPackages.remove(app.packageName);
      _gentlePackages.remove(app.packageName);
      if (mode == 'strict') _blockedPackages.add(app.packageName);
      if (mode == 'gentle') _gentlePackages.add(app.packageName);
      if (_blockedPackages.isEmpty) _strictBlockingEnabled = false;
      else _strictBlockingEnabled = true;
    });
    await _saveSettings();
  }

  Future<void> _openBlockSettings(String mode) async {
    if (mode == 'strict' && (!_usageAccess || !_overlayAccess)) {
      await _showPermissionPrompt();
      await _refresh();
      if (!_usageAccess || !_overlayAccess) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mode == 'strict' ? 'Strict Block setup' : 'Gentle Block setup',
            style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(mode == 'strict'
            ? 'Choose Strict Block for each app below. When its daily limit is reached, a pause screen will appear. Usage Access and Display over other apps are required.'
            : 'Choose Gentle Block for each app below. It uses reminders and mindful pauses instead of forced blocking.'),
          const SizedBox(height: 12),
          Text(mode == 'strict' ? 'Selected apps: ${_blockedPackages.length}' : 'Selected apps: ${_gentlePackages.length}'),
          if (mode == 'strict' && (!_usageAccess || !_overlayAccess))
            Align(alignment: Alignment.centerRight, child: FilledButton(
              onPressed: () { Navigator.pop(sheetContext); _showPermissionPrompt(); },
              child: const Text('Complete permissions'),
            )),
        ]),
      ),
    );
  }

  String _time(int minutes) {
    if (minutes >= 60) return '${minutes ~/ 60}h ${minutes % 60}m';
    return '${minutes}m';
  }

  Future<void> _openUsageSettings() async {
    await _dwbChannel.invokeMethod<bool>('openUsageAccessSettings');
  }

  Future<void> _openOverlaySettings() async {
    await _dwbChannel.invokeMethod<bool>('openOverlaySettings');
  }

  Future<void> _configureApp(_UsageApp app) async {
    var limit = _limits[app.packageName] ?? 30;
    var reminder = _reminderMinutes;
    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.label, style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(app.packageName, style: Theme.of(sheetContext).textTheme.bodySmall),
            const SizedBox(height: 18),
            Text('Daily app limit: ${limit == 0 ? 'Off' : '$limit minutes'}'),
            Slider(
              min: 0, max: 180, divisions: 36, value: limit.toDouble(),
              label: limit == 0 ? 'Off' : '$limit min',
              onChanged: (v) => setSheet(() => limit = v.round()),
            ),
            const Text('0 = no limit · Strict blocking locks the app until the next day after this limit'),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: reminder,
              decoration: const InputDecoration(labelText: 'Usage reminder'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Off')),
                DropdownMenuItem(value: 5, child: Text('Every 5 minutes')),
                DropdownMenuItem(value: 10, child: Text('Every 10 minutes')),
                DropdownMenuItem(value: 15, child: Text('Every 15 minutes')),
                DropdownMenuItem(value: 20, child: Text('Every 20 minutes')),
                DropdownMenuItem(value: 30, child: Text('Every 30 minutes')),
              ],
              onChanged: (v) => setSheet(() => reminder = v ?? 0),
            ),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () => Navigator.pop(sheetContext, {'limit': limit, 'reminder': reminder}),
              child: const Text('Save app settings'),
            )),
          ]),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _limits[app.packageName] = result['limit'] ?? 30;
      _reminderMinutes = result['reminder'] ?? 5;
    });
    await _saveSettings();
  }

  Future<bool> _pauseBeforeOpen(_UsageApp app) async {
    if (!_pauseEnabled || !_pausedPackages.contains(app.packageName)) return true;
    var remaining = _pauseSeconds;
    Timer? timer;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (remaining <= 1) {
              t.cancel();
              setDialog(() => remaining = 0);
            } else {
              setDialog(() => remaining--);
            }
          });
          return AlertDialog(
            icon: const Icon(Icons.spa_rounded, size: 42),
            title: const Text('Take a mindful pause'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(app.label, style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(remaining > 0 ? 'Breathe slowly. You can still choose how to spend your time.' : 'Ready? Make an intentional choice before opening the app.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(remaining > 0 ? '$remaining' : '✓', style: Theme.of(dialogContext).textTheme.displayMedium?.copyWith(color: Theme.of(dialogContext).colorScheme.primary, fontWeight: FontWeight.w300)),
            ]),
            actions: [
              TextButton(onPressed: () { timer?.cancel(); Navigator.pop(dialogContext, false); }, child: const Text('Not now')),
              FilledButton(
                onPressed: remaining > 0 ? null : () { timer?.cancel(); Navigator.pop(dialogContext, true); },
                child: const Text('Open app'),
              ),
            ],
          );
        },
      ),
    );
    timer?.cancel();
    return accepted ?? false;
  }

  Future<void> _startSession(_UsageApp app) async {
    if (!_usageAccess) {
      await _openUsageSettings();
      return;
    }
    if (_overlayReminders && !_overlayAccess && (_limits[app.packageName] ?? 30) > 0) {
      await _openOverlaySettings();
      if (!mounted) return;
      await _refresh();
      if (!_overlayAccess) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Overlay permission is optional; session can still run with notifications.')));
      }
    }
    final ok = await _pauseBeforeOpen(app);
    if (!ok || !mounted) return;
    try {
      await _dwbChannel.invokeMethod<bool>('startSession', {
        'packageName': app.packageName,
        'appName': app.label,
        'limitMinutes': _limits[app.packageName] ?? 30,
        'reminderMinutes': _reminderMinutes,
        'overlayEnabled': _overlayReminders,
      });
      final launched = await _dwbChannel.invokeMethod<bool>('launchApp', {'packageName': app.packageName}) ?? false;
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This app could not be launched.')));
      }
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Could not start session')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _apps.where((a) => a.label.toLowerCase().contains(_query.toLowerCase()) || a.packageName.toLowerCase().contains(_query.toLowerCase())).toList();
    final totalToday = _apps.fold<int>(0, (sum, app) => sum + app.todayMinutes);
    final totalYesterday = _apps.fold<int>(0, (sum, app) => sum + app.yesterdayMinutes);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Wellbeing'),
        actions: [IconButton(tooltip: 'Refresh usage', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF172A3A), Color(0xFF39275E), Color(0xFF176B70)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.self_improvement_rounded, color: Color(0xFF68F0D5), size: 32),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Make time intentional', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 8),
                const Text('Understand your screen time, pause before opening distracting apps, and set a limit for each focus session.', style: TextStyle(color: Color(0xFFE2E8F0), height: 1.4)),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(child: _metric('Today', _time(totalToday))),
                  Container(width: 1, height: 38, color: Colors.white30),
                  Expanded(child: _metric('Yesterday', _time(totalYesterday))),
                  Container(width: 1, height: 38, color: Colors.white30),
                  Expanded(child: _metric('Apps used', '${_apps.where((a) => a.todayMinutes > 0).length}')),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            if (!_usageAccess)
              _permissionCard(
                icon: Icons.query_stats_rounded,
                title: 'Allow Usage Access',
                text: 'Android requires special permission before Daily Tracker can read app screen-time statistics.',
                action: 'Open settings',
                onTap: _openUsageSettings,
              )
            else if (!_overlayAccess)
              _permissionCard(
                icon: Icons.layers_outlined,
                title: 'Allow display over other apps',
                text: _strictBlockingEnabled ? 'Strict blocking needs this permission to show a full-screen pause screen over selected apps.' : 'Optional for focus-session pause reminders. Strict app blocking requires this permission.',
                action: 'Grant overlay',
                onTap: _openOverlaySettings,
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.shield_rounded),
                    title: const Text('Strict Block', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${_blockedPackages.length} apps selected · daily limit + pause screen'),
                    trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openBlockSettings('strict')),
                  const Divider(),
                  ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.spa_rounded),
                    title: const Text('Gentle Block', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${_gentlePackages.length} apps selected · reminders and mindful pause'),
                    trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openBlockSettings('gentle')),
                  const Divider(),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _pauseEnabled, onChanged: (v) { setState(() => _pauseEnabled = v); _saveSettings(); }, title: const Text('Mindful pause'), subtitle: const Text('Pause briefly before launching a selected app')),
                  if (_pauseEnabled) Row(children: [
                    const Expanded(child: Text('Pause duration')),
                    DropdownButton<int>(value: _pauseSeconds, items: const [3, 5, 10, 15, 20, 30].map((v) => DropdownMenuItem(value: v, child: Text('$v sec'))).toList(), onChanged: (v) { if (v != null) setState(() => _pauseSeconds = v); _saveSettings(); }),
                  ]),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _guiltMode, onChanged: (v) { setState(() => _guiltMode = v); _saveSettings(); }, title: const Text('Time awareness'), subtitle: const Text('Show today and yesterday usage in each app row')),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _overlayReminders, onChanged: (v) { setState(() => _overlayReminders = v); _saveSettings(); }, title: const Text('Overlay at time limit'), subtitle: const Text('Requires Display over other apps permission')),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            Text('App usage', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Choose Off, Strict or Gentle for each app. A new choice replaces the previous mode for that app.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search apps', isDense: true),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            if (_loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (!_usageAccess) const Padding(padding: EdgeInsets.all(22), child: Text('Grant Usage Access above to view your apps and screen time.'))
            else if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(22), child: Text('No matching apps found. Try refreshing after using a few apps.'))
            else ...filtered.map((app) {
              final limit = _limits[app.packageName] ?? 30;
              final maxMinutes = _apps.fold<int>(1, (m, a) => a.todayMinutes > m ? a.todayMinutes : m);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(children: [
                    Row(children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.apps_rounded, color: cs.onPrimaryContainer)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(_guiltMode ? 'Today ${_time(app.todayMinutes)} · Yesterday ${_time(app.yesterdayMinutes)}' : 'Today ${_time(app.todayMinutes)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ])),
                      IconButton(
                        tooltip: _pausedPackages.contains(app.packageName) ? 'Remove mindful pause' : 'Add mindful pause',
                        onPressed: () {
                          setState(() {
                            if (_pausedPackages.contains(app.packageName)) {
                              _pausedPackages.remove(app.packageName);
                            } else {
                              _pausedPackages.add(app.packageName);
                            }
                          });
                          _saveSettings();
                        },
                        icon: Icon(_pausedPackages.contains(app.packageName) ? Icons.pause_circle_filled_rounded : Icons.pause_circle_outline_rounded,
                            color: _pausedPackages.contains(app.packageName) ? cs.primary : cs.onSurfaceVariant),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Choose block mode',
                        initialValue: _blockedPackages.contains(app.packageName) ? 'strict' : (_gentlePackages.contains(app.packageName) ? 'gentle' : 'off'),
                        onSelected: (mode) => _setAppBlockMode(app, mode),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'off', child: ListTile(dense: true, leading: Icon(Icons.block_outlined), title: Text('Off'))),
                          PopupMenuItem(value: 'strict', child: ListTile(dense: true, leading: Icon(Icons.lock_outline_rounded), title: Text('Strict Block'))),
                          PopupMenuItem(value: 'gentle', child: ListTile(dense: true, leading: Icon(Icons.spa_outlined), title: Text('Gentle Block'))),
                        ],
                        child: Padding(padding: const EdgeInsets.all(8), child: Icon(
                          _blockedPackages.contains(app.packageName) ? Icons.lock_rounded : (_gentlePackages.contains(app.packageName) ? Icons.spa_rounded : Icons.shield_outlined),
                          color: _blockedPackages.contains(app.packageName) ? cs.error : (_gentlePackages.contains(app.packageName) ? cs.primary : cs.onSurfaceVariant))),
                      ),
                      IconButton(tooltip: 'App settings', onPressed: () => _configureApp(app), icon: const Icon(Icons.tune_rounded)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: (app.todayMinutes / maxMinutes).clamp(0.0, 1.0), minHeight: 5)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.timer_outlined, size: 17, color: cs.primary),
                      const SizedBox(width: 5),
                      Expanded(child: Text('Daily limit: ${limit == 0 ? 'Off' : '$limit min'}', style: Theme.of(context).textTheme.bodySmall)),
                      TextButton(onPressed: () => _configureApp(app), child: const Text('Configure')),
                      const SizedBox(width: 4),
                      FilledButton.tonalIcon(onPressed: () => _startSession(app), icon: const Icon(Icons.play_arrow_rounded, size: 18), label: const Text('Start focus')),
                    ]),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.sync_rounded), label: const Text('Refresh usage data')),
            const SizedBox(height: 8),
            Text('Usage statistics are read locally from Android. Android may delay or round usage data; this page does not send your app usage to a server.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
    ]),
  );

  Widget _permissionCard({required IconData icon, required String title, required String text, required String action, required Future<void> Function() onTap}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)))]),
        const SizedBox(height: 8),
        Text(text),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: FilledButton.tonal(onPressed: () async => onTap(), child: Text(action))),
      ]),
    ),
  );
}
