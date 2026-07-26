import 'package:flutter/material.dart';

/// Visual state of a forced-choice tile after an answer.
enum TrainingChoiceState { neutral, correct, wrong }

/// A large tappable answer tile shared by the Tier-2 training pages. Mirrors the
/// look of the other renderers: neutral card, green when correct, red when the
/// chosen answer was wrong.
class TrainingChoiceTile extends StatelessWidget {
  const TrainingChoiceTile({
    super.key,
    required this.label,
    required this.enabled,
    required this.state,
    required this.onTap,
    this.fontSize = 22,
    this.emoji,
  });

  final String label;
  final bool enabled;
  final TrainingChoiceState state;
  final VoidCallback onTap;
  final double fontSize;

  /// Optional large emoji shown above the label.
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = const Color(0x33ffffff);
    if (state == TrainingChoiceState.correct) {
      bg = const Color(0x3322c55e);
      border = const Color(0xff22c55e);
    } else if (state == TrainingChoiceState.wrong) {
      bg = const Color(0x33ef4444);
      border = const Color(0xffef4444);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: border,
              width: state == TrainingChoiceState.neutral ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emoji != null) ...[
                  Text(emoji!, style: const TextStyle(fontSize: 34)),
                  const SizedBox(height: 6),
                ],
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: enabled || state != TrainingChoiceState.neutral
                          ? const Color(0xffe2e8f0)
                          : Colors.white38,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A correct/incorrect feedback line with the correct answer when wrong.
class TrainingFeedbackLine extends StatelessWidget {
  const TrainingFeedbackLine({
    super.key,
    required this.correct,
    required this.answer,
  });

  final bool correct;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(correct ? Icons.check_circle : Icons.cancel,
                color: correct
                    ? const Color(0xff22c55e)
                    : const Color(0xffef4444)),
            const SizedBox(width: 8),
            Text(correct ? 'Correct' : 'Not quite'),
          ],
        ),
        if (!correct) ...[
          const SizedBox(height: 6),
          Text('The answer was: $answer',
              style: const TextStyle(color: Color(0xff94a3b8))),
        ],
      ],
    );
  }
}

/// A label/value row for the training results summary.
class TrainingSummaryRow extends StatelessWidget {
  const TrainingSummaryRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
