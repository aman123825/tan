import 'package:flutter/material.dart';

import 'aphab_page.dart';
import 'fisher_page.dart';
import 'hhie_page.dart';
import 'ssq12_page.dart';
import 'tfi_page.dart';
import 'thi_page.dart';

/// One place to reach every self-report / observer questionnaire:
/// SSQ12, HHIE-S, APHAB and Fisher's checklist.
class QuestionnairesHubPage extends StatelessWidget {
  const QuestionnairesHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, Color color, String title, String subtitle,
            Widget Function() builder) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            button: true,
            label: title,
            child: Material(
              color: const Color(0x1affffff),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => builder())),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x33ffffff)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Icon(icon, color: color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    color: Color(0xffe2e8f0),
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: const TextStyle(
                                    color: Color(0xff94a3b8),
                                    fontSize: 12.5)),
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
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Questionnaires')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Standard self-report and observer questionnaires. They '
                  'describe everyday listening — they do not diagnose.',
                  style: TextStyle(
                      color: Color(0xff94a3b8), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                tile(
                    Icons.hearing,
                    const Color(0xff3b82f6),
                    'SSQ12',
                    'Speech, Spatial & Qualities of Hearing (12 items, 0–10)',
                    () => const Ssq12Page()),
                tile(
                    Icons.elderly,
                    const Color(0xff8b5cf6),
                    'HHIE-S',
                    'Hearing Handicap Inventory (10 items)',
                    () => const HhiePage()),
                tile(
                    Icons.assignment_outlined,
                    const Color(0xff06b6d4),
                    'APHAB',
                    'Abbreviated Profile of Hearing Aid Benefit '
                        '(24 items, A–G)',
                    () => const AphabPage()),
                tile(
                    Icons.checklist_outlined,
                    const Color(0xff22c55e),
                    'Fisher\'s checklist',
                    'Auditory Problems Checklist for parents/teachers '
                        '(25 items)',
                    () => const FisherPage()),
                tile(
                    Icons.hearing_disabled,
                    const Color(0xfff87171),
                    'THI',
                    'Tinnitus Handicap Inventory (25 items, graded)',
                    () => const ThiPage()),
                tile(
                    Icons.hearing_disabled,
                    const Color(0xfffbbf24),
                    'Tinnitus impact (TFI-style)',
                    'Paraphrased 8-domain impact screen (0-10)',
                    () => const TfiPage()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
