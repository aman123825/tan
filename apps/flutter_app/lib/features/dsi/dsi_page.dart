import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/dsi.dart';
import '../catalog/validation_badge.dart';
import '../common/focus_ring.dart';
import '../common/trial_scaffold.dart';

/// Dichotic Sentence Identification (DSI) renderer.
///
/// A different sentence plays in each ear at once. In free-recall mode the
/// listener taps BOTH sentences from a closed set of six; in directed mode only
/// the cued ear's sentence. Scored per ear with an ear-advantage summary. Wired
/// headphones required. Research demonstration only — synthesised speech-like
/// audio, not validated clinical DSI material.
class DsiPage extends StatefulWidget {
  const DsiPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'dsi',
    required this.comfortableLevel,
    this.mode = DsiMode.freeRecall,
    this.maxTrials = 20,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final DsiMode mode;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final void Function(DsiSession session)? onCompleted;

  @override
  State<DsiPage> createState() => _DsiPageState();
}

class _DsiPageState extends State<DsiPage> {
  late final DsiSession _session = DsiSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    dsiMode: widget.mode,
    maxTrials: widget.maxTrials,
  );
  late final DsiGenerator _generator = DsiGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  DsiTrial? _current;
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

  bool get _isFreeRecall => widget.mode == DsiMode.freeRecall;
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
      final wav = buildDsiStimulus(
        leftSentence: trial.leftSentence,
        rightSentence: trial.rightSentence,
      );
      await _audio.playWav(wav);
    } catch (_) {
      // Playback failure must not block the exercise.
    }
  }

  int get _latencyMs => _shownAt == null
      ? 0
      : DateTime.now().difference(_shownAt!).inMilliseconds;

  void _tap(String sentence) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    if (_isFreeRecall) {
      setState(() {
        if (_selected.contains(sentence)) {
          _selected.remove(sentence);
        } else if (_selected.length < 2) {
          _selected.add(sentence);
        }
      });
      if (_selected.length == 2) {
        final latency = _latencyMs;
        final correct = _session.submitFreeRecall(
            trial, Set<String>.of(_selected), latencyMs: latency);
        setState(() {
          _answered = true;
          _lastCorrect = correct;
          _lastLatency = latency;
        });
      }
    } else {
      final latency = _latencyMs;
      final correct =
          _session.submitDirected(trial, sentence, latencyMs: latency);
      setState(() {
        _selected
          ..clear()
          ..add(sentence);
        _answered = true;
        _lastCorrect = correct;
        _lastLatency = latency;
      });
    }
  }

  void _onDigitKey(int digit) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    if (digit < 1 || digit > trial.choices.length) return;
    _tap(trial.choices[digit - 1]);
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
        appBar: AppBar(title: const Text('Dichotic Sentence Identification')),
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
    final cued = trial.cuedEar.label;
    final instruction = _counting
        ? 'A different sentence plays in each ear.'
        : _isFreeRecall
            ? 'Tap BOTH sentences you heard (keys 1–6).'
            : 'Tap the sentence you heard in your $cued ear (keys 1–6).';
    return TrialScaffold(
      title: 'Dichotic Sentence ID',
      subtitle: 'Dichotic · ${_isFreeRecall ? 'Free recall' : 'Directed'}',
      instruction: instruction,
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
        if (_isFreeRecall)
          const MetaPill(icon: Icons.hearing, text: 'Report: both ears')
        else
          MetaPill(icon: Icons.hearing, text: 'Cued ear: $cued'),
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

  Widget _choicesArea(DsiTrial trial) {
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
                  child: _SentenceButton(
                    number: i + 1,
                    text: trial.choices[i],
                    enabled: _played && !_answered,
                    state: _choiceState(trial.choices[i], trial),
                    onTap: () => _tap(trial.choices[i]),
                  ),
                ),
              ],
              if (!_played && !_answered)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('The sentences will play automatically.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xff94a3b8))),
                ),
              if (_played && !_answered && _isFreeRecall)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                      'Selected: ${_selected.isEmpty ? "—" : _selected.length}/2',
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

  _ChoiceState _choiceState(String sentence, DsiTrial trial) {
    if (!_answered) {
      return _selected.contains(sentence)
          ? _ChoiceState.selected
          : _ChoiceState.neutral;
    }
    if (!_session.showsFeedback) return _ChoiceState.neutral;
    final isTarget = _isFreeRecall
        ? (sentence == trial.leftSentence || sentence == trial.rightSentence)
        : sentence == trial.cuedSentence;
    if (isTarget) return _ChoiceState.correct;
    if (_selected.contains(sentence)) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(DsiTrial trial) {
    final answer = _isFreeRecall
        ? 'L: ${trial.leftSentence} · R: ${trial.rightSentence}'
        : trial.cuedSentence;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback && _lastCorrect != null)
          _FeedbackLine(correct: _lastCorrect!, answer: answer),
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
    final rea = _session.rightEarAdvantage;
    return ListView(
      children: [
        Text('DSI results',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(
            label: 'Overall accuracy',
            value: '${(_session.accuracy * 100).round()}%'),
        _SummaryRow(label: 'Left ear', value: '${_session.leftPercent}%'),
        _SummaryRow(label: 'Right ear', value: '${_session.rightPercent}%'),
        _SummaryRow(
          label: 'Right-ear advantage',
          value: '${rea >= 0 ? '+' : ''}${rea.toStringAsFixed(0)} pts',
        ),
        const SizedBox(height: 14),
        Text(
            'Research demonstration only — not a diagnosis. Sentences are '
            'synthesised speech-like audio (per-ear split preserved), not '
            'validated clinical DSI material.',
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

enum _ChoiceState { neutral, selected, correct, wrong }

class _SentenceButton extends StatelessWidget {
  const _SentenceButton({
    required this.number,
    required this.text,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final int number;
  final String text;
  final bool enabled;
  final _ChoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = const Color(0x33ffffff);
    switch (state) {
      case _ChoiceState.correct:
        bg = const Color(0x3322c55e);
        border = const Color(0xff22c55e);
      case _ChoiceState.wrong:
        bg = const Color(0x33ef4444);
        border = const Color(0xffef4444);
      case _ChoiceState.selected:
        bg = const Color(0x333b82f6);
        border = const Color(0xff3b82f6);
      case _ChoiceState.neutral:
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
              color: border, width: state == _ChoiceState.neutral ? 1 : 2),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled || state != _ChoiceState.neutral
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
            Text(correct ? 'Correct' : 'Not quite'),
          ],
        ),
        const SizedBox(height: 6),
        Text(answer,
            textAlign: TextAlign.center,
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
          Text(label, style: const TextStyle(color: Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
