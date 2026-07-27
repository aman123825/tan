import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pattern_synth.dart';
import '../../core/difficulty.dart';
import '../../core/pattern_test.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_flow_timing.dart';
import '../common/trial_scaffold.dart';

/// Duration Pattern Test or Frequency Pattern Test page.
///
/// Synthesizes 3-tone sequences, presents them monaurally (per ear), and
/// collects responses in one of two modes: linguistic labeling (6-choice
/// grid) or the Buffalo/Musiek hummed response — the listener hums the
/// pattern back, the answer is revealed, and the reproduction is scored
/// matched / not matched. Intact humming with poor labeling points to
/// interhemispheric-transfer rather than pattern-perception deficits.
class PatternTestPage extends StatefulWidget {
  const PatternTestPage({
    super.key,
    required this.testType,
    this.trialsPerEar,
    this.difficulty = DifficultyLevel.medium,
    this.responseMode,
    this.seed = 0,
    this.audioPort,
    this.onCompleted,
  });

  /// 'dpt' or 'fpt'.
  final String testType;

  /// Trials per ear. When null, derived from [difficulty] (easy 30 → expert 15).
  final int? trialsPerEar;

  /// Starting difficulty — controls the effective trials per ear when
  /// [trialsPerEar] is not given. Defaults to [DifficultyLevel.medium].
  final DifficultyLevel difficulty;

  /// Fixed response mode; when null the listener chooses on an in-page
  /// selection screen before the first trial.
  final PatternResponseMode? responseMode;

  final int seed;
  final AudioPort? audioPort;
  final void Function(PatternSession session)? onCompleted;

  @override
  State<PatternTestPage> createState() => _PatternTestPageState();
}

class _PatternTestPageState extends State<PatternTestPage> {
  /// Effective trials per ear: explicit override, else the difficulty preset.
  int get _trialsPerEar =>
      widget.trialsPerEar ?? widget.difficulty.config.trialsPerEar;

  PatternResponseMode? _mode;
  PatternSession? _session;
  late final PatternGenerator _generator = PatternGenerator(
    patterns: widget.testType == 'dpt' ? kDptPatterns : kFptPatterns,
    trialsPerEar: _trialsPerEar,
    seed: widget.seed,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  final Stopwatch _sw = Stopwatch()..start();

  PatternTrial? _current;
  bool _played = false;
  String? _chosen;
  bool? _lastCorrect;
  bool _revealed = false; // hum mode: answer shown, awaiting match score
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  int _replays = 0;
  static const int _maxReplays = 3;
  final List<bool> _results = <bool>[];

  bool get _isHum => _mode == PatternResponseMode.humBack;

  List<String> get _choices =>
      widget.testType == 'dpt' ? kDptPatterns : kFptPatterns;

  String get _title => widget.testType == 'dpt'
      ? 'Duration Pattern Test'
      : 'Frequency Pattern Test';

  String get _instruction {
    if (_isHum) {
      return widget.testType == 'dpt'
          ? 'Listen to three tones, hum the long/short rhythm back aloud.'
          : 'Listen to three tones, hum the high/low melody back aloud.';
    }
    return widget.testType == 'dpt'
        ? 'Listen to three tones, then choose the Long/Short pattern.'
        : 'Listen to three tones, then choose the High/Low pattern.';
  }

  @override
  void initState() {
    super.initState();
    if (widget.responseMode != null) _selectMode(widget.responseMode!);
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  void _selectMode(PatternResponseMode mode) {
    final hum = mode == PatternResponseMode.humBack;
    final baseGroup =
        widget.testType == 'dpt' ? 'duration_pattern' : 'frequency_pattern';
    setState(() {
      _mode = mode;
      // Hummed runs persist under their own group id so labeled-response
      // norms are never applied to hummed scores.
      _session = PatternSession(
        moduleId: 'temporal',
        groupId: hum ? '${baseGroup}_hum' : baseGroup,
        testName: widget.testType == 'dpt'
            ? 'Duration Pattern Test${hum ? ' (hummed)' : ''}'
            : 'Frequency Pattern Test${hum ? ' (hummed)' : ''}',
        trialsPerEar: _trialsPerEar,
        responseMode: mode,
      );
    });
    _nextTrial();
  }

  void _nextTrial() {
    if (_generator.isComplete) {
      _finish();
      return;
    }
    setState(() {
      _current = _generator.next();
      _played = false;
      _chosen = null;
      _lastCorrect = null;
      _revealed = false;
      _replays = 0;
    });
    // Short breathing room, then the new pattern auto-plays.
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(kTrialPrePlayDelay, () {
      if (mounted && !_finished && _chosen == null) _play();
    });
  }

  Future<void> _play() async {
    final trial = _current;
    if (trial == null) return;
    setState(() {
      if (_played) _replays++;
      _played = true;
    });
    try {
      final samples = widget.testType == 'dpt'
          ? synthesizeDpt(trial.pattern)
          : synthesizeFpt(trial.pattern);
      final wav = encodeMonauralWav(samples, ear: trial.ear);
      await _audio.playWav(wav);
    } catch (_) {}
  }

  void _choose(String pattern) {
    if (_chosen != null || !_played) return;
    final correct = _session!.submit(_current!, pattern);
    setState(() {
      _chosen = pattern;
      _lastCorrect = correct;
      _results.add(correct);
    });
    // Hands-free flow: a wrong answer re-plays the pattern twice before the
    // next question; a correct answer moves on after a short feedback beat.
    // Next remains a manual override.
    _autoAdvanceTimer?.cancel();
    if (!correct) {
      unawaited(_replayFailThenAdvance());
    } else {
      _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
        if (mounted && !_finished && _chosen != null) _advance();
      });
    }
  }

