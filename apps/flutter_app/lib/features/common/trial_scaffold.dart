import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import 'audio_wave_animation.dart';
import 'countdown_ring.dart';
import 'focus_ring.dart';
import 'live_chart.dart';
import 'playback_controls.dart';
import 'response_time_flash.dart';

const Color _border = Color(0x33ffffff);
const Color _ink = Color(0xfff1f5f9);

/// Palette for transport buttons (kept in sync with the interval renderer).
class TransportColors {
  static const Color play = Color(0xff2e9e5b);
  static const Color pause = Color(0xff3d9be9);
  static const Color stop = Color(0xfff08c2e);
  static const Color replay = Color(0xffe0a400);
}

/// One button in the vertical transport panel. A null [onTap] renders disabled.
class TransportAction {
  const TransportAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
}

/// Angel-Sound-style vertical transport panel (Resume/Pause/Stop/Replay etc.).
class TrialTransportPanel extends StatelessWidget {
  const TrialTransportPanel({super.key, required this.actions});

  final List<TransportAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              _TransportButton(action: actions[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.action});

  final TransportAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: action.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Keyboard focus draws a visible ring around the transport (WCAG
          // 2.4.7) — these are the primary controls of every trial page.
          FocusRing(
            borderRadius: 40,
            child: Material(
              color: enabled ? action.color : const Color(0xff334155),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: action.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Icon(action.icon,
                      size: 24,
                      color:
                          enabled ? Colors.white : const Color(0xff8b9bb4)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 88,
            child: Text(action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: enabled ? _ink : Colors.white38)),
          ),
        ],
      ),
    );
  }
}

/// Bottom status strip: left "Question X of N" · right "Elapsed Time MM:SS".
class TrialStatusBar extends StatelessWidget {
  const TrialStatusBar({super.key, required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x1affffff), Color(0x0dffffff)],
            ),
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(left,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _ink)),
              Text(right,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small status pill (e.g. "SNR 8 dB", "Volume locked").
class MetaPill extends StatelessWidget {
  const MetaPill({super.key, this.icon, required this.text});

  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xff94a3b8)),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _ink)),
        ],
      ),
    );
  }
}

