import 'package:flutter/material.dart';

import '../../core/session_planner.dart';
import '../../data/session_history.dart';

// Dark glassmorphic palette.
const Color _ink = Color(0xffe2e8f0);
const Color _muted = Color(0xff94a3b8);
const Color _border = Color(0x33ffffff);
const Color _primary = Color(0xff3b82f6);
const Color _needsWork = Color(0xffef4444); // red
const Color _improving = Color(0xfffbbf24); // yellow
const Color _mastered = Color(0xff22c55e); // green

/// Traffic-light colour for a mastery status.
Color statusColor(ExerciseStatus status) => switch (status) {
      ExerciseStatus.needsWork => _needsWork,
      ExerciseStatus.improving => _improving,
      ExerciseStatus.mastered => _mastered,
    };

String statusLabel(ExerciseStatus status) => switch (status) {
      ExerciseStatus.needsWork => 'Needs work',
      ExerciseStatus.improving => 'Improving',
      ExerciseStatus.mastered => 'Mastered',
    };

/// Automated Session Planner — ranks every exercise the listener has practised
/// by how much it needs attention, and offers to start the top pick.
///
/// Pass [records] directly for tests/previews; otherwise the on-device
/// [SessionHistory] is loaded. [onStartExercise] is invoked with the chosen
/// exercise (the host wires it to the matching renderer).
class PlannerPage extends StatefulWidget {
  const PlannerPage({
    super.key,
    this.records,
    this.onStartExercise,
    this.now,
  });

  final List<SessionRecord>? records;
  final void Function(ExercisePriority pick)? onStartExercise;
  final DateTime? now;

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  List<ExercisePriority>? _ranked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = widget.records ?? await SessionHistory().load();
    if (!mounted) return;
    setState(() {
      _ranked = SessionPlanner.analyze(records, now: widget.now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ranked = _ranked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session planner'),
      ),
      body: ranked == null
          ? const Center(child: CircularProgressIndicator())
          : ranked.isEmpty
              ? _emptyState(context)
              : _rankedList(context, ranked),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tips_and_updates_outlined,
                size: 48, color: _muted),
            const SizedBox(height: 14),
            Text('No recommendations yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Complete a training session or test and the planner will suggest '
              'what to practise next, based on your scores and how long since '
              'you last tried each exercise.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankedList(BuildContext context, List<ExercisePriority> ranked) {
    final top = ranked.first;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _RecommendedCard(
          pick: top,
          onStart: widget.onStartExercise == null
              ? null
              : () => widget.onStartExercise!(top),
        ),
        const SizedBox(height: 22),
        Text(
          'All exercises by priority',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800, color: _ink),
        ),
        const SizedBox(height: 4),
        const Text(
          'Higher priority = more in need of practice.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < ranked.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ExerciseTile(
              rank: i + 1,
              item: ranked[i],
              onTap: widget.onStartExercise == null
                  ? null
                  : () => widget.onStartExercise!(ranked[i]),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Motivational study aid — it never changes scoring, adaptation or '
          'master volume.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }
}

/// The highlighted "Recommended for you" card for the top pick.
class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.pick, this.onStart});

  final ExercisePriority pick;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusColor(pick.status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x553b82f6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: _primary, size: 18),
              const SizedBox(width: 8),
              Text('RECOMMENDED FOR YOU',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xff7dd3fc),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatusDot(color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(pick.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: _ink)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(pick.reason, style: const TextStyle(color: _muted)),
          const SizedBox(height: 16),
          if (onStart != null)
            FilledButton.icon(
              key: const Key('planner-start-recommended'),
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start recommended'),
            ),
        ],
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.rank, required this.item, this.onTap});

  final int rank;
  final ExercisePriority item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(item.status);
    return Semantics(
      button: onTap != null,
      label: '${item.title}, ${statusLabel(item.status)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x14ffffff),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                _StatusDot(color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          )),
                      const SizedBox(height: 3),
                      Text(item.reason,
                          style: const TextStyle(color: _muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: color.withOpacity(0.5)),
                  ),
                  child: Text(statusLabel(item.status),
                      style: TextStyle(
                          color: color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.5), blurRadius: 8),
        ],
      ),
    );
  }
}
