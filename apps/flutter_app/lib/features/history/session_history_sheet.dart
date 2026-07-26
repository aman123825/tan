import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/session_history.dart';

/// Displays the on-device session history (most recent first).
class SessionHistorySheet extends StatelessWidget {
  const SessionHistorySheet({super.key, required this.records});

  final List<SessionRecord> records;

  static Future<void> show(BuildContext context) async {
    final history = await SessionHistory().load();
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff1e293b),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => SessionHistorySheet(
          records: history,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 48, color: Color(0xff8b9bb4)),
            const SizedBox(height: 12),
            Text('No sessions yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: const Color(0xff94a3b8))),
            const SizedBox(height: 6),
            Text('Complete a task to see your history here.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white38)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(Icons.history, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text('Session history',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${records.length} sessions',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xff94a3b8))),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: records.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _SessionTile(record: records[i]),
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (record.accuracy * 100).round();
    final dateStr = _formatDate(record.timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Accuracy circle
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: record.accuracy.clamp(0.0, 1.0),
                  strokeWidth: 4,
                  backgroundColor: const Color(0x33ffffff),
                  color: pct >= 80
                      ? const Color(0xff2e9e5b)
                      : pct >= 50
                          ? const Color(0xffe0a400)
                          : const Color(0xffef4444),
                ),
                Text('$pct',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xffe2e8f0))),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    record.label == null
                        ? record.title
                        : '${record.title} · “${record.label}”',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    record.metric == null
                        ? '${record.trials} trials · $dateStr'
                        : '${record.metric} · ${record.trials} trials · $dateStr',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xff94a3b8))),
              ],
            ),
          ),
          Text('$pct%',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: pct >= 80
                      ? const Color(0xff2e9e5b)
                      : pct >= 50
                          ? const Color(0xffe0a400)
                          : const Color(0xffef4444))),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today ${DateFormat.Hm().format(dt)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day) {
      return 'Yesterday ${DateFormat.Hm().format(dt)}';
    }
    return DateFormat('d MMM, HH:mm').format(dt);
  }
}
