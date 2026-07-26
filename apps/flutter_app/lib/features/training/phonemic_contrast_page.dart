import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/phonemic_contrast.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

/// Deterministic "spoken word" placeholder: two short formant-like tone bursts
/// whose pitches are seeded by the word, so the two words of a minimal pair
/// sound distinct. A labelled demonstration proxy — NOT recorded speech and
/// not validated clinical stimuli.
List<double> _wordTone(String word, {int sampleRate = kSampleRate}) {
  final rng = Random(word.hashCode & 0x7fffffff);
  final f1 = 220.0 + rng.nextInt(160); // 220–380 Hz
  final f2 = 700.0 + rng.nextInt(900); // 700–1600 Hz
  final onset = tone(seconds: 0.12, freqHz: f2, amp: 0.18, sampleRate: sampleRate);
  final vowel = tone(seconds: 0.24, freqHz: f1, amp: 0.24, sampleRate: sampleRate);
  return <double>[...onset, ...silence(0.02, sampleRate), ...vowel];
}

/// Phonemic-Contrast training: the listener hears one word of a minimal pair
/// and, in a 2-alternative forced choice, picks which of the pair it was.
/// Contrast difficulty adapts by tier (easier voicing → harder place).
class PhonemicContrastPage extends StatefulWidget {
  const PhonemicContrastPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'phonemic_contrast',
    required this.comfortableLevel,
    this.maxTrials = 30,
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
  final void Function(PhonemicContrastSession session)? onCompleted;

  @override
  State<PhonemicContrastPage> createState() => _PhonemicContrastPageState();
}

class _PhonemicContrastPageState extends State<PhonemicContrastPage> {
  late final PhonemicContrastSession _session = PhonemicContrastSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final PhonemicContrastGenerator _generator =
      PhonemicContrastGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  PhonemicContrastTrial? _current;
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
      _current = _generator.next(_session.currentTier);
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
      await _audio.playWav(encodeWav16(_wordTone(trial.target)));
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
        appBar: AppBar(title: const Text('Phonemic contrast')),
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
    return TrialScaffold(
      title: 'Phonemic contrast',
      subtitle: 'Minimal pairs',
      instruction: 'Listen, then tap the word you heard.',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(icon: Icons.trending_up, text: 'Tier ${_session.currentTier}'),
        MetaPill(icon: Icons.compare_arrows, text: trial.pair.contrast),
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

  Widget _choicesArea(PhonemicContrastTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < trial.choices.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(
                    child: _WordButton(
                      text: trial.choices[i],
                      enabled: _played && !answered,
                      state: _choiceState(i, trial),
                      onTap: () => _choose(i),
                    ),
                  ),
                ],
              ],
            ),
            if (!_played && !answered)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Play the word to enable the choices.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xff94a3b8))),
              ),
          ],
        ),
      ),
    );
  }

  _ChoiceState _choiceState(int index, PhonemicContrastTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(PhonemicContrastTrial trial) {
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
        _SummaryRow(label: 'Accuracy', value: '${_session.percent}%'),
        _SummaryRow(
            label: 'Hardest tier reached',
            value: '${_session.maxTierReached}'),
        const SizedBox(height: 14),
        Text(
            'Training exercise — not a diagnosis. Synthesized demonstration '
            'syllables, not validated clinical stimuli.',
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

class _WordButton extends StatelessWidget {
  const _WordButton({
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
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: border, width: state == _ChoiceState.neutral ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 96,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: enabled || state != _ChoiceState.neutral
                      ? const Color(0xffe2e8f0)
                      : Colors.white38,
                )),
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
