import 'package:flutter/material.dart';

/// Fisher's Auditory Problems Checklist (Fisher, 1976).
///
/// 25 listening behaviours a parent/teacher checks when observed. Each
/// checked item subtracts 4 points from 100, so the score is the percent of
/// problem-free behaviours (higher = fewer observed problems). A screening
/// checklist — not a diagnosis.
class FisherChecklist {
  const FisherChecklist._();

  /// The 25 observed-behaviour statements.
  static const List<String> items = <String>[
    'Has a history of hearing loss.',
    'Hears sound but does not understand what is said.',
    'Has a history of ear infections (otitis media).',
    'Does not listen carefully — appears not to pay attention.',
    'Has difficulty following spoken directions.',
    'Does not comprehend many words or verbal concepts for their age.',
    'Frequently misunderstands what is said.',
    'Often asks to have information repeated.',
    'Has poor auditory attention.',
    'Has a short auditory attention span.',
    'Daydreams — attention drifts, seems "not with it".',
    'Is easily distracted by background sound.',
    'Has difficulty with phonics or learning sound–letter links.',
    'Has problems telling similar speech sounds apart.',
    'Cannot associate sounds with what makes them.',
    'Has difficulty telling where a sound comes from.',
    'Has poor memory for spoken sequences (e.g. multi-step requests).',
    'Forgets what is said within a few minutes.',
    'Does not remember simple routine requests from day to day.',
    'Has difficulty recalling what was heard last week or month.',
    'Has problems relating what is heard to what is seen.',
    'Performs better in a small group than in a large group.',
    'Has language problems (grammar, sentence structure).',
    'Has speech problems (articulation).',
    'Says "huh?" or "what?" at least five times a day.',
  ];

  /// Points per unchecked item.
  static const int pointsPerItem = 4;

  /// Score 0–100 from the set of checked (observed) item indices.
  static int score(Set<int> checked) =>
      100 - pointsPerItem * checked.length.clamp(0, items.length);
}

/// Fisher's Auditory Problems Checklist page: tick observed behaviours, see
/// the 0–100 score (100 = no observed problems).
class FisherPage extends StatefulWidget {
  const FisherPage({super.key, this.onCompleted});

  /// Called with the 0–100 score when the observer taps "See result".
  final void Function(int score)? onCompleted;

  @override
  State<FisherPage> createState() => _FisherPageState();
}

class _FisherPageState extends State<FisherPage> {
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  final Set<int> _checked = <int>{};
  bool _showResult = false;

  void _seeResult() {
    setState(() => _showResult = true);
    widget.onCompleted?.call(FisherChecklist.score(_checked));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('Fisher\'s checklist'),
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
                Container(
                  decoration: BoxDecoration(
                    color: _glass,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  // ListTiles need a Material ancestor for their ink.
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (var i = 0;
                            i < FisherChecklist.items.length;
                            i++) ...[
                          CheckboxListTile(
                            key: Key('fisher-$i'),
                            value: _checked.contains(i),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: _primary,
                            title: Text(
                              '${i + 1}. ${FisherChecklist.items[i]}',
                              style: const TextStyle(
                                  color: _ink, fontSize: 14, height: 1.3),
                            ),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _checked.add(i);
                              } else {
                                _checked.remove(i);
                              }
                            }),
                          ),
                          if (i < FisherChecklist.items.length - 1)
                            const Divider(height: 1, color: Color(0x22ffffff)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
              Icon(Icons.checklist_outlined, color: _primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fisher\'s Auditory Problems Checklist',
                  style: TextStyle(
                      color: _ink, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'For a parent or teacher: tick each behaviour you have observed '
            'in the child. Each ticked item lowers the score by 4 points '
            'from 100.',
            style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'Observer screening checklist (Fisher, 1976) — not a diagnosis.',
            style: TextStyle(
                color: _muted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _submitBar() {
    return FilledButton(
      key: const Key('fisher-see-result'),
      onPressed: _seeResult,
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: const Text('See result'),
    );
  }

  Widget _resultCard() {
    final score = FisherChecklist.score(_checked);
    return Container(
      key: const Key('fisher-result'),
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
            child: Text('$score',
                style: const TextStyle(
                    color: _primary,
                    fontSize: 40,
                    fontWeight: FontWeight.w900)),
          ),
          const Center(
            child: Text('Score out of 100',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
                '${_checked.length} of ${FisherChecklist.items.length} '
                'behaviours observed',
                style: const TextStyle(color: _muted, fontSize: 13)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Lower scores mean more observed listening problems. Published '
            'grade-level means vary; interpret the pattern of ticked items '
            'with a professional. This checklist does not diagnose an '
            'auditory processing disorder.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(score),
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
