import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/difficulty.dart';

/// SharedPreferences-backed persistence for the last-selected difficulty, so a
/// listener's choice is remembered between sessions. Failures fall back to
/// [DifficultyLevel.medium] and never throw into the UI.
class DifficultyStore {
  DifficultyStore({this.storageKey = 'hearbloom.difficulty.v1'});

  final String storageKey;

  Future<DifficultyLevel> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DifficultyLevelInfo.fromStorage(prefs.getString(storageKey));
    } catch (_) {
      return DifficultyLevel.medium;
    }
  }

  Future<void> save(DifficultyLevel level) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, level.storageKey);
    } catch (_) {
      // Persistence is best-effort; a failure must never block starting a test.
    }
  }
}

/// Glyph for each level (kept in the widget layer so `core/difficulty.dart`
/// stays Flutter-free).
IconData difficultyIcon(DifficultyLevel level) => switch (level) {
      DifficultyLevel.easy => Icons.spa_outlined,
      DifficultyLevel.medium => Icons.tune,
      DifficultyLevel.hard => Icons.bolt,
      DifficultyLevel.expert => Icons.science_outlined,
    };

const Color _bg = Color(0xff0f172a);
const Color _ink = Color(0xffe2e8f0);
const Color _muted = Color(0xff94a3b8);
const Color _border = Color(0x33ffffff);
const Color _primary = Color(0xff3b82f6);

/// Shows the difficulty selector in a glass dialog and returns the chosen level
/// (or `null` if dismissed). The selection is persisted via [DifficultyStore]
/// and pre-selects [initial] (or the last saved level when [initial] is null).
Future<DifficultyLevel?> showDifficultyDialog(
  BuildContext context, {
  DifficultyLevel? initial,
  String title = 'Choose a starting level',
  DifficultyStore? store,
}) async {
  final s = store ?? DifficultyStore();
  final start = initial ?? await s.load();
  if (!context.mounted) return null;
  final chosen = await showDialog<DifficultyLevel>(
    context: context,
    builder: (context) => _DifficultyDialog(title: title, initial: start),
  );
  if (chosen != null) await s.save(chosen);
  return chosen;
}

class _DifficultyDialog extends StatefulWidget {
  const _DifficultyDialog({required this.title, required this.initial});

  final String title;
  final DifficultyLevel initial;

  @override
  State<_DifficultyDialog> createState() => _DifficultyDialogState();
}

class _DifficultyDialogState extends State<_DifficultyDialog> {
  late DifficultyLevel _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff1e293b),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: _border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: DifficultySelector(
            title: widget.title,
            initial: _selected,
            persistSelection: false,
            onChanged: (level) => _selected = level,
            onStart: (level) => Navigator.of(context).pop(level),
          ),
        ),
      ),
    );
  }
}

/// A glass-card difficulty picker: a header, four selectable cards (Easy /
/// Medium / Hard / Expert) and a Start button. The selected card carries a blue
/// glow border. Shown before starting any test or training run.
///
/// Reusable both inside [showDifficultyDialog] and as a standalone screen body.
class DifficultySelector extends StatefulWidget {
  const DifficultySelector({
    super.key,
    required this.onStart,
    this.onChanged,
    this.initial = DifficultyLevel.medium,
    this.title = 'Choose a starting level',
    this.startLabel = 'Start',
    this.persistSelection = true,
    this.store,
  });

  /// Called with the chosen level when Start is pressed.
  final void Function(DifficultyLevel level) onStart;

  /// Called whenever the selected card changes (before Start).
  final void Function(DifficultyLevel level)? onChanged;

  /// Pre-selected level. When [persistSelection] is true the last-saved level
  /// is loaded and overrides this once available.
  final DifficultyLevel initial;

  final String title;
  final String startLabel;

  /// When true, loads/saves the selection via [store] (default [DifficultyStore]).
  final bool persistSelection;
  final DifficultyStore? store;

  @override
  State<DifficultySelector> createState() => _DifficultySelectorState();
}

class _DifficultySelectorState extends State<DifficultySelector> {
  late DifficultyLevel _selected = widget.initial;
  late final DifficultyStore _store = widget.store ?? DifficultyStore();

  @override
  void initState() {
    super.initState();
    if (widget.persistSelection) {
      _store.load().then((level) {
        if (mounted) setState(() => _selected = level);
      });
    }
  }

  void _select(DifficultyLevel level) {
    setState(() => _selected = level);
    widget.onChanged?.call(level);
  }

  void _start() {
    if (widget.persistSelection) _store.save(_selected);
    widget.onStart(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Start where it suits you. Higher levels begin closer to threshold so '
          'you spend fewer trials on easy items — you can stop anytime, and '
          'master volume never changes.',
          style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            // Four in a row when there is room; otherwise a 2×2 grid.
            final twoPerRow = constraints.maxWidth < 520;
            final cardWidth = twoPerRow
                ? (constraints.maxWidth - 12) / 2
                : (constraints.maxWidth - 3 * 12) / 4;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final level in DifficultyLevel.values)
                  SizedBox(
                    width: cardWidth <= 0 ? null : cardWidth,
                    child: _DifficultyCard(
                      level: level,
                      selected: _selected == level,
                      onTap: () => _select(level),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('difficulty-start'),
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: Text('${widget.startLabel} · ${_selected.label}'),
        ),
      ],
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final DifficultyLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${level.label} — ${level.shortDescription}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('difficulty-card-${level.name}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? const [Color(0x333b82f6), Color(0x1a3b82f6)]
                    : const [Color(0x1affffff), Color(0x0dffffff)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _primary : _border,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x553b82f6),
                        blurRadius: 22,
                        spreadRadius: 1,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0x403b82f6)
                        : const Color(0x14ffffff),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected ? _primary : _border,
                    ),
                  ),
                  child: Icon(
                    difficultyIcon(level),
                    color: selected ? const Color(0xff93c5fd) : _muted,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  level.label,
                  style: TextStyle(
                    color: selected ? _ink : const Color(0xffcbd5e1),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  level.shortDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen difficulty picker (used where a page — rather than a dialog — is
/// preferred). Pops with the chosen [DifficultyLevel].
class DifficultySelectorPage extends StatelessWidget {
  const DifficultySelectorPage({
    super.key,
    this.title = 'Choose a starting level',
    this.initial = DifficultyLevel.medium,
  });

  final String title;
  final DifficultyLevel initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('Difficulty'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: DifficultySelector(
                title: title,
                initial: initial,
                onStart: (level) => Navigator.of(context).pop(level),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