  /// Wrong-answer sequence: replay the presented pattern twice (the synth is
  /// deterministic per trial), a brief beat, then advance automatically.
  Future<void> _replayFailThenAdvance() async {
    final trial = _current;
    for (var i = 0; i < 2 && trial != null; i++) {
      if (!mounted || _finished) return;
      try {
        final samples = widget.testType == 'dpt'
            ? synthesizeDpt(trial.pattern)
            : synthesizeFpt(trial.pattern);
        await _audio.playWav(encodeMonauralWav(samples, ear: trial.ear));
      } catch (_) {
        break;
      }
    }
    if (!mounted || _finished || _chosen == null) return;
    // Cancellable beat before advancing (a raw Future.delayed would leak a
    // timer past dispose).
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
      if (mounted && !_finished && _chosen != null) _advance();
    });
  }

  /// Hum mode: reveal the answer (and replay it) so the listener can compare
  /// their hummed reproduction against the actual sequence.
  void _reveal() {
    if (_revealed || !_played) return;
    setState(() => _revealed = true);
    _play(); // replay for comparison; counts as a replay
  }

  /// Hum mode: score the revealed trial as matched / not matched.
  void _scoreHum(bool matched) {
    if (!_revealed || _chosen != null) return;
    _session!.submitHum(_current!, matched: matched);
    setState(() {
      _chosen = matched ? 'hum-match' : 'hum-mismatch';
      _lastCorrect = matched;
      _results.add(matched);
    });
    _autoAdvanceTimer?.cancel();
    if (!matched) {
      unawaited(_replayFailThenAdvance());
    } else {
      _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
        if (mounted && !_finished && _chosen != null) _advance();
      });
    }
  }

  void _advance() {
    _autoAdvanceTimer?.cancel();
    if (_session!.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    _autoAdvanceTimer?.cancel();
    setState(() => _finished = true);
    final s = _session;
    if (s != null) widget.onCompleted?.call(s);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _patternLabel(String p) {
    if (widget.testType == 'dpt') {
      return p.split('').map((c) => c == 'L' ? 'Long' : 'Short').join(' – ');
    } else {
      return p.split('').map((c) => c == 'H' ? 'High' : 'Low').join(' – ');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == null) return _modeChooser(context);
    if (_finished) return _buildResults(context);
    final trial = _current;
    if (trial == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final answered = _chosen != null;
    return TrialScaffold(
      title: _title,
      subtitle: 'Temporal ordering',
      instruction: _instruction,
      validationBadge: const ValidationBadge(validationStatus: 'unvalidated'),
      liveResults: _results,
      pills: [
        MetaPill(
          icon: Icons.hearing,
          text: 'Ear: ${trial.ear == "left" ? "LEFT" : "RIGHT"}',
        ),
        MetaPill(
          icon: Icons.tag,
          text: 'Trial ${_session!.trialNumber}/${_session!.totalTrials}',
        ),
        MetaPill(
          icon: _isHum ? Icons.music_note : Icons.signal_cellular_alt,
          text:
              _isHum ? 'Hummed response' : 'Level: ${widget.difficulty.label}',
        ),
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
          'Question ${_session!.trialNumber} of ${_session!.totalTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      footer: answered && !_isHum ? _feedbackFooter() : null,
      child: _isHum ? _humArea(trial, answered) : _choiceGrid(answered),
    );
  }

  /// In-page response-mode chooser (labels vs hum-back) shown before the run.
  Widget _modeChooser(BuildContext context) {
    final theme = Theme.of(context);
    Widget card(IconData icon, String title, String body,
            PatternResponseMode mode, Key key) =>
        Semantics(
          button: true,
          label: title,
          child: Material(
            color: const Color(0x1affffff),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(16),
              onTap: () => _selectMode(mode),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x33ffffff)),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 30, color: const Color(0xff3b82f6)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: Color(0xffe2e8f0),
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(body,
                              style: const TextStyle(
                                  color: Color(0xff94a3b8),
                                  fontSize: 12.5,
                                  height: 1.35)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
                  ],
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('How do you want to respond?',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'The same patterns play either way; only the response '
                'changes. Humming removes the need to name the pattern, so '
                'comparing the two modes is diagnostically informative '
                '(Musiek, Pinheiro & Wilson, 1980).',
                style: TextStyle(
                    color: Color(0xff8b9bb4), fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 18),
              card(
                  Icons.grid_view,
                  'Name the pattern',
                  'Choose the pattern label from six options '
                      '(standard scored mode with norms).',
                  PatternResponseMode.labels,
                  const Key('pattern-mode-labels')),
              const SizedBox(height: 12),
              card(
                  Icons.music_note,
                  'Hum it back',
                  'Hum the pattern aloud, reveal the answer, then score '
                      'whether your hum matched (self- or helper-scored).',
                  PatternResponseMode.humBack,
                  const Key('pattern-mode-hum')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceGrid(bool answered) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 2.2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final p in _choices)
              _PatternButton(
                label: _patternLabel(p),
                enabled: _played && !answered,
                selected: _chosen == p,
                correct: answered && p == _current!.pattern,
                wrong: answered && _chosen == p && p != _current!.pattern,
                onTap: () => _choose(p),
              ),
          ],
        ),
      ),
    );
  }

  /// Hum-back response area: hum aloud → reveal → score the match.
  Widget _humArea(PatternTrial trial, bool answered) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_revealed) ...[
              const Icon(Icons.mic, size: 44, color: Color(0xff8b9bb4)),
              const SizedBox(height: 10),
              const Text(
                'Hum the three tones back aloud, then reveal the answer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xff94a3b8), height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('pattern-hum-reveal'),
                onPressed: _played ? _reveal : null,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('I hummed it — reveal the pattern'),
              ),
            ] else ...[
              Text(
                _patternLabel(trial.pattern),
                key: const Key('pattern-hum-answer'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xffe2e8f0),
                    fontSize: 26,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'The sequence replays for comparison. Did your hum match it?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xff94a3b8), height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('pattern-hum-match'),
                      onPressed: answered ? null : () => _scoreHum(true),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff2e9e5b)),
                      icon: const Icon(Icons.check),
                      label: const Text('Matched'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('pattern-hum-mismatch'),
                      onPressed: answered ? null : () => _scoreHum(false),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffb04545)),
                      icon: const Icon(Icons.close),
                      label: const Text('Didn\'t match'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _feedbackFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _lastCorrect! ? Icons.check_circle : Icons.cancel,
              color: _lastCorrect!
                  ? const Color(0xff22c55e)
                  : const Color(0xffef4444),
            ),
            const SizedBox(width: 8),
            Text(_lastCorrect! ? 'Correct' : 'Not quite',
                style: const TextStyle(color: Color(0xffe2e8f0))),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session!.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session!;
    final rPct = session.rightEarPercent;
    final lPct = session.leftEarPercent;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Session Results',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            _ResultRow(label: 'Right ear', value: '$rPct%'),
            _ResultRow(label: 'Left ear', value: '$lPct%'),
            _ResultRow(
                label: 'Overall',
                value: '${(session.overallAccuracy * 100).round()}%'),
            const SizedBox(height: 16),
            Text('Normative interpretation',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_isHum)
              const Text(
                'Hummed responses are self-/helper-scored and typically '
                'exceed labeled scores — published labeled-response norms '
                'are NOT applied. Compare against a labeled run: intact '
                'humming with poor labeling suggests the patterns were '
                'perceived but not linguistically reported.',
                style: TextStyle(color: Color(0xff94a3b8), height: 1.4),
              )
            else
              Text(
                'Right ear: ${PatternNorms.interpret(test: widget.testType, ageYears: 25, percentCorrect: rPct)}\n'
                'Left ear: ${PatternNorms.interpret(test: widget.testType, ageYears: 25, percentCorrect: lPct)}',
                style: const TextStyle(color: Color(0xff94a3b8)),
              ),
            const SizedBox(height: 8),
            Text(
              _isHum
                  ? 'Hummed-response condition (Musiek, Pinheiro & Wilson, '
                      '1980). This is a research measurement, not a clinical '
                      'diagnosis.'
                  : 'Norms: Musiek (1994). Age-stratified cut-off shown for '
                      '18-50 years. This is a research measurement, not a '
                      'clinical diagnosis.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff8b9bb4)),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(session),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatternButton extends StatelessWidget {
  const _PatternButton({
    required this.label,
    required this.enabled,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = const Color(0x33ffffff);
    if (correct) {
      bg = const Color(0x3322c55e);
      border = const Color(0xff22c55e);
    } else if (wrong) {
      bg = const Color(0x33ef4444);
      border = const Color(0xffef4444);
    }
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: correct || wrong ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: enabled || correct || wrong
                  ? const Color(0xffe2e8f0)
                  : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});
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
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xffe2e8f0))),
        ],
      ),
    );
  }
}
