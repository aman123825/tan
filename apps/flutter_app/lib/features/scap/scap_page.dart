import 'package:flutter/material.dart';

/// Screening Checklist for Auditory Processing (SCAP) — a 12-item behavioural
/// screen (Yathiraj & Mascarenhas, 2004). Each item is rated 0 (Never),
/// 1 (Sometimes) or 2 (Often); a total ≥ 9 suggests a full CAPD evaluation.
///
/// This is a screening aid, not a diagnosis.
class ScapScreening {
  const ScapScreening._();

  /// The 12 checklist items, in order.
  static const List<String> items = <String>[
    'Difficulty understanding speech in noisy environments',
    'Frequently asks for repetitions',
    'Difficulty following multi-step verbal instructions',
    'Easily distracted by background sounds',
    'Difficulty with reading, spelling, or phonics',
    'Responds inconsistently to auditory information',
    'Difficulty localizing sounds',
    'Poor auditory memory (forgets what was just said)',
    'Difficulty distinguishing similar-sounding words',
    'Needs more time to process verbal information',
    'Better understanding with visual cues than auditory alone',
    'History of ear infections or hearing concerns',
  ];

  /// Response labels indexed by their score (0, 1, 2).
  static const List<String> optionLabels = <String>['Never', 'Sometimes', 'Often'];

  /// Total score at or above which a CAPD evaluation is suggested.
  static const int referralCutoff = 9;

  /// Maximum possible score (12 items × 2).
  static int get maxScore => items.length * 2;

  /// Sum of the item scores.
  static int total(List<int> answers) =>
      answers.fold<int>(0, (sum, v) => sum + v);

  /// Whether [total] meets the referral cut-off (≥ 9).
  static bool suggestsEvaluation(int total) => total >= referralCutoff;

  /// One-line interpretation of a [total].
  static String interpretation(int total) => suggestsEvaluation(total)
      ? 'Score $total / $maxScore is at or above the screening cut-off (≥ $referralCutoff).'
      : 'Score $total / $maxScore is below the screening cut-off (< $referralCutoff).';

  /// Recommended next step for a [total].
  static String recommendation(int total) => suggestsEvaluation(total)
      ? 'A comprehensive central auditory processing (CAPD) evaluation by an '
          'audiologist is recommended.'
      : 'A full CAPD evaluation is not indicated by this screen alone. '
          'Re-screen if concerns persist.';
}

/// The SCAP screening questionnaire page.
class ScapPage extends StatefulWidget {
  const ScapPage({super.key, this.onCompleted});

  /// Called with the total score when the listener taps "See result".
  final void Function(int total)? onCompleted;

  @override
  State<ScapPage> createState() => _ScapPageState();
}

class _ScapPageState extends State<ScapPage> {
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);
  static const Color _good = Color(0xff22c55e);
  static const Color _warn = Color(0xfffbbf24);

  final List<int?> _answers =
      List<int?>.filled(ScapScreening.items.length, null);
  bool _showResult = false;

  int get _answeredCount => _answers.where((a) => a != null).length;
  bool get _allAnswered => _answeredCount == _answers.length;
  int get _total => ScapScreening.total(
        _answers.map((a) => a ?? 0).toList(growable: false),
      );

  void _setAnswer(int index, int value) {
    setState(() => _answers[index] = value);
  }

  void _seeResult() {
    if (!_allAnswered) return;
    setState(() => _showResult = true);
    widget.onCompleted?.call(_total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('SCAP screening'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _introCard(),
                const SizedBox(height: 16),
                for (var i = 0; i < ScapScreening.items.length; i++) ...[
                  _ScapItemCard(
                    index: i,
                    text: ScapScreening.items[i],
                    value: _answers[i],
                    onChanged: (v) => _setAnswer(i, v),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                if (_showResult) _resultCard() else _submitBar(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rtl, color: _primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Screening Checklist for Auditory Processing',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Rate each of the 12 statements. Choose Never (0), Sometimes (1) '
            'or Often (2). A total of 9 or more suggests a full CAPD '
            'evaluation may be worthwhile.',
            style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'Screening aid only (Yathiraj & Mascarenhas, 2004) — not a diagnosis.',
            style: TextStyle(color: _muted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _submitBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$_answeredCount of ${_answers.length} answered',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const Key('scap-see-result'),
          onPressed: _allAnswered ? _seeResult : null,
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0x333b82f6),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('See result'),
        ),
      ],
    );
  }

  Widget _resultCard() {
    final total = _total;
    final flagged = ScapScreening.suggestsEvaluation(total);
    final color = flagged ? _warn : _good;
    return Container(
      key: const Key('scap-result'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '$total / ${ScapScreening.maxScore}',
              style: TextStyle(
                color: color,
                fontSize: 40,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Center(
            child: Text('Total score',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          _resultRow(Icons.insights, 'Interpretation',
              ScapScreening.interpretation(total)),
          const SizedBox(height: 12),
          _resultRow(Icons.flag_outlined, 'Recommendation',
              ScapScreening.recommendation(total)),
          const SizedBox(height: 16),
          const Text(
            'This screening does not diagnose a central auditory processing '
            'disorder. Discuss results with a qualified audiologist.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(total),
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(IconData icon, String label, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(body,
                  style: const TextStyle(color: _muted, fontSize: 14, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScapItemCard extends StatelessWidget {
  const _ScapItemCard({
    required this.index,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final int index;
  final String text;
  final int? value;
  final ValueChanged<int> onChanged;

  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _primary = Color(0xff3b82f6);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${index + 1}.',
                  style: const TextStyle(
                      color: _primary, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: _ink, fontSize: 15, height: 1.35)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var v = 0; v < ScapScreening.optionLabels.length; v++) ...[
                if (v > 0) const SizedBox(width: 8),
                Expanded(
                  child: _OptionChip(
                    label: ScapScreening.optionLabels[v],
                    score: v,
                    selected: value == v,
                    onTap: () => onChanged(v),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.score,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int score;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xffe2e8f0);
    const muted = Color(0xff94a3b8);
    const primary = Color(0xff3b82f6);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label ($score)',
      child: Material(
        color: selected ? const Color(0x1a3b82f6) : const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? primary : const Color(0x33ffffff),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Text('$score',
                    style: TextStyle(
                        color: selected ? primary : muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 2),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: selected ? ink : muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
