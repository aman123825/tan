import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/psychometrics.dart';
import '../../data/session_history.dart';

/// Session A-vs-B comparison with a test–retest reliability panel.
///
/// Pick a test with at least two stored sessions, then any two of its
/// sessions: the page shows both headline metrics, the change (aware of
/// whether lower is better for thresholds), per-sub-score deltas, and — when
/// the stored history supports it — the test–retest ICC(2,1)/ICC(3,1)
/// computed across patients' first vs second administrations
/// (Shrout & Fleiss, 1979). Research summaries — never a diagnosis.
class SessionComparePage extends StatefulWidget {
  const SessionComparePage({super.key, this.history});

  /// Injectable for tests; defaults to the on-device [SessionHistory].
  final SessionHistory? history;

  @override
  State<SessionComparePage> createState() => _SessionComparePageState();
}

class _SessionComparePageState extends State<SessionComparePage> {
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _soft = Color(0xff8b9bb4);
  static const Color _good = Color(0xff22c55e);
  static const Color _bad = Color(0xffef4444);

  List<SessionRecord> _all = const [];
  bool _loaded = false;
  String? _groupId;
  int _indexA = 1; // older of the default pair
  int _indexB = 0; // most recent

  @override
  void initState() {
    super.initState();
    (widget.history ?? SessionHistory()).load().then((records) {
      if (!mounted) return;
      setState(() {
        _all = records;
        _loaded = true;
        _groupId = _comparableGroups.isEmpty ? null : _comparableGroups.first;
      });
    });
  }

  /// Group ids with at least two sessions, in history (recency) order.
  List<String> get _comparableGroups {
    final counts = <String, int>{};
    final order = <String>[];
    for (final r in _all) {
      final n = (counts[r.groupId] ?? 0) + 1;
      counts[r.groupId] = n;
      if (n == 2) order.add(r.groupId);
    }
    return order;
  }

  /// Sessions of the selected test, most recent first.
  List<SessionRecord> get _ofGroup =>
      [for (final r in _all) if (r.groupId == _groupId) r];

  String _titleOf(String groupId) {
    for (final r in _all) {
      if (r.groupId == groupId) return r.title;
    }
    return groupId;
  }

  /// The comparable numeric value of a record: the persisted headline metric,
  /// falling back to percent accuracy for legacy records.
  double _valueOf(SessionRecord r) => r.metricValue ?? r.accuracy * 100;

  String _unitOf(SessionRecord r) => r.metricUnit ?? '%';

