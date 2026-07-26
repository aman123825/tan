import 'package:flutter/material.dart';

/// Subscale of the HHIE-S (Hearing Handicap Inventory for the Elderly/Adults —
/// Screening version).
enum HhieSubscale { emotional, social }

extension HhieSubscaleInfo on HhieSubscale {
  String get label => switch (this) {
        HhieSubscale.emotional => 'Emotional',
        HhieSubscale.social => 'Social / Situational',
      };
}

/// One HHIE-S item: its [subscale] and prompt [text].
class HhieItem {
  const HhieItem(this.subscale, this.text);
  final HhieSubscale subscale;
  final String text;
}

/// HHIE-S (screening) items and scoring (Ventry & Weinstein, 1982;
/// Weinstein, 1986). Each item scores Yes = 4, Sometimes = 2, No = 0; the
/// 10-item total ranges 0–40 and a total > 10 suggests a hearing handicap.
///
/// A screening aid, not a diagnosis.
class HhieScreening {
  const HhieScreening._();

  /// Score for each response option (index 0 = Yes, 1 = Sometimes, 2 = No).
  static const List<int> optionScores = <int>[4, 2, 0];

  /// Response option labels indexed to match [optionScores].
  static const List<String> optionLabels = <String>['Yes', 'Sometimes', 'No'];

  /// Total above which a hearing handicap is suggested.
  static const int referralCutoff = 10;

  /// The ten items (five Emotional, five Social/Situational), in order.
  static const List<HhieItem> items = <HhieItem>[
    HhieItem(HhieSubscale.emotional,
        'Does a hearing problem cause you to feel embarrassed when meeting new people?'),
    HhieItem(HhieSubscale.emotional,
        'Does a hearing problem cause you to feel frustrated when talking to family?'),
    HhieItem(HhieSubscale.emotional,
        'Do you feel handicapped by a hearing problem?'),
    HhieItem(HhieSubscale.emotional,
        'Does a hearing problem cause you difficulty when visiting friends or relatives?'),
    HhieItem(HhieSubscale.emotional,
        'Does a hearing problem cause you to feel foolish or stupid?'),
    HhieItem(HhieSubscale.social,
        'Does a hearing problem cause you difficulty listening to the TV or radio?'),
    HhieItem(HhieSubscale.social,
        'Do you have difficulty hearing when you attend a party?'),
    HhieItem(HhieSubscale.social,
        'Do you have difficulty hearing someone whisper?'),
    HhieItem(HhieSubscale.social,
        'Do you feel that a hearing problem causes you to miss out on information?'),
    HhieItem(HhieSubscale.social,
        'Does a hearing problem cause you difficulty in a restaurant with relatives or friends?'),
  ];

  /// Maximum possible total (10 items × 4).
  static int get maxScore => items.length * optionScores.first;

  /// Sum of the item scores for [answers] (each 0/1/2 option index).
  static int total(List<int> answers) {
    var sum = 0;
    for (final a in answers) {
      sum += optionScores[a.clamp(0, optionScores.length - 1)];
    }
    return sum;
  }

  /// Subscale total for [subscale].
  static int subscaleTotal(List<int> answers, HhieSubscale subscale) {
    var sum = 0;
    for (var i = 0; i < items.length; i++) {
      if (items[i].subscale == subscale) {
        sum += optionScores[answers[i].clamp(0, optionScores.length - 1)];
      }
    }
    return sum;
  }

  /// Whether [total] exceeds the screening cut-off (> 10).
  static bool suggestsHandicap(int total) => total > referralCutoff;

  /// A banded interpretation of [total] (Weinstein, 1986).
  static String interpretation(int total) {
    if (total <= 10) {
      return 'Score $total / $maxScore suggests no self-perceived handicap '
          '(≤ 10).';
    }
    if (total <= 24) {
      return 'Score $total / $maxScore suggests a mild-to-moderate '
          'self-perceived handicap (12–24).';
    }
    return 'Score $total / $maxScore suggests a significant self-perceived '
        'handicap (26–40).';
  }

  /// Recommended next step for [total].
  static String recommendation(int total) => suggestsHandicap(total)
      ? 'A hearing evaluation by an audiologist is recommended.'
      : 'No hearing evaluation is indicated by this screen alone. Re-screen if '
          'concerns arise.';
}

/// The HHIE-S screening questionnaire page (Yes / Sometimes / No radios).
class HhiePage extends StatefulWidget {
  const HhiePage({super.key, this.onCompleted});

