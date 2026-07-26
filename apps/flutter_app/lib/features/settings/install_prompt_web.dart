/// Web implementation of the PWA install-prompt seam. Selected automatically
/// via a conditional import when compiling for the web.
///
/// `web/index.html` registers a `beforeinstallprompt` listener that stores the
/// deferred event on `window.hbDeferredPrompt`. This reads that event and calls
/// its `prompt()` method to show the browser's native "Install app" dialog.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the browser has offered (and we captured) a deferred install prompt.
bool get canInstallApp {
  final v = globalContext.getProperty<JSAny?>('hbDeferredPrompt'.toJS);
  return v != null && !v.isUndefinedOrNull;
}

/// Shows the browser's native install prompt if available. Returns true if a
/// prompt was shown (the deferred event can only be used once).
Future<bool> promptInstall() async {
  final v = globalContext.getProperty<JSAny?>('hbDeferredPrompt'.toJS);
  if (v == null || v.isUndefinedOrNull) return false;
  final prompt = v as JSObject;
  prompt.callMethod<JSAny?>('prompt'.toJS);
  // A deferred prompt is single-use; clear it so the UI reflects that.
  globalContext.setProperty('hbDeferredPrompt'.toJS, null);
  return true;
}
