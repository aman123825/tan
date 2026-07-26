import 'package:flutter/material.dart';

/// APHAB subscale (Cox & Alexander, 1995).
enum AphabScale { ec, bn, rv, av }

extension AphabScaleInfo on AphabScale {
  String get label => switch (this) {
        AphabScale.ec => 'Ease of Communication',
        AphabScale.bn => 'Background Noise',
        AphabScale.rv => 'Reverberation',
        AphabScale.av => 'Aversiveness',
      };

  String get short => switch (this) {
        AphabScale.ec => 'EC',
        AphabScale.bn => 'BN',
        AphabScale.rv => 'RV',
        AphabScale.av => 'AV',
      };
}

/// One APHAB item: prompt [text], its [scale], and whether the wording is
/// positive so its response is [reversed] before scoring.
class AphabItem {
  const AphabItem(this.text, this.scale, {this.reversed = false});

  final String text;
  final AphabScale scale;
  final bool reversed;
}

/// APHAB — Abbreviated Profile of Hearing Aid Benefit (Cox & Alexander,
/// 1995). 24 items over four 6-item subscales (EC/BN/RV/AV) on the 7-point
/// A–G frequency scale. Subscale score = mean item "percent of problems"
/// (positively-worded items reversed); global = mean of EC+BN+RV.
///
/// Unaided form, self-report — not a diagnosis.
class Aphab {
  const Aphab._();

  /// A–G response labels, most to least frequent.
  static const List<String> responseLabels = <String>[
    'A · Always (99%)',
    'B · Almost always (87%)',
    'C · Generally (75%)',
    'D · Half the time (50%)',
    'E · Occasionally (25%)',
    'F · Seldom (12%)',
    'G · Never (1%)',
  ];

  /// Percent value behind each A–G response.
  static const List<double> responsePercents = <double>[
    99, 87, 75, 50, 25, 12, 1,
  ];

  /// The 24 standard items in published order.
  static const List<AphabItem> items = <AphabItem>[
    AphabItem(
        'When I am in a crowded grocery store, talking with the cashier, I '
        'can follow the conversation.',
        AphabScale.bn,
        reversed: true), // 1
    AphabItem('I miss a lot of information when I\'m listening to a lecture.',
        AphabScale.rv), // 2
    AphabItem(
        'Unexpected sounds, like a smoke detector or alarm bell, are '
        'uncomfortable.',
        AphabScale.av), // 3
    AphabItem(
        'I have difficulty hearing a conversation when I\'m with one of my '
        'family at home.',
        AphabScale.ec), // 4
    AphabItem('I have trouble understanding dialogue in a movie or at a '
        'theater.',
        AphabScale.rv), // 5
    AphabItem(
        'When I am listening to the news on the car radio, and family '
        'members are talking, I have trouble hearing the news.',
        AphabScale.bn), // 6
    AphabItem(
        'When I\'m at the dinner table with several people, and am trying '
        'to have a conversation with one person, understanding speech is '
        'difficult.',
        AphabScale.bn), // 7
    AphabItem('Traffic noises are too loud.', AphabScale.av), // 8
    AphabItem(
        'When I am talking with someone across a large empty room, I '
        'understand the words.',
        AphabScale.rv,
        reversed: true), // 9
    AphabItem(
        'When I am in a small office, interviewing or answering questions, '
        'I have difficulty following the conversation.',
        AphabScale.ec), // 10
    AphabItem(
        'When I am in a theater watching a movie or play, and the people '
        'around me are whispering and rustling paper wrappers, I can still '
        'make out the dialogue.',
        AphabScale.rv,
        reversed: true), // 11
    AphabItem(
        'When I am having a quiet conversation with a friend, I have '
        'difficulty understanding.',
        AphabScale.ec), // 12
    AphabItem(
        'The sounds of running water, such as a toilet or shower, are '
        'uncomfortably loud.',
        AphabScale.av), // 13
    AphabItem(
        'When a speaker is addressing a small group, and everyone is '
        'listening quietly, I have to strain to understand.',
        AphabScale.ec), // 14
    AphabItem(
        'When I\'m in a quiet conversation with my doctor in an examination '
        'room, it is hard to follow the conversation.',
        AphabScale.ec), // 15
    AphabItem('I can understand conversations even when several people are '
        'talking.',
        AphabScale.bn,
        reversed: true), // 16
    AphabItem('The sounds of construction work are uncomfortably loud.',
        AphabScale.av), // 17
    AphabItem(
        'It\'s hard for me to understand what is being said at lectures or '
        'church services.',
        AphabScale.rv), // 18
    AphabItem('I can communicate with others when we are in a crowd.',
        AphabScale.bn,
        reversed: true), // 19
    AphabItem(
        'The sound of a fire engine siren close by is so loud that I need '
        'to cover my ears.',
        AphabScale.av), // 20
    AphabItem(
        'I can follow the words of a sermon when listening to a religious '
        'service.',
        AphabScale.rv,
        reversed: true), // 21
    AphabItem('The sound of screeching tires is uncomfortably loud.',
        AphabScale.av), // 22
    AphabItem(
        'I have to ask people to repeat themselves in one-on-one '
        'conversation in a quiet room.',
        AphabScale.ec), // 23
    AphabItem(
        'I have trouble understanding others when an air conditioner or fan '
        'is on.',
        AphabScale.bn), // 24
  ];

