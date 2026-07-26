import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web implementation of the browser-print seam. Selected automatically via a
/// conditional import when compiling for the web (`dart.library.js_interop`).
bool get canPrintPage => true;

/// Invokes the browser's native print dialog (`window.print()`).
void printPage() {
  globalContext.callMethod('print'.toJS);
}
