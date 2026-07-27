import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/settings/app_settings.dart';
import '../../data/cloud_sync.dart';
import '../../data/session_history.dart';
import '../remote/remote_sync_page.dart';
import '../trends/trend_page.dart';
import 'enhanced_report_page.dart';
import 'report_data.dart';
import 'session_result_sheet.dart';

/// Unified report center backed by real on-device session history.
///
/// Reports always work offline. Online sync is optional and exposed as a
/// separate action; sample data is never substituted for a user's report.
class ReportTabPage extends StatefulWidget {
  const ReportTabPage({
    super.key,
    this.history,
    this.syncService,
    this.onStartTests,
    this.onOpenIntroduction,
  });

  final SessionHistory? history;
  final CloudSyncService? syncService;
  final VoidCallback? onStartTests;
  final VoidCallback? onOpenIntroduction;

  @override
  State<ReportTabPage> createState() => _ReportTabPageState();
}

class _ReportTabPageState extends State<ReportTabPage> {
  late final SessionHistory _history = widget.history ?? SessionHistory();
  late final CloudSyncService _sync =
      widget.syncService ?? CloudSyncService(history: _history);
  late Future<List<SessionRecord>> _future = _history.load();
  int _pending = 0;
  DateTime? _lastSync;

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _history.load());
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    final pending = await _sync.pendingCount();
    final last = await _sync.lastSync();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _lastSync = last;
    });
  }

  @override
  void initState() {
    super.initState();
    sessionHistoryRevision.addListener(_reload);
    appSettings.addListener(_reload);
    _loadSyncStatus();
  }

  @override
  void dispose() {
    sessionHistoryRevision.removeListener(_reload);
    appSettings.removeListener(_reload);
    super.dispose();
  }

  void _openSync() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => RemoteSyncPage(
            history: _history,
            syncService: _sync,
          ),
        ))
        .then((_) => _loadSyncStatus());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SessionRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Reports')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not load reports from this device.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final records = snapshot.data ?? const <SessionRecord>[];
        final age = appSettings.value.listenerAgeYears;
        final data = buildReportData(records, ageYears: age);

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Reports'),
              actions: [
                IconButton(
                  key: const Key('report-sync-action'),
                  tooltip: _pending == 0
                      ? 'Online sync'
                      : 'Online sync: $_pending pending',
                  onPressed: _openSync,
                  icon: Badge(
                    isLabelVisible: _pending > 0,
                    label: Text('$_pending'),
                    child: Icon(
                      _pending == 0 && _lastSync != null
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                    ),
                  ),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.assessment_outlined), text: 'Summary'),
                  Tab(icon: Icon(Icons.history), text: 'Sessions'),
                  Tab(icon: Icon(Icons.show_chart), text: 'Progress'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                if (data == null || data.tests.isEmpty)
                  _EmptyReport(
                    onStartTests: widget.onStartTests,
                    onOpenIntroduction: widget.onOpenIntroduction,
                  )
                else
                  Column(
                    children: [
                      _StorageBanner(
                        sessionCount: records.length,
                        pending: _pending,
                        lastSync: _lastSync,
                        onSync: _openSync,
                      ),
                      Expanded(
                        child: EnhancedReportPage(
                          embedded: true,
                          demo: false,
                          tests: data.tests,
                          ageYears: age,
                          narrativeInput: data.narrative,
                          staircase: data.staircase,
                          sessionCount: data.sessionCount,
                          confusionMatrix: data.confusionMatrix,
                          confusionSessionCount: data.confusionSessionCount,
                          patientName: kDefaultPatient,
                          patientId: 'on-device',
                        ),
                      ),
                    ],
                  ),
                _SessionsTab(records: records),
                TrendPage(records: records, embedded: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StorageBanner extends StatelessWidget {
  const _StorageBanner({
    required this.sessionCount,
    required this.pending,
    required this.lastSync,
    required this.onSync,
  });

  final int sessionCount;
  final int pending;
  final DateTime? lastSync;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final synced = pending == 0 && lastSync != null;
    final syncMessage = synced
        ? 'Online copy is up to date.'
        : pending > 0
            ? '$pending waiting for optional sync.'
            : 'Not synced online yet.';
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onSync,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.offline_pin_outlined,
                size: 19,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '$sessionCount saved offline. $syncMessage',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Sync',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({
    this.onStartTests,
    this.onOpenIntroduction,
  });

  final VoidCallback? onStartTests;
  final VoidCallback? onOpenIntroduction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.assessment_outlined,
                  size: 36,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your reports will appear here',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Complete a test to create a real on-device report with the '
                'score, graph, session history, and progress trend. Reports '
                'remain available without internet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              if (onStartTests != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('empty-report-start-tests'),
                    onPressed: onStartTests,
                    icon: const Icon(Icons.hearing_outlined),
                    label: const Text('Browse tests'),
                  ),
                ),
              if (onOpenIntroduction != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('empty-report-introduction'),
                    onPressed: onOpenIntroduction,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('View introduction'),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'No demonstration or sample patient data is shown here.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionsTab extends StatelessWidget {
  const _SessionsTab({required this.records});

  final List<SessionRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (records.isEmpty) {
      return Center(
        child: Text(
          'No completed sessions yet.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: records.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = records[index];
        final accuracy = (record.accuracy * 100).round();
        return ListTile(
          key: Key('report-session-$index'),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            foregroundColor: theme.colorScheme.primary,
            child: Text(
              '$accuracy',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          title: Text(
            record.label == null
                ? record.title
                : '${record.title} - ${record.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${record.metric ?? '$accuracy%'} | ${record.trials} trials | '
            '${DateFormat.yMMMd().format(record.timestamp)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            record.synced
                ? Icons.cloud_done_outlined
                : Icons.offline_pin_outlined,
            color: record.synced
                ? const Color(0xff2f9e75)
                : theme.colorScheme.onSurfaceVariant,
          ),
          onTap: () async {
            await showSessionResultSheet(context, record: record);
          },
        );
      },
    );
  }
}
