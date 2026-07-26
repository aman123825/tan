import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/audio/timbre.dart' show sfxStimulus;
import '../../core/training/continuum.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/trial_scaffold.dart';

/// Environmental-to-Speech Continuum training: a five-level ladder from pitch
/// discrimination to speech in heavy noise. The listener must reach 80% at a
/// level to advance; the highest level reached is the outcome. Difficulty on
/// the speech levels is set by SNR, never by master volume.
class ContinuumPage extends StatefulWidget {
  const ContinuumPage({
    super.key,
    this.moduleId = 'learning',
    this.groupId = 'continuum',
    required this.comfortableLevel,
    this.trialsPerLevel = 5,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int trialsPerLevel;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(ContinuumSession session)? onCompleted;

  @override
  State<ContinuumPage> createState() => _ContinuumPageState();
}

class _ContinuumPageState extends State<ContinuumPage> {
  late final ContinuumSession _session = ContinuumSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    trialsPerLevel: widget.trialsPerLevel,
    seed: widget.seed,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  ContinuumTrial? _current;
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
      _current = _session.nextTrial();
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

  Future<Uint8List> _buildWav(ContinuumTrial trial) async {
    switch (trial.kind) {
      case ContinuumTrialKind.toneOddball:
        final parts = <List<double>>[];
        for (var i = 0; i < trial.choices.length; i++) {
          if (i > 0) parts.add(silence(0.25));
          final f = i == trial.targetIndex ? trial.oddFreqHz! : trial.baseFreqHz!;
          parts.add(tone(seconds: 0.4, freqHz: f, amp: 0.24));
        }
        return encodeWav16(concat(parts));
      case ContinuumTrialKind.environment:
        return encodeWav16(sfxStimulus(trial.sfxId!));
      case ContinuumTrialKind.word:
        final decoded = decodeWav16(
            await _loadAsset('assets/stimuli/words/word_${trial.word}.wav'));
        var samples = decoded.samples;
        if (trial.snrDb != null) {
          final noise = whiteNoise(
            seconds: samples.length / decoded.sampleRate,
            amp: 0.3,
            seed: 100 + _session.completedTrials,
          );
          samples = mixAtSnr(samples, noise, trial.snrDb!);
        }
        return encodeWav16(samples, sampleRate: decoded.sampleRate);
    }
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
      await _audio.playWav(await _buildWav(trial));
    } catch (_) {
      // Asset missing / playback failure must not block the exercise.
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

  String _instructionFor(ContinuumTrial trial) {
    switch (trial.kind) {
      case ContinuumTrialKind.toneOddball:
        return 'Three tones play. Which one is different?';
      case ContinuumTrialKind.environment:
        return 'Listen, then choose the sound you heard.';
      case ContinuumTrialKind.word:
        return trial.snrDb == null
            ? 'Listen, then choose the word you heard.'
            : 'Listen through the noise, then choose the word.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Continuum')),
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
      title: 'Continuum · Level ${trial.level}',
      subtitle: 'Sound to speech',
      instruction: _instructionFor(trial),
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(icon: Icons.stairs, text: 'Stage ${trial.level} of $kContinuumMaxLevel'),
        if (trial.snrDb != null)
          MetaPill(
              icon: Icons.graphic_eq,
              text: 'SNR ${trial.snrDb!.toStringAsFixed(0)} dB'),
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
      statusLeft:
          'Stage ${trial.level} · ${_session.levelTrialNumber} of ${widget.trialsPerLevel}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: answered ? _footer(trial) : null,
      child: _choicesArea(trial, answered),
    );
  }

  Widget _choicesArea(ContinuumTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ChoiceLayout(
            count: trial.choices.length,
            itemBuilder: (context, i) => _ChoiceButton(
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
            child: Text('Play the sound to enable the choices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  _ChoiceState _choiceState(int index, ContinuumTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(ContinuumTrial trial) {
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
            label: 'Highest level reached',
            value: '${_session.highestLevel} of $kContinuumMaxLevel'),
        _SummaryRow(
            label: 'Completed all levels',
            value: _session.passedAll ? 'Yes' : 'No'),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(
            label: 'Overall accuracy',
            value: '${(_session.accuracy * 100).round()}%'),
        const SizedBox(height: 14),
        Text(
            'Training exercise — not a diagnosis. Synthesized tones/effects and '
            'demonstration speech, not validated clinical stimuli.',
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

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
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
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(text,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
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
