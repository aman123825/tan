import 'package:flutter/material.dart';

import 'audio_wave_animation.dart';

/// One previewable stimulus: a [label], an optional [emoji] or colour
/// [swatchArgb], and an opaque [id] passed back to the play callback.
class StimulusPreviewItem {
  const StimulusPreviewItem({
    required this.id,
    required this.label,
    this.sublabel,
    this.emoji,
    this.swatchArgb,
  });

  final String id;
  final String label;
  final String? sublabel;
  final String? emoji;
  final int? swatchArgb;
}

/// A "familiarise yourself" screen shown before a test: a scrollable grid of
/// every possible stimulus with a play button on each, plus a confirm button.
///
/// The listener taps items to hear them, then presses "I'm familiar, start the
/// test". Pure UI — playback is delegated to [onPlay]; it never scores anything.
class StimulusPreview extends StatefulWidget {
  const StimulusPreview({
    super.key,
    required this.title,
    required this.items,
    required this.onPlay,
    required this.onStart,
    this.subtitle = 'Tap any item to hear it. Press start when you are ready.',
    this.startLabel = "I'm familiar, start the test",
    this.validationNote,
  });

  final String title;
  final String subtitle;
  final List<StimulusPreviewItem> items;

  /// Plays the tapped item's audio. May be async; the tapped card shows a brief
  /// "playing" animation until it completes.
  final Future<void> Function(StimulusPreviewItem item) onPlay;

  final VoidCallback onStart;
  final String startLabel;
  final String? validationNote;

  @override
  State<StimulusPreview> createState() => _StimulusPreviewState();
}

class _StimulusPreviewState extends State<StimulusPreview> {
  String? _playingId;

  Future<void> _play(StimulusPreviewItem item) async {
    setState(() => _playingId = item.id);
    try {
      await widget.onPlay(item);
    } catch (_) {
      // Playback failure must not block the preview.
    }
    if (mounted && _playingId == item.id) {
      setState(() => _playingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                widget.subtitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: const Color(0xff94a3b8)),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth > 900
                      ? 4
                      : constraints.maxWidth > 560
                          ? 3
                          : 2;
                  return GridView.count(
                    crossAxisCount: cols,
                    padding: const EdgeInsets.all(20),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      for (final item in widget.items)
                        _PreviewCard(
                          item: item,
                          playing: _playingId == item.id,
                          onTap: () => _play(item),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (widget.validationNote != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  widget.validationNote!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xff8b9bb4)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('stimulus-preview-start'),
                  onPressed: widget.onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(widget.startLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.item,
    required this.playing,
    required this.onTap,
  });

  final StimulusPreviewItem item;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSwatch = item.swatchArgb != null;
    return Semantics(
      button: true,
      label: 'Play ${item.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x1affffff), Color(0x0dffffff)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: playing
                    ? const Color(0xff22c55e)
                    : const Color(0x33ffffff),
                width: playing ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSwatch)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(item.swatchArgb!),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x55ffffff)),
                    ),
                  )
                else if (item.emoji != null)
                  Text(item.emoji!, style: const TextStyle(fontSize: 30))
                else
                  Icon(
                    playing ? Icons.volume_up : Icons.play_circle_outline,
                    color: playing
                        ? const Color(0xff22c55e)
                        : const Color(0xff3b82f6),
                    size: 30,
                  ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffe2e8f0),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (item.sublabel != null)
                  Text(
                    item.sublabel!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff94a3b8),
                      fontSize: 11.5,
                    ),
                  ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 16,
                  child: playing
                      ? const AudioWaveAnimation(
                          width: 34, height: 16, active: true)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
