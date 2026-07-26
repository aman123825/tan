import 'package:flutter/material.dart';

/// TFI-style domain (the eight domains of Meikle et al., 2012).
enum TfiDomain {
  intrusive,
  senseOfControl,
  cognitive,
  sleep,
  auditory,
  relaxation,
  qualityOfLife,
  emotional,
}

extension TfiDomainInfo on TfiDomain {
  String get label => switch (this) {
        TfiDomain.intrusive => 'Intrusiveness',
        TfiDomain.senseOfControl => 'Sense of control',
        TfiDomain.cognitive => 'Cognitive interference',
        TfiDomain.sleep => 'Sleep',
        TfiDomain.auditory => 'Hearing interference',
        TfiDomain.relaxation => 'Relaxation',
        TfiDomain.qualityOfLife => 'Quality of life',
        TfiDomain.emotional => 'Emotional distress',
      };
}

/// One TFI-style item: prompt and domain. Each is rated 0 (not at all /
/// never) to 10 (extremely / always) about the PAST WEEK.
class TfiItem {
  const TfiItem(this.text, this.domain);

  final String text;
  final TfiDomain domain;
}

/// TFI-STYLE tinnitus impact screen.
///
/// The licensed Tinnitus Functional Index (Meikle et al., 2012, © OHSU)
/// cannot be redistributed verbatim, so these 25 items are PARAPHRASED
/// research adaptations covering the same eight domains with the same 0–10
/// response format and 0–100 scoring. Clearly labelled: this is NOT the
/// validated TFI and its scores are not interchangeable with it.
class TfiStyle {
  const TfiStyle._();

  static const List<TfiItem> items = <TfiItem>[
    // Intrusiveness
    TfiItem('What percentage of your awake time did you notice your '
        'tinnitus?', TfiDomain.intrusive),
    TfiItem('How strong or loud did your tinnitus feel?',
        TfiDomain.intrusive),
    TfiItem('How much did your tinnitus force itself into your attention?',
        TfiDomain.intrusive),
    // Sense of control
    TfiItem('How much did you feel unable to do anything about your '
        'tinnitus?', TfiDomain.senseOfControl),
    TfiItem('How easily were you able to put your tinnitus out of your '
        'mind? (0 = very easily, 10 = not at all)',
        TfiDomain.senseOfControl),
    TfiItem('How much did your tinnitus feel out of your control?',
        TfiDomain.senseOfControl),
    // Cognitive
    TfiItem('How much did your tinnitus get in the way of concentrating?',
        TfiDomain.cognitive),
    TfiItem('How much did your tinnitus interfere with clear thinking?',
        TfiDomain.cognitive),
    TfiItem('How much did your tinnitus make it hard to focus on one '
        'task?', TfiDomain.cognitive),
    // Sleep
    TfiItem('How often did your tinnitus make it hard to fall asleep or '
        'stay asleep?', TfiDomain.sleep),
    TfiItem('How often did your tinnitus leave you short of sleep?',
        TfiDomain.sleep),
    TfiItem('How much did your tinnitus stop you sleeping as deeply as '
        'you would like?', TfiDomain.sleep),
    // Auditory
    TfiItem('How much did your tinnitus make it hard to hear speech '
        'clearly?', TfiDomain.auditory),
    TfiItem('How much did your tinnitus make it hard to follow '
        'conversation in a group?', TfiDomain.auditory),
    TfiItem('How much did your tinnitus get in the way of picking out '
        'sounds you wanted to hear?', TfiDomain.auditory),
    // Relaxation
    TfiItem('How much did your tinnitus get in the way of quiet resting?',
        TfiDomain.relaxation),
    TfiItem('How much did your tinnitus make it hard to relax?',
        TfiDomain.relaxation),
    TfiItem('How much did your tinnitus stop you feeling at peace?',
        TfiDomain.relaxation),
    // Quality of life
    TfiItem('How much did your tinnitus get in the way of enjoying social '
        'time?', TfiDomain.qualityOfLife),
    TfiItem('How much did your tinnitus get in the way of hobbies and '
        'things you enjoy?', TfiDomain.qualityOfLife),
    TfiItem('How much did your tinnitus get in the way of work or daily '
        'tasks?', TfiDomain.qualityOfLife),
    TfiItem('How much did your tinnitus reduce your overall enjoyment of '
        'life?', TfiDomain.qualityOfLife),
    // Emotional
    TfiItem('How anxious or worried did your tinnitus make you feel?',
        TfiDomain.emotional),
    TfiItem('How bothered or upset were you because of your tinnitus?',
        TfiDomain.emotional),
    TfiItem('How depressed did your tinnitus make you feel?',
        TfiDomain.emotional),
  ];