  /// The "percent of problems" for one answered item (reversal applied).
  static double itemProblemPercent(int itemIndex, int responseIndex) {
    final pct = responsePercents[responseIndex];
    return items[itemIndex].reversed ? 100 - pct : pct;
  }

  /// Mean problem percent (0–100) for [scale]. [answers] holds a response
  /// index 0–6 per item (null = unanswered → skipped).
  static double? scaleScore(List<int?> answers, AphabScale scale) {
    final vals = <double>[
      for (var i = 0; i < items.length; i++)
        if (items[i].scale == scale && answers[i] != null)
          itemProblemPercent(i, answers[i]!),
    ];
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Global score: mean of the EC, BN and RV subscales (AV excluded, per the
  /// published scoring).
  static double? globalScore(List<int?> answers) {
    final parts = <double>[
      for (final s in const [AphabScale.ec, AphabScale.bn, AphabScale.rv])
        if (scaleScore(answers, s) != null) scaleScore(answers, s)!,
    ];
    if (parts.length < 3) return null;
    return parts.reduce((a, b) => a + b) / parts.length;
  }
}

/// The APHAB self-report questionnaire page (24 items, A–G scale, subscale +
/// global "percent of problems" scores).
class AphabPage extends StatefulWidget {
  const AphabPage({super.key, this.onCompleted});

  /// Called with the global score when the listener taps "See result".
  final void Function(double? globalScore)? onCompleted;

  @override
  State<AphabPage> createState() => _AphabPageState();
}

class _AphabPageState extends State<AphabPage> {
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  final List<int?> _answers =
      List<int?>.filled(Aphab.items.length, null, growable: false);
  bool _showResult = false;

  int get _answeredCount => _answers.where((a) => a != null).length;

  void _seeResult() {
    setState(() => _showResult = true);
    widget.onCompleted?.call(Aphab.globalScore(_answers));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('APHAB questionnaire'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _introCard(),
                const SizedBox(height: 16),
                for (var i = 0; i < Aphab.items.length; i++) ...[
                  _itemCard(i),
                  const SizedBox(height: 12),
                ],
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
              Icon(Icons.assignment_outlined, color: _primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Abbreviated Profile of Hearing Aid Benefit (unaided)',
                  style: TextStyle(
                      color: _ink, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'For each statement, choose how often it is true of your '
            'everyday listening (A = always … G = never). Answer for how you '
            'hear WITHOUT hearing aids.',
            style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'Self-report questionnaire (Cox & Alexander, 1995) — not a '
            'diagnosis.',
            style: TextStyle(
                color: _muted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(int index) {
    final item = Aphab.items[index];
    final chosen = _answers[index];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                      color: _primary, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.text,
                    style: const TextStyle(
                        color: _ink, fontSize: 14.5, height: 1.35)),
              ),
              const SizedBox(width: 8),
              Text(item.scale.short,
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var r = 0; r < Aphab.responseLabels.length; r++)
                ChoiceChip(
                  key: Key('aphab-$index-$r'),
                  label: Text(
                    Aphab.responseLabels[r].substring(0, 1),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: chosen == r ? Colors.white : _muted),
                  ),
                  tooltip: Aphab.responseLabels[r],
                  selected: chosen == r,
                  selectedColor: _primary,
                  backgroundColor: const Color(0xff1e293b),
                  onSelected: (_) => setState(() => _answers[index] = r),
                ),
            ],
          ),
          if (chosen != null) ...[
            const SizedBox(height: 6),
            Text(Aphab.responseLabels[chosen],
                style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _submitBar() {
    final done = _answeredCount == Aphab.items.length;
    return Column(
      children: [
        if (!done)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$_answeredCount of ${Aphab.items.length} answered',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        FilledButton(
          key: const Key('aphab-see-result'),
          onPressed: done ? _seeResult : null,
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('See result'),
        ),
      ],
    );
  }

  Widget _resultCard() {
    final global = Aphab.globalScore(_answers);
    return Container(
      key: const Key('aphab-result'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(global == null ? '—' : global.toStringAsFixed(0),
                style: const TextStyle(
                    color: _primary,
                    fontSize: 40,
                    fontWeight: FontWeight.w900)),
          ),
          const Center(
            child: Text('Global % of problems (EC+BN+RV)',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          for (final scale in AphabScale.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${scale.label} (${scale.short})',
                      style: const TextStyle(color: _muted)),
                  Text(
                      Aphab.scaleScore(_answers, scale)?.toStringAsFixed(0) ??
                          '—',
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Higher scores mean listening problems occur more often '
            '(Aversiveness: environmental sounds are unpleasant more often). '
            'Unaided norms: typical adults with impaired hearing average '
            '≈ 25–60% on EC/BN/RV. This questionnaire does not diagnose a '
            'hearing or auditory processing disorder.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(global),
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
}
