import 'dart:io';
import 'dart:typed_data';

/// Non-web implementation of the PDF-download seam: writes the bytes to the
/// system temp directory and returns the saved path (shown to the user). The
/// web implementation triggers a browser download instead.
bool get canSavePdf => true;

Future<String?> savePdf(Uint8List bytes, String filename) async {
  final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
