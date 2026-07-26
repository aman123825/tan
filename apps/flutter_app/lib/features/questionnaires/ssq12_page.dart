import 'package:flutter/material.dart';

/// Section of the SSQ12 (Speech, Spatial and Qualities of Hearing Scale — short
/// form).
enum Ssq12Section { speech, spatial, qualities }

extension Ssq12SectionInfo on Ssq12Section {
  String get label => switch (this) {
        Ssq12Section.speech => 'Speech',
        Ssq12Section.spatial => 'Spatial',
        Ssq12Section.qualities => 'Qualities',
      };
}

/// One SSQ12 item: its [section] and prompt [text]. Each is rated 0
/// (not at all) to 10 (perfectly).
class Ssq12Item {
  const Ssq12Item(this.section, this.text);
  final Ssq12Section section;
  final String text;
}

/// SSQ12 (short form) items and scoring (simplified from Noble & Gatehouse,
/// 2004; Noble et al., 2013). Higher scores = better self-reported hearing.
///
/// A self-report questionnaire, not a diagnosis.
class Ssq12 {
  const Ssq12._();

  /// Minimum and maximum rating per item.
  static const int minRating = 0;
  static const int maxRating = 10;

  /// The twelve items in order (four Speech, four Spatial, four Qualities).
  static const List<Ssq12Item> items = <Ssq12Item>[
    // Speech
    Ssq12Item(Ssq12Section.speech,
        'You can follow a conversation with several people in a group.'),
    Ssq12Item(Ssq12Section.speech,
        'You can understand someone talking when there is background noise.'),
    Ssq12Item(Ssq12Section.speech,
        'You can recognise which person is speaking when several people talk.'),
    Ssq12Item(Ssq12Section.speech,
        'You can tell when someone is calling you from another room.'),
    // Spatial
    Ssq12Item(Ssq12Section.spatial,
        'You can judge the direction a sound is coming from.'),
    Ssq12Item(Ssq12Section.spatial,
        'You can judge how far away a sound or a talker is.'),
    Ssq12Item(Ssq12Section.spatial,
        'You can locate where a sound is within a room.'),
    Ssq12Item(Ssq12Section.spatial,
        'Sounds seem to come from outside your head rather than inside it.'),
    // Qualities
    Ssq12Item(Ssq12Section.qualities,
        'Sounds you want to hear are clear rather than muffled.'),
    Ssq12Item(Ssq12Section.qualities,
        'Everyday sounds seem natural rather than unnatural.'),
    Ssq12Item(Ssq12Section.qualities,
        'You can listen to someone without effort or concentration.'),
    Ssq12Item(Ssq12Section.qualities,
        'You can separate different sounds happening at the same time.'),
  ];

  /// Mean rating (0–10) for [section] from [answers] (length 12).
  static double sectionMean(List<double> answers, Ssq12Section section) {
    final vals = <double>[
      for (var i = 0; i < items.length; i++)
        if (items[i].section == section) answers[i],
    ];
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Overall mean rating (0–10) across all twelve items.
  static double overallMean(List<double> answers) {
    if (answers.isEmpty) return 0;
    return answers.reduce((a, b) => a + b) / answers.length;
  }
}

/// The SSQ12 self-report questionnaire page (0–10 sliders, three sections,
/// per-section and overall means).
class Ssq12Page extends StatefulWidget {
  const Ssq12Page({super.key, this.onCompleted});

  /// Called with the overall mean when the listener taps "See result".
  final void Function(double overallMean)? onCompleted;

  @override
  State<Ssq12Page> createState() => _Ssq12PageState();
}

class _Ssq12PageState extends State<Ssq12Page> {
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  // Start each item at the mid-point (5).
  final List<double> _answers =
      List<double>.filled(Ssq12.items.length, 5, growable: false);
  bool _showResult = false;

  void _seeResult() {
    setState(() => _showResult = true);
    widget.onCompleted?.call(Ssq12.overallMean(_answers));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('SSQ12 questionnaire'),
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
                for (final section in Ssq12Section.values) ...[
                  _sectionHeader(section),
                  const SizedBox(height: 10),
                  for (var i = 0; i < Ssq12.items.length; i++)
                    if (Ssq12.items[i].section == section) ...[
                      _itemCard(i),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 6),
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
              Icon(Icons.hearing, color: _primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Speech, Spatial and Qualities of Hearing (short form)',
                  style: TextStyle(
                      color: _ink, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Rate each statement from 0 (not at all) to 10 (perfectly), based '
            'on your everyday experience.',
            style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'Self-report questionnaire (Noble & Gatehouse, 2004) — not a '
            'diagnosis.',
            style: TextStyle(
                color: _muted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(Ssq12Section section) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x333b82f6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primary),
          ),
          child: Text(section.label,
              style: const TextStyle(
                  color: Color(0xffbfdbfe),
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ),
      ],
    );
  }

  Widget _itemCard(int index) {
    final item = Ssq12.items[index];
    final value = _answers[index];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.text,
              style: const TextStyle(color: _ink, fontSize: 15, height: 1.35)),
          Row(
            children: [
              const Text('0', style: TextStyle(color: _muted, fontSize: 12)),
              Expanded(
                child: Slider(
                  key: Key('ssq12-slider-$index'),
                  value: value,
                  min: Ssq12.minRating.toDouble(),
                  max: Ssq12.maxRating.toDouble(),
                  divisions: Ssq12.maxRating - Ssq12.minRating,
                  label: value.round().toString(),
                  onChanged: (v) => setState(() => _answers[index] = v),
                ),
              ),
              const Text('10', style: TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(width: 8),
              SizedBox(
                width: 26,
                child: Text('${value.round()}',
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

  Widget _submitBar() {
    return FilledButton(
      key: const Key('ssq12-see-result'),
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
    final overall = Ssq12.overallMean(_answers);
    return Container(
      key: const Key('ssq12-result'),
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
            child: Text(overall.toStringAsFixed(1),
                style: const TextStyle(
                    color: _primary,
                    fontSize: 40,
                    fontWeight: FontWeight.w900)),
          ),
          const Center(
            child: Text('Overall mean (0–10)',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          for (final section in Ssq12Section.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${section.label} mean',
                      style: const TextStyle(color: _muted)),
                  Text(
                      Ssq12.sectionMean(_answers, section).toStringAsFixed(1),
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Higher scores indicate fewer self-reported hearing difficulties. '
            'This questionnaire does not diagnose a hearing or auditory '
            'processing disorder.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(overall),
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
