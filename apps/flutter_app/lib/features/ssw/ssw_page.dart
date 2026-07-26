import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/ssw.dart';
import '../catalog/validation_badge.dart';
import '../common/focus_ring.dart';
import '../common/trial_scaffold.dart';

/// Staggered Spondaic Word (SSW) renderer.
///
/// Two spondees are presented staggered across the ears (word 1 → right, word 2
/// → left) so the inner syllables overlap, creating the four Buffalo-model
/// conditions (RNC/RC/LC/LNC). The listener taps the TWO words heard from a
/// closed set of six (keyboard 1–6 also works). Wired headphones required.
/// Research demonstration only — synthesised tones stand in for speech.
class SswPage extends StatefulWidget {
  const SswPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'ssw',
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
  final void Function(SswSession session)? onCompleted;

  @override
  State<SswPage> createState() => _SswPageState();
}

class _SswPageState extends State<SswPage> {
  late final SswSession _session = SswSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final SswGenerator _generator = SswGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  SswTrial? _current;
  DateTime? _shownAt;
  bool _counting = false;
  bool _played = false;
  final Set<String> _selected = <String>{};
  bool _answered = false;
  bool? _lastCorrect;
  int? _lastLatency;
  int _replays = 0;
  bool _finished = false;
  Timer? _countdownFallback;

  static const int _maxReplays = 3;
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
    _countdownFallback?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    _countdownFallback?.cancel();
    setState(() {
      _current = _generator.next();
      _shownAt = null;
      _counting = true;
      _played = false;
      _selected.clear();
      _answered = false;
      _lastCorrect = null;
      _lastLatency = null;
      _replays = 0;
    });
    _countdownFallback = Timer(const Duration(milliseconds: 2200), () {
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
        _counting = false;
        _shownAt = DateTime.now();
      }
    });
    try {
      final wav = buildSswStimulus(right: trial.right, left: trial.left);
      await _audio.playWav(wav);
    } catch (_) {
      // Playback failure must not block the exercise.
    }
  }

  void _toggle(String word) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    setState(() {
      if (_selected.contains(word)) {
        _selected.remove(word);
      } else if (_selected.length < 2) {
        _selected.add(word);
      }
    });
    if (_selected.length == 2) _score(trial);
  }

  void _onDigitKey(int digit) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    if (digit < 1 || digit > trial.choices.length) return;
    _toggle(trial.choices[digit - 1]);
  }

  void _score(SswTrial trial) {
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, Set<String>.of(_selected), latencyMs: latency);
    setState(() {
      _answered = true;
      _lastCorrect = correct;
      _lastLatency = latency;
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
    _countdownFallback?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staggered Spondaic Words')),
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
      title: 'Staggered Spondaic Words',
      subtitle: 'Dichotic · Buffalo model',
      instruction: _counting
          ? 'Two words play, staggered across your ears.'
          : 'Tap the TWO words you heard (keys 1–6).',
      isPlaying: _played && !_answered && !_counting,
      showCountdown: _counting,
      onCountdownComplete: () {
        if (mounted && !_played) _play();
      },
      responseTimeMs: _answered ? _lastLatency : null,
      onDigitKey: _onDigitKey,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        const MetaPill(icon: Icons.hearing, text: 'Word 1 → R · Word 2 → L'),
        const MetaPill(icon: Icons.headphones, text: 'Wired headphones'),
      ],
      transport: [
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
      footer: _answered ? _footer(trial) : null,
      child: _choicesArea(trial),
    );
  }

  Widget _choicesArea(SswTrial trial) {
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
                FocusRing(
                  child: _WordButton(
                    number: i + 1,
                    text: trial.choices[i],
                    enabled: _played && !_answered,
                    state: _choiceState(trial.choices[i], trial),
                    onTap: () => _toggle(trial.choices[i]),
                  ),
                ),
              ],
              if (!_played && !_answered)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('The words will play automatically.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xff94a3b8))),
                ),
              if (_played && !_answered)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                      'Selected: ${_selected.isEmpty ? "—" : _selected.join(", ")}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xff94a3b8))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  _WordState _choiceState(String word, SswTrial trial) {
    if (!_answered) {
      return _selected.contains(word) ? _WordState.selected : _WordState.neutral;
    }
    if (!_session.showsFeedback) return _WordState.neutral;
    final isTarget = word == trial.right.word || word == trial.left.word;
    if (isTarget) return _WordState.correct;
    if (_selected.contains(word)) return _WordState.wrong;
    return _WordState.neutral;
  }

  Widget _footer(SswTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback && _lastCorrect != null)
          _FeedbackLine(
            correct: _lastCorrect!,
            answer: '${trial.right.word} (R), ${trial.left.word} (L)',
          ),
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
        Text('SSW results',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(label: 'Overall', value: '${_session.totalPercent}%'),
        const SizedBox(height: 10),
        Text('By condition (Buffalo model)',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 6),
        for (final c in SswCondition.values)
          _SummaryRow(
              label: '${c.label} · ${c.description}',
              value: '${_session.percent(c)}%'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x14ffffff),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x33ffffff)),
          ),
          child: Text(_session.interpret(),
              style: const TextStyle(color: Color(0xffe2e8f0), height: 1.4)),
        ),
        const SizedBox(height: 12),
        Text(
            'Research demonstration only — not a diagnosis. Whole-word closed-'
            'set responses are a simplification of clinical per-syllable SSW '
            'scoring; stimuli are synthesised tones, not validated speech.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff8b9bb4))),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_session),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

enum _WordState { neutral, selected, correct, wrong }

class _WordButton extends StatelessWidget {
  const _WordButton({
    required this.number,
    required this.text,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final int number;
  final String text;
  final bool enabled;
  final _WordState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = const Color(0x33ffffff);
    switch (state) {
      case _WordState.correct:
        bg = const Color(0x3322c55e);
        border = const Color(0xff22c55e);
      case _WordState.wrong:
        bg = const Color(0x33ef4444);
        border = const Color(0xffef4444);
      case _WordState.selected:
        bg = const Color(0x333b82f6);
        border = const Color(0xff3b82f6);
      case _WordState.neutral:
        break;
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$number. $text',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: border, width: state == _WordState.neutral ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Text('$number',
                    style: const TextStyle(
                        color: Color(0xff94a3b8),
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: enabled || state != _WordState.neutral
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
            Text(correct ? 'Both correct' : 'Not quite'),
          ],
        ),
        const SizedBox(height: 6),
        Text('Words: $answer',
            style: const TextStyle(color: Color(0xff94a3b8))),
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
          Expanded(
              child:
                  Text(label, style: const TextStyle(color: Color(0xff94a3b8)))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
