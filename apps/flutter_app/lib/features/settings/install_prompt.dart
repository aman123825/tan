import 'package:flutter/material.dart';

import 'install_prompt_io.dart'
    if (dart.library.js_interop) 'install_prompt_web.dart' as installer;

/// A settings row that installs the app as a PWA.
///
/// On the web, tapping it triggers the browser's captured `beforeinstallprompt`
/// event (native "Install app" dialog). When no deferred prompt is available
/// (already installed, unsupported browser, or the event has not fired) it
/// shows manual "Add to Home Screen" guidance instead. On non-web builds it
/// simply shows guidance. Presentation-only — never affects scoring or volume.
class InstallAppButton extends StatelessWidget {
  const InstallAppButton({super.key});

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);

  Future<void> _install(BuildContext context) async {
    final shown = await installer.promptInstall();
    if (!context.mounted) return;
    if (!shown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'To install: use your browser menu → “Install app” / “Add to '
            'Home screen”. (Already installed browsers won’t re-prompt.)',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Install app',
      child: Material(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const Key('install-app-button'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => _install(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xff22c55e).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: const Color(0xff22c55e).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.install_mobile,
                      color: Color(0xff22c55e), size: 21),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Install app',
                          style: TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text('Add HearBloom to your device for offline use',
                          style: TextStyle(color: _muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
