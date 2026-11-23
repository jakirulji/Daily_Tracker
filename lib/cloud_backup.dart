import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'persist.dart';
import 'store.dart';
import 'tuition.dart';

/// One app-owned Drive JSON file. Google Drive account security protects it;
/// this implementation does not claim end-to-end encryption.
class CloudBackupService extends ChangeNotifier {
  CloudBackupService._();
  static final CloudBackupService instance = CloudBackupService._();
  static const _scope = drive.DriveApi.driveFileScope;
  static const _backupName = 'Daily Tracker Backup.json';
  static const _propertyKey = 'daily_tracker_backup';
  static const _propertyValue = 'v1';

  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  final GoogleSignIn _google = GoogleSignIn(
    scopes: const [_scope],
    serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
  );
  GoogleSignInAccount? _account;
  _GoogleAuthClient? _httpClient;
  String? _fileId;
  DateTime? _lastBackupAt;
  Timer? _debounce;
  bool _initialized = false, _busy = false, _restoreAvailable = false;
  bool _needsDecision = false, _restoring = false;
  String _status = 'Not connected', _error = '';

  String? get email => _account?.email;
  bool get connected => _account != null;
  bool get busy => _busy;
  bool get restoreAvailable => _restoreAvailable;
  bool get needsDecision => _needsDecision;
  String get status => _status;
  String get error => _error;
  DateTime? get lastBackupAt => _lastBackupAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    Persist.onCloudBackupRequested = (_) => scheduleBackup();
    try {
      _account = await _google.signInSilently();
      if (_account != null) {
        await detectBackup();
        if (_restoreAvailable) {
          final prefs = await SharedPreferences.getInstance();
          _needsDecision = prefs.getString('cloud_backup_account') != _account!.email;
          if (_needsDecision) _status = 'Cloud backup found. Choose Restore or Use this device.';
        } else {
          await backupNow();
        }
      } else {
        _status = 'Connect Google Drive to enable cloud backup';
      }
    } catch (e) {
      _error = _friendlyError(e);
      _status = 'Could not check Google Drive';
    }
    notifyListeners();
  }

  Future<drive.DriveApi> _driveApi() async {
    final account = _account;
    if (account == null) throw StateError('Connect a Google account first.');
    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Google authorization expired. Reconnect Google Drive.');
    }
    _httpClient?.close();
    _httpClient = _GoogleAuthClient(token);
    return drive.DriveApi(_httpClient!);
  }

  Future<void> connect() async {
    if (_busy) return;
    _setBusy(true, 'Connecting to Google Drive…');
    try {
      _account = await _google.signIn();
      if (_account == null) {
        _status = 'Google sign-in cancelled';
        return;
      }
      _error = '';
      await _loadBackupList();
      final prefs = await SharedPreferences.getInstance();
      _needsDecision = _restoreAvailable && prefs.getString('cloud_backup_account') != _account!.email;
      if (_restoreAvailable) {
        _status = _needsDecision
            ? 'Backup found. Restore it or choose this device as the source.'
            : 'Connected · existing backup detected';
      } else {
        _needsDecision = false;
        await _uploadBackup();
        _status = 'Connected · backup created';
      }
    } catch (e) {
      _error = _friendlyError(e);
      _status = 'Google Drive connection failed';
    } finally {
      _setBusy(false);
    }
  }

  Future<void> disconnect() async {
    _debounce?.cancel();
    try { await _google.signOut(); } catch (_) {}
    _httpClient?.close();
    _httpClient = null;
    _account = null;
    _fileId = null;
    _restoreAvailable = false;
    _needsDecision = false;
    _lastBackupAt = null;
    _status = 'Disconnected';
    _error = '';
    notifyListeners();
  }

  Future<void> detectBackup() async {
    if (_account == null || _busy) return;
    _setBusy(true, 'Searching for your backup…');
    try {
      await _loadBackupList();
      _error = '';
    } catch (e) {
      _error = _friendlyError(e);
      _status = 'Backup detection failed';
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _loadBackupList() async {
    final api = await _driveApi();
    final result = await api.files.list(
      q: "appProperties has { key='$_propertyKey' and value='$_propertyValue' } and trashed=false",
      spaces: 'drive',
      pageSize: 20,
      $fields: 'files(id,name,modifiedTime,size)',
      orderBy: 'modifiedTime desc',
    );
    final files = result.files ?? <drive.File>[];
    if (files.isEmpty) {
      _fileId = null;
      _lastBackupAt = null;
      _restoreAvailable = false;
      _needsDecision = false;
      _status = 'No cloud backup found';
    } else {
      _fileId = files.first.id;
      _lastBackupAt = DateTime.tryParse(files.first.modifiedTime ?? '');
      _restoreAvailable = true;
      _status = 'Backup found';
    }
  }

  void scheduleBackup() {
    if (!_initialized || _account == null || _needsDecision || _restoring) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => unawaited(_automaticUpload()));
  }

  Future<void> _automaticUpload() async {
    if (_busy || _account == null || _needsDecision) return;
    await backupNow();
  }

  void onAppResumed() {
    if (!_initialized || _account == null || _needsDecision || _busy) return;
    final last = _lastBackupAt;
    if (last == null || DateTime.now().difference(last) >= const Duration(hours: 24)) {
      scheduleBackup();
    }
  }

  Future<void> backupNow() async {
    if (_account == null) {
      _status = 'Connect Google Drive first';
      notifyListeners();
      return;
    }
    if (_needsDecision) {
      _status = 'Restore the cloud backup or choose “Use this device” first';
      notifyListeners();
      return;
    }
    if (_busy) return;
    _setBusy(true, 'Uploading backup…');
    try {
      await _uploadBackup();
      _status = 'Backup completed · ${DateTime.now().toLocal()}';
      _error = '';
    } catch (e) {
      _error = _friendlyError(e);
      _status = 'Backup failed · your phone data is safe';
    } finally {
      _setBusy(false);
    }
  }

  Future<void> useThisDevice() async {
    if (_busy || _account == null) return;
    _needsDecision = false;
    _restoreAvailable = false;
    await backupNow();
  }

  Future<void> _uploadBackup() async {
    final api = await _driveApi();
    final payload = jsonEncode({
      'schemaVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'mainData': st.json,
      'tuitionData': tst.json,
    });
    final bytes = Uint8List.fromList(utf8.encode(payload));
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length,
        contentType: 'application/json');
    final metadata = drive.File()
      ..name = _backupName
      ..mimeType = 'application/json'
      ..appProperties = {_propertyKey: _propertyValue};

    if (_fileId == null) {
      final created = await api.files.create(metadata, uploadMedia: media);
      _fileId = created.id;
    } else {
      await api.files.update(metadata, _fileId!, uploadMedia: media);
    }
    if (_fileId == null) throw StateError('Google Drive did not return a backup file ID.');
    final prefs = await SharedPreferences.getInstance();
    if (_account != null) await prefs.setString('cloud_backup_account', _account!.email);
    final leftovers = await api.files.list(
      q: "appProperties has { key='$_propertyKey' and value='$_propertyValue' } and trashed=false",
      spaces: 'drive',
      pageSize: 50,
      $fields: 'files(id)',
    );
    for (final old in leftovers.files ?? <drive.File>[]) {
      if (old.id != null && old.id != _fileId) {
        try { await api.files.delete(old.id!); } catch (_) {}
      }
    }
    _lastBackupAt = DateTime.now();
    _restoreAvailable = true;
    _needsDecision = false;
    _status = 'Backup completed';
    notifyListeners();
  }

  Future<void> restoreBackup() async {
    if (_busy || _account == null) return;
    if (_fileId == null) await detectBackup();
    final id = _fileId;
    if (id == null) {
      _status = 'No backup is available to restore';
      notifyListeners();
      return;
    }
    _setBusy(true, 'Downloading backup…');
    _restoring = true;
    try {
      final api = await _driveApi();
      final response = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia);
      if (response is! drive.Media) throw StateError('Google Drive returned an invalid backup response.');
      final raw = await response.stream.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map || decoded['schemaVersion'] != 1 ||
          decoded['mainData'] is! String || decoded['tuitionData'] is! String) {
        throw const FormatException('Unsupported or incomplete backup file.');
      }
      final main = jsonDecode(decoded['mainData'] as String);
      final tuition = jsonDecode(decoded['tuitionData'] as String);
      if (main is! Map || main['profiles'] is! List ||
          tuition is! Map || tuition['students'] is! List) {
        throw const FormatException('Backup contents failed validation.');
      }
      final previousMain = st.json;
      final previousTuition = tst.json;
      try {
        if (!st.apply(decoded['mainData'] as String)) {
          throw const FormatException('Daily Tracker data could not be restored.');
        }
        tst.apply(decoded['tuitionData'] as String);
      } catch (_) {
        st.apply(previousMain);
        tst.apply(previousTuition);
        rethrow;
      }
      await st.save();
      await tst.save();
      final prefs = await SharedPreferences.getInstance();
      if (_account != null) await prefs.setString('cloud_backup_account', _account!.email);
      _needsDecision = false;
      _restoreAvailable = true;
      _status = 'Restore completed successfully';
      _error = '';
    } catch (e) {
      _error = _friendlyError(e);
      _status = 'Restore failed · check the error; local data is retained where possible';
    } finally {
      _restoring = false;
      _setBusy(false);
    }
  }

  void _setBusy(bool value, [String? status]) {
    _busy = value;
    if (status != null) _status = status;
    notifyListeners();
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No internet connection. Try again when online.';
    }
    if (s.contains('401') || s.contains('403') || s.contains('authorization')) {
      return 'Google Drive permission expired or unavailable. Reconnect the account.';
    }
    return s.replaceFirst('Exception: ', '');
  }
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._token);
  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class CloudBackupCard extends StatelessWidget {
  const CloudBackupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CloudBackupService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.cloud_sync_rounded, color: cs.primary, size: 27),
                const SizedBox(width: 10),
                const Expanded(child: Text('Google Drive Backup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                if (service.connected) const Icon(Icons.check_circle, color: Colors.green),
              ]),
              const SizedBox(height: 6),
              Text(service.email ?? service.status, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              if (service.connected) ...[
                const SizedBox(height: 4),
                Text(service.status, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
              if (service.error.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(service.error, style: TextStyle(color: cs.error, fontSize: 12)),
              ],
              const SizedBox(height: 10),
              if (!service.connected)
                FilledButton.icon(
                  onPressed: service.busy ? null : service.connect,
                  icon: const Icon(Icons.add_to_drive),
                  label: const Text('Connect Google Drive'),
                )
              else if (service.needsDecision) ...[
                FilledButton.icon(
                  onPressed: service.busy ? null : service.restoreBackup,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore cloud backup'),
                ),
                OutlinedButton.icon(
                  onPressed: service.busy ? null : service.useThisDevice,
                  icon: const Icon(Icons.phone_android),
                  label: const Text('Use this device and replace cloud backup'),
                ),
              ] else ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: service.busy ? null : service.backupNow,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Backup now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: service.busy ? null : service.detectBackup,
                    icon: const Icon(Icons.search),
                    label: const Text('Detect backup'),
                  ),
                  TextButton.icon(
                    onPressed: service.busy ? null : service.disconnect,
                    icon: const Icon(Icons.logout),
                    label: const Text('Disconnect'),
                  ),
                ]),
              ],
              if (service.busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 4),
              Text(
                'Automatic backup runs after saved changes and checks for a daily backup when the app is opened. One cloud backup is retained. Google Drive access is limited to files created by Daily Tracker; this file is not end-to-end encrypted.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ]),
          ),
        );
      },
    );
  }
}
