import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/lisns.dart';
import '../../core/open_set.dart' show scoreResponse, OpenSetScoreMode;
import '../catalog/validation_badge.dart';
import '../common/focus_ring.dart';
import '../common/trial_scaffold.dart';

/// LiSN-S (Listening in Spatialized Noise – Sentences) renderer.
///
/// A target sentence (shipped demonstration audio, centred at 0°) is presented
/// against a competing "story" masker in one of four talker/spatial
/// configurations. The listener types what they heard; the SNR adapts
/// 2-down/1-up per condition to estimate an SRT, and three advantage measures
/// (talker, spatial, total) are derived. Wired headphones required for the
/// ±90° spatial cues. Research demonstration only — not a diagnosis.
class LisnsPage extends StatefulWidget {
  const LisnsPage({
    super.key,
    this.moduleId = 'noise',
    this.groupId = 'lisn_s',
    required this.comfortableLevel,
    this.maxTrialsPerCondition = 5,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int maxTrialsPerCondition;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(LisnsSession session)? onCompleted;

  @override
  State<LisnsPage> createState() => _LisnsPageState();
}

class _LisnsPageState extends State<LisnsPage> {
  late final LisnsSession _session = LisnsSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrialsPerCondition: widget.maxTrialsPerCondition,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();
  final TextEditingController _input = TextEditingController();

  LisnsCondition _condition = LisnsCondition.sameTalker0;
  LisnsSentence? _target;
  DateTime? _shownAt;
  bool _counting = false;
  bool _played = false;
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
    _input.dispose();
    super.dispose();
  }

  void _nextTrial() {
    _countdownFallback?.cancel();
    setState(() {
      _condition = _session.currentCondition;
      _target = kLisnsTargetSentences[
          _session.completedTrials % kLisnsTargetSentences.length];
      _shownAt = null;
      _counting = true;
      _played = false;
      _answered = false;
      _lastCorrect = null;
      _lastLatency = null;
      _replays = 0;
      _input.clear();
    });
    // Fallback in case the countdown ring's callback is missed.
    _countdownFallback = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && !_played) _play();
    });
  }

  Future<void> _play() async {
    final target = _target;
    if (target == null) return;
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
      final decoded = decodeWav16(await _loadAsset(target.assetPath));
      final rate = decoded.sampleRate;
      final masker = lisnsMaskerStory(
        seed: widget.seed + _session.completedTrials,
        seconds: (decoded.samples.length / rate) + 0.5,
        sampleRate: rate,
      );
      final wav = buildLisnsStimulus(
        target: decoded.samples,
        masker: masker,
        condition: _condition,
        snrDb: _session.currentSnrDb(_condition),
        sampleRate: rate,
      );
      await _audio.playWav(wav);
    } catch (_) {
      // Asset missing/playback failure must not block the exercise.
    }
  }

  void _submit() {
    final target = _target;
    if (target == null || _answered || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final score =
        scoreResponse(target.text, _input.text, OpenSetScoreMode.wordAccuracy);
    final correct = _session.submit(
      _condition,
      target: target.text,
      response: _input.text,
      scoreFraction: score,
      latencyMs: latency,
      replays: _replays,
    );
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
        appBar: AppBar(title: const Text('LiSN-S')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    return TrialScaffold(
      title: 'LiSN-S',
      subtitle: 'Spatialized speech-in-noise',
      instruction: _counting
          ? 'Listen for the target sentence (centre), then type it.'
          : 'Type the sentence you heard in the centre.',
      enableShortcuts: false,
      isPlaying: _played && !_answered && !_counting,
      showCountdown: _counting,
      onCountdownComplete: () {
        if (mounted && !_played) _play();
      },
      responseTimeMs: _answered ? _lastLatency : null,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        for (final c in LisnsCondition.values) _condPill(c),
        MetaPill(
          icon: Icons.graphic_eq,
          text: 'SNR ${_session.currentSnrDb(_condition).toStringAsFixed(0)} dB',
        ),
        const MetaPill(icon: Icons.headphones, text: 'Wired headphones'),
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
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
      statusLeft: 'Question ${_session.trialNumber} of ${_session.totalTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: _answered ? _footer() : null,
      child: _answerArea(),
    );
  }

  Widget _condPill(LisnsCondition c) {
    final active = c == _condition;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0x333b82f6) : const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? const Color(0xff3b82f6) : const Color(0x33ffffff),
          width: active ? 2 : 1,
        ),
      ),
      child: Text(
        c.label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: active ? const Color(0xffbfdbfe) : const Color(0xff94a3b8),
        ),
      ),
    );
  }

  Widget _answerArea() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusRing(
              child: TextField(
                controller: _input,
                enabled: _played && !_answered,
                onSubmitted: (_) => _submit(),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Type the target sentence',
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_answered)
              FocusRing(
                child: FilledButton(
                  onPressed: _played ? _submit : null,
                  child: const Text('Submit'),
                ),
              ),
            if (!_played && !_answered)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('The sentence will play automatically.',
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
        if (_session.showsFeedback && _lastCorrect != null)
          _FeedbackLine(correct: _lastCorrect!, answer: _target?.text ?? ''),
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
    String srt(LisnsCondition c) {
      final v = _session.srtFor(c);
      return v == null ? '—' : '${v.toStringAsFixed(1)} dB';
    }

    String adv(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB';

    return ListView(
      children: [
        Text('LiSN-S results',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Text('SRT by condition',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 6),
        for (final c in LisnsCondition.values)
          _SummaryRow(label: c.label, value: srt(c)),
        const Divider(height: 28),
        Text('Advantage measures (higher = more benefit)',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 6),
        _SummaryRow(label: 'Talker advantage', value: adv(_session.talkerAdvantage)),
        _SummaryRow(
            label: 'Spatial advantage', value: adv(_session.spatialAdvantage)),
        _SummaryRow(label: 'Total advantage', value: adv(_session.totalAdvantage)),
        const SizedBox(height: 16),
        Text(
            'Talker advantage = benefit of a different masker voice at 0°. '
            'Spatial advantage = benefit of ±90° separation (same voice). '
            'Total advantage = combined benefit.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 8),
        Text(
            'Research demonstration only — not a diagnosis. Target audio is '
            'generated demo speech and the masker is synthesised; not '
            'validated clinical LiSN-S material. SNR adapts, never volume.',
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
        Text('Target: “$answer”',
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
