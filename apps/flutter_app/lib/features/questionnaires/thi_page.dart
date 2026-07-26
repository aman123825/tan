import 'package:flutter/material.dart';

/// THI subscale (Functional / Emotional / Catastrophic).
enum ThiScale { functional, emotional, catastrophic }

/// One THI item: prompt and subscale.
class ThiItem {
  const ThiItem(this.text, this.scale);

  final String text;
  final ThiScale scale;
}

/// Tinnitus Handicap Inventory (Newman, Jacobson & Spitzer, 1996).
/// 25 items answered Yes (4) / Sometimes (2) / No (0); total 0–100 with the
/// conventional severity grades (McCombe et al., 2001). Self-report — not a
/// diagnosis.
class Thi {
  const Thi._();

  static const List<String> responses = <String>['Yes', 'Sometimes', 'No'];
  static const List<int> responsePoints = <int>[4, 2, 0];

  static const List<ThiItem> items = <ThiItem>[
    ThiItem('Because of your tinnitus, is it difficult for you to '
        'concentrate?', ThiScale.functional), // 1
    ThiItem('Does the loudness of your tinnitus make it difficult for you '
        'to hear people?', ThiScale.functional), // 2
    ThiItem('Does your tinnitus make you angry?', ThiScale.emotional), // 3
    ThiItem('Does your tinnitus make you feel confused?',
        ThiScale.functional), // 4
    ThiItem('Because of your tinnitus, do you feel desperate?',
        ThiScale.catastrophic), // 5
    ThiItem('Do you complain a great deal about your tinnitus?',
        ThiScale.emotional), // 6
    ThiItem('Because of your tinnitus, do you have trouble falling to '
        'sleep at night?', ThiScale.functional), // 7
    ThiItem('Do you feel as though you cannot escape your tinnitus?',
        ThiScale.catastrophic), // 8
    ThiItem('Does your tinnitus interfere with your ability to enjoy your '
        'social activities (such as going out to dinner, to the movies)?',
        ThiScale.functional), // 9
    ThiItem('Because of your tinnitus, do you feel frustrated?',
        ThiScale.emotional), // 10
    ThiItem('Because of your tinnitus, do you feel that you have a '
        'terrible disease?', ThiScale.catastrophic), // 11
    ThiItem('Does your tinnitus make it difficult for you to enjoy life?',
        ThiScale.functional), // 12
    ThiItem('Does your tinnitus interfere with your job or household '
        'responsibilities?', ThiScale.functional), // 13
    ThiItem('Because of your tinnitus, do you find that you are often '
        'irritable?', ThiScale.emotional), // 14
    ThiItem('Because of your tinnitus, is it difficult for you to read?',
        ThiScale.functional), // 15
    ThiItem('Does your tinnitus make you upset?', ThiScale.emotional), // 16
    ThiItem('Do you feel that your tinnitus problem has placed stress on '
        'your relationships with members of your family and friends?',
        ThiScale.emotional), // 17
    ThiItem('Do you find it difficult to focus your attention away from '
        'your tinnitus and on other things?', ThiScale.functional), // 18
    ThiItem('Do you feel that you have no control over your tinnitus?',
        ThiScale.catastrophic), // 19
    ThiItem('Because of your tinnitus, do you often feel tired?',
        ThiScale.functional), // 20
    ThiItem('Because of your tinnitus, do you feel depressed?',
        ThiScale.emotional), // 21
    ThiItem('Does your tinnitus make you feel anxious?',
        ThiScale.emotional), // 22
    ThiItem('Do you feel that you can no longer cope with your tinnitus?',
        ThiScale.catastrophic), // 23
    ThiItem('Does your tinnitus get worse when you are under stress?',
        ThiScale.functional), // 24
    ThiItem('Does your tinnitus make you feel insecure?',
        ThiScale.emotional), // 25
  ];

