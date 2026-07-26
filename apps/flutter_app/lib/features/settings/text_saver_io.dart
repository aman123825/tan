import 'dart:io';

/// Non-web implementation of the text-download seam: writes to the system
/// temp directory and returns the path (shown to the user).
Future<String?> saveTextFile(String text, String filename) async {
  final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$filename');
  await file.writeAsString(text, flush: true);
  return file.path;
}
