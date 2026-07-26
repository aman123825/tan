import 'package:flutter/material.dart';

/// WCAG 2.4.7 (focus visible): a high-visibility outline drawn on themed
/// buttons when they hold keyboard focus, falling back to [base] otherwise.
/// Applied through every theme's button styles so all Filled/Elevated/
/// Outlined/Text buttons get the same focus treatment; custom
/// `Material`+`InkWell` controls are covered by `ThemeData.focusColor`
/// (see `kFocusHighlight`).
WidgetStateProperty<BorderSide?> focusOutline({BorderSide? base}) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? const BorderSide(color: Color(0xff93c5fd), width: 2.5)
          : base,
    );

/// The InkWell focus-highlight color for `ThemeData.focusColor` — visible on
/// both the dark glass and light paper surfaces, so every InkWell-based
/// custom control (choice tiles, dots, transports) shows keyboard focus.
const Color kFocusHighlight = Color(0x59609af8);
