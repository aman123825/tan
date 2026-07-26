import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/compressed_speech.dart';
import '../catalog/validation_badge.dart';
import '../common/norm_tile.dart';
import '../common/trial_scaffold.dart';
import '../open_set/open_set_page.dart' show kOpenWordPool;

/// Research-only, task-relative interpretation for a time-compressed-speech
/// score (typical ≥ 70% on this task). Illustrative on uncalibrated audio.
NormResult compressedSpeechNorm(double? percent) {
  if (percent == null) return const NormResult.insufficient();
  const cite = 'Time-compressed speech norm ≈ ≥ 70% '
      '(task-relative, illustrative)';
  if (percent >= 85) {
    return const NormResult(NormBand.betterThanTypical,
        '≥ 85% is strong performance on time-compressed speech.', cite);
  }
  if (percent >= 70) {
    return const NormResult(NormBand.withinTypical,
        '≥ 70% is within the typical range for this task.', cite);
  }
  if (percent >= 55) {
    return const NormResult(NormBand.slightlyBelowTypical,
        '55–70% is just below the typical range.', cite);
  }
  return const NormResult(NormBand.belowTypical,
      '< 55% is below the typical time-compressed-speech range.', cite);
}

/// Time-Compressed Speech Test renderer: each word is time-compressed
/// (default 40% → ~60% duration) and presented; the listener types what they
/// heard. Scored as percent correct (typical ≥ 70%).
class CompressedSpeechPage extends StatefulWidget {
  const CompressedSpeechPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'compressed_speech',
    required this.comfortableLevel,
    this.wordPool = kOpenWordPool,
    this.compressionRatio = 0.4,
    this.maxTrials = 25,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final List<String> wordPool;
  final double compressionRatio;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(CompressedSpeechSession session)? onCompleted;

  @override
  State<CompressedSpeechPage> createState() => _CompressedSpeechPageState();
}

class _CompressedSpeechPageState extends State<CompressedSpeechPage> {
  late final CompressedSpeechSession _session = CompressedSpeechSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    compressionRatio: widget.compressionRatio,
    maxTrials: widget.maxTrials,
  );
  late final CompressedSpeechGenerator _generator = CompressedSpeechGenerator(
    pool: widget.wordPool,
    maxTrials: widget.maxTrials,
    seed: widget.seed,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();
  final TextEditingController _input = TextEditingController();

  CompressedSpeechTrial? _current;
  DateTime? _shownAt;
  bool _played = false;
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;
  int _replays = 0;
  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

  int get _levelPercent => (widget.comfortableLevel * 100).round();
  int get _durationPercent => ((1 - widget.compressionRatio) * 100).round();

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
    if (_generator.isComplete) {
      _finish();
      return;
    }
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _played = false;
      _replays = 0;
      _answered = false;
      _lastCorrect = null;
      _input.clear();
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
      final decoded = decodeWav16(
          await _loadAsset('assets/stimuli/speech/word_${trial.word}.wav'));
      final compressed =
          timeCompress(decoded.samples, widget.compressionRatio);
      final wav = encodeWav16(compressed, sampleRate: decoded.sampleRate);
      await _audio.playWav(wav);
    } catch (_) {
      // Asset missing / playback failure must not block the exercise.
    }
  }

  void _submit() {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(trial, _input.text,
        latencyMs: latency, replays: _replays);
    setState(() {
      _answered = true;
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
        appBar: AppBar(title: const Text('Time-compressed speech')),
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
    return TrialScaffold(
      title: 'Time-compressed speech',
      subtitle: 'Rapid speech',
      instruction: 'Listen to the fast word, then type what you heard.',
      enableShortcuts: false,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(icon: Icons.speed, text: '$_durationPercent% duration'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play word',
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _input,
              enabled: _played && !_answered,
              onSubmitted: (_) => _submit(),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'What word did you hear?',
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
                child: Text('Play the word to enable typing.',
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: _current?.word ?? ''),
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
        const SizedBox(height: 14),
        NormTile(compressedSpeechNorm(
            _session.completedTrials == 0 ? null : _session.percent.toDouble())),
        const SizedBox(height: 12),
        Text(
            'Research measurement only — not a diagnosis. Time-compressed '
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
