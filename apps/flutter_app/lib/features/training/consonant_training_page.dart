import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/confusion_matrix.dart';
import '../../core/protocol_engine.dart';
import '../../core/training/consonant_training.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/encouragement.dart';
import '../common/level_progress_map.dart';
import '../common/stimulus_preview.dart';
import '../common/trial_scaffold.dart';
import '../report/confusion_matrix_page.dart';

/// Consonant-recognition training (4 graded levels). Uses the existing
/// generated CV-syllable assets (`assets/stimuli/phonemes/syl_*.wav`,
/// `demo_only` demonstration speech, not validated clinical stimuli).
class ConsonantTrainingPage extends StatefulWidget {
  const ConsonantTrainingPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.startLevel = 1,
    this.maxTrials = 30,
    this.seed = 0,
    this.showPreview = true,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int startLevel;
  final int maxTrials;
  final int seed;
  final bool showPreview;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<ConsonantTrainingPage> createState() => _ConsonantTrainingPageState();
}

enum _Stage { preview, training, results }

class _ConsonantTrainingPageState extends State<ConsonantTrainingPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  late int _level = widget.startLevel;
  late int _maxLevelReached = widget.startLevel;

  late ConsonantTrainingSession _session;
  late ConsonantTrainingGenerator _generator;
  late _Stage _stage = widget.showPreview ? _Stage.preview : _Stage.training;

  ConsonantTrial? _current;
  DateTime? _shownAt;
  bool _played = false;
  bool _isPlaying = false;
  int? _chosen;
  bool? _lastCorrect;
  String? _encouragement;
  Timer? _autoPlayTimer;

  final List<TrialRecord> _records = <TrialRecord>[];
  final ConfusionMatrix _confusion = ConfusionMatrix();
  final Stopwatch _sw = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _startLevel(_level);
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  void _startLevel(int level) {
    _session =
        ConsonantTrainingSession(level: level, maxTrials: widget.maxTrials);
    _generator = ConsonantTrainingGenerator(seed: widget.seed + level);
    _level = level;
    if (level > _maxLevelReached) _maxLevelReached = level;
    if (_stage == _Stage.preview) {
      // Wait for the preview's Start button before drawing the first trial.
      return;
    }
    _stage = _Stage.training;
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next(_level);
      _shownAt = DateTime.now();
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _play() async {
    final trial = _current;
    if (trial == null) return;
    setState(() {
      _played = true;
      _isPlaying = true;
    });
    try {
      final bytes = await _loadAsset(trial.target.assetPath);
      final decoded = decodeWav16(bytes);
      var out = decoded.samples;
      if (trial.inNoise) {
        final noise = whiteNoise(
          seconds: decoded.samples.length / decoded.sampleRate,
          amp: 0.2,
          seed: widget.seed + _session.completedTrials,
          sampleRate: decoded.sampleRate,
        );
        out = mixAtSnr(decoded.samples, noise, trial.snrDb);
      }
      await _audio.playWav(encodeWav16(out, sampleRate: decoded.sampleRate));
    } catch (_) {
      // Missing asset / playback failure must not block the exercise.
    }
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _playPreview(Consonant c) async {
    try {
      final bytes = await _loadAsset(c.assetPath);
      final decoded = decodeWav16(bytes);
      await _audio.playWav(
          encodeWav16(decoded.samples, sampleRate: decoded.sampleRate));
    } catch (_) {}
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosen != null || !_played) return;
    final prior = _session.currentStreak;
    final correct = _session.submit(trial, index);
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final responseLabel = trial.choices[index].label;
    _records.add(TrialRecord(
      target: trial.target.label,
      response: responseLabel,
      correct: correct,
      latencyMs: latency,
      parameters: <String, Object?>{
        'level': _level,
        if (trial.inNoise) 'snr_db': trial.snrDb,
      },
    ));
    _confusion.record(trial.target.label, responseLabel);
    setState(() {
      _chosen = index;
      _lastCorrect = correct;
      _encouragement = Encouragement.forTrial(
        correct: correct,
        streakAfter: _session.currentStreak,
        priorStreak: prior,
        completed: _session.completedTrials,
        total: _session.maxTrials,
      );
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

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.preview:
        return _buildPreview();
      case _Stage.results:
        return _buildResults();
      case _Stage.training:
        return _buildTraining();
    }
  }

  Widget _buildPreview() {
    return StimulusPreview(
      title: 'Consonant sounds — Level $_level',
      subtitle: consonantLevelConfig(_level).description,
      validationNote:
          'Generated Indian-English demonstration syllables (`demo_only`), not '
          'validated clinical stimuli.',
      items: [
        for (final c in kAvailableConsonants)
          StimulusPreviewItem(id: c.id, label: c.label),
      ],
      onPlay: (item) => _playPreview(consonantById(item.id)),
      onStart: () {
        _stage = _Stage.training;
        _nextTrial();
      },
    );
  }

  Widget _buildTraining() {
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cfg = consonantLevelConfig(_level);
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Consonant training',
      subtitle: 'Identification',
      instruction: 'Listen, then tap the syllable you heard.',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      isPlaying: _isPlaying,
      liveResults: _session.results,
      encouragement: _encouragement,
      pills: [
        LevelProgressMap(
          currentLevel: _level - 1,
          totalLevels: kConsonantMaxLevel,
          completedLevels: _level - 1,
        ),
        MetaPill(icon: Icons.forum, text: '${cfg.choiceCount}AFC'),
        if (trial.inNoise)
          MetaPill(
              icon: Icons.graphic_eq,
              text: 'SNR ${trial.snrDb.toStringAsFixed(0)} dB'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: _played ? 'Replay' : 'Play',
          color: _played ? TransportColors.replay : TransportColors.play,
          onTap: !answered ? _play : null,
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
      footer: answered ? _footer(trial) : null,
      child: _choicesArea(trial, answered),
    );
  }

  Widget _choicesArea(ConsonantTrial trial, bool answered) {
    final theme = Theme.of(context);
    final count = trial.choices.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ChoiceLayout(
            count: count,
            itemBuilder: (context, i) => _ChoiceTile(
              label: trial.choices[i].label,
              enabled: _played && !answered,
              state: _choiceState(i, trial),
              onTap: () => _choose(i),
            ),
          ),
        ),
        if (!_played)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Play the sound to enable the choices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  _ChoiceState _choiceState(int index, ConsonantTrial trial) {
    if (_chosen == null) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(ConsonantTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeedbackLine(correct: _lastCorrect!, answer: trial.target.label),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final theme = Theme.of(context);
    final passed = _session.passed;
    final canAdvance = passed && _level < kConsonantMaxLevel;
    return Scaffold(
      appBar: AppBar(title: const Text('Consonant training')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Level $_level results',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            _SummaryRow(
                label: 'Trials completed',
                value: '${_session.completedTrials}'),
            _SummaryRow(label: 'Accuracy', value: '${_session.percent}%'),
            _SummaryRow(label: 'Best streak', value: '${_session.bestStreak}'),
            _SummaryRow(
                label: 'Highest level reached',
                value: '$_maxLevelReached / $kConsonantMaxLevel'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:
                    passed ? const Color(0x2622c55e) : const Color(0x26ef4444),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: passed
                        ? const Color(0x5522c55e)
                        : const Color(0x55ef4444)),
              ),
              child: Text(
                passed
                    ? (canAdvance
                        ? 'Passed! Level ${_level + 1} unlocked. 🎉'
                        : _level >= kConsonantMaxLevel
                            ? 'All levels complete — outstanding! 🏆'
                            : 'Passed! 🎉')
                    : 'Score ≥ 70% to unlock the next level. Keep practising!',
                style: const TextStyle(
                    color: Color(0xffe2e8f0), fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConfusionMatrixPage(
                    matrix: _confusion,
                    title: 'Consonant confusions',
                  ),
                ),
              ),
              icon: const Icon(Icons.grid_on),
              label: const Text('View confusion matrix'),
            ),
            const SizedBox(height: 12),
            if (canAdvance)
              FilledButton(
                onPressed: () => setState(() => _startLevel(_level + 1)),
                child: Text('Start Level ${_level + 1}'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _startLevel(_level)),
              child: const Text('Repeat this level'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
            const SizedBox(height: 12),
            Text(
              'Training exercise — not a diagnosis. Generated demonstration '
              'syllables, not validated clinical stimuli.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff94a3b8)),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChoiceState { neutral, correct, wrong }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final String label;
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
      label: label,
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
          child: Center(
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
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
          Text('The correct answer was: $answer',
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
