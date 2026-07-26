/// Default (non-web) implementation of the browser-print seam.
///
/// On the Dart VM (tests) and native builds there is no `window.print()`, so
/// printing is unavailable and the report page shows Ctrl+P instructions
/// instead. The web implementation in `report_printer_web.dart` is selected
/// automatically via a conditional import when `dart.library.js_interop` is
/// available.
bool get canPrintPage => false;

/// No-op on non-web platforms.
void printPage() {}
