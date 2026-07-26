import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web implementation of the text-download seam: data-URI anchor download.
/// Returns null (the browser owns the destination).
Future<String?> saveTextFile(String text, String filename) async {
  final document = globalContext.getProperty('document'.toJS) as JSObject;
  final anchor =
      document.callMethod('createElement'.toJS, 'a'.toJS) as JSObject;
  anchor.setProperty(
      'href'.toJS,
      'data:application/json;charset=utf-8;base64,'
              '${base64Encode(utf8.encode(text))}'
          .toJS);
  anchor.setProperty('download'.toJS, filename.toJS);
  anchor.callMethod('click'.toJS);
  return null;
}