  String _displayOf(SessionRecord r) =>
      r.metric ?? '${(r.accuracy * 100).round()}%';

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// (patients × [first, second] administrations) matrix for the selected
  /// test — the input for the across-patients test–retest ICC.
  List<List<double>> _retestMatrix() {
    final byPatient = <String, List<SessionRecord>>{};
    for (final r in _ofGroup) {
      byPatient.putIfAbsent(r.patient, () => []).add(r);
    }
    final rows = <List<double>>[];
    for (final sessions in byPatient.values) {
      if (sessions.length < 2) continue;
      // History is most-recent first; chronological = reversed.
      final chrono = sessions.reversed.toList();
      rows.add([_valueOf(chrono[0]), _valueOf(chrono[1])]);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare sessions (A/B)')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _comparableGroups.isEmpty
              ? _emptyState()
              : _body(),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows, size: 44, color: _soft),
            SizedBox(height: 12),
            Text(
              'Run the same test at least twice to compare two sessions '
              'side by side.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 14.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final sessions = _ofGroup;
    // Clamp selections after test switches.
    final a = _indexA.clamp(0, sessions.length - 1);
    final b = _indexB.clamp(0, sessions.length - 1);
    final recA = sessions[a];
    final recB = sessions[b];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _testSelector(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _sessionPicker('Session A', sessions, a,
                        (i) => setState(() => _indexA = i))),
                const SizedBox(width: 10),
                Expanded(
                    child: _sessionPicker('Session B', sessions, b,
                        (i) => setState(() => _indexB = i))),
              ],
            ),
            const SizedBox(height: 14),
            _comparisonCard(recA, recB),
            const SizedBox(height: 14),
            _reliabilityCard(),
            const SizedBox(height: 10),
            const Text(
              'Research comparison on uncalibrated audio — differences '
              'between two single sessions include normal measurement '
              'variability, not only real change. Not a diagnosis.',
              style: TextStyle(color: _soft, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _testSelector() {
    return _card(
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: _muted, size: 20),
          const SizedBox(width: 10),
          const Text('Test',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 14),
          Expanded(
            child: DropdownButton<String>(
              key: const Key('compare-test'),
              value: _groupId,
              isExpanded: true,
              dropdownColor: const Color(0xff1e293b),
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
              underline: const SizedBox.shrink(),
              items: [
                for (final g in _comparableGroups)
                  DropdownMenuItem(value: g, child: Text(_titleOf(g))),
              ],
              onChanged: (g) => setState(() {
                _groupId = g;
                _indexB = 0;
                _indexA = 1;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionPicker(String label, List<SessionRecord> sessions, int value,
      void Function(int) onChanged) {
    final df = DateFormat('d MMM, HH:mm');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
          DropdownButton<int>(
            key: Key('compare-${label.toLowerCase().replaceAll(' ', '-')}'),
            value: value,
            isExpanded: true,
            dropdownColor: const Color(0xff1e293b),
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
            underline: const SizedBox.shrink(),
            items: [
              for (var i = 0; i < sessions.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    '${df.format(sessions[i].timestamp)} · '
                    '${_displayOf(sessions[i])}'
                    '${sessions[i].label == null ? '' : ' · “${sessions[i].label}”'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (i) => i == null ? null : onChanged(i),
          ),
        ],
      ),
    );
  }

  Widget _comparisonCard(SessionRecord a, SessionRecord b) {
    final higherBetter = b.higherIsBetter ?? a.higherIsBetter ?? true;
    final delta = _valueOf(b) - _valueOf(a);
    final improved = delta == 0 ? null : (higherBetter ? delta > 0 : delta < 0);
    final unit = _unitOf(b);

    Widget row(String label, String va, String vb, {Widget? trailing}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text(label,
                      style: const TextStyle(color: _muted, fontSize: 13))),
              Expanded(
                  flex: 2,
                  child: Text(va,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700))),
              Expanded(
                  flex: 2,
                  child: Text(vb,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700))),
              SizedBox(width: 86, child: trailing ?? const SizedBox.shrink()),
            ],
          ),
        );

    Widget deltaChip(double d, bool? better) {
      if (better == null) {
        return const Text('no change',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12));
      }
      final color = better ? _good : _bad;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(better ? Icons.trending_up : Icons.trending_down,
                size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text('${d > 0 ? '+' : ''}${_fmt(d)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }

    final subKeys = <String>{
      ...?a.subScores?.keys,
      ...?b.subScores?.keys,
    }.toList()
      ..sort();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('Measure',
                      style: TextStyle(
                          color: _soft,
                          fontSize: 12,
                          fontWeight: FontWeight.w800))),
              Expanded(
                  flex: 2,
                  child: Text('A',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _soft,
                          fontSize: 12,
                          fontWeight: FontWeight.w800))),
              Expanded(
                  flex: 2,
                  child: Text('B',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _soft,
                          fontSize: 12,
                          fontWeight: FontWeight.w800))),
              SizedBox(
                  width: 86,
                  child: Text('B − A',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _soft,
                          fontSize: 12,
                          fontWeight: FontWeight.w800))),
            ],
          ),
          const Divider(color: _border, height: 18),
          row(
            'Headline ($unit)${higherBetter ? '' : ' · lower is better'}',
            _displayOf(a),
            _displayOf(b),
            trailing: deltaChip(delta, improved),
          ),
          for (final k in subKeys)
            if (a.subScores?[k] != null && b.subScores?[k] != null)
              row(
                k,
                _fmt(a.subScores![k]!),
                _fmt(b.subScores![k]!),
                trailing: deltaChip(
                  b.subScores![k]! - a.subScores![k]!,
                  b.subScores![k]! == a.subScores![k]!
                      ? null
                      : higherBetter
                          ? b.subScores![k]! > a.subScores![k]!
                          : b.subScores![k]! < a.subScores![k]!,
                ),
              ),
          row('Trials', '${a.trials}', '${b.trials}'),
          row('Raw accuracy', '${(a.accuracy * 100).round()}%',
              '${(b.accuracy * 100).round()}%'),
          if (a.confidence != null || b.confidence != null)
            row('Confidence (0–10)', a.confidence?.toString() ?? '—',
                b.confidence?.toString() ?? '—'),
        ],
      ),
    );
  }

  Widget _reliabilityCard() {
    final matrix = _retestMatrix();
    final icc2 = matrix.length >= 2 ? icc21(matrix) : null;
    final icc3 = matrix.length >= 2 ? icc31(matrix) : null;

    // Within-history repeatability: mean |difference| over consecutive
    // same-test pairs (plain description, not an inferential statistic).
    final chrono = _ofGroup.reversed.toList();
    final diffs = <double>[
      for (var i = 1; i < chrono.length; i++)
        (_valueOf(chrono[i]) - _valueOf(chrono[i - 1])).abs(),
    ];
    final meanAbsDiff = diffs.isEmpty
        ? null
        : diffs.reduce((x, y) => x + y) / diffs.length;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Test–retest reliability',
              style: TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 8),
          if (icc2 != null || icc3 != null) ...[
            _statRow('ICC(2,1) — absolute agreement',
                icc2 == null ? '—' : icc2.toStringAsFixed(2)),
            _statRow('ICC(3,1) — consistency',
                icc3 == null ? '—' : icc3.toStringAsFixed(2)),
            _statRow('Patients with ≥2 administrations', '${matrix.length}'),
            const SizedBox(height: 6),
            const Text(
              'Computed across patients from each one\'s first vs second '
              'administration (Shrout & Fleiss, 1979). ICC ≥ 0.75 is '
              'conventionally read as good reliability.',
              style: TextStyle(color: _soft, fontSize: 12, height: 1.4),
            ),
          ] else ...[
            if (meanAbsDiff != null)
              _statRow('Mean session-to-session change (${_unitOf(chrono.last)})',
                  _fmt(meanAbsDiff)),
            _statRow('Sessions of this test', '${chrono.length}'),
            const SizedBox(height: 6),
            const Text(
              'A test–retest ICC needs at least two patients with two '
              'administrations each (see the clinician dashboard for '
              'multi-patient use). The change shown above describes this '
              'device\'s repeated runs only.',
              style: TextStyle(color: _soft, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child:
                    Text(label, style: const TextStyle(color: _muted))),
            Text(value,
                style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: child,
      );
}
