import 'package:flutter/material.dart';

import '../../models/catalog.dart';

/// Small pill that surfaces a protocol group's research [validationStatus].
///
/// Required by the KIRO handoff "Definition of done": validation status must
/// be visible in the UI. Nothing is presented as clinically validated unless
/// the catalog explicitly says so.
class ValidationBadge extends StatelessWidget {
  const ValidationBadge({super.key, required this.validationStatus});

  ValidationBadge.fromGroup(ProtocolGroup group, {super.key})
      : validationStatus = group.validationStatus;

  final String validationStatus;

  ({Color fg, Color bg, IconData icon, String label}) _style() {
    switch (validationStatus) {
      case 'validated':
        return (
          fg: const Color(0xff22c55e),
          bg: const Color(0x3322c55e),
          icon: Icons.verified_outlined,
          label: 'VALIDATED',
        );
      case 'demo_only':
        return (
          fg: const Color(0xfffbbf24),
          bg: const Color(0x33f59e0b),
          icon: Icons.science_outlined,
          label: 'DEMO ONLY',
        );
      case 'unvalidated':
      default:
        return (
          fg: const Color(0xfffbbf24),
          bg: const Color(0x33f59e0b),
          icon: Icons.warning_amber_rounded,
          label: 'UNVALIDATED',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 14, color: s.fg),
          const SizedBox(width: 6),
          Text(
            s.label,
            style: TextStyle(
              color: s.fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
