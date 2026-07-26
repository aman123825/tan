/// Following-Directions *training* logic (pure Dart), inspired by HearBuilder.
///
/// The listener is given a multi-step instruction ("Tap the blue circle, then
/// tap the green triangle") and must tap the referenced shapes in the grid in
/// the correct order. The number of steps is the difficulty level: it climbs
/// after two correct trials and drops after a miss.
///
/// SAFETY: adaptation changes instruction length (working-memory / sequencing
/// load), never master volume. Flutter-free / rendering-free so it can be
/// unit-tested headlessly (the page maps colour names to swatches).
library;

import 'dart:math';

import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// The shape geometries used in the grid.
enum ShapeKind { circle, square, triangle }

String shapeName(ShapeKind s) => s.name;

/// Colour names used in the grid (the page maps these to swatch colours).
const List<String> kDirectionColors = <String>[
  'blue',
  'red',
  'green',
  'yellow',
  'purple',
  'orange',
];

const List<ShapeKind> kDirectionShapes = <ShapeKind>[
  ShapeKind.circle,
  ShapeKind.square,
  ShapeKind.triangle,
];

/// A coloured shape in the grid.
class ColoredShape {
  const ColoredShape(this.color, this.shape);

  final String color;
  final ShapeKind shape;

  String get label => '$color ${shapeName(shape)}';

  @override
  bool operator ==(Object other) =>
      other is ColoredShape && other.color == color && other.shape == shape;

  @override
  int get hashCode => Object.hash(color, shape);
}

/// A following-directions trial: the [grid] of shapes and the ordered
/// [sequence] of grid indices that must be tapped.
class FollowingDirectionsTrial {
  const FollowingDirectionsTrial({required this.grid, required this.sequence});

  final List<ColoredShape> grid;

  /// Ordered indices into [grid] the listener must tap.
  final List<int> sequence;

  int get steps => sequence.length;

  /// Human-readable instruction, e.g. "Tap the blue circle, then tap the
  /// green triangle".
  String get instruction {
    final parts = <String>[
      for (final i in sequence) 'tap the ${grid[i].label}',
    ];
    final joined = parts.join(', then ');
    return '${joined[0].toUpperCase()}${joined.substring(1)}.';
  }

  /// Whether [tappedOrder] (grid indices) matches [sequence] exactly.
  bool isCorrect(List<int> tappedOrder) {
    if (tappedOrder.length != sequence.length) return false;
    for (var i = 0; i < sequence.length; i++) {
      if (tappedOrder[i] != sequence[i]) return false;
    }
    return true;
  }
}

/// Deterministic generator: builds a grid of [gridSize] distinct coloured
/// shapes and picks [level] of them (in order) as the instruction sequence.
class FollowingDirectionsGenerator {
  FollowingDirectionsGenerator({
    int seed = 0,
    this.gridSize = 6,
    this.colors = kDirectionColors,
    this.shapes = kDirectionShapes,
  })  : assert(gridSize >= 1),
        _rng = Random(seed);

  final int gridSize;
  final List<String> colors;
  final List<ShapeKind> shapes;
  final Random _rng;

  /// The maximum distinct colour×shape combinations available.
  int get maxDistinct => colors.length * shapes.length;

  FollowingDirectionsTrial next(int level) {
    // Build a set of distinct coloured shapes for the grid.
    final combos = <ColoredShape>[
      for (final c in colors)
        for (final s in shapes) ColoredShape(c, s),
    ]..shuffle(_rng);
    final size = min(gridSize, combos.length);
    final grid = combos.take(size).toList();

    // Pick `level` distinct positions (in a random order) as the sequence.
    final steps = level.clamp(1, size);
    final positions = List<int>.generate(size, (i) => i)..shuffle(_rng);
    final sequence = positions.take(steps).toList();
    return FollowingDirectionsTrial(grid: grid, sequence: sequence);
  }
}

/// Sequences and scores a following-directions run with an adaptive step count.
class FollowingDirectionsSession {
  FollowingDirectionsSession({
    this.moduleId = 'auditory',
    this.groupId = 'following_directions',
    this.startLevel = 1,
    this.minLevel = 1,
    this.maxLevel = 4,
    this.maxTrials = 15,
    this.mode = ProtocolMode.training,
  })  : _level = startLevel,
        _maxLevelReached = startLevel;

  final String moduleId;
  final String groupId;
  final int startLevel;
  final int minLevel;
  final int maxLevel;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  int _level;
  int _maxLevelReached;
  int _consecutiveCorrect = 0;

  /// Step count (level) for the next trial.
  int get currentLevel => _level;

  /// Highest level reached.
  int get maxLevelReached => _maxLevelReached;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  bool submit(
    FollowingDirectionsTrial trial,
    List<int> tappedOrder, {
    required int latencyMs,
  }) {
    final correct = trial.isCorrect(tappedOrder);
    records.add(
      TrialRecord(
        target: trial.sequence.join(','),
        response: tappedOrder.join(','),
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{'steps': trial.steps},
      ),
    );
    if (correct) {
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        _level = min(maxLevel, _level + 1);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _level = max(minLevel, _level - 1);
    }
    if (_level > _maxLevelReached) _maxLevelReached = _level;
    return correct;
  }
}
