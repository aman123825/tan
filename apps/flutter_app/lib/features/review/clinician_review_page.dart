import 'package:flutter/material.dart';

import '../../data/api.dart';

/// Clinician review mode: lists a profile's sessions and lets a clinician mark
/// each approved/flagged with a note. Reviewing is annotation only — it never
/// changes the locked deterministic scoring (enforced server-side).
class ClinicianReviewPage extends StatefulWidget {
  const ClinicianReviewPage({
    super.key,
    required this.profileId,
    required this.api,
  });

  final String profileId;
  final Api api;

  @override
  State<ClinicianReviewPage> createState() => _ClinicianReviewPageState();
}

class _ClinicianReviewPageState extends State<ClinicianReviewPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await widget.api.exportJson(widget.profileId);
    final sessions = (data['sessions'] as List<dynamic>? ?? const [])
        .map((dynamic e) => (e as Map).cast<String, dynamic>())
        .toList();
    return sessions;
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _review(Map<String, dynamic> session) async {
    final result = await showDialog<_ReviewInput>(
      context: context,
      builder: (context) => const _ReviewDialog(),
    );
    if (result == null) return;
    try {
      await widget.api.reviewSession(
        session['id'] as String,
        reviewedBy: result.reviewedBy,
        status: result.status,
        note: result.note,
      );
    } catch (_) {
      // Surface nothing intrusive; a reload will reflect server state.
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician review'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Could not load sessions.\n${snapshot.error}'));
          }
          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return const Center(child: Text('No sessions to review yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _SessionCard(
                session: sessions[i], onReview: () => _review(sessions[i])),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onReview});

  final Map<String, dynamic> session;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (session['review_status'] as String?) ?? 'unreviewed';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${session['condition'] ?? '?'} · ${session['output_device'] ?? '?'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _ReviewStatusChip(status: status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Started: ${session['started_at'] ?? '—'}',
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
            ),
            if ((session['reviewed_by'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                'Reviewed by ${session['reviewed_by']}'
                '${(session['review_note'] as String?)?.isNotEmpty ?? false ? ' — ${session['review_note']}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onReview,
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: const Text('Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStatusChip extends StatelessWidget {
  const _ReviewStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (status) {
      'approved' => (const Color(0xff22c55e), const Color(0x3322c55e)),
      'flagged' => (const Color(0xffef4444), const Color(0x33ef4444)),
      _ => (const Color(0xff5f6368), const Color(0xffeceff1)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ReviewInput {
  const _ReviewInput(this.reviewedBy, this.status, this.note);
  final String reviewedBy;
  final String status;
  final String note;
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _reviewer = TextEditingController();
  final _note = TextEditingController();
  String _status = 'approved';

  @override
  void dispose() {
    _reviewer.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _reviewer,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Reviewer name'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'approved', label: Text('Approve')),
              ButtonSegment(value: 'flagged', label: Text('Flag')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reviewer.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _ReviewInput(
                        _reviewer.text.trim(), _status, _note.text.trim()),
                  ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
