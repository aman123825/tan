import 'package:flutter/material.dart';

import '../../core/training/following_directions.dart';

/// Maps colour names to display swatches.
const Map<String, Color> kShapeColors = <String, Color>{
  'blue': Color(0xff3b82f6),
  'red': Color(0xffef4444),
  'green': Color(0xff22c55e),
  'yellow': Color(0xfffbbf24),
  'purple': Color(0xff8b5cf6),
  'orange': Color(0xfff97316),
};

/// Following Directions training (HearBuilder-style): the listener is given a
/// multi-step instruction and must tap the referenced shapes, in order. Step
/// count adapts (climbs after two correct, drops after a miss). Visual action
/// task — a custom UI rather than the audio [TrialScaffold].
class FollowingDirectionsPage extends StatefulWidget {
  const FollowingDirectionsPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'following_directions',
    required this.comfortableLevel,
    this.maxTrials = 15,
    this.seed = 0,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final void Function(FollowingDirectionsSession session)? onCompleted;

  @override
  State<FollowingDirectionsPage> createState() =>
      _FollowingDirectionsPageState();
}

class _FollowingDirectionsPageState extends State<FollowingDirectionsPage> {
  late final FollowingDirectionsSession _session = FollowingDirectionsSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final FollowingDirectionsGenerator _generator =
      FollowingDirectionsGenerator(seed: widget.seed);

  FollowingDirectionsTrial? _current;
  final List<int> _tapped = <int>[];
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next(_session.currentLevel);
      _tapped.clear();
      _answered = false;
      _lastCorrect = null;
      _shownAt = DateTime.now();
    });
  }

  void _onTap(int index) {
    final trial = _current;
    if (trial == null || _answered) return;
    if (_tapped.contains(index)) return; // ignore repeats
    setState(() => _tapped.add(index));
    if (_tapped.length >= trial.sequence.length) {
      _evaluate();
    }
  }

  void _evaluate() {
    final trial = _current;
    if (trial == null || _answered) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, List<int>.of(_tapped), latencyMs: latency);
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

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Following directions')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              Text('Session summary',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _SummaryRow(
                  label: 'Trials completed',
                  value: '${_session.completedTrials}'),
              _SummaryRow(
                  label: 'Accuracy',
                  value: '${(_session.accuracy * 100).round()}%'),
              _SummaryRow(
                  label: 'Longest instruction followed',
                  value: '${_session.maxLevelReached} step'
                      '${_session.maxLevelReached == 1 ? '' : 's'}'),
              const SizedBox(height: 14),
              Text('Training exercise — not a diagnosis.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xff94a3b8))),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_session),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Following directions'),
        actions: [
          IconButton(
            tooltip: 'End exercise',
            onPressed: _finish,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _InstructionCard(text: trial.instruction),
            const SizedBox(height: 12),
            Text(
              _answered
                  ? 'Green numbers show the correct order.'
                  : 'Tapped ${_tapped.length} of ${trial.sequence.length}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff94a3b8)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < trial.grid.length; i++)
                        _ShapeTile(
                          shape: trial.grid[i],
                          tapOrder: _tapOrderFor(i),
                          correctOrder: _correctOrderFor(trial, i),
                          answered: _answered,
                          onTap: () => _onTap(i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_answered) ...[
              _FeedbackLine(correct: _lastCorrect ?? false),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _advance,
                child: Text(_session.isComplete ? 'See results' : 'Next'),
              ),
            ] else
              Text('Question ${_session.trialNumber} of ${widget.maxTrials}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: const Color(0xff94a3b8))),
          ],
        ),
      ),
    );
  }

  /// 1-based order this tile was tapped in (0 if not tapped).
  int _tapOrderFor(int index) {
    final i = _tapped.indexOf(index);
    return i < 0 ? 0 : i + 1;
  }

  /// 1-based position of this tile in the correct sequence (0 if not in it).
  int _correctOrderFor(FollowingDirectionsTrial trial, int index) {
    final i = trial.sequence.indexOf(index);
    return i < 0 ? 0 : i + 1;
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_outlined, color: Color(0xff3b82f6)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.shape,
    required this.tapOrder,
    required this.correctOrder,
    required this.answered,
    required this.onTap,
  });

  final ColoredShape shape;
  final int tapOrder;
  final int correctOrder;
  final bool answered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = kShapeColors[shape.color] ?? const Color(0xff8b9bb4);
    // Badge: while answering show the blue tap order; after answering show the
    // green correct order for sequence tiles.
    final showBadge = answered ? correctOrder > 0 : tapOrder > 0;
    final badgeNumber = answered ? correctOrder : tapOrder;
    final badgeColor =
        answered ? const Color(0xff22c55e) : const Color(0xff3b82f6);
    return Semantics(
      button: true,
      label: shape.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            children: [
              Center(
                child: CustomPaint(
                  size: const Size(72, 72),
                  painter: _ShapePainter(shape.shape, color),
                ),
              ),
              if (showBadge)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text('$badgeNumber',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.shape, this.color);

  final ShapeKind shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    switch (shape) {
      case ShapeKind.circle:
        canvas.drawCircle(
            size.center(Offset.zero), size.width / 2, paint);
      case ShapeKind.square:
        final r = RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(10),
        );
        canvas.drawRRect(r, paint);
      case ShapeKind.triangle:
        final path = Path()
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.correct});

  final bool correct;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(correct ? Icons.check_circle : Icons.cancel,
            color:
                correct ? const Color(0xff22c55e) : const Color(0xffef4444)),
        const SizedBox(width: 8),
        Text(correct ? 'Correct order!' : 'Not the right order'),
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
