import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/audio/voice_variants.dart';
import '../../core/closed_set.dart';
import '../../core/protocol_engine.dart';
import '../catalog/validation_badge.dart';
import '../common/norm_tile.dart';
import '../common/trial_scaffold.dart';

/// Generic closed-set identification renderer: a recorded item plays (optionally
/// in noise — at a fixed SNR, or an adaptive SNR when [snrTrack] is given); the
/// listener chooses it from a closed set. Choices render as text labels, or as
/// color swatches when items carry [ClosedSetItem.swatchArgb].
class ClosedSetPage extends StatefulWidget {
  const ClosedSetPage({
    super.key,
    required this.moduleId,
    required this.groupId,
    required this.comfortableLevel,
    required this.pool,
    required this.title,
    required this.instruction,
    this.choiceCount = 4,
    this.maxTrials = 20,
    this.seed = 0,
    this.snrDb,
    this.snrTrack,
    this.varyVoice = false,
    this.processor,
    this.validationStatus = 'unvalidated',
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final List<ClosedSetItem> pool;
  final String title;
  final String instruction;
  final int choiceCount;
  final int maxTrials;
  final int seed;
  final double? snrDb;

  /// When supplied, the item is presented in noise at an *adaptive* SNR that
  /// tracks correctness (2-down/1-up). This makes the noise the adaptive
  /// variable — recognition difficulty follows the SNR. Master volume is fixed.
  final AdaptiveTrack? snrTrack;

  /// When true, each trial rotates through the four proxy voice variants
  /// (deterministic pitch/rate transposition of the base recording) for
  /// talker variety. Presentation only — never affects scoring.
  final bool varyVoice;

  /// Optional acoustic-environment transform applied to the decoded samples
  /// each trial (e.g. reverb, phone band-pass, café babble mix for the kids
  /// ABC worlds). Runs after the voice variant and before the built-in noise
  /// mix. Must never raise the overall level.
  final List<double> Function(List<double> samples, int trialIndex)? processor;

  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(ClosedSetSession session)? onCompleted;

  @override
  State<ClosedSetPage> createState() => _ClosedSetPageState();
}

class _ClosedSetPageState extends State<ClosedSetPage> {
  late final ClosedSetSession _session = ClosedSetSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    snrDb: widget.snrDb,
    snrTrack: widget.snrTrack,
    maxTrials: widget.maxTrials,
  );
  late final ClosedSetGenerator _generator = ClosedSetGenerator(
    pool: widget.pool,
    choiceCount: widget.choiceCount,
    seed: widget.seed,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  ClosedSetTrial? _current;
  VoiceVariant _voice = kVoiceVariants.first;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  Timer? _autoPlayTimer;
  final List<bool> _results = <bool>[];

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _breadcrumb =>
      widget.snrTrack != null ? 'Recognition in noise' : 'Closed-set recognition';

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
      _voice = widget.varyVoice
          ? voiceForTrial(widget.seed, _session.completedTrials)
          : kVoiceVariants.first;
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
      final bytes = await _loadAsset(trial.target.assetPath);
      final speech = decodeWav16(bytes);
      // Proxy talker variety (presentation only, never scoring).
      var out = applyVoiceVariant(speech.samples, _voice);
      if (widget.processor != null) {
        out = widget.processor!(out, _session.completedTrials);
      }
      final snr = _session.currentSnrDb;
      if (snr != null) {
        final noise = whiteNoise(
          seconds: out.length / speech.sampleRate,
          amp: 0.2,
          seed: widget.seed + _session.completedTrials,
          sampleRate: speech.sampleRate,
        );
        out = mixAtSnr(out, noise, snr);
      }
      await _audio.playWav(encodeWav16(out, sampleRate: speech.sampleRate));
    } catch (_) {
      // Missing asset / playback failure must not block the exercise.
    }
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosen != null) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(
      trial,
      index,
      latencyMs: latency,
      replays: _replays,
    );
    setState(() {
      _chosen = index;
      _lastCorrect = correct;
      _results.add(correct);
    });
    // Show feedback briefly, then auto-advance; Next remains a manual override.
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_finished && _chosen != null) _advance();
    });
  }

  void _advance() {
    _autoAdvanceTimer?.cancel();
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    _autoAdvanceTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final answered = _chosen != null;
    final snr = _session.currentSnrDb;
    return TrialScaffold(
      title: widget.title,
      subtitle: _breadcrumb,
      instruction: widget.instruction,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      liveResults: _results,
      pills: [
        MetaPill(
          icon: widget.snrTrack != null ? Icons.graphic_eq : null,
          text: snr == null
              ? 'Quiet'
              : '${widget.snrTrack != null ? 'Adaptive ' : ''}SNR '
                  '${snr.toStringAsFixed(0)} dB',
        ),
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        if (widget.varyVoice)
          MetaPill(
              icon: Icons.record_voice_over,
              text: '${_voice.label} (proxy)'),
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
      revealedText: answered ? trial.target.label : null,
      onFlagLastTrial: answered
          ? () => setState(() => flagLastTrial(_session.records))
          : null,
      lastTrialFlagged: lastTrialFlagged(_session.records),
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: answered ? _footer(trial) : null,
      child: _choicesArea(trial, answered),
    );
  }

  Widget _choicesArea(ClosedSetTrial trial, bool answered) {
    final theme = Theme.of(context);
    final swatches = trial.choices.any((c) => c.swatchArgb != null);
    final cols = swatches ? 4 : (trial.choices.length <= 4 ? 2 : 3);
    final aspect = swatches ? 1.0 : (cols == 2 ? 2.4 : 1.9);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: GridView.count(
                crossAxisCount: cols,
                childAspectRatio: aspect,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < trial.choices.length; i++)
                    _ChoiceButton(
                      item: trial.choices[i],
                      enabled: _played && !answered,
                      state: _choiceState(i, trial),
                      onTap: () => _choose(i),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!answered && !_played)
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

  Widget _footer(ClosedSetTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: trial.target.label),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  _ChoiceState _choiceState(int index, ClosedSetTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
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
        _SummaryRow(
            label: 'Accuracy', value: '${(_session.accuracy * 100).round()}%'),
        _SummaryRow(
            label: 'Chance-corrected (${widget.choiceCount}AFC)',
            value:
                '${(Norms.chanceCorrected(_session.accuracy, widget.choiceCount) * 100).round()}%'),
        if (widget.snrTrack != null) ...[
          _SummaryRow(
            label: 'Adaptive SNR threshold',
            value: _session.thresholdSnrDb == null
                ? 'not reached (needs more reversals)'
                : '${_session.thresholdSnrDb!.toStringAsFixed(1)}'
                    '${widget.snrTrack!.thresholdSd == null ? '' : ' ± ${widget.snrTrack!.thresholdSd!.toStringAsFixed(1)}'} dB',
          ),
          const SizedBox(height: 14),
          NormTile(Norms.speechSnrDb(_session.thresholdSnrDb)),
        ],
        const SizedBox(height: 12),
        Text(
            'Research measurement only — not a diagnosis. Generated demo '
            'speech, not validated clinical stimuli.',
            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8))),
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
    required this.item,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final ClosedSetItem item;
  final bool enabled;
  final _ChoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = switch (state) {
      _ChoiceState.correct => const Color(0xff22c55e),
      _ChoiceState.wrong => const Color(0xffef4444),
      _ChoiceState.neutral => Colors.transparent,
    };
    final isSwatch = item.swatchArgb != null;
    final Color bg = isSwatch
        ? Color(item.swatchArgb!)
        : (switch (state) {
            _ChoiceState.correct => const Color(0x3322c55e),
            _ChoiceState.wrong => const Color(0x33ef4444),
            _ChoiceState.neutral =>
              const Color(0xff293548),
          });
    return Semantics(
      button: true,
      enabled: enabled,
      label: item.label,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 3),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Center(
            child: isSwatch
                ? const SizedBox.shrink()
                : Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: enabled || state != _ChoiceState.neutral
                          ? const Color(0xffe2e8f0)
                          : Colors.white38,
                    ),
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
          Text('The correct answer was: $answer',
              style: const TextStyle(color: const Color(0xff94a3b8))),
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
          Text(label, style: const TextStyle(color: const Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
