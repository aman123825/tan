import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/auditory_closure.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/trial_scaffold.dart';

/// Default word pool (all have `assets/stimuli/words/word_<w>.wav`).
const List<String> kClosureWordPool = <String>[
  'bell',
  'ball',
  'bat',
  'bag',
  'pen',
  'pin',
  'cup',
  'cap',
];

/// Auditory-Closure training: a spoken word has its central portion replaced by
/// noise; the listener identifies it from four choices. The masked fraction
/// grows on a correct streak (30% → 60%), never touching master volume.
class ClosureTrainingPage extends StatefulWidget {
  const ClosureTrainingPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'auditory_closure',
    required this.comfortableLevel,
    this.wordPool = kClosureWordPool,
    this.maxTrials = 20,
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
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(AuditoryClosureSession session)? onCompleted;

  @override
  State<ClosureTrainingPage> createState() => _ClosureTrainingPageState();
}

class _ClosureTrainingPageState extends State<ClosureTrainingPage> {
  late final AuditoryClosureSession _session = AuditoryClosureSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final AuditoryClosureGenerator _generator = AuditoryClosureGenerator(
    pool: widget.wordPool,
    seed: widget.seed,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  AuditoryClosureTrial? _current;
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

  /// Auto-play the new trial's masked word after a short delay so the listener
  /// does not have to press Play for every question. A no-op if it was already
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
      final decoded = decodeWav16(
          await _loadAsset('assets/stimuli/words/word_${trial.word}.wav'));
      final masked = maskMiddle(decoded.samples, _session.currentMask);
      await _audio.playWav(encodeWav16(masked, sampleRate: decoded.sampleRate));
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

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Auditory closure')),
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
      title: 'Auditory closure',
      subtitle: 'Fill in the gap',
      instruction: 'Part of the word is hidden by noise. Choose the word.',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(
            icon: Icons.blur_on, text: '${_session.currentMaskPercent}% masked'),
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

  Widget _choicesArea(AuditoryClosureTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ChoiceLayout(
            count: trial.choices.length,
            itemBuilder: (context, i) => _WordButton(
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
            child: Text('Play the word to enable the choices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  _ChoiceState _choiceState(int index, AuditoryClosureTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(AuditoryClosureTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: trial.word),
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
        _SummaryRow(
            label: 'Hardest mask reached',
            value: '${_session.maxMaskPercent}%'),
        const SizedBox(height: 14),
        Text(
            'Training exercise — not a diagnosis. Demonstration speech masked '
            'with noise, not validated clinical stimuli.',
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

class _WordButton extends StatelessWidget {
  const _WordButton({
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
          child: Center(
            child: Text(text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
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
