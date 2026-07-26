import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/competing_sentences.dart';
import '../catalog/validation_badge.dart';
import '../common/norm_tile.dart';
import '../common/trial_scaffold.dart';

/// Deterministic "speech-like" placeholder for a sentence.
///
/// One amplitude-shaped tone burst per word, with a per-sentence base pitch, so
/// the target and the competing sentence sound clearly different per ear. This
/// is a labelled demonstration proxy — NOT recorded speech and not validated
/// clinical stimuli.
List<double> sentenceSpeechPlaceholder(String sentence,
    {int sampleRate = kSampleRate}) {
  final words = sentence.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final rng = Random(sentence.hashCode & 0x7fffffff);
  final basePitch = 140.0 + rng.nextInt(80); // 140–220 Hz "voice"
  final out = <double>[];
  for (final w in words) {
    final durSec = (0.13 + w.length * 0.02).clamp(0.11, 0.30);
    final f = basePitch * (0.85 + rng.nextDouble() * 0.5);
    final fundamental =
        tone(seconds: durSec, freqHz: f, amp: 0.24, sampleRate: sampleRate);
    final harmonic = tone(
        seconds: durSec, freqHz: f * 2, amp: 0.07, sampleRate: sampleRate);
    for (var j = 0; j < fundamental.length; j++) {
      out.add(fundamental[j] + (j < harmonic.length ? harmonic[j] : 0.0));
    }
    out.addAll(silence(0.05, sampleRate)); // brief inter-word gap
  }
  return out;
}

/// Research-only, task-relative interpretation for competing sentences
/// (typical ≥ 90% per ear). Illustrative on uncalibrated audio; never a
/// diagnosis.
NormResult competingSentencesNorm(double? percent) {
  if (percent == null) return const NormResult.insufficient();
  const cite = 'Competing-sentences norm ≈ ≥ 90%/ear '
      '(cf. Willeford; task-relative, illustrative)';
  if (percent >= 95) {
    return const NormResult(NormBand.betterThanTypical,
        '≥ 95% per ear is at the top of the expected range.', cite);
  }
  if (percent >= 90) {
    return const NormResult(NormBand.withinTypical,
        '≥ 90% per ear is the typical competing-sentences expectation.', cite);
  }
  if (percent >= 80) {
    return const NormResult(NormBand.slightlyBelowTypical,
        '80–90% per ear is just below the typical expectation.', cite);
  }
  return const NormResult(NormBand.belowTypical,
      '< 80% per ear is below the typical competing-sentences range.', cite);
}

/// Competing Sentences Test renderer: a target sentence plays in the cued ear
/// while a different competing sentence plays in the other ear (stereo — wired
/// headphones required). The listener picks the cued-ear sentence from four
/// choices. Scored per ear (typical ≥ 90%/ear).
class CompetingSentencesPage extends StatefulWidget {
  const CompetingSentencesPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'competing_sentences',
    required this.comfortableLevel,
    this.maxTrials = 20,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final void Function(CompetingSentenceSession session)? onCompleted;

  @override
  State<CompetingSentencesPage> createState() => _CompetingSentencesPageState();
}

class _CompetingSentencesPageState extends State<CompetingSentencesPage> {
  late final CompetingSentenceSession _session = CompetingSentenceSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final CompetingSentenceGenerator _generator =
      CompetingSentenceGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  CompetingSentenceTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;

  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosen = null;
      _lastCorrect = null;
    });
  }

  Future<void> _play() async {
    final trial = _current;
    if (trial == null) return;
    setState(() {
      if (_played) {
        _replays++;
      } else {
        _played = true;
      }
    });
    try {
      final targetSamples = sentenceSpeechPlaceholder(trial.target);
      final distractorSamples = sentenceSpeechPlaceholder(trial.distractor);
      final leftIsTarget = trial.targetEar == 'left';
      final wav = encodeWavStereo16(
        leftIsTarget ? targetSamples : distractorSamples,
        leftIsTarget ? distractorSamples : targetSamples,
      );
      await _audio.playWav(wav);
    } catch (_) {
      // Playback failure must not block the exercise.
    }
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosen != null || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, index, latencyMs: latency, replays: _replays);
    setState(() {
      _chosen = index;
      _lastCorrect = correct;
    });
  }

  void _advance() {
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Competing sentences')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final answered = _chosen != null;
    final cued = trial.targetEar == 'left' ? 'LEFT' : 'RIGHT';
    return TrialScaffold(
      title: 'Competing sentences',
      subtitle: 'Dichotic listening',
      instruction:
          'Two sentences play at once. Choose the one you heard in your $cued ear.',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(icon: Icons.hearing, text: 'Cued ear: $cued'),
        const MetaPill(icon: Icons.headphones, text: 'Wired headphones'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play',
          color: TransportColors.play,
          onTap: (!_played && !answered) ? _play : null,
        ),
        TransportAction(
          icon: Icons.replay,
          label: 'Replay ($_replays/$_maxReplays)',
          color: TransportColors.replay,
          onTap:
              (_played && !answered && _replays < _maxReplays) ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: answered ? _footer(trial) : null,
      child: _choicesArea(trial, answered),
    );
  }

  Widget _choicesArea(CompetingSentenceTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < trial.choices.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _SentenceButton(
                text: trial.choices[i],
                enabled: _played && !answered,
                state: _choiceState(i, trial),
                onTap: () => _choose(i),
              ),
            ],
            if (!_played && !answered)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text('Play the sentences to enable the choices.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xff94a3b8))),
              ),
          ],
        )),
      ),
    );
  }

  _ChoiceState _choiceState(int index, CompetingSentenceTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(CompetingSentenceTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: trial.target),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('Session summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(
            label: 'Overall accuracy',
            value: '${(_session.accuracy * 100).round()}%'),
        _SummaryRow(
            label: 'Left ear',
            value: _session.hasEar('left')
                ? '${(_session.leftAccuracy * 100).round()}%'
                : '—'),
        _SummaryRow(
            label: 'Right ear',
            value: _session.hasEar('right')
                ? '${(_session.rightAccuracy * 100).round()}%'
                : '—'),
        const SizedBox(height: 14),
        Text('Left ear (per-ear norm)', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        NormTile(competingSentencesNorm(
            _session.hasEar('left') ? _session.leftAccuracy * 100 : null)),
        const SizedBox(height: 10),
        Text('Right ear (per-ear norm)', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        NormTile(competingSentencesNorm(
            _session.hasEar('right') ? _session.rightAccuracy * 100 : null)),
        const SizedBox(height: 12),
        Text(
            'Research measurement only — not a diagnosis. Sentences are '
            'synthesized demonstration audio, not validated clinical stimuli.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_session),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

enum _ChoiceState { neutral, correct, wrong }

class _SentenceButton extends StatelessWidget {
  const _SentenceButton({
    required this.text,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final String text;
  final bool enabled;
  final _ChoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = const Color(0x33ffffff);
    if (state == _ChoiceState.correct) {
      bg = const Color(0x3322c55e);
      border = const Color(0xff22c55e);
    } else if (state == _ChoiceState.wrong) {
      bg = const Color(0x33ef4444);
      border = const Color(0xffef4444);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: border,
              width: state == _ChoiceState.neutral ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled || state != _ChoiceState.neutral
                            ? const Color(0xffe2e8f0)
                            : Colors.white38,
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.correct, required this.answer});

  final bool correct;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          Text('It was “$answer”',
              style: const TextStyle(color: Color(0xff94a3b8))),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

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
