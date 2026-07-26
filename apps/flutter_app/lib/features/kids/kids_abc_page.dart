import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/closed_set.dart';
import '../../core/content_pools.dart';
import '../../core/training/reverb_training.dart' show combReverb;
import '../../core/training/scene_training.dart'
    show bandPass, multiTalkerBabble;
import '../closed_set/closed_set_page.dart';

/// The four ABC listening worlds: the same letter game in four everyday
/// acoustics (quiet room, noisy café, echoey hall, phone call).
enum AbcWorld { quiet, cafe, hall, phone }

extension AbcWorldInfo on AbcWorld {
  String get title => switch (this) {
        AbcWorld.quiet => 'Quiet room',
        AbcWorld.cafe => 'Noisy café',
        AbcWorld.hall => 'Echoey hall',
        AbcWorld.phone => 'Phone call',
      };

  String get emoji => switch (this) {
        AbcWorld.quiet => '🤫',
        AbcWorld.cafe => '🍰',
        AbcWorld.hall => '🏛️',
        AbcWorld.phone => '📞',
      };

  String get blurb => switch (this) {
        AbcWorld.quiet => 'Nice and calm — hear every letter.',
        AbcWorld.cafe => 'People are chatting — listen through the buzz!',
        AbcWorld.hall => 'Big echoes — letters bounce around!',
        AbcWorld.phone => 'A thin phone voice — tricky but fun!',
      };

  String get groupId => 'kids_abc_$name';

  /// The world's acoustic transform (level never rises: reverb and band-pass
  /// only remove/redistribute energy; the café mix is peak-normalized).
  List<double> Function(List<double>, int) get processor => switch (this) {
        AbcWorld.quiet => (s, _) => s,
        AbcWorld.cafe => (s, i) => mixAtSnr(
              s,
              multiTalkerBabble(
                  seconds: s.length / kSampleRate, seed: 100 + i),
              5,
            ),
        AbcWorld.hall => (s, _) => combReverb(s, rt60Seconds: 0.9),
        AbcWorld.phone => (s, _) => bandPass(s, 300, 3400, kSampleRate),
      };
}

/// Kids ABC: letter listening across the four worlds (F1). Each world runs
/// the closed-set letter game with that world's acoustics; kid-friendly
/// framing, standard scoring underneath.
class KidsAbcPage extends StatelessWidget {
  const KidsAbcPage({
    super.key,
    this.trialsPerWorld = 10,
    this.audioPortBuilder,
    this.onCompleted,
  });

  final int trialsPerWorld;

  /// Builds a fresh audio port per world run (pages own their port).
  final AudioPort Function()? audioPortBuilder;
  final void Function(ClosedSetSession session)? onCompleted;

  void _startWorld(BuildContext context, AbcWorld world) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ClosedSetPage(
        moduleId: 'learning',
        groupId: world.groupId,
        comfortableLevel: 0.4,
        pool: kLetterItems,
        title: 'ABC — ${world.title}',
        instruction: 'Which letter did you hear? ${world.emoji}',
        choiceCount: 4,
        maxTrials: trialsPerWorld,
        processor: world.processor,
        validationStatus: 'demo_only',
        audioPort: audioPortBuilder?.call(),
        onCompleted: onCompleted,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ABC listening worlds')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'The same letter game in four different places — can you '
                  'hear the ABCs everywhere?',
                  style: TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 16),
                for (final world in AbcWorld.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      button: true,
                      label: '${world.title}: ${world.blurb}',
                      child: Material(
                        color: const Color(0x1affffff),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          key: Key('abc-${world.name}'),
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _startWorld(context, world),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: const Color(0x33ffffff)),
                            ),
                            child: Row(
                              children: [
                                Text(world.emoji,
                                    style: const TextStyle(fontSize: 36)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(world.title,
                                          style: const TextStyle(
                                              fontSize: 16.5,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 3),
                                      Text(world.blurb,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              height: 1.3,
                                              color: Color(0xff94a3b8))),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: Color(0xff94a3b8)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'Synthesized demonstration acoustics — a listening game, '
                  'not a test.',
                  style: TextStyle(color: Color(0xff8b9bb4), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
