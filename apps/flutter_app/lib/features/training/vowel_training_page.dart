import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/confusion_matrix.dart';
import '../../core/protocol_engine.dart';
import '../../core/training/consonant_training.dart' show TrainingMode;
import '../../core/training/vowel_training.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/encouragement.dart';
import '../common/level_progress_map.dart';
import '../common/stimulus_preview.dart';
import '../common/trial_scaffold.dart';
import '../report/confusion_matrix_page.dart';

/// Vowel-recognition training (5 graded levels). Vowels are additively
/// synthesized from a three-formant table — a labelled demonstration proxy,
/// NOT recorded speech and not validated clinical stimuli.
class VowelTrainingPage extends StatefulWidget {
  const VowelTrainingPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.startLevel = 1,
    this.maxTrials = 25,
    this.seed = 0,
    this.showPreview = true,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int startLevel;
  final int maxTrials;
  final int seed;
  final bool showPreview;
  final String validationStatus;
  final AudioPort? audioPort;

  /// Called with the completed level's trial records (for persistence).
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<VowelTrainingPage> createState() => _VowelTrainingPageState();
}

enum _Stage { preview, training, results }

class _VowelTrainingPageState extends State<VowelTrainingPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late int _level = widget.startLevel;
  late int _maxLevelReached = widget.startLevel;

  late VowelTrainingSession _session;
  late VowelTrainingGenerator _generator;
  late _Stage _stage = widget.showPreview ? _Stage.preview : _Stage.training;

  VowelTrial? _current;
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
    _session = VowelTrainingSession(level: level, maxTrials: widget.maxTrials);
    _generator = VowelTrainingGenerator(seed: widget.seed + level);
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

  List<double> _render(VowelTrial trial) {
    if (trial.isDiscrimination) {
      final parts = <List<double>>[];
      for (var i = 0; i < trial.sequence.length; i++) {
        if (i > 0) parts.add(silence(0.25));
        parts.add(synthesizeVowel(trial.sequence[i]));
      }
      return concat(parts);
    }
    var s = synthesizeVowel(trial.target);
    if (trial.inNoise) {
      final noise = whiteNoise(
        seconds: s.length / kSampleRate,
        amp: 0.2,
        seed: widget.seed + _session.completedTrials,
      );
      s = mixAtSnr(s, noise, trial.snrDb);
    }
    return s;
  }

  Future<void> _play() async {
    final trial = _current;
    if (trial == null) return;
    setState(() {
      _played = true;
      _isPlaying = true;
    });
    try {
      await _audio.playWav(encodeWav16(_render(trial)));
    } catch (_) {
      // Playback failure must not block the exercise.
    }
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _playPreview(Vowel v) async {
    try {
      await _audio.playWav(encodeWav16(synthesizeVowel(v)));
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

    // Record with vowel-word labels so a confusion matrix can be built.
    final responseLabel = trial.isDiscrimination
        ? trial.sequence[index].word
        : trial.choices[index].word;
    _records.add(TrialRecord(
      target: trial.target.word,
      response: responseLabel,
      correct: correct,
      latencyMs: latency,
      parameters: <String, Object?>{
        'level': _level,
        'mode': trial.mode.name,
        if (trial.inNoise) 'snr_db': trial.snrDb,
      },
    ));
    _confusion.record(trial.target.word, responseLabel);

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
      title: 'Vowel sounds — Level $_level',
      subtitle: vowelLevelConfig(_level).description,
      validationNote:
          'Synthesized demonstration vowels (three-formant), not recorded '
          'speech and not validated clinical stimuli.',
      items: [
        for (final v in kVowels)
          StimulusPreviewItem(id: v.id, label: v.word, sublabel: '/${v.ipa}/'),
      ],
      onPlay: (item) => _playPreview(vowelById(item.id)),
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
    final cfg = vowelLevelConfig(_level);
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Vowel training',
      subtitle: cfg.mode == TrainingMode.discrimination
          ? 'Discrimination'
          : 'Identification',
      instruction: trial.isDiscrimination
          ? 'Listen, then tap the sound that was different.'
          : 'Listen, then tap the vowel you heard.',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      isPlaying: _isPlaying,
      liveResults: _session.results,
      encouragement: _encouragement,
      pills: [
        LevelProgressMap(
          currentLevel: _level - 1,
          totalLevels: kVowelMaxLevel,
          completedLevels: _level - 1,
        ),
        MetaPill(
            icon: Icons.stars, text: 'Best reached $_maxLevelReached'),
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

  void _finishEarly() {
    widget.onCompleted?.call(List<TrialRecord>.of(_records));
    setState(() => _stage = _Stage.results);
  }

  Widget _choicesArea(VowelTrial trial, bool answered) {
    final theme = Theme.of(context);
    final int count =
        trial.isDiscrimination ? trial.sequence.length : trial.choices.length;
    final labels = <String>[
      for (var i = 0; i < count; i++)
        trial.isDiscrimination ? 'Sound ${i + 1}' : trial.choices[i].word,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ChoiceLayout(
            count: count,
            itemBuilder: (context, i) => _ChoiceTile(
              label: labels[i],
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

  _ChoiceState _choiceState(int index, VowelTrial trial) {
    if (_chosen == null) return _ChoiceState.neutral;
    final correctIndex = trial.isDiscrimination ? trial.oddIndex : trial.targetIndex;
    if (index == correctIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(VowelTrial trial) {
    final correctIndex = trial.isDiscrimination ? trial.oddIndex : trial.targetIndex;
    final answerText =
        trial.isDiscrimination ? 'Sound ${correctIndex + 1}' : trial.target.word;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeedbackLine(correct: _lastCorrect!, answer: answerText),
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
    final canAdvance = passed && _level < kVowelMaxLevel;
    return Scaffold(
      appBar: AppBar(title: const Text('Vowel training')),
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
                value: '$_maxLevelReached / $kVowelMaxLevel'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: passed ? const Color(0x2622c55e) : const Color(0x26ef4444),
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
                        : _level >= kVowelMaxLevel
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
                    title: 'Vowel confusions',
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
              'Training exercise — not a diagnosis. Synthesized demonstration '
              'vowels, not validated clinical stimuli.',
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
                  fontSize: 20,
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
