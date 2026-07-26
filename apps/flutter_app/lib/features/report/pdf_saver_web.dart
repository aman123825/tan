import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Web implementation of the PDF-download seam: builds a data-URI anchor and
/// clicks it, triggering the browser's download flow. Returns null (the
/// browser owns the destination). Selected via conditional import when
/// `dart.library.js_interop` is available.
bool get canSavePdf => true;

Future<String?> savePdf(Uint8List bytes, String filename) async {
  final document = globalContext.getProperty('document'.toJS) as JSObject;
  final anchor =
      document.callMethod('createElement'.toJS, 'a'.toJS) as JSObject;
  anchor.setProperty('href'.toJS,
      'data:application/pdf;base64,${base64Encode(bytes)}'.toJS);
  anchor.setProperty('download'.toJS, filename.toJS);
  anchor.callMethod('click'.toJS);
  return null;
}
