import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saves every key in TWO places (SharedPreferences + a file in the app's private folder)
/// and reads back whichever copy is newer. Errors are recorded (not hidden) so the
/// "Storage status" screen in Settings can show exactly what went wrong.
class Persist {
  static String lastError = '';
  static String loadedFrom = 'not loaded yet';
  static DateTime? lastSaved;
  static Directory? _dir;

  static Future<File?> _file(String key) async {
    try {
      _dir ??= await getApplicationSupportDirectory();
      return File('${_dir!.path}/$key.json');
    } catch (e) {
      lastError = 'folder: $e';
      return null;
    }
  }

  static Future<String?> read(String key) async {
    String? a, b;
    var tsMs = 0, fileMs = 0;
    try {
      final sp = await SharedPreferences.getInstance();
      a = sp.getString(key);
      tsMs = sp.getInt('${key}_ts') ?? 0;
    } catch (e) {
      lastError = 'prefs read: $e';
    }
    try {
      final f = await _file(key);
      if (f != null && await f.exists()) {
        b = await f.readAsString();
        fileMs = (await f.lastModified()).millisecondsSinceEpoch;
      }
    } catch (e) {
      lastError = 'file read: $e';
    }
    final useFile = b != null && b.isNotEmpty && (a == null || fileMs >= tsMs);
    final r = useFile ? b : a;
    if (key == 'data') loadedFrom = r == null ? 'nothing saved yet' : (useFile ? 'file' : 'prefs');
    return r;
  }

  static Future<bool> write(String key, String value) async {
    var ok = false;
    try {
      final sp = await SharedPreferences.getInstance();
      ok = await sp.setString(key, value);
      await sp.setInt('${key}_ts', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      lastError = 'prefs write: $e';
    }
    try {
      final f = await _file(key);
      if (f != null) {
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(value, flush: true);
        await tmp.rename(f.path);
        ok = true;
      }
    } catch (e) {
      lastError = 'file write: $e';
    }
    if (ok) lastSaved = DateTime.now();
    return ok;
  }

  /// Keeps a copy of data that could not be understood, instead of silently overwriting it.
  static Future<void> keepBad(String key, String value) async {
    lastError = 'saved data could not be read; copy kept as ${key}_corrupt';
    try {
      await write('${key}_corrupt', value);
    } catch (_) {}
  }
}

Future<void> showStorageStatus(BuildContext c) async {
  final t = DateTime.now().millisecondsSinceEpoch.toString();
  await Persist.write('persist_test', t);
  final ok = (await Persist.read('persist_test')) == t;
  if (!c.mounted) return;
  showDialog(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Storage status'),
      content: Text('Write/read test: ${ok ? 'OK ✅' : 'FAILED ❌'}\n'
          'Data loaded at start from: ${Persist.loadedFrom}\n'
          'Last saved: ${Persist.lastSaved ?? 'never'}\n'
          'Last error: ${Persist.lastError.isEmpty ? 'none' : Persist.lastError}'),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
    ),
  );
}
