import 'package:flutter/material.dart';

/// One documentation section in the validation protocol page.
class _ProtocolSection {
  const _ProtocolSection(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const List<_ProtocolSection> _sections = <_ProtocolSection>[
  _ProtocolSection(
    Icons.science_outlined,
    'Study design',
    'Compare HearBloom results to a gold-standard clinical CAPD battery '
        '(SCAN-3 or equivalent). A cross-sectional concurrent-validity design '
        'with a test–retest sub-study for reliability.',
  ),
  _ProtocolSection(
    Icons.groups_outlined,
    'Participants',
    'N ≥ 30, ages 7–65, with normal peripheral hearing (pure-tone average '
        'PTA ≤ 25 dB HL). Exclude active middle-ear pathology. Stratify by age '
        'band where feasible.',
  ),
  _ProtocolSection(
    Icons.list_alt_outlined,
    'Procedure',
    'Administer the HearBloom Full Battery plus the clinical reference '
        'battery in counterbalanced order to control for order/fatigue '
        'effects. Standardise headphones, level and environment across '
        'sessions.',
  ),
  _ProtocolSection(
    Icons.analytics_outlined,
    'Outcome measures',
    'Sensitivity, specificity and ROC-AUC for each HearBloom test against the '
        'clinical reference classification; test–retest intraclass '
        'correlation (ICC) for reliability of each threshold/score.',
  ),
  _ProtocolSection(
    Icons.verified_user_outlined,
    'Ethics',
    'IRB / ethics-committee approval required before enrolment. Written '
        'informed consent (and assent for minors). No risk beyond standard '
        'audiometry; participants may withdraw at any time.',
  ),
  _ProtocolSection(
    Icons.storage_outlined,
    'Data collection',
    'HearBloom stores all trials encrypted at rest (AES-GCM) on-device. '
        'Export per-trial CSV/JSON for analysis. De-identify before analysis; '
        'store the code key separately from the data set.',
  ),
  _ProtocolSection(
    Icons.functions_outlined,
    'Statistical plan',
    'Pearson correlation between HearBloom and reference scores; '
        'Bland–Altman plots for agreement/bias; ROC analysis (AUC with 95% CI) '
        'per test; ICC for test–retest. Pre-register hypotheses and analysis '
        'plan; correct for multiple comparisons.',
  ),
];

/// Scrollable documentation of the proposed validation study. Reference /
/// research material only — describes how HearBloom would be validated against
/// a clinical battery. Not a diagnosis and not a registered protocol.
class ValidationProtocolPage extends StatelessWidget {
  const ValidationProtocolPage({super.key});

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Validation study protocol')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Proposed validation study',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'How HearBloom could be validated against a gold-standard '
                'clinical CAPD battery. Reference material only — this is a '
                'research plan, not a registered protocol or a diagnosis.',
                style: TextStyle(color: _muted, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 18),
              for (final s in _sections) ...[
                _SectionCard(section: s),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x1afbbf24),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x33fbbf24)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: Color(0xfffbbf24), size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'HearBloom is research-development software and is not '
                        'a validated medical device. Validation must be '
                        'completed before any clinical claim.',
                        style: TextStyle(
                            color: _ink, fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final _ProtocolSection section;

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${section.title}. ${section.body}',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x1a3b82f6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x333b82f6)),
                  ),
                  child: Icon(section.icon,
                      color: const Color(0xff3b82f6), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(section.title,
                      style: const TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(section.body,
                style: const TextStyle(
                    color: _muted, fontSize: 13.5, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
