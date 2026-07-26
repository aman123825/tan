import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/gamification_store.dart';
import '../../data/session_history.dart';

/// Guardian view (F7): a plain-language progress summary for parents and
/// carers — practice frequency, streak, what was practised, and the latest
/// results in words instead of clinical tables. Points to the full Report
/// tab for detail. Research summaries — never a diagnosis.
class GuardianViewPage extends StatefulWidget {
  const GuardianViewPage({super.key, this.history, this.store});

  final SessionHistory? history;
  final GamificationStore? store;

  @override
  State<GuardianViewPage> createState() => _GuardianViewPageState();
}

class _GuardianViewPageState extends State<GuardianViewPage> {
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _soft = Color(0xff8b9bb4);

  List<SessionRecord> _all = const [];
  int _streak = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await (widget.history ?? SessionHistory()).load();
    var streak = 0;
    try {
      streak = (await (widget.store ?? GamificationStore()).load())
          .currentStreak;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _all = records;
      _streak = streak;
      _loaded = true;
    });
  }

  List<SessionRecord> get _thisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return [for (final r in _all) if (r.timestamp.isAfter(cutoff)) r];
  }

  /// ≈ minutes practised, from trial counts (~8 s per trial).
  int _minutesOf(Iterable<SessionRecord> records) {
    final trials = records.fold<int>(0, (a, r) => a + r.trials);
    return (trials * 8 / 60).ceil();
  }

  /// Plain-language line for a recent session.
  String _plainResult(SessionRecord r) {
    final when = DateFormat('EEE d MMM').format(r.timestamp);
    final what = r.title;
    if (r.metric != null && r.higherIsBetter == false) {
      return '$when — $what: reached ${r.metric} (smaller numbers mean '
          'finer listening).';
    }
    if (r.metric != null) {
      return '$when — $what: ${r.metric}.';
    }
    return '$when — $what: ${(r.accuracy * 100).round()}% of '
        '${r.trials} questions.';
  }

  @override
  Widget build(BuildContext context) {
    final week = _thisWeek;
    final byModule = <String, int>{};
    for (final r in week) {
      byModule[r.moduleId] = (byModule[r.moduleId] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Guardian view')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'A plain-language summary of the listening practice on '
                      'this device — no jargon, no diagnosis.',
                      style:
                          TextStyle(color: _muted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _stat('${week.length}',
                                'sessions this week')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _stat('≈${_minutesOf(week)} min',
                                'practised this week')),
                        const SizedBox(width: 10),
                        Expanded(
                            child:
                                _stat('$_streak', 'day streak')),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (byModule.isNotEmpty) ...[
                      _sectionTitle('What was practised this week'),
                      const SizedBox(height: 8),
                      _card(
                        child: Column(
                          children: [
                            for (final e in byModule.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 5),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_moduleName(e.key),
                                        style: const TextStyle(
                                            color: _muted)),
                                    Text(
                                        '${e.value} '
                                        'session${e.value == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                            color: _ink,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    _sectionTitle('Recent results, in words'),
                    const SizedBox(height: 8),
                    if (_all.isEmpty)
                      const Text(
                        'Nothing recorded yet — results will appear here '
                        'after the first session.',
                        style: TextStyle(color: _muted),
                      )
                    else
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final r in _all.take(6))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 5),
                                child: Text(_plainResult(r),
                                    style: const TextStyle(
                                        color: _ink,
                                        fontSize: 13.5,
                                        height: 1.4)),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      'Practice apps support listening skills but do not '
                      'diagnose. If you are concerned about hearing or '
                      'attention, the full Report tab has the detailed '
                      'numbers to take to an audiologist.',
                      style: TextStyle(
                          color: _soft, fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _moduleName(String id) => switch (id) {
        'auditory' => 'Sound & timing games',
        'noise' => 'Listening in noise',
        'music' => 'Music listening',
        'memory' => 'Listening memory',
        'learning' => 'Speech sounds',
        'openset' => 'Word & sentence games',
        'temporal' => 'Pattern games',
        _ => id,
      };

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(
          color: _ink, fontWeight: FontWeight.w800, fontSize: 15));

  Widget _stat(String value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: _ink, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _soft, fontSize: 11.5)),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: child,
      );
}
