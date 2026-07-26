import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/session_history.dart';
import '../trends/trend_page.dart';

/// Aggregated per-patient summary computed from that patient's sessions.
class PatientSummary {
  const PatientSummary({
    required this.patient,
    required this.sessions,
    required this.lastSession,
    required this.trend,
    required this.overallAccuracy,
  });

  final String patient;
  final List<SessionRecord> sessions;
  final DateTime lastSession;
  final TrendDirection trend;

  /// Mean accuracy across the patient's sessions (0.0–1.0).
  final double overallAccuracy;

  int get sessionCount => sessions.length;
}

/// Groups [records] by patient and computes a summary for each, ordered by
/// most-recent session first.
List<PatientSummary> summarisePatients(List<SessionRecord> records) {
  final byPatient = <String, List<SessionRecord>>{};
  for (final r in records) {
    byPatient.putIfAbsent(r.patient, () => <SessionRecord>[]).add(r);
  }
  final summaries = <PatientSummary>[];
  byPatient.forEach((patient, sessions) {
    final ordered = [...sessions]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final xs = <double>[
      for (var i = 0; i < ordered.length; i++) i.toDouble()
    ];
    final ys = <double>[for (final s in ordered) s.accuracy * 100];
    final slope = linearRegressionSlope(xs, ys);
    final trend = ordered.length >= 2
        ? trendFromSlope(slope)
        : TrendDirection.stable;
    final meanAcc = ordered.isEmpty
        ? 0.0
        : ordered.map((s) => s.accuracy).reduce((a, b) => a + b) /
            ordered.length;
    summaries.add(PatientSummary(
      patient: patient,
      sessions: ordered,
      lastSession: ordered.last.timestamp,
      trend: trend,
      overallAccuracy: meanAcc,
    ));
  });
  summaries.sort((a, b) => b.lastSession.compareTo(a.lastSession));
  return summaries;
}

/// Clinician-facing dashboard: a list of patients (grouped from on-device
/// session history) with per-patient session counts, last-session date and an
/// accuracy-trend indicator. Tapping a patient opens their history + trend
/// chart. "Export All Data" copies the full record set as JSON to the
/// clipboard. Research use only — not a diagnosis.
class ClinicianDashboardPage extends StatefulWidget {
  const ClinicianDashboardPage({super.key, this.history, this.records});

  final SessionHistory? history;

  /// Optional pre-loaded records (bypasses [history] when provided; used by
  /// tests).
  final List<SessionRecord>? records;

  @override
  State<ClinicianDashboardPage> createState() => _ClinicianDashboardPageState();
}

class _ClinicianDashboardPageState extends State<ClinicianDashboardPage> {
  static const Color _muted = Color(0xff94a3b8);

  List<SessionRecord>? _records;

  @override
  void initState() {
    super.initState();
    if (widget.records != null) {
      _records = widget.records;
    } else {
      (widget.history ?? SessionHistory()).load().then((r) {
        if (mounted) setState(() => _records = r);
      });
    }
  }

  void _exportAll() {
    final records = _records ?? const <SessionRecord>[];
    final payload = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'session_count': records.length,
      'sessions': records.map((r) => r.toJson()).toList(),
      'note': 'HearBloom research export — not a clinical record.',
    };
    unawaited(Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload))));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Copied ${records.length} session record(s) as '
              'JSON to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = _records;
    final summaries = records == null ? null : summarisePatients(records);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician dashboard'),
        actions: [
          IconButton(
            key: const Key('dashboard-export'),
            tooltip: 'Export all data as JSON',
            icon: const Icon(Icons.ios_share),
            onPressed: records == null ? null : _exportAll,
          ),
        ],
      ),
      body: summaries == null
          ? const Center(child: CircularProgressIndicator())
          : summaries.isEmpty
              ? _empty(theme)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text('Patients',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text(
                          'Sessions are grouped by patient from on-device '
                          'history. Research use only — not a diagnosis.',
                          style: TextStyle(
                              color: _muted, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        for (final s in summaries) ...[
                          _PatientCard(
                            summary: s,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _PatientDetailPage(summary: s),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 8),
                        Semantics(
                          button: true,
                          label: 'Export all data as JSON',
                          child: FilledButton.icon(
                            onPressed: _exportAll,
                            icon: const Icon(Icons.ios_share),
                            label: const Text('Export All Data'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.medical_information_outlined,
                  size: 48, color: Color(0xff8b9bb4)),
              const SizedBox(height: 12),
              Text('No patient sessions yet',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text(
                'Complete a few exercises to populate the dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.summary, required this.onTap});

  final PatientSummary summary;
  final VoidCallback onTap;

  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);

  @override
  Widget build(BuildContext context) {
    final pct = (summary.overallAccuracy * 100).round();
    final dateStr = DateFormat('d MMM yyyy, HH:mm').format(summary.lastSession);
    return Semantics(
      button: true,
      label: '${summary.patient}, ${summary.sessionCount} sessions, '
          'trend ${summary.trend.label}',
      child: Material(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('patient-${summary.patient}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x1a3b82f6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x333b82f6)),
                  ),
                  child: const Icon(Icons.person_outline,
                      color: Color(0xff3b82f6)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(summary.patient,
                          style: const TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        '${summary.sessionCount} session'
                        '${summary.sessionCount == 1 ? '' : 's'} · '
                        'last $dateStr',
                        style: const TextStyle(color: _muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 2),
                      Text('Mean accuracy $pct%',
                          style: const TextStyle(
                              color: _muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _TrendBadge(trend: summary.trend),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});

  final TrendDirection trend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: trend.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: trend.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(trend.icon, size: 15, color: trend.color),
          const SizedBox(width: 5),
          Text(trend.label,
              style: TextStyle(
                  color: trend.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Per-patient detail: session history list + the reusable trend chart.
class _PatientDetailPage extends StatelessWidget {
  const _PatientDetailPage({required this.summary});

  final PatientSummary summary;

  static const Color _muted = Color(0xff94a3b8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Most-recent first for the list view.
    final recent = [...summary.sessions]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Scaffold(
      appBar: AppBar(title: Text(summary.patient)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Session history',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  _TrendBadge(trend: summary.trend),
                ],
              ),
              const SizedBox(height: 4),
              Text('${summary.sessionCount} sessions recorded',
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 12),
              // Reuse the existing trend view (per-test line charts).
              SizedBox(
                height: 420,
                child: TrendPage(records: summary.sessions),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              for (final r in recent) _SessionRow(record: r),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.record});

  final SessionRecord record;

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);

  @override
  Widget build(BuildContext context) {
    final pct = (record.accuracy * 100).round();
    final dateStr = DateFormat('d MMM, HH:mm').format(record.timestamp);
    final color = pct >= 80
        ? const Color(0xff22c55e)
        : pct >= 50
            ? const Color(0xfffbbf24)
            : const Color(0xffef4444);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.title,
                    style: const TextStyle(
                        color: _ink, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${record.trials} trials · $dateStr',
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          Text('$pct%',
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
