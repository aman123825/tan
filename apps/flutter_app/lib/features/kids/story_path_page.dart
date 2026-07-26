import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../data/gamification_store.dart';
import 'kids_theme.dart';

/// One story chapter on the journey path, unlocked at [sessionsNeeded]
/// completed sessions.
class StoryChapter {
  const StoryChapter(this.title, this.emoji, this.text, this.sessionsNeeded);

  final String title;
  final String emoji;
  final String text;
  final int sessionsNeeded;
}

/// The listening-journey story (original content): each practice session
/// moves the mascot further along the path.
const List<StoryChapter> kStoryChapters = <StoryChapter>[
  StoryChapter('The Quiet Meadow', '🌼',
      'Pip the fox wakes up in a quiet meadow. "My ears feel sleepy," Pip '
      'says. "Let\'s wake them up with some listening games!"', 0),
  StoryChapter('The Whispering Woods', '🌳',
      'The trees whisper soft sounds. Pip listens carefully and hears a '
      'tiny bell far away. Your practice helped Pip hear it!', 3),
  StoryChapter('The Chattering Café', '🧁',
      'The café is LOUD! Everyone is talking at once. But Pip has been '
      'practising with you — and picks out Grandma Owl\'s voice easily.', 6),
  StoryChapter('The Echo Caves', '🦇',
      'Woooo… woo… wo…! Sounds bounce everywhere in the caves. Pip claps a '
      'rhythm and listens for the echo to find the way through.', 10),
  StoryChapter('The Musical Mountain', '🎵',
      'At the top of the mountain, the wind plays melodies. Pip hums along '
      'and names every tune. "Your ears are getting so strong!"', 15),
  StoryChapter('The Star Listening Party', '🌟',
      'All the animals gather under the stars for Pip\'s listening party. '
      '"You did it!" they cheer. "Champion ears!" — and a new adventure '
      'begins tomorrow.', 21),
];

/// Kids story path (F6): a painted winding trail where completed practice
/// sessions carry the mascot from chapter to chapter. Purely motivational —
/// progress comes from the gamification session count and never affects
/// scoring.
class StoryPathPage extends StatefulWidget {
  const StoryPathPage({super.key, this.store});

  final GamificationStore? store;

  @override
  State<StoryPathPage> createState() => _StoryPathPageState();
}

class _StoryPathPageState extends State<StoryPathPage> {
  int _sessions = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    (widget.store ?? GamificationStore()).load().then((state) {
      if (mounted) {
        setState(() {
          _sessions = state.sessionsCompleted;
          _loaded = true;
        });
      }
    });
  }

  int get _currentChapter {
    var current = 0;
    for (var i = 0; i < kStoryChapters.length; i++) {
      if (_sessions >= kStoryChapters[i].sessionsNeeded) current = i;
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentChapter;
    return Scaffold(
      appBar: AppBar(title: const Text('Pip\'s listening journey')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Every practice session moves Pip along the path. '
                      'You have finished $_sessions '
                      'session${_sessions == 1 ? '' : 's'}!',
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: kStoryChapters.length * 118,
                      child: CustomPaint(
                        painter: _PathPainter(
                          chapterCount: kStoryChapters.length,
                          currentChapter: current,
                          reduceMotion: reduceMotionActive(context),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0;
                                i < kStoryChapters.length;
                                i++)
                              Expanded(
                                child: _ChapterNode(
                                  chapter: kStoryChapters[i],
                                  index: i,
                                  state: i < current
                                      ? _NodeState.done
                                      : i == current
                                          ? _NodeState.current
                                          : _NodeState.locked,
                                  sessions: _sessions,
                                  onTap: () =>
                                      _showChapter(context, i, current),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A story for motivation only — it never changes any '
                      'measurement.',
                      style:
                          TextStyle(color: Color(0xff8b9bb4), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showChapter(BuildContext context, int index, int current) {
    final chapter = kStoryChapters[index];
    final locked = index > current;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(locked ? '🔒' : chapter.emoji,
                style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(chapter.title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              locked
                  ? 'Practise ${chapter.sessionsNeeded - _sessions} more '
                      'session${chapter.sessionsNeeded - _sessions == 1 ? '' : 's'} '
                      'to unlock this part of Pip\'s story!'
                  : chapter.text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NodeState { done, current, locked }

class _ChapterNode extends StatelessWidget {
  const _ChapterNode({
    required this.chapter,
    required this.index,
    required this.state,
    required this.sessions,
    required this.onTap,
  });

  final StoryChapter chapter;
  final int index;
  final _NodeState state;
  final int sessions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leftSide = index.isEven;
    final node = Semantics(
      button: true,
      label: '${chapter.title}: '
          '${state == _NodeState.locked ? 'locked' : state == _NodeState.current ? 'current chapter' : 'finished'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('story-node-$index'),
          borderRadius: BorderRadius.circular(40),
          onTap: onTap,
          child: Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (state) {
                _NodeState.done => KidsColors.primary.withValues(alpha: 0.25),
                _NodeState.current =>
                  KidsColors.accent.withValues(alpha: 0.3),
                _NodeState.locked => const Color(0x22ffffff),
              },
              border: Border.all(
                color: switch (state) {
                  _NodeState.done => KidsColors.primary,
                  _NodeState.current => KidsColors.accent,
                  _NodeState.locked => const Color(0x33ffffff),
                },
                width: state == _NodeState.current ? 3 : 2,
              ),
            ),
            child: Text(
              state == _NodeState.locked ? '🔒' : chapter.emoji,
              style: TextStyle(
                  fontSize: state == _NodeState.current ? 34 : 28),
            ),
          ),
        ),
      ),
    );
    return Row(
      mainAxisAlignment:
          leftSide ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        if (!leftSide) const Spacer(),
        Padding(
          padding: EdgeInsets.only(
              left: leftSide ? 24 : 0, right: leftSide ? 0 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state == _NodeState.current) const Text('🦊'),
              node,
              const SizedBox(height: 4),
              Text(chapter.title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (leftSide) const Spacer(),
      ],
    );
  }
}

/// Paints the dotted winding trail connecting alternate-side chapter nodes.
class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.chapterCount,
    required this.currentChapter,
    required this.reduceMotion,
  });

  final int chapterCount;
  final int currentChapter;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (chapterCount < 2) return;
    final rowH = size.height / chapterCount;
    Offset centerOf(int i) => Offset(
          i.isEven ? size.width * 0.22 : size.width * 0.78,
          rowH * i + rowH * 0.45,
        );
    for (var i = 0; i < chapterCount - 1; i++) {
      final from = centerOf(i);
      final to = centerOf(i + 1);
      final done = i < currentChapter;
      final paint = Paint()
        ..color = done
            ? KidsColors.primary.withValues(alpha: 0.8)
            : const Color(0x33ffffff)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      // Dotted curve: sample a quadratic bezier and draw dots.
      final mid = Offset((from.dx + to.dx) / 2,
          (from.dy + to.dy) / 2 + (i.isEven ? 18 : -18));
      const dots = 14;
      for (var d = 0; d <= dots; d++) {
        final t = d / dots;
        final p = Offset(
          _quad(from.dx, mid.dx, to.dx, t),
          _quad(from.dy, mid.dy, to.dy, t),
        );
        canvas.drawCircle(p, max(1.5, 2.4 - (d % 2)), paint);
      }
    }
  }

  double _quad(double a, double b, double c, double t) =>
      (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c;

  @override
  bool shouldRepaint(_PathPainter oldDelegate) =>
      oldDelegate.currentChapter != currentChapter ||
      oldDelegate.chapterCount != chapterCount;
}
