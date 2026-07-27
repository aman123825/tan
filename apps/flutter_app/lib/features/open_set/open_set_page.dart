import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/asr.dart';
import '../../core/open_set.dart';
import '../../core/word_lists.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

/// Word corpus for open-set recognition (matches the generated speech assets).
const List<String> kOpenWordPool = <String>[
  'bell',
  'ball',
  'bat',
  'bag',
  'pen',
  'pin',
  'cup',
  'cap',
];

/// Typed open-set recognition renderer: the listener hears an item (a word, a
/// sentence, or a runtime-concatenated matrix sentence) and types what they
/// heard; scoring normalizes case/punctuation/whitespace and compares as a
/// whole word or by word accuracy. Optionally presented in noise at a fixed SNR
/// (adapts speech-to-noise ratio, never master volume).
class OpenSetPage extends StatefulWidget {
  const OpenSetPage({
    super.key,
    this.moduleId = 'openset',
    this.groupId = 'open_word',
    required this.comfortableLevel,
    this.itemPool = kOpenWordPool,
    this.itemBuilder,
    this.scoreMode = OpenSetScoreMode.wholeWord,
    this.title = 'Open-word recognition',
    this.instruction = 'Listen, then type the word you heard.',
    this.playNoun = 'word',
    this.maxTrials = 20,
    this.seed = 0,
    this.snrDb,
    this.validationStatus = 'unvalidated',
    this.audioPort,
    this.assetLoader,
    this.asr = const DisabledAsrProvider(),
    this.onCompleted,
    this.poolOptions,
    this.poolLabel,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;

  /// Word pool used by the default (single-word) item source.
  final List<String> itemPool;

  /// Optional per-trial item source. When provided it overrides [itemPool];
  /// used for sentences (single asset) and matrix (concatenated assets).
  final OpenSetItem Function(int trialIndex)? itemBuilder;

  final OpenSetScoreMode scoreMode;
  final String title;
  final String instruction;
  final String playNoun;
  final int maxTrials;
  final int seed;

  /// SNR (dB) if presented in noise; null = quiet.
  final double? snrDb;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;

  /// Optional, correctable speech-to-text assistance (disabled by default).
  final AsrProvider asr;
  final void Function(OpenSetSession session)? onCompleted;

  /// Optional selectable word-list pools (Demo / CNC / NU-6). When provided and
  /// [itemBuilder] is null, an in-page "Word pool" selector is shown; switching
  /// pools restarts the run. When null the fixed [itemPool] is used.
  final List<WordListPool>? poolOptions;

  /// Optional label for the active pool (shown as a pill).
  final String? poolLabel;

  @override
  State<OpenSetPage> createState() => _OpenSetPageState();
}

class _OpenSetPageState extends State<OpenSetPage> {
  late OpenSetSession _session;
  late OpenSetGenerator _generator;
  late List<String> _activePool;
  WordListPool? _selectedPool;
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();
  final TextEditingController _input = TextEditingController();

  OpenSetItem? _current;
  DateTime? _shownAt;
  bool _played = false;
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  static const int _maxReplays = 5;
  int _replays = 0;
  final Stopwatch _sessionSw = Stopwatch()..start();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  void initState() {
    super.initState();
    _selectedPool = (widget.poolOptions != null && widget.poolOptions!.isNotEmpty)
        ? widget.poolOptions!.first
        : null;
    _buildForPool();
    _nextTrial();
  }

  /// (Re)builds the session + generator for the currently-selected pool.
  void _buildForPool() {
    _activePool = _selectedPool?.words ?? widget.itemPool;
    _session = OpenSetSession(
      moduleId: widget.moduleId,
      groupId: _selectedPool?.id ?? widget.groupId,
      scoreMode: widget.scoreMode,
      snrDb: widget.snrDb,
      maxTrials: widget.maxTrials,
    );
    _generator = OpenSetGenerator(_activePool, seed: widget.seed);
  }

  /// Switches the active word pool and restarts the run.
  void _onPoolChanged(WordListPool? pool) {
    if (pool == null || pool.id == _selectedPool?.id) return;
    setState(() {
      _selectedPool = pool;
      _finished = false;
      _buildForPool();
    });
    _nextTrial();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  OpenSetItem _buildItem(int trialIndex) {
    if (widget.itemBuilder != null) return widget.itemBuilder!(trialIndex);
    final word = _generator.next();
    return OpenSetItem(word, <String>['assets/stimuli/speech/word_$word.wav']);
  }

  void _nextTrial() {
    setState(() {
      _current = _buildItem(_session.completedTrials);
      _shownAt = DateTime.now();
      _played = false;
      _replays = 0;
      _answered = false;
      _lastCorrect = null;
      _input.clear();
    });
  }

  Future<void> _play() async {
    final item = _current;
    if (item == null) return;
    setState(() {
      if (_played) {
        _replays++;
      } else {
        _played = true;
      }
    });
    try {
      final parts = <double>[];
      var rate = kSampleRate;
      for (final path in item.assetPaths) {
        final decoded = decodeWav16(await _loadAsset(path));
        rate = decoded.sampleRate;
        parts.addAll(decoded.samples);
      }
      var out = parts;
      final snr = widget.snrDb;
      if (snr != null && parts.isNotEmpty) {
        final noise = whiteNoise(
          seconds: parts.length / rate,
          amp: 0.2,
          seed: widget.seed + _session.completedTrials,
          sampleRate: rate,
        );
        out = mixAtSnr(parts, noise, snr);
      }
      await _audio.playWav(encodeWav16(out, sampleRate: rate));
    } catch (_) {
      // Asset missing/playback failure must not block the exercise.
    }
  }

  Future<void> _speak() async {
    if (!_played || _answered) return;
    final result = await widget.asr.listen();
    if (result != null && mounted) {
      setState(() {
        _input.text = result.transcript;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      });
    }
    // Never auto-submits: the listener reviews/edits, then presses Submit.
  }

  void _submit() {
    final item = _current;
    if (item == null || _answered || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(item.text, _input.text, latencyMs: latency);
    setState(() {
      _answered = true;
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
    return TrialScaffold(
      title: widget.title,
      subtitle: 'Open-set recognition',
      instruction: widget.instruction,
      enableShortcuts: false,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(
          icon: widget.snrDb == null ? null : Icons.graphic_eq,
          text: widget.snrDb == null
              ? 'Quiet'
              : 'SNR ${widget.snrDb!.toStringAsFixed(0)} dB',
        ),
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        if (_selectedPool != null || widget.poolLabel != null)
          MetaPill(
            icon: Icons.list_alt,
            text: 'Pool: ${_selectedPool?.name ?? widget.poolLabel}',
          ),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play ${widget.playNoun}',
          color: TransportColors.play,
          onTap: (!_played && !_answered) ? _play : null,
        ),
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
      footer: _answered ? _footer() : null,
      child: _answerArea(),
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
            if (widget.poolOptions != null &&
                widget.itemBuilder == null &&
                widget.poolOptions!.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Word pool: ',
                      style: TextStyle(color: Color(0xff94a3b8))),
                  DropdownButton<WordListPool>(
                    key: const Key('word-pool-selector'),
                    value: _selectedPool,
                    dropdownColor: const Color(0xff1e293b),
                    items: [
                      for (final p in widget.poolOptions!)
                        DropdownMenuItem<WordListPool>(
                          value: p,
                          child: Text(p.name),
                        ),
                    ],
                    onChanged: _answered ? null : _onPoolChanged,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _input,
              enabled: _played && !_answered,
              onSubmitted: (_) => _submit(),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'What did you hear?',
              ),
            ),
            const SizedBox(height: 16),
            if (!_answered)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.asr.isAvailable) ...[
                    OutlinedButton.icon(
                      onPressed: _played ? _speak : null,
                      icon: const Icon(Icons.mic),
                      label: const Text('Speak'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  FilledButton(
                    onPressed: _played ? _submit : null,
                    child: const Text('Submit'),
                  ),
                ],
              ),
            if (!_played && !_answered)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Play the ${widget.playNoun} to enable typing.',
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
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: _current?.text ?? ''),
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
        _SummaryRow(
            label: 'Word accuracy',
            value: '${(_session.accuracy * 100).round()}%'),
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
