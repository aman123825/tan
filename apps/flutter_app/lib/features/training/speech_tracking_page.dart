import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/protocol_engine.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Word bank for speech tracking (matches the bundled demo speech assets).
const List<String> kTrackingWords = <String>[
  'bell', 'ball', 'bat', 'bag', 'pen', 'pin', 'cup', 'cap',
];

/// Speech tracking (running dictation): a sequence of spoken words is presented
/// one at a time and the listener types them back. Sequences grow longer and
/// the pace speeds up as tracking succeeds. Score is words-per-minute correctly
/// tracked. Training — not a diagnosis; master volume is never changed.
class SpeechTrackingPage extends StatefulWidget {
  const SpeechTrackingPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.maxTrials = 8,
    this.seed = 0,
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<SpeechTrackingPage> createState() => _SpeechTrackingPageState();
}

class _SpeechTrackingPageState extends State<SpeechTrackingPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();
  late final Random _rng = Random(widget.seed);

  final TextEditingController _input = TextEditingController();
  final Stopwatch _sw = Stopwatch()..start();
  final List<TrialRecord> _records = <TrialRecord>[];

  int _length = 3; // words this trial
  int _gapMs = 700; // adaptive inter-word gap (speed)
  List<String> _sequence = <String>[];
  String? _flashWord;
  bool _presenting = false;
  bool _typingEnabled = false;
  bool _answered = false;
  bool _finished = false;

  int _totalCorrectWords = 0;
  int _lastCorrectWords = 0;
  final Stopwatch _trackClock = Stopwatch();

  @override
  void initState() {
    super.initState();
    _next();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _next() {
    setState(() {
      _sequence = <String>[
        for (var i = 0; i < _length.clamp(2, 8); i++)
          kTrackingWords[_rng.nextInt(kTrackingWords.length)],
      ];
      _input.clear();
      _flashWord = null;
      _presenting = false;
      _typingEnabled = false;
      _answered = false;
    });
  }

  Future<void> _playWord(String w) async {
    try {
      final decoded =
          decodeWav16(await _loadAsset('assets/stimuli/speech/word_$w.wav'));
      await _audio.playWav(encodeWav16(decoded.samples, sampleRate: decoded.sampleRate));
    } catch (_) {
      // No asset → present visually only (still trains tracking).
      await _audio.playWav(encodeWav16(tone(seconds: 0.3, freqHz: 620, amp: 0.18)));
    }
  }

  Future<void> _present() async {
    if (_presenting) return;
    setState(() {
      _presenting = true;
      _typingEnabled = false;
    });
    if (!_trackClock.isRunning) _trackClock.start();
    for (final w in _sequence) {
      if (!mounted || !_presenting) break;
      setState(() => _flashWord = w);
      await _playWord(w);
      await Future<void>.delayed(Duration(milliseconds: _gapMs));
      if (!mounted) return;
      setState(() => _flashWord = null);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!mounted) return;
    setState(() {
      _presenting = false;
      _typingEnabled = true;
    });
  }

  int _scoreWords(List<String> typed) {
    var correct = 0;
    final n = min(typed.length, _sequence.length);
    for (var i = 0; i < n; i++) {
      if (_normalize(typed[i]) == _normalize(_sequence[i])) correct++;
    }
    return correct;
  }

  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  void _submit() {
    if (!_typingEnabled || _answered) return;
    final typed = _input.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final correct = _scoreWords(typed);
    _lastCorrectWords = correct;
    _totalCorrectWords += correct;
    final wordAcc = _sequence.isEmpty ? 0.0 : correct / _sequence.length;
    _records.add(TrialRecord(
      target: _sequence.join(' '),
      response: typed.join(' '),
      correct: wordAcc >= 0.99,
      latencyMs: 0,
      parameters: <String, Object?>{
        'length': _sequence.length,
        'gap_ms': _gapMs,
        'words_correct': correct,
      },
    ));
    // Adapt: succeed → longer + faster; struggle → shorter + slower.
    if (wordAcc >= 0.8) {
      _length = min(8, _length + 1);
      _gapMs = max(150, _gapMs - 100);
    } else {
      _length = max(2, _length - 1);
      _gapMs = min(1200, _gapMs + 100);
    }
    setState(() => _answered = true);
  }

  void _advance() {
    if (_records.length >= widget.maxTrials) {
      _finish();
    } else {
      _next();
    }
  }

  void _finish() {
    if (_finished) return;
    _trackClock.stop();
    setState(() => _finished = true);
    widget.onCompleted?.call(_records);
  }

  double get _wpm {
    final minutes = _trackClock.elapsed.inMilliseconds / 60000.0;
    if (minutes <= 0) return 0;
    return _totalCorrectWords / minutes;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _results(context);
    return TrialScaffold(
      title: 'Speech tracking',
      subtitle: 'Running dictation',
      instruction: _presenting
          ? (_flashWord ?? '· · ·')
          : (_typingEnabled
              ? 'Type the words you heard, in order.'
              : 'Press play to hear ${_sequence.length} words.'),
      instructionIcon: Icons.keyboard_voice_outlined,
      enableShortcuts: false,
      pills: [
        MetaPill(icon: Icons.short_text, text: '${_sequence.length} words'),
        MetaPill(icon: Icons.speed, text: 'Gap ${_gapMs}ms'),
        MetaPill(icon: Icons.lock, text: 'Volume locked'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play words',
          color: TransportColors.play,
          onTap: (!_presenting && !_answered) ? _present : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Sentence ${_records.length + (_answered ? 0 : 1)} '
          'of ${widget.maxTrials}',
      statusRight: 'Time ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      footer: _answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_lastCorrectWords / ${_sequence.length} words correct',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_records.length >= widget.maxTrials
                      ? 'See results'
                      : 'Next'),
                ),
              ],
            )
          : null,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _input,
                enabled: _typingEnabled && !_answered,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Type the words (space between each)',
                ),
              ),
              const SizedBox(height: 12),
              if (_typingEnabled && !_answered)
                FilledButton(onPressed: _submit, child: const Text('Submit')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Speech tracking')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Session summary',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TrainingSummaryRow(
                label: 'Sentences tracked', value: '${_records.length}'),
            TrainingSummaryRow(
                label: 'Words correct', value: '$_totalCorrectWords'),
            TrainingSummaryRow(
                label: 'Tracking rate',
                value: '${_wpm.toStringAsFixed(0)} words/min'),
            const SizedBox(height: 14),
            const Text('Training exercise — not a diagnosis.',
                style: TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