  /// Overall score 0–100: mean item rating × 10 (null while incomplete).
  static double? overall(List<double?> answers) {
    var sum = 0.0;
    for (final a in answers) {
      if (a == null) return null;
      sum += a;
    }
    return sum / answers.length * 10;
  }

  /// Domain score 0–100 (partial answers skipped; null when none answered).
  static double? domainScore(List<double?> answers, TfiDomain domain) {
    final vals = <double>[
      for (var i = 0; i < items.length; i++)
        if (items[i].domain == domain && answers[i] != null) answers[i]!,
    ];
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length * 10;
  }
}

/// The TFI-style questionnaire page (25 paraphrased items, 0–10 sliders).
class TfiPage extends StatefulWidget {
  const TfiPage({super.key, this.onCompleted});

  final void Function(double overall)? onCompleted;

  @override
  State<TfiPage> createState() => _TfiPageState();
}

class _TfiPageState extends State<TfiPage> {
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  final List<double?> _answers =
      List<double?>.filled(TfiStyle.items.length, null, growable: false);
  bool _showResult = false;

  int get _answeredCount => _answers.where((a) => a != null).length;

  void _seeResult() {
    final overall = TfiStyle.overall(_answers);
    if (overall == null) return;
    setState(() => _showResult = true);
    widget.onCompleted?.call(overall);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('Tinnitus impact (TFI-style)'),
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
                    border: Border.all(color: const Color(0x66fbbf24)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tinnitus impact screen (TFI-style)',
                          style: TextStyle(
                              color: _ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 8),
                      Text(
                          'Rate each item for the PAST WEEK from 0 (not at '
                          'all) to 10 (extremely).',
                          style: TextStyle(
                              color: _muted, fontSize: 13.5, height: 1.4)),
                      SizedBox(height: 8),
                      Text(
                          'PARAPHRASED research adaptation covering the '
                          'eight TFI domains (cf. Meikle et al., 2012). '
                          'This is NOT the licensed Tinnitus Functional '
                          'Index and scores are not interchangeable with '
                          'it. Not a diagnosis.',
                          style: TextStyle(
                              color: Color(0xfffbbf24),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < TfiStyle.items.length; i++) ...[
                  _itemCard(i),
                  const SizedBox(height: 10),
                ],
                if (_showResult)
                  _resultCard()
                else
                  FilledButton(
                    key: const Key('tfi-see-result'),
                    onPressed: _answeredCount == TfiStyle.items.length
                        ? _seeResult
                        : null,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(_answeredCount == TfiStyle.items.length
                        ? 'See result'
                        : '$_answeredCount of ${TfiStyle.items.length} '
                            'answered'),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(int i) {
    final value = _answers[i];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${i + 1}. ${TfiStyle.items[i].text}',
              style: const TextStyle(
                  color: _ink, fontSize: 14, height: 1.35)),
          Row(
            children: [
              const Text('0', style: TextStyle(color: _muted, fontSize: 12)),
              Expanded(
                child: Slider(
                  key: Key('tfi-slider-$i'),
                  value: value ?? 0,
                  max: 10,
                  divisions: 10,
                  label: (value ?? 0).round().toString(),
                  onChanged: (v) => setState(() => _answers[i] = v),
                ),
              ),
              const Text('10',
                  style: TextStyle(color: _muted, fontSize: 12)),
              SizedBox(
                width: 26,
                child: Text(value == null ? '—' : '${value.round()}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        color: _primary, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultCard() {
    final overall = TfiStyle.overall(_answers)!;
    return Container(
      key: const Key('tfi-result'),
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
            child: Text(overall.toStringAsFixed(0),
                style: const TextStyle(
                    color: _primary,
                    fontSize: 38,
                    fontWeight: FontWeight.w900)),
          ),
          const Center(
            child: Text('Overall impact (0–100, higher = more impact)',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
          const SizedBox(height: 14),
          for (final d in TfiDomain.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(d.label, style: const TextStyle(color: _muted)),
                  Text(
                      TfiStyle.domainScore(_answers, d)?.toStringAsFixed(0) ??
                          '—',
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'A research screen of where tinnitus intrudes most. For the '
            'validated TFI, licensing is via Oregon Health & Science '
            'University. Discuss bothersome tinnitus with a professional.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(overall),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
