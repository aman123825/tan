import 'package:flutter/material.dart';

/// A named, time-boxed CAPD assessment battery: a fixed list of sub-tests run
/// in sequence. This is configuration only — launching a battery is wired up
/// separately (this page currently just returns the chosen preset's name).
class CapdBatteryPreset {
  const CapdBatteryPreset({
    required this.name,
    required this.durationMinutes,
    required this.tests,
    required this.description,
  });

  /// Display name (e.g. "Screening").
  final String name;

  /// Approximate total duration in minutes.
  final int durationMinutes;

  /// Ordered list of sub-test codes included (e.g. GIN, DDT, DPT).
  final List<String> tests;

  /// One-line summary of what the battery covers.
  final String description;

  /// Human-readable duration label.
  String get durationLabel => '~$durationMinutes min';
}

/// The three built-in battery presets.
const List<CapdBatteryPreset> kCapdBatteryPresets = <CapdBatteryPreset>[
  CapdBatteryPreset(
    name: 'Screening',
    durationMinutes: 30,
    tests: <String>['GIN', 'DDT', 'DPT'],
    description:
        'Quick screen — temporal resolution, dichotic listening and duration '
        'patterns.',
  ),
  CapdBatteryPreset(
    name: 'Full',
    durationMinutes: 60,
    tests: <String>['GIN', 'DDT', 'DPT', 'FPT', 'MLD', 'SIN'],
    description:
        'Comprehensive battery across temporal, dichotic, binaural and '
        'speech-in-noise domains.',
  ),
  CapdBatteryPreset(
    name: 'ANSD-Focus',
    durationMinutes: 45,
    tests: <String>['GIN', 'MLD', 'SIN', 'Digit Span'],
    description:
        'Auditory-neuropathy focus — temporal, binaural, speech-in-noise and '
        'auditory working memory.',
  ),
];

/// Battery-preset selection screen. Shows the three presets as glass cards;
/// tapping one returns its name to the caller (via [onSelected] if provided,
/// otherwise `Navigator.pop(preset.name)`).
class CapdBatteryPresetsPage extends StatelessWidget {
  const CapdBatteryPresetsPage({
    super.key,
    this.presets = kCapdBatteryPresets,
    this.onSelected,
  });

  final List<CapdBatteryPreset> presets;

  /// Optional selection handler. When null, the page pops with the preset name.
  final void Function(CapdBatteryPreset preset)? onSelected;

  static const Color _bg = Color(0xff0f172a);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);

  void _select(BuildContext context, CapdBatteryPreset preset) {
    if (onSelected != null) {
      onSelected!(preset);
    } else {
      Navigator.of(context).maybePop(preset.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('CAPD battery'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Choose an assessment battery',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Each battery runs its sub-tests in sequence. Research '
                  'measurement only — not a diagnosis.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 18),
                for (final preset in presets) ...[
                  _PresetCard(
                    preset: preset,
                    onTap: () => _select(context, preset),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.onTap});

  final CapdBatteryPreset preset;
  final VoidCallback onTap;

  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${preset.name} battery, ${preset.durationLabel}, '
          '${preset.tests.length} tests',
      child: Material(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('preset-${preset.name}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.name,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x1a3b82f6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x333b82f6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule,
                              size: 14, color: _primary),
                          const SizedBox(width: 5),
                          Text(
                            preset.durationLabel,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  preset.description,
                  style: const TextStyle(
                      color: _muted, fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final test in preset.tests) _TestChip(label: test),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TestChip extends StatelessWidget {
  const _TestChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xffe2e8f0),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
