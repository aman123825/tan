import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/competing_speakers.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/trial_scaffold.dart';

/// Deterministic "speech-like" placeholder for one voice: an amplitude-shaped
/// tone burst per word at a per-voice base pitch. A labelled demonstration
/// proxy — NOT recorded speech and not validated clinical stimuli.
List<double> _voice(
  String sentence, {
  required double basePitch,
  required double amp,
  int sampleRate = kSampleRate,
}) {
  final words = sentence.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final rng = Random(sentence.hashCode & 0x7fffffff);
  final out = <double>[];
  for (final w in words) {
    final durSec = (0.13 + w.length * 0.02).clamp(0.11, 0.30);
    final f = basePitch * (0.85 + rng.nextDouble() * 0.5);
    final fundamental =
        tone(seconds: durSec, freqHz: f, amp: amp, sampleRate: sampleRate);
    final harmonic = tone(
        seconds: durSec, freqHz: f * 2, amp: amp * 0.3, sampleRate: sampleRate);
    for (var j = 0; j < fundamental.length; j++) {
      out.add(fundamental[j] + (j < harmonic.length ? harmonic[j] : 0.0));
    }
    out.addAll(silence(0.05, sampleRate));
  }
  return out;
}

/// Mixes two mono voices into one buffer, peak-limited to avoid clipping.
List<double> _mixVoices(List<double> a, List<double> b) {
  final n = max(a.length, b.length);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    out[i] = (i < a.length ? a[i] : 0.0) + (i < b.length ? b[i] : 0.0);
  }
  var mx = 0.0;
  for (final x in out) {
    final v = x.abs();
    if (v > mx) mx = v;
  }
  if (mx > 0.95) {
    final k = 0.95 / mx;
    for (var i = 0; i < n; i++) {
      out[i] *= k;
    }
  }
  return out;
}

/// Competing Speakers training: two synthesized voices talk at once. The target
/// is the HIGHER-pitched voice; the listener picks the sentence it said from
/// four choices. The between-voice level difference shrinks on a 2-down/1-up
/// staircase (harder), never touching master volume.
class CompetingSpeakersPage extends StatefulWidget {
  const CompetingSpeakersPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'competing_speakers',
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
  final void Function(CompetingSpeakersSession session)? onCompleted;

  @override
  State<CompetingSpeakersPage> createState() => _CompetingSpeakersPageState();
}

class _CompetingSpeakersPageState extends State<CompetingSpeakersPage> {
  late final CompetingSpeakersSession _session = CompetingSpeakersSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final CompetingSpeakersGenerator _generator =
      CompetingSpeakersGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  CompetingSpeakersTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _autoPlayTimer;

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

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
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
    _scheduleAutoPlay();
  }

  /// Auto-play the new trial's audio after a short delay so the listener does
  /// not have to press Play for every question. A no-op if it was already
  /// played; the Play button remains a first-trial fallback.
  void _scheduleAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_played) _play();
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
      final levelDiff = _session.currentLevelDiffDb;
      // Target is the higher-pitched, reference-level voice; the competing
      // voice is quieter by `levelDiff` dB (smaller difference = harder).
      final target = _voice(trial.target, basePitch: 220, amp: 0.24);
      final distractorAmp = 0.24 * pow(10, -levelDiff / 20).toDouble();
      final distractor =
          _voice(trial.distractor, basePitch: 140, amp: distractorAmp);
      final wav = encodeWav16(_mixVoices(target, distractor));
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
        appBar: AppBar(title: const Text('Competing speakers')),
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
      title: 'Competing speakers',
      subtitle: 'Selective attention',
      instruction: 'Two voices speak at once. Choose the sentence the '
          'HIGHER voice said.',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(
            icon: Icons.graphic_eq,
            text: 'Δ ${_session.currentLevelDiffDb.toStringAsFixed(0)} dB'),
        const MetaPill(icon: Icons.record_voice_over, text: 'Higher = target'),
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

  Widget _choicesArea(CompetingSpeakersTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ChoiceLayout(
            count: trial.choices.length,
            maxWidth: 760,
            itemBuilder: (context, i) => _SentenceButton(
              text: trial.choices[i],
              enabled: _played && !answered,
              state: _choiceState(i, trial),
              onTap: () => _choose(i),
            ),
          ),
        ),
        if (!_played && !answered)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Play the voices to enable the choices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  _ChoiceState _choiceState(int index, CompetingSpeakersTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(CompetingSpeakersTrial trial) {
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
            label: 'Accuracy',
            value: '${(_session.accuracy * 100).round()}%'),
        _SummaryRow(
            label: 'Hardest level difference',
            value: _session.minLevelDiffDb == null
                ? '—'
                : '${_session.minLevelDiffDb!.toStringAsFixed(0)} dB'),
        const SizedBox(height: 14),
        Text(
            'Training exercise — not a diagnosis. Voices are synthesized '
            'demonstration audio, not validated clinical stimuli.',
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
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: border, width: state == _ChoiceState.neutral ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(text,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: enabled || state != _ChoiceState.neutral
                        ? const Color(0xffe2e8f0)
                        : Colors.white38,
                  )),
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
          Text('The higher voice said “$answer”',
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
