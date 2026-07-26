import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/hint_sin.dart';
import '../catalog/validation_badge.dart';
import '../common/norm_tile.dart';
import '../common/trial_scaffold.dart';
import '../competing_sentences/competing_sentences_page.dart'
    show sentenceSpeechPlaceholder;

/// Research-only, task-relative interpretation for the sentence reception
/// threshold (SRT-50). Normal-hearing adults reach roughly −2.9 dB SNR
/// (Nilsson et al., 1994); shown as illustrative context on uncalibrated audio.
NormResult hintSrtNorm(double? srtDb) {
  if (srtDb == null) return const NormResult.insufficient();
  const cite = 'HINT SRT ≈ −2.9 dB SNR for normal-hearing adults '
      '(Nilsson, Soli & Sullivan, 1994; task-relative)';
  if (srtDb <= -2.9) {
    return const NormResult(NormBand.betterThanTypical,
        'Understanding sentences at ≤ −2.9 dB SNR meets/exceeds the HINT '
        'normal-adult reference.', cite);
  }
  if (srtDb <= 0) {
    return const NormResult(NormBand.withinTypical,
        'A threshold near 0 dB SNR is close to the normal-adult reference.',
        cite);
  }
  if (srtDb <= 4) {
    return const NormResult(NormBand.slightlyBelowTypical,
        'A more favourable SNR is needed than the normal-adult reference.',
        cite);
  }
  return const NormResult(NormBand.belowTypical,
      'Needing > 4 dB SNR indicates difficulty with sentences in noise.', cite);
}

/// HINT-style adaptive sentence-in-noise renderer: full sentences in babble at
/// an adaptive SNR (start +10 dB, 2 dB step, 2-down/1-up). The listener types
/// what they heard; word-accuracy drives the staircase and the mean of the
/// trailing reversals is reported as SRT-50.
class HintSinPage extends StatefulWidget {
  const HintSinPage({
    super.key,
    this.moduleId = 'noise',
    this.groupId = 'hint_sin',
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
  final void Function(HintSinSession session)? onCompleted;

  @override
  State<HintSinPage> createState() => _HintSinPageState();
}

class _HintSinPageState extends State<HintSinPage> {
  late final HintSinSession _session = HintSinSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final HintSentenceSequencer _sequencer =
      HintSentenceSequencer(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  final TextEditingController _input = TextEditingController();

  String? _current;
  DateTime? _shownAt;
  bool _played = false;
  bool _answered = false;
  double? _lastScore;
  bool _finished = false;
  int _replays = 0;
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
    _input.dispose();
    super.dispose();
  }

  void _nextTrial() {
    setState(() {
      _current = _sequencer.sentenceFor(_session.completedTrials);
      _shownAt = DateTime.now();
      _played = false;
      _replays = 0;
      _answered = false;
      _lastScore = null;
      _input.clear();
    });
  }

  Future<void> _play() async {
    final sentence = _current;
    if (sentence == null) return;
    setState(() {
      if (_played) {
        _replays++;
      } else {
        _played = true;
      }
    });
    try {
      final speech = sentenceSpeechPlaceholder(sentence);
      final babble = whiteNoise(
        seconds: speech.length / kSampleRate,
        amp: 0.2,
        seed: widget.seed + _session.completedTrials + 1,
      );
      final mixed = mixAtSnr(speech, babble, _session.currentSnrDb);
      await _audio.playWav(encodeWav16(mixed));
    } catch (_) {
      // Playback failure must not block the exercise.
    }
  }

  void _submit() {
    final sentence = _current;
    if (sentence == null || _answered || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final score = _session.submit(sentence, _input.text, latencyMs: latency);
    setState(() {
      _answered = true;
      _lastScore = score;
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
        appBar: AppBar(title: const Text('Sentences in noise')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    return TrialScaffold(
      title: 'Sentences in noise',
      subtitle: 'Adaptive HINT-style',
      instruction: 'Listen to the sentence in the noise, then type what you heard.',
      enableShortcuts: false,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(
            icon: Icons.graphic_eq,
            text: 'SNR ${_session.currentSnrDb.toStringAsFixed(0)} dB'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play',
          color: TransportColors.play,
          onTap: (!_played && !_answered) ? _play : null,
        ),
        TransportAction(
          icon: Icons.replay,
          label: 'Replay ($_replays/$_maxReplays)',
          color: TransportColors.replay,
          onTap:
              (_played && !_answered && _replays < _maxReplays) ? _play : null,
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
      footer: _answered ? _footer() : null,
      child: _answerArea(),
    );
  }

  Widget _answerArea() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _input,
              enabled: _played && !_answered,
              onSubmitted: (_) => _submit(),
              minLines: 1,
              maxLines: 3,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Type the whole sentence',
              ),
            ),
            const SizedBox(height: 16),
            if (!_answered)
              FilledButton(
                onPressed: _played ? _submit : null,
                child: const Text('Submit'),
              ),
            if (!_played && !_answered)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Play the sentence to enable typing.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xff94a3b8))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final pct = ((_lastScore ?? 0) * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback) ...[
          Text('You matched $pct% of the words',
              style: const TextStyle(color: Color(0xffe2e8f0))),
          const SizedBox(height: 4),
          Text('It was “${_current ?? ''}”',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff94a3b8))),
        ],
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
    final srt = _session.srtDb;
    final sd = _session.srtSd;
    return ListView(
      children: [
        Text('Session summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Sentences presented',
            value: '${_session.completedTrials}'),
        _SummaryRow(
            label: 'Mean word accuracy',
            value: '${(_session.meanWordAccuracy * 100).round()}%'),
        _SummaryRow(
          label: 'SRT-50 (threshold)',
          value: srt == null
              ? 'not reached'
              : '${srt.toStringAsFixed(1)} dB'
                  '${sd == null ? '' : ' ± ${sd.toStringAsFixed(1)}'}',
        ),
        const SizedBox(height: 14),
        NormTile(hintSrtNorm(srt)),
        const SizedBox(height: 12),
        Text(
            'Research measurement only — not a diagnosis. Synthesized '
            'demonstration sentences in white-noise babble; adaptation moves '
            'the SNR only, never master volume.',
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
