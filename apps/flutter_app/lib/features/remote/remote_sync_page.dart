import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api.dart';
import '../../data/cloud_sync.dart';
import '../../data/session_history.dart';

/// Persists the signed-in study account (email + bearer token) locally.
/// Accounts are OPT-IN (J5): everything works anonymously without one; an
/// account only lets a participant reconnect and erase server data.
class AccountStore {
  AccountStore({this.prefix = 'hearbloom.account.v1'});

  final String prefix;

  Future<({String email, String token})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('$prefix.email');
    final token = prefs.getString('$prefix.token');
    if (email == null || token == null) return null;
    return (email: email, token: token);
  }

  Future<void> save(String email, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$prefix.email', email);
    await prefs.setString('$prefix.token', token);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$prefix.email');
    await prefs.remove('$prefix.token');
  }
}

/// Persists the linked clinician code locally. This is a seam only — no data
/// leaves the device today.
class ClinicianLinkStore {
  ClinicianLinkStore({this.key = 'hearbloom.clinician_code.v1'});

  final String key;

  Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? '';
  }

  Future<void> save(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, code.trim());
  }
}

/// Remote-monitoring page. Links a clinician code and uploads pending session
/// summaries via [CloudSyncService]. When offline (or no backend is reachable)
/// sessions stay queued locally and upload on the next successful sync.
class RemoteSyncPage extends StatefulWidget {
  const RemoteSyncPage({super.key, this.history, this.linkStore, this.syncService});

  final SessionHistory? history;
  final ClinicianLinkStore? linkStore;
  final CloudSyncService? syncService;

  @override
  State<RemoteSyncPage> createState() => _RemoteSyncPageState();
}

class _RemoteSyncPageState extends State<RemoteSyncPage> {
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);

  late final ClinicianLinkStore _linkStore =
      widget.linkStore ?? ClinicianLinkStore();
  late final SessionHistory _history = widget.history ?? SessionHistory();
  late final CloudSyncService _sync = widget.syncService ??
      CloudSyncService(history: _history, linkStore: _linkStore);
  final TextEditingController _codeController = TextEditingController();

  int _pending = 0;
  bool _loading = true;
  bool _syncing = false;
  DateTime? _lastSync;
  String _statusText = 'Offline — data stored locally';
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = await _linkStore.load();
    final pending = await _sync.pendingCount();
    final last = await _sync.lastSync();
    if (!mounted) return;
    setState(() {
      _codeController.text = code;
      _pending = pending;
      _lastSync = last;
      _synced = pending == 0 && last != null;
      _statusText = _synced
          ? 'All sessions synced'
          : (last == null
              ? 'Not yet synced — data stored locally'
              : '$pending pending — data stored locally');
      _loading = false;
    });
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return 'Never';
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _saveCode() async {
    await _linkStore.save(_codeController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clinician code saved on this device')),
    );
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final result = await _sync.syncNow();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _pending = result.pending;
      _lastSync = result.lastSync;
      _synced = result.pending == 0 && result.lastSync != null;
      _statusText = result.message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote monitoring')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _AccountCard(),
                    const SizedBox(height: 16),
                    const Text(
                      'Link this device to a clinician to share your session '
                      'progress. Sessions upload only after you enter a '
                      'clinician code and tap Sync Now; until then everything '
                      'stays on-device.',
                      style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Clinician code',
                              style: TextStyle(
                                  color: _ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          TextField(
                            key: const Key('clinician-code-field'),
                            controller: _codeController,
                            style: const TextStyle(color: _ink),
                            decoration: const InputDecoration(
                              hintText: 'e.g. CLIN-4821',
                              prefixIcon: Icon(Icons.link),
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _saveCode(),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Semantics(
                              button: true,
                              label: 'Save clinician code',
                              child: OutlinedButton.icon(
                                onPressed: _saveCode,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Save code'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _card(
                      child: Column(
                        children: [
                          _statusRow(
                            icon: _synced ? Icons.cloud_done : Icons.cloud_off,
                            color: _synced
                                ? const Color(0xff22c55e)
                                : const Color(0xfffbbf24),
                            label: 'Sync status',
                            value: _statusText,
                          ),
                          const Divider(color: _border, height: 22),
                          _statusRow(
                            icon: Icons.schedule,
                            color: _muted,
                            label: 'Last sync',
                            value: _fmtTime(_lastSync),
                            valueKey: const Key('last-sync-value'),
                          ),
                          const Divider(color: _border, height: 22),
                          _statusRow(
                            icon: Icons.pending_actions,
                            color: const Color(0xff3b82f6),
                            label: 'Pending sessions',
                            value: '$_pending',
                            valueKey: const Key('pending-sessions-value'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      button: true,
                      label: 'Sync now',
                      child: FilledButton.icon(
                        key: const Key('sync-now-button'),
                        onPressed: _syncing ? null : _syncNow,
                        icon: _syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: Text(_syncing ? 'Syncing…' : 'Sync Now'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'When a clinician backend is connected, pending sessions '
                      'will upload securely here. Research use only — not a '
                      'diagnosis.',
                      style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: child,
      );

  Widget _statusRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    Key? valueKey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(color: _muted, fontSize: 13.5)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              key: valueKey,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: _ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Optional study-account card: register / sign in (stores the bearer token
/// on-device), signed-in state with sign-out. The account is a reconnection
/// + erasure convenience; sync itself stays clinician-code based.
class _AccountCard extends StatefulWidget {
  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);

  final AccountStore _store = AccountStore();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  String? _signedInEmail;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store.load().then((account) {
      if (mounted && account != null) {
        setState(() => _signedInEmail = account.email);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(bool register) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = Api();
    try {
      final result = register
          ? await api.register(_email.text.trim(), _password.text)
          : await api.login(_email.text.trim(), _password.text);
      await _store.save(
          result['email'] as String, result['token'] as String);
      if (mounted) {
        setState(() => _signedInEmail = result['email'] as String);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not reach the study server; you can keep working '
            'offline.');
      }
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await _store.clear();
    if (mounted) setState(() => _signedInEmail = null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: _signedInEmail != null
          ? Row(
              children: [
                const Icon(Icons.verified_user_outlined,
                    color: Color(0xff22c55e)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Signed in as $_signedInEmail',
                          style: const TextStyle(
                              color: _ink, fontWeight: FontWeight.w700)),
                      const Text(
                          'Your uploads can be reconnected and erased '
                          'through this account.',
                          style:
                              TextStyle(color: _muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                TextButton(
                    key: const Key('account-signout'),
                    onPressed: _signOut,
                    child: const Text('Sign out')),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Study account (optional)',
                    style: TextStyle(
                        color: _ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    'Everything works without one. An account only lets '
                    'you reconnect to your uploaded data and delete it '
                    'from the server.',
                    style: TextStyle(color: _muted, fontSize: 12.5)),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('account-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('account-password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password (8+ characters)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(
                          color: Color(0xfff87171), fontSize: 12.5)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const Key('account-register'),
                        onPressed: _busy ? null : () => _submit(true),
                        child: const Text('Create account'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('account-login'),
                        onPressed: _busy ? null : () => _submit(false),
                        child: const Text('Sign in'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