  /// Total score 0–100 from response indices (0=Yes, 1=Sometimes, 2=No);
  /// null entries (unanswered) are treated as absent → null total.
  static int? total(List<int?> answers) {
    var sum = 0;
    for (final a in answers) {
      if (a == null) return null;
      sum += responsePoints[a];
    }
    return sum;
  }

  /// Subscale score for [scale] (partial answers skipped).
  static int scaleScore(List<int?> answers, ThiScale scale) {
    var sum = 0;
    for (var i = 0; i < items.length; i++) {
      final a = answers[i];
      if (a != null && items[i].scale == scale) sum += responsePoints[a];
    }
    return sum;
  }

  /// Conventional severity grade (McCombe et al., 2001).
  static String grade(int total) {
    if (total <= 16) return 'Grade 1 — slight';
    if (total <= 36) return 'Grade 2 — mild';
    if (total <= 56) return 'Grade 3 — moderate';
    if (total <= 76) return 'Grade 4 — severe';
    return 'Grade 5 — catastrophic';
  }
}

/// The THI questionnaire page (25 items, Yes/Sometimes/No).
class ThiPage extends StatefulWidget {
  const ThiPage({super.key, this.onCompleted});

  final void Function(int total)? onCompleted;

  @override
  State<ThiPage> createState() => _ThiPageState();
}

class _ThiPageState extends State<ThiPage> {
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  final List<int?> _answers =
      List<int?>.filled(Thi.items.length, null, growable: false);
  bool _showResult = false;

  int get _answeredCount => _answers.where((a) => a != null).length;

  void _seeResult() {
    final total = Thi.total(_answers);
    if (total == null) return;
    setState(() => _showResult = true);
    widget.onCompleted?.call(total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('THI questionnaire'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _glass,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tinnitus Handicap Inventory',
                          style: TextStyle(
                              color: _ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 8),
                      Text(
                          'For each question, answer for how things have '
                          'been recently. Self-report questionnaire '
                          '(Newman, Jacobson & Spitzer, 1996) — not a '
                          'diagnosis.',
                          style: TextStyle(
                              color: _muted, fontSize: 13.5, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < Thi.items.length; i++) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    decoration: BoxDecoration(
                      color: _glass,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${Thi.items[i].text}',
                            style: const TextStyle(
                                color: _ink, fontSize: 14, height: 1.35)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (var r = 0; r < Thi.responses.length; r++)
                              ChoiceChip(
                                key: Key('thi-$i-$r'),
                                label: Text(Thi.responses[r]),
                                selected: _answers[i] == r,
                                selectedColor: _primary,
                                onSelected: (_) =>
                                    setState(() => _answers[i] = r),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_showResult)
                  _resultCard()
                else
                  FilledButton(
                    key: const Key('thi-see-result'),
                    onPressed:
                        _answeredCount == Thi.items.length ? _seeResult : null,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(_answeredCount == Thi.items.length
                        ? 'See result'
                        : '$_answeredCount of ${Thi.items.length} answered'),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultCard() {
    final total = Thi.total(_answers)!;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: _muted)),
              Text(value,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Container(
      key: const Key('thi-result'),
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
            child: Text('$total / 100',
                style: const TextStyle(
                    color: _primary,
                    fontSize: 38,
                    fontWeight: FontWeight.w900)),
          ),
          Center(
            child: Text(Thi.grade(total),
                style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          row('Functional (max 44)',
              '${Thi.scaleScore(_answers, ThiScale.functional)}'),
          row('Emotional (max 36)',
              '${Thi.scaleScore(_answers, ThiScale.emotional)}'),
          row('Catastrophic (max 20)',
              '${Thi.scaleScore(_answers, ThiScale.catastrophic)}'),
          const SizedBox(height: 10),
          const Text(
            'Grades follow McCombe et al. (2001). A high score describes '
            'impact, not disease severity — discuss persistent bothersome '
            'tinnitus with an audiologist or doctor.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(total),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
