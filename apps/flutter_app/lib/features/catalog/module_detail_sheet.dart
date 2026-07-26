import 'package:flutter/material.dart';

import '../../models/catalog.dart';
import 'validation_badge.dart';

/// Bottom sheet that lists the protocol groups inside a [Module].
///
/// Handles inheritance: the Telephone module carries no groups of its own and
/// inherits Foundation's groups (through a telephone-band signal chain).
class ModuleDetailSheet extends StatelessWidget {
  const ModuleDetailSheet({
    super.key,
    required this.module,
    required this.catalog,
    this.onOpenGroup,
    this.extraGroups = const <ProtocolGroup>[],
    this.extraGroupsLabel,
  });

  final Module module;
  final Catalog catalog;

  /// Invoked when the user opens a specific protocol group. Wired by later
  /// slices (comfortable-level check / speech-in-noise training).
  final void Function(Module module, ProtocolGroup group)? onOpenGroup;

  /// Additional research protocols to surface for this module that do not live
  /// in the signed catalog (e.g. the CAPD diagnostic tests). They render below
  /// the catalog groups and route through the same [onOpenGroup] callback.
  final List<ProtocolGroup> extraGroups;

  /// Optional sub-header shown above [extraGroups].
  final String? extraGroupsLabel;

  /// Resolves the groups to display, following [Module.inherits] when a module
  /// (e.g. Telephone) defines none of its own.
  List<ProtocolGroup> _resolveGroups() {
    if (module.groups.isNotEmpty) return module.groups;
    final parentId = module.inherits;
    if (parentId != null) {
      final parent = catalog.moduleById(parentId);
      if (parent != null) return parent.groups;
    }
    return const <ProtocolGroup>[];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _resolveGroups();
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                module.name,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xffe2e8f0),
                ),
              ),
              if (module.inheritsAnother) ...[
                const SizedBox(height: 6),
                Text(
                  'Inherits ${module.inherits} groups through a telephone-band '
                  'signal chain (300–3200 Hz).',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xff94a3b8),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Protocol details load from protocols/catalog.json. Generated '
                'voices and stimuli are demonstration material until reviewed '
                'by an audiologist.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xff94a3b8),
                ),
              ),
              const SizedBox(height: 16),
              for (final group in groups)
                _GroupTile(
                  group: group,
                  onOpen: onOpenGroup == null
                      ? null
                      : () => onOpenGroup!(module, group),
                ),
              if (extraGroups.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  extraGroupsLabel ?? 'CAPD diagnostic tests (research)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xffe2e8f0),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Additional research protocols for this module. Demonstration '
                  'stimuli on uncalibrated audio — not a diagnosis.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xff94a3b8),
                  ),
                ),
                const SizedBox(height: 12),
                for (final group in extraGroups)
                  _GroupTile(
                    group: group,
                    onOpen: onOpenGroup == null
                        ? null
                        : () => onOpenGroup!(module, group),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, this.onOpen});

  final ProtocolGroup group;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xff273449),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x33ffffff)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xffe2e8f0),
                    ),
                  ),
                ),
                ValidationBadge.fromGroup(group),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              group.protocol,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xff7dd3fc),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            _WorkflowStrip(modes: group.modes),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Open protocol'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the five-stage workflow (introduction → results) as connected chips.
class _WorkflowStrip extends StatelessWidget {
  const _WorkflowStrip({required this.modes});

  final List<String> modes;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final mode in modes)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xff293548),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              mode,
              style: const TextStyle(fontSize: 11, color: Color(0xff94a3b8)),
            ),
          ),
      ],
    );
  }
}
