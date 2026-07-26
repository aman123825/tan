import 'package:flutter/material.dart';

/// Reports the outcome of a single practice trial back to the [PracticeOverlay].
/// [correct] is whether the listener's response was right; [correctAnswer] is
/// an optional human-readable label of the right answer to show in feedback.
typedef PracticeSubmit = void Function({
  required bool correct,
  String? correctAnswer,
});

/// Builds the interactive content for practice trial [trialNumber] (1-based).
/// The builder must call [submit] exactly once when the listener responds.
typedef PracticeTrialBuilder = Widget Function(
  BuildContext context,
  int trialNumber,
  PracticeSubmit submit,
);

/// Wraps any test in a short block of practice trials with immediate feedback.
///
/// It is a plain [StatefulWidget] (not a page) so it can be dropped into an
/// existing flow — typically shown before the real, scored test. It:
///  * shows a "Practice round (X of N)" header,
///  * renders each practice trial via [trialBuilder],
///  * after each response shows correct/incorrect feedback (with the right
///    answer) and a Next button,
///  * after [practiceCount] trials shows "Practice complete! Starting the real
///    test…" and then calls [onComplete].
///
/// Practice is never scored and never affects the locked master volume.
class PracticeOverlay extends StatefulWidget {
  const PracticeOverlay({
    super.key,
    required this.trialBuilder,
    required this.onComplete,
    this.practiceCount = 3,
    this.title = 'Practice',
  });

  final PracticeTrialBuilder trialBuilder;

  /// Called once, after the final practice trial's feedback, to hand control
  /// to the real test.
  final VoidCallback onComplete;

  /// How many practice trials to run before completing. Defaults to 3.
  final int practiceCount;

  /// Short label shown in the header ("<title> round (X of N)").
  final String title;

  @override
  State<PracticeOverlay> createState() => _PracticeOverlayState();
}

class _PracticeOverlayState extends State<PracticeOverlay> {
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);
  static const Color _good = Color(0xff22c55e);
  static const Color _bad = Color(0xffef4444);

  int _trial = 1; // 1-based
  bool _showingFeedback = false;
  bool _lastCorrect = false;
  String? _lastAnswer;
  bool _completed = false;
  bool _completeCalled = false;

  bool get _isLastTrial => _trial >= widget.practiceCount;

  void _submit({required bool correct, String? correctAnswer}) {
    if (_showingFeedback || _completed) return;
    setState(() {
      _showingFeedback = true;
      _lastCorrect = correct;
      _lastAnswer = correctAnswer;
    });
  }

  void _next() {
    if (_isLastTrial) {
      setState(() => _completed = true);
      // Give the "starting the real test" message a beat to be seen, then hand
      // off. Guarded so onComplete fires at most once.
      Future.delayed(const Duration(milliseconds: 1000), _finish);
    } else {
      setState(() {
        _trial += 1;
        _showingFeedback = false;
        _lastAnswer = null;
      });
    }
  }

  void _finish() {
    if (!mounted || _completeCalled) return;
    _completeCalled = true;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 16),
        if (_completed)
          _completionCard()
        else if (_showingFeedback)
          _feedbackCard()
        else
          widget.trialBuilder(context, _trial, _submit),
      ],
    );
  }

  Widget _header() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined, size: 16, color: _primary),
            const SizedBox(width: 8),
            Text(
              '${widget.title} round ($_trial of ${widget.practiceCount})',
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedbackCard() {
    final color = _lastCorrect ? _good : _bad;
    return Container(
      key: const Key('practice-feedback'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Icon(_lastCorrect ? Icons.check_circle : Icons.cancel,
              size: 48, color: color),
          const SizedBox(height: 10),
          Text(
            _lastCorrect ? 'Correct!' : 'Not quite.',
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_lastAnswer != null) ...[
            const SizedBox(height: 8),
            Text(
              _lastCorrect
                  ? 'The answer was: ${_lastAnswer!}'
                  : 'The correct answer was: ${_lastAnswer!}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Practice is not scored.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('practice-next'),
              onPressed: _next,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_isLastTrial ? 'Finish practice' : 'Next practice'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _completionCard() {
    return Container(
      key: const Key('practice-complete'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: const Column(
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: _good),
          SizedBox(height: 12),
          Text(
            'Practice complete! Starting the real test…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3, color: _primary),
          ),
        ],
      ),
    );
  }
}
