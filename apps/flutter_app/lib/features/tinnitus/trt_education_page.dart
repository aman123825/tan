import 'package:flutter/material.dart';

/// TRT-model education (D8): original plain-language content on the
/// neurophysiological model of tinnitus (Jastreboff, 1990) and habituation —
/// what clinical Tinnitus Retraining Therapy builds on. Education only:
/// reading this is not therapy, and the page says so.
class TrtEducationPage extends StatelessWidget {
  const TrtEducationPage({super.key});

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);

  @override
  Widget build(BuildContext context) {
    Widget section(IconData icon, String title, String body) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xff3b82f6), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(body,
                  style: const TextStyle(
                      color: _muted, fontSize: 13.5, height: 1.5)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Understanding tinnitus')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                section(
                    Icons.hearing,
                    'What tinnitus is',
                    'Tinnitus is a sound — ringing, hissing, buzzing — that '
                        'the brain hears without an outside source. It is '
                        'extremely common, and for most people it is a '
                        'benign signal, not a disease. It usually starts in '
                        'the hearing system, but how much it BOTHERS you is '
                        'decided elsewhere in the brain.'),
                section(
                    Icons.loop,
                    'Perception vs. reaction',
                    'The neurophysiological model (Jastreboff, 1990) '
                        'separates hearing the sound from reacting to it. '
                        'When the brain tags tinnitus as important or '
                        'threatening, attention and alarm systems amplify '
                        'it — a loop where monitoring the sound makes it '
                        'more noticeable, which invites more monitoring.'),
                section(
                    Icons.self_improvement,
                    'Habituation — the goal',
                    'Brains automatically stop noticing constant, '
                        'meaningless signals (a fridge hum, your own '
                        'clothing). Habituation to tinnitus means the sound '
                        'may still be measurable, but it stops grabbing '
                        'attention and stops causing distress. Most people '
                        'habituate substantially with time; retraining '
                        'approaches aim to speed that up.'),
                section(
                    Icons.spatial_audio_off,
                    'Sound enrichment',
                    'Silence turns the gain up — tinnitus is loudest in '
                        'quiet rooms. Keeping gentle background sound '
                        '(open window, soft fan, the sound-therapy player '
                        'in this app) at a level BELOW the tinnitus gives '
                        'the brain context and reduces contrast. The aim '
                        'is never to mask it completely: hearing it '
                        'faintly while relaxed is what teaches the brain '
                        'it is safe.'),
                section(
                    Icons.psychology_outlined,
                    'What clinical TRT adds',
                    'Formal Tinnitus Retraining Therapy combines '
                        'structured counselling on this model with '
                        'prescribed sound therapy over 12–24 months, '
                        'tailored to categories that consider hearing '
                        'loss and sound tolerance. That tailoring — and '
                        'the counselling itself — needs a trained '
                        'clinician; this page only explains the ideas.'),
                section(
                    Icons.medical_services_outlined,
                    'When to seek help promptly',
                    'See a doctor or audiologist soon if tinnitus is in '
                        'one ear only, pulses with your heartbeat, came '
                        'with sudden hearing loss or dizziness, or is '
                        'driving low mood or poor sleep. Effective, '
                        'evidence-based help (including CBT) exists — '
                        'nobody has to just live with distressing '
                        'tinnitus.'),
                const SizedBox(height: 6),
                const Text(
                  'Educational content (cf. Jastreboff, 1990; Jastreboff & '
                  'Hazell, 2004) — reading this is not therapy, and this '
                  'app does not treat or diagnose tinnitus.',
                  style: TextStyle(
                      color: Color(0xff8b9bb4),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.4),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