/// Full single-stimulus trial chrome: app bar + meta pills + instruction (with
/// ear icon) + response [child] + right transport panel + bottom status bar
/// (+ optional [footer] for feedback/Next). Matches the interval renderer.
class TrialScaffold extends StatelessWidget {
  const TrialScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.instruction,
    this.instructionIcon = Icons.hearing,
    required this.pills,
    required this.child,
    required this.transport,
    required this.statusLeft,
    required this.statusRight,
    this.validationBadge,
    this.onStop,
    this.footer,
    this.enableShortcuts = true,
    this.showPlaybackControls = false,
    this.liveResults,
    this.isPlaying = false,
    this.encouragement,
    this.showCountdown = false,
    this.countdownDuration = const Duration(seconds: 2),
    this.onCountdownComplete,
    this.responseTimeMs,
    this.onDigitKey,
    this.revealedText,
    this.helpText,
    this.onFlagLastTrial,
    this.lastTrialFlagged = false,
  });

  final String title;
  final String? subtitle;
  final String instruction;
  final IconData instructionIcon;
  final List<Widget> pills;
  final Widget child;
  final List<TransportAction> transport;
  final String statusLeft;
  final String statusRight;
  final Widget? validationBadge;
  final VoidCallback? onStop;
  final Widget? footer;
  final bool enableShortcuts;

  /// When true, a manual playback-controls (speed + channel) button is shown in
  /// the app bar. Presentation only — it never changes scoring or master volume.
  final bool showPlaybackControls;

  /// When non-null, a live accuracy sparkline is shown between the pills row and
  /// the instruction (one entry per completed trial: true = correct).
  final List<bool>? liveResults;

  /// When true, an animated equalizer replaces the instruction ear icon to
  /// signal that audio is currently playing.
  final bool isPlaying;

  /// A brief motivational line shown (fading in/out) just above the status bar.
  final String? encouragement;

  /// When true, a 2-second [CountdownRing] is shown between the instruction and
  /// the response [child] to signal that audio is about to auto-play. Pages set
  /// this during their pre-play delay.
  final bool showCountdown;

  /// Duration of the pre-play [CountdownRing].
  final Duration countdownDuration;

  /// Fires once when the [CountdownRing] finishes (i.e. audio should start).
  final VoidCallback? onCountdownComplete;

  /// When set (and changed), a fading "X ms" response-time chip is shown with
  /// the footer feedback. Informational only.
  final int? responseTimeMs;

  /// Optional handler for number-key answering: pressing a digit key `0`–`9`
  /// (top row or numpad) invokes this with that digit. Pages with numbered
  /// choices use it to select a choice from the keyboard (WCAG operability).
  final void Function(int digit)? onDigitKey;

  /// The stimulus text of the just-answered trial, when the page has one.
  /// Shown as a caption chip ONLY while the "show stimulus text" setting is
  /// on — pages pass it after the response, so it can never reveal an answer
  /// early.
  final String? revealedText;

  /// Optional page-specific help ("what does this measure / how to respond")
  /// shown in the consistent Help sheet behind the app-bar `?` button.
  final String? helpText;

  /// When non-null (pages pass it after a response), a small "Flag trial"
  /// control lets the listener mark the just-answered trial as distracted.
  /// The flag travels with the exported record; scoring is unchanged.
  final VoidCallback? onFlagLastTrial;

  /// Whether the just-answered trial is already flagged (renders filled).
  final bool lastTrialFlagged;

  /// Space/Enter target: the first *enabled* transport button that is not the
  /// Stop control (by convention Play, then Replay).
  VoidCallback? get _primaryAction {
    for (final a in transport) {
      if (a.color == TransportColors.stop) continue;
      if (a.onTap != null) return a.onTap;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffold = Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: subtitle == null
            ? Text(title)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      )),
                  Text(title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
        actions: [
          if (showPlaybackControls) const PlaybackControlsButton(),
          // Consistent help entry point on every trial page (WCAG 3.2.6):
          // same icon, same position, same sheet structure.
          IconButton(
            tooltip: 'Help',
            onPressed: () => _showHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
          if (onStop != null)
            IconButton(
              tooltip: 'End exercise',
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < pills.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          pills[i],
                        ],
                      ],
                    ),
                  ),
                ),
                if (validationBadge != null) ...[
                  const SizedBox(width: 8),
                  validationBadge!,
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (liveResults != null) ...[
              LiveChart(results: liveResults!),
              _AnswerHaptics(results: liveResults!),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(instruction,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center),
                            ),
                            const SizedBox(width: 12),
                            if (isPlaying)
                              const AudioWaveAnimation(active: true)
                            else
                              Icon(instructionIcon,
                                  size: 26, color: theme.colorScheme.primary),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (showCountdown) ...[
                          CountdownRing(
                            duration: countdownDuration,
                            onComplete: onCountdownComplete,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Expanded(child: child),
                        if (revealedText != null &&
                            appSettings.value.showStimulusText) ...[
                          const SizedBox(height: 10),
                          _StimulusCaption(text: revealedText!),
                        ],
                        if (footer != null) ...[
                          const SizedBox(height: 12),
                          footer!,
                        ],
                        if (onFlagLastTrial != null) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton.icon(
                              key: const Key('flag-trial'),
                              onPressed:
                                  lastTrialFlagged ? null : onFlagLastTrial,
                              icon: Icon(
                                lastTrialFlagged
                                    ? Icons.flag
                                    : Icons.outlined_flag,
                                size: 16,
                                color: lastTrialFlagged
                                    ? const Color(0xfffbbf24)
                                    : const Color(0xff8b9bb4),
                              ),
                              label: Text(
                                lastTrialFlagged
                                    ? 'Trial flagged for review'
                                    : 'Flag trial (I was distracted)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: lastTrialFlagged
                                      ? const Color(0xfffbbf24)
                                      : const Color(0xff8b9bb4),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (responseTimeMs != null) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: ResponseTimeFlash(
                              key: ValueKey<int>(responseTimeMs!),
                              latencyMs: responseTimeMs,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (transport.isNotEmpty) ...[
                    const SizedBox(width: 18),
                    TrialTransportPanel(actions: transport),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (encouragement != null) ...[
              _EncouragementBanner(message: encouragement!),
              const SizedBox(height: 8),
            ],
            TrialStatusBar(left: statusLeft, right: statusRight),
            if (enableShortcuts) ...[
              const SizedBox(height: 6),
              Text('Space = play / replay    ·    Esc = end',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: const Color(0xff8b9bb4))),
            ],
          ],
        ),
      ),
    );
    if (!enableShortcuts) return scaffold;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _primaryAction?.call(),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _primaryAction?.call(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            _primaryAction?.call(),
        const SingleActivator(LogicalKeyboardKey.escape): () => onStop?.call(),
        if (onDigitKey != null) ..._digitBindings(onDigitKey!),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  /// The consistent help sheet: what this page asks, how to respond, and the
  /// controls/shortcuts that are the same on every trial page.
  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.help_outline, color: Color(0xff3b82f6)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Help — $title',
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('This exercise',
                  style: TextStyle(
                      color: Color(0xff8b9bb4),
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(instruction,
                  style: const TextStyle(color: _ink, height: 1.4)),
              if (helpText != null) ...[
                const SizedBox(height: 8),
                Text(helpText!,
                    style: const TextStyle(
                        color: Color(0xff94a3b8), height: 1.4)),
              ],
              const SizedBox(height: 14),
              const Text('Controls (same on every exercise)',
                  style: TextStyle(
                      color: Color(0xff8b9bb4),
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                '• Play / Replay — the round buttons on the right.\n'
                '• Stop — the orange button (or the ⏹ icon top-right) ends '
                'the exercise; progress so far is kept.\n'
                '• Space or Enter — play / replay.\n'
                '• Number keys 1–9 — choose an answer where choices are '
                'numbered.\n'
                '• Esc — end the exercise.',
                style: TextStyle(color: _ink, height: 1.55),
              ),
              const SizedBox(height: 14),
              const Text(
                'Difficulty adapts to you; master volume never changes. '
                'Research exercise — not a diagnosis.',
                style: TextStyle(color: Color(0xff8b9bb4), fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps the top-row and numpad digit keys `0`–`9` to [handler].
  static Map<ShortcutActivator, VoidCallback> _digitBindings(
      void Function(int) handler) {
    final digits = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    };
    return <ShortcutActivator, VoidCallback>{
      for (final e in digits.entries)
        SingleActivator(e.key): () => handler(e.value),
    };
  }
}



/// Caption chip revealing the stimulus text of an answered trial ("Heard:
/// …"), shown only while the "show stimulus text" setting is on.
class _StimulusCaption extends StatelessWidget {
  const _StimulusCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x263b82f6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x553b82f6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.closed_caption_outlined,
                size: 16, color: Color(0xffbfdbfe)),
            const SizedBox(width: 7),
            Flexible(
              child: Text('“$text”',
                  style: const TextStyle(
                      color: Color(0xffe2e8f0),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A brief motivational line that fades in then out (~1.2s) whenever its
/// [message] changes. Purely decorative; never affects scoring.
class _EncouragementBanner extends StatefulWidget {
  const _EncouragementBanner({required this.message});

  final String message;

  @override
  State<_EncouragementBanner> createState() => _EncouragementBannerState();
}

class _EncouragementBannerState extends State<_EncouragementBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final Animation<double> _opacity = TweenSequence<double>(<
      TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25),
    TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 45),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(_EncouragementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x2622c55e),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x5522c55e)),
      ),
      child: Text(
        widget.message,
        style: const TextStyle(
          color: Color(0xffe2e8f0),
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
    // Reduced motion: show the line statically instead of fading (WCAG 2.3.3).
    if (reduceMotionActive(context)) return Center(child: chip);
    return Center(child: FadeTransition(opacity: _opacity, child: chip));
  }
}

/// Fires platform haptic feedback when a new trial outcome is appended to
/// [results] — a light tap for correct, a heavier one for incorrect. Renders
/// nothing; harmlessly a no-op on platforms without haptics (desktop/web).
class _AnswerHaptics extends StatefulWidget {
  const _AnswerHaptics({required this.results});

  final List<bool> results;

  @override
  State<_AnswerHaptics> createState() => _AnswerHapticsState();
}

class _AnswerHapticsState extends State<_AnswerHaptics> {
  late int _seen = widget.results.length;

  @override
  void didUpdateWidget(_AnswerHaptics oldWidget) {
    super.didUpdateWidget(oldWidget);
    final results = widget.results;
    if (results.length > _seen && results.isNotEmpty) {
      try {
        if (results.last) {
          HapticFeedback.lightImpact();
        } else {
          HapticFeedback.mediumImpact();
        }
      } catch (_) {
        // No haptics on this platform — fine.
      }
    }
    _seen = results.length;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