  /// Called with the total score when the listener taps "See result".
  final void Function(int total)? onCompleted;

  @override
  State<HhiePage> createState() => _HhiePageState();
}

class _HhiePageState extends State<HhiePage> {
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);
  static const Color _good = Color(0xff22c55e);
  static const Color _warn = Color(0xfffbbf24);

  final List<int?> _answers =
      List<int?>.filled(HhieScreening.items.length, null);
  bool _showResult = false;

  int get _answeredCount => _answers.where((a) => a != null).length;
  bool get _allAnswered => _answeredCount == _answers.length;
  int get _total =>
      HhieScreening.total(_answers.map((a) => a ?? 2).toList(growable: false));

  void _setAnswer(int index, int value) =>
      setState(() => _answers[index] = value);

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
        title: const Text('HHIE-S screening'),
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
                for (var i = 0; i < HhieScreening.items.length; i++) ...[
                  _itemCard(i),
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
              Icon(Icons.record_voice_over, color: _primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hearing Handicap Inventory — Screening',
                  style: TextStyle(
                      color: _ink, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Answer each of the 10 questions Yes, Sometimes or No. A total above '
            '10 suggests a hearing evaluation may be worthwhile.',
            style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'Screening aid (Ventry & Weinstein, 1982) — not a diagnosis.',
            style: TextStyle(
                color: _muted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(int index) {
    final item = HhieScreening.items[index];
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
                      color: _primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.text,
                    style: const TextStyle(
                        color: _ink, fontSize: 15, height: 1.35)),
              ),
              _subscaleTag(item.subscale),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var v = 0; v < HhieScreening.optionLabels.length; v++) ...[
                if (v > 0) const SizedBox(width: 8),
                Expanded(
                  child: _RadioOption(
                    key: Key('hhie-$index-opt$v'),
                    label: HhieScreening.optionLabels[v],
                    score: HhieScreening.optionScores[v],
                    selected: _answers[index] == v,
                    onTap: () => _setAnswer(index, v),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _subscaleTag(HhieSubscale subscale) {
    final isE = subscale == HhieSubscale.emotional;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Text(isE ? 'E' : 'S',
          style: const TextStyle(
              color: _muted, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Widget _submitBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$_answeredCount of ${_answers.length} answered',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13)),
        const SizedBox(height: 10),
        FilledButton(
          key: const Key('hhie-see-result'),
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
    final flagged = HhieScreening.suggestsHandicap(total);
    final color = flagged ? _warn : _good;
    return Container(
      key: const Key('hhie-result'),
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
            child: Text('$total / ${HhieScreening.maxScore}',
                style: TextStyle(
                    color: color, fontSize: 40, fontWeight: FontWeight.w900)),
          ),
          const Center(
            child: Text('Total score',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _subscaleScore('Emotional',
                  HhieScreening.subscaleTotal(_filled(), HhieSubscale.emotional)),
              _subscaleScore('Social',
                  HhieScreening.subscaleTotal(_filled(), HhieSubscale.social)),
            ],
          ),
          const SizedBox(height: 14),
          Text(HhieScreening.interpretation(total),
              style: const TextStyle(color: _ink, height: 1.4)),
          const SizedBox(height: 10),
          Text(HhieScreening.recommendation(total),
              style: const TextStyle(color: _muted, height: 1.4)),
          const SizedBox(height: 16),
          const Text(
            'This screening does not diagnose a hearing loss. Discuss results '
            'with a qualified audiologist.',
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

  List<int> _filled() => _answers.map((a) => a ?? 2).toList(growable: false);

  Widget _subscaleScore(String label, int value) {
    return Column(
      children: [
        Text('$value',
            style: const TextStyle(
                color: _ink, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

/// A radio-style, tappable Yes/Sometimes/No option (a circle indicator plus a
/// label). Avoids the newly-deprecated RadioListTile group API while keeping a
/// clear single-select affordance.
class _RadioOption extends StatelessWidget {
  const _RadioOption({
    super.key,
    required this.label,
    required this.score,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int score;
  final bool selected;
  final VoidCallback onTap;

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$label ($score)',
      child: Material(
        color: selected ? const Color(0x1a3b82f6) : const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? _primary : const Color(0x33ffffff),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? _primary : _muted,
                ),
                const SizedBox(height: 4),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: selected ? _ink : _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
