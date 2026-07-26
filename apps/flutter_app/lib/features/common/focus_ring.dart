import 'package:flutter/material.dart';

/// Wraps [child] so that, when it (or anything inside it) receives *keyboard*
/// focus, a visible 2px ring is drawn around it — a WCAG 2.4.7 (focus visible)
/// aid for keyboard/switch users.
///
/// Pointer taps do not draw the ring (Flutter only reports focus highlight for
/// keyboard/traversal), so mouse users are unaffected. Purely presentational.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.color = const Color(0xff3b82f6),
    this.width = 2,
    this.padding = 2,
  });

  final Widget child;
  final double borderRadius;
  final Color color;
  final double width;

  /// Inset of the ring from the child's edge, so it reads as an outline rather
  /// than overlapping the content.
  final double padding;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false, // don't add a stop; just observe descendants
      descendantsAreFocusable: true,
      onFocusChange: (has) {
        if (has != _focused) setState(() => _focused = has);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.all(widget.padding),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(widget.borderRadius + widget.padding),
          border: Border.all(
            color: _focused ? widget.color : Colors.transparent,
            width: widget.width,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
