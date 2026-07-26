import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/gamification_store.dart';
import '../../data/session_history.dart';

/// Self-leaderboard: your personal bests per test (aware of whether lower is
/// better for thresholds), plus streak and totals. You compete only with
/// yourself — no accounts, nothing leaves the device.
class PersonalBestsPage extends StatefulWidget {
  const PersonalBestsPage({super.key, this.history});

  final SessionHistory? history;

  @override
  State<PersonalBestsPage> createState() => _PersonalBestsPageState();
}

class _Best {
  _Best(this.record, this.sessionCount);

  final SessionRecord record;
  final int sessionCount;
}

class _PersonalBestsPageState extends State<PersonalBestsPage> {
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _soft = Color(0xff8b9bb4);
  static const Color _gold = Color(0xfffbbf24);

  List<SessionRecord> _all = const [];
  int _points = 0;
  int _streak = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await (widget.history ?? SessionHistory()).load();
    var points = 0, streak = 0;
    try {
      final state = await GamificationStore().load();
      points = state.points;
      streak = state.currentStreak;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _all = records;
      _points = points;
      _streak = streak;
      _loaded = true;
    });
  }

  /// Best record per test: highest/lowest metricValue depending on the
  /// persisted direction (falls back to accuracy for legacy records).
  List<_Best> get _bests {
    final byGroup = <String, List<SessionRecord>>{};
    for (final r in _all) {
      byGroup.putIfAbsent(r.groupId, () => []).add(r);
    }
    final out = <_Best>[];
    for (final sessions in byGroup.values) {
      SessionRecord best = sessions.first;
      double valueOf(SessionRecord r) => r.metricValue ?? r.accuracy * 100;
      for (final r in sessions.skip(1)) {
        final higherBetter = r.higherIsBetter ?? true;
        final better = higherBetter
            ? valueOf(r) > valueOf(best)
            : valueOf(r) < valueOf(best);
        if (better) best = r;
      }
      out.add(_Best(best, sessions.length));
    }
    out.sort((a, b) => b.sessionCount.compareTo(a.sessionCount));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal bests')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _all.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Complete a few sessions and your best results will '
                      'collect here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, height: 1.4),
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: _statTile(
                                    Icons.stars, '$_points', 'points')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _statTile(Icons.local_fire_department,
                                    '$_streak', 'day streak')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _statTile(Icons.hearing,
                                    '${_all.length}', 'sessions')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'You compete only with yourself — every row is '
                          'your best run of that test on this device.',
                          style: TextStyle(color: _soft, fontSize: 12.5),
                        ),
                        const SizedBox(height: 10),
                        for (final b in _bests) _bestRow(b),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _statTile(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Icon(icon, color: _gold, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    color: _ink, fontSize: 18, fontWeight: FontWeight.w900)),
            Text(label,
                style: const TextStyle(color: _soft, fontSize: 11.5)),
          ],
        ),
      );

  Widget _bestRow(_Best best) {
    final r = best.record;
    final display = r.metric ?? '${(r.accuracy * 100).round()}%';
    final lowerBetter = r.higherIsBetter == false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: _gold, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    style: const TextStyle(
                        color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${best.sessionCount} '
                  'run${best.sessionCount == 1 ? '' : 's'} · best on '
                  '${DateFormat('d MMM').format(r.timestamp)}'
                  '${lowerBetter ? ' · lower is better' : ''}',
                  style: const TextStyle(color: _soft, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(display,
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w900, fontSize: 15)),
        ],
      ),
    );
  }
}
