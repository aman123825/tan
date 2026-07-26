import 'package:flutter/material.dart';

import '../../data/consent_store.dart';

/// Research-consent screen (J8): the plain-language consent text from
/// `docs/CONSENT.md`, with an explicit choice between "agree and save
/// results" and "use without saving". Shown once per consent-text version.
class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key, this.onDecided, this.store});

  /// Called after the decision is stored (e.g. to pop the screen).
  final void Function(bool consented)? onDecided;
  final ConsentStore? store;

  Future<void> _decide(BuildContext context, bool consented) async {
    await (store ?? ConsentStore()).record(consented: consented);
    onDecided?.call(consented);
    if (context.mounted) Navigator.of(context).maybePop(consented);
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xffe2e8f0);
    const muted = Color(0xff94a3b8);
    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: ink, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Text(body,
                  style: const TextStyle(
                      color: muted, fontSize: 13.5, height: 1.45)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Before you start'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined,
                        color: Color(0xff3b82f6), size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Taking part in HearBloom (research software)',
                        style: TextStyle(
                            color: ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                section(
                    'What this is',
                    'HearBloom is research software for practising and '
                        'exploring listening skills. It is NOT a medical '
                        'device and does not diagnose hearing loss, auditory '
                        'processing disorder, tinnitus or any other '
                        'condition.'),
                section(
                    'What is recorded',
                    'When you complete an exercise the app stores, on this '
                        'device: your answers, response times, exercise '
                        'settings, optional self-ratings (fatigue, '
                        'confidence) and optional session names. If remote '
                        'monitoring is linked, the same records are uploaded '
                        'to the study server.'),
                section(
                    'What is NOT recorded',
                    'No audio from your microphone is captured. No '
                        'advertising identifiers are used. Nothing is shared '
                        'with third parties.'),
                section(
                    'Your choices',
                    'You can use the app without saving anything. You can '
                        'export everything ("Export my data" in Settings) '
                        'or delete everything ("Delete all my data") at any '
                        'time.'),
                section(
                    'Sound safety',
                    'The app never changes your device volume, caps its own '
                        'output levels, and asks for a comfortable level '
                        'before listening tasks. Stop any exercise that is '
                        'uncomfortable.'),
                const Text(
                  'Consent text version $kConsentVersion. Any hearing '
                  'concern belongs with a qualified audiologist.',
                  style: TextStyle(
                      color: Color(0xff8b9bb4),
                      fontSize: 12,
                      fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('consent-agree'),
                  onPressed: () => _decide(context, true),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('I agree — save my results'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const Key('consent-decline'),
                  onPressed: () => _decide(context, false),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Use without saving results'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can change this anytime in Settings → Privacy & data.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
