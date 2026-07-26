import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/protocol_engine.dart';
import '../../core/training/pitch_ranking.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Pitch-ranking training: hear 3–5 tones in a random order and tap them from
/// LOW → HIGH. Difficulty grows with more, closer-spaced tones. 15 adaptive
/// trials; scoring is the fraction of positions placed correctly.
///
/// Synthesized tones (`demo_only`). Adaptation changes only the tone count and
/// spacing, never master volume.
class PitchRankingPage extends StatefulWidget {
  const PitchRankingPage({
    super.key,
    this.audioPort,
    this.maxTrials = 15,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.onCompleted,
  });

  final AudioPort? audioPort;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<PitchRankingPage> createState() => _PitchRankingPageState();
}

enum _Stage { training, results }

class _PitchRankingPageState extends State<PitchRankingPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late PitchRankingSession _session =
      PitchRankingSession(maxTrials: widget.maxTrials);
  late PitchRankingGenerator _generator =
      PitchRankingGenerator(seed: widget.seed);

  _Stage _stage = _Stage.training;
  PitchRankingTrial? _current;
  DateTime? _shownAt;
  bool _isPlaying = false;
  bool _answered = false;
  double? _lastScore;
  final List<int> _placed = <int>[]; // presentation indices, low→high

  final List<TrialRecord> _records = <TrialRecord>[];
  final Stopwatch _sw = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next(_session.level);
      _shownAt = DateTime.now();
      _answered = false;
      _lastScore = null;
      _placed.clear();
    });
    Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_answered) _playAll();
    });
  }

  Future<void> _playAll() async {
    final trial = _current;
    if (trial == null) return;
    setState(() => _isPlaying = true);
    try {
      final parts = <List<double>>[];
      for (var i = 0; i < trial.freqs.length; i++) {
        if (i > 0) parts.add(silence(0.12));
        parts.add(pitchRankingTone(trial.freqs[i]));
      }
      await _audio.playWav(encodeWav16(concat(parts)));
    } catch (_) {}
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _playTone(int presentationIndex) async {
    final trial = _current;
    if (trial == null) return;
    try {
      await _audio.playWav(encodeWav16(pitchRankingTone(
          trial.freqs[presentationIndex])));
    } catch (_) {}
  }

  void _place(int presentationIndex) {
    if (_answered || _placed.contains(presentationIndex)) return;
    setState(() => _placed.add(presentationIndex));
    _playTone(presentationIndex);
  }

  void _undo() {
    if (_answered || _placed.isEmpty) return;
    setState(() => _placed.removeLast());
  }

  void _clear() {
    if (_answered) return;
    setState(_placed.clear);
  }

  void _submit() {
    final trial = _current;
    if (trial == null || _answered || _placed.length != trial.toneCount) return;
    final score = _session.submit(trial, List<int>.of(_placed));
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    _records.add(TrialRecord(
      target: trial.correctOrder.join('>'),
      response: _placed.join('>'),
      correct: score,
      latencyMs: latency,
      parameters: <String, Object?>{
        'level': trial.level,
        'tones': trial.toneCount,
        'score': _session.scores.isEmpty ? 0 : _session.scores.last,
      },
    ));
    setState(() {
      _answered = true;
      _lastScore = _session.scores.last;
    });
  }

  void _advance() {
    if (_session.isComplete) {
      widget.onCompleted?.call(List<TrialRecord>.of(_records));
      setState(() => _stage = _Stage.results);
    } else {
      _nextTrial();
    }
  }

  void _finishEarly() {
    widget.onCompleted?.call(List<TrialRecord>.of(_records));
    setState(() => _stage = _Stage.results);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) =>
      _stage == _Stage.results ? _buildResults() : _buildTraining();

  Widget _buildTraining() {
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final complete = _placed.length == trial.toneCount;
    return TrialScaffold(
      title: 'Pitch ranking',
      subtitle: 'Order the tones low to high',
      instruction: 'Tap the tones from LOWEST to HIGHEST',
      instructionIcon: Icons.sort,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      isPlaying: _isPlaying,
      liveResults: _session.results,
      showPlaybackControls: true,
      pills: [
        MetaPill(icon: Icons.music_note, text: '${trial.toneCount} tones'),
        MetaPill(
            icon: Icons.straighten,
            text: '${pitchRankingLevelConfig(trial.level)
                .spacingSemitones.toStringAsFixed(0)} st'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play all',
          color: TransportColors.replay,
          onTap: _playAll,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finishEarly,
        ),
      ],
      statusLeft: 'Question ${_session.trialNumber} of ${_session.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sw.elapsed)}',
      onStop: _finishEarly,
      footer: _answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _lastScore! >= 1.0
                      ? 'Perfect ordering! 🎯'
                      : 'Score ${((_lastScore ?? 0) * 100).round()}% — correct '
                          'order: ${_correctOrderLabel(trial)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _lastScore! >= 1.0
                        ? const Color(0xff22c55e)
                        : const Color(0xffe2e8f0),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_session.isComplete ? 'See results' : 'Next'),
                ),
              ],
            )
          : null,
      child: _orderingUi(trial, complete),
    );
  }

  String _correctOrderLabel(PitchRankingTrial trial) =>
      trial.correctOrder.map((i) => 'T${i + 1}').join(' → ');

  Widget _orderingUi(PitchRankingTrial trial, bool complete) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your order (low → high)',
              style: TextStyle(
                  color: Color(0xff94a3b8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var slot = 0; slot < trial.toneCount; slot++) ...[
                if (slot > 0) const SizedBox(width: 8),
                Expanded(child: _slot(slot)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _answered || _placed.isEmpty ? null : _undo,
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _answered || _placed.isEmpty ? null : _clear,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
              ),
            ],
          ),
          const Divider(height: 24),
          const Text('Tap a tone to hear it and add it to the next slot',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff94a3b8), fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < trial.toneCount; i++)
                _toneChip(i, placed: _placed.contains(i)),
            ],
          ),
          const SizedBox(height: 16),
          if (!_answered)
            FilledButton.icon(
              key: const Key('pitch-submit'),
              onPressed: complete ? _submit : null,
              icon: const Icon(Icons.check),
              label: const Text('Submit order'),
            ),
        ],
      ),
    );
  }

  Widget _slot(int slot) {
    final filled = slot < _placed.length;
    final toneIndex = filled ? _placed[slot] : null;
    return GestureDetector(
      onTap: toneIndex == null ? null : () => _playTone(toneIndex),
      child: Container(
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? const Color(0x333b82f6) : const Color(0x11ffffff),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: filled
                  ? const Color(0xff3b82f6)
                  : const Color(0x33ffffff),
              width: filled ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${slot + 1}',
                style: const TextStyle(
                    color: Color(0xff94a3b8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            Text(toneIndex == null ? '—' : 'T${toneIndex + 1}',
                style: const TextStyle(
                    color: Color(0xffe2e8f0),
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _toneChip(int i, {required bool placed}) {
    return Semantics(
      button: true,
      enabled: !placed && !_answered,
      label: 'Tone ${i + 1}',
      child: SizedBox(
        width: 96,
        height: 72,
        child: Material(
          color: placed ? const Color(0xff1e293b) : const Color(0xff293548),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: placed
                    ? const Color(0x22ffffff)
                    : const Color(0x66ffffff)),
          ),
          child: InkWell(
            key: Key('tone-$i'),
            borderRadius: BorderRadius.circular(16),
            onTap: placed || _answered ? null : () => _place(i),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.volume_up,
                      color: placed ? Colors.white24 : const Color(0xff3b82f6)),
                  const SizedBox(height: 4),
                  Text('Tone ${i + 1}',
                      style: TextStyle(
                          color: placed
                              ? Colors.white24
                              : const Color(0xffe2e8f0),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pitch ranking')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Results',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TrainingSummaryRow(
                label: 'Trials completed',
                value: '${_session.completedTrials}'),
            TrainingSummaryRow(
                label: 'Mean position accuracy',
                value: '${_session.percent}%'),
            TrainingSummaryRow(
                label: 'Perfect orderings',
                value: '${_session.fullyCorrectCount}'),
            TrainingSummaryRow(
                label: 'Highest level reached',
                value: '${_session.maxLevelReached + 1} '
                    '/ ${kPitchRankingMaxLevel + 1}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _records.clear();
                  _session = PitchRankingSession(maxTrials: widget.maxTrials);
                  _generator = PitchRankingGenerator(seed: widget.seed);
                  _sw
                    ..reset()
                    ..start();
                  _stage = _Stage.training;
                });
                _nextTrial();
              },
              child: const Text('Train again'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
            const SizedBox(height: 12),
            Text(
              'Training exercise — not a diagnosis. Synthesized tones, not '
              'validated clinical stimuli.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff94a3b8)),
            ),
          ],
        ),
      ),
    );
  }
}
