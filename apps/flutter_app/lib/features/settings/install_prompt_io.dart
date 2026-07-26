/// Default (non-web) implementation of the PWA install-prompt seam.
///
/// On the Dart VM (tests) and native builds there is no `beforeinstallprompt`
/// event, so installation is unavailable. The web implementation in
/// `install_prompt_web.dart` is selected automatically via a conditional import
/// when `dart.library.js_interop` is available.
library;

/// Whether a deferred browser install prompt is currently available.
bool get canInstallApp => false;

/// No-op on non-web platforms. Returns false (nothing prompted).
Future<bool> promptInstall() async => false;
