/// Minimal pure-Dart PDF writer (no dependencies, no Flutter).
///
/// Produces a real, valid PDF 1.4 byte stream for the text report: A4 pages,
/// the standard-14 Helvetica / Helvetica-Bold fonts (no embedding needed),
/// word-wrapped paragraphs, key-value rows, simple table rows and dividers,
/// with automatic pagination and correct xref offsets. Text is transliterated
/// to WinAnsi-safe ASCII (the report is English). Verified headlessly by the
/// diagnostics harness (parses its own output's header/xref/EOF).
library;

import 'dart:typed_data';

/// A content block for [buildSimplePdf].
sealed class PdfBlock {
  const PdfBlock();
}

/// A section heading (level 1 = document title, 2 = section).
class PdfHeading extends PdfBlock {
  const PdfHeading(this.text, {this.level = 2});
  final String text;
  final int level;
}

/// A word-wrapped body paragraph.
class PdfParagraph extends PdfBlock {
  const PdfParagraph(this.text, {this.size = 10, this.gray = false});
  final String text;
  final double size;
  final bool gray;
}

/// A "Key: value" line (key bold, value regular).
class PdfKeyValue extends PdfBlock {
  const PdfKeyValue(this.keyText, this.value);
  final String keyText;
  final String value;
}

/// One table row; column widths come from [buildSimplePdf]'s `tableColumns`
/// fractions. Long cells are clipped to their column.
class PdfTableRow extends PdfBlock {
  const PdfTableRow(this.cells, {this.bold = false});
  final List<String> cells;
  final bool bold;
}

/// A horizontal rule.
class PdfDivider extends PdfBlock {
  const PdfDivider();
}

/// Vertical whitespace (points).
class PdfSpacer extends PdfBlock {
  const PdfSpacer([this.height = 8]);
  final double height;
}

// --- Layout constants (A4, points) ---
const double _pageW = 595, _pageH = 842, _margin = 50;
const double _contentW = _pageW - 2 * _margin;

/// Transliterates common report characters to WinAnsi-safe ASCII.
String _sanitize(String s) {
  const map = <String, String>{
    '—': '-', '–': '-', '−': '-', '·': '*', '•': '*',
    '‘': "'", '’': "'", '“': '"', '”': '"',
    '≈': '~', '±': '+/-', '×': 'x', '÷': '/',
    '≥': '>=', '≤': '<=', '→': '->', '←': '<-',
    'µ': 'u', '′': "'", '″': '"', '⟨': '<', '⟩': '>',
    '…': '...', '°': ' deg', '↑': '^', '↓': 'v', '▼': 'v',
  };
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    if (map.containsKey(ch)) {
      b.write(map[ch]);
    } else if (rune >= 32 && rune < 127) {
      b.write(ch);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

/// Escapes a sanitized string for a PDF literal string.
String _escape(String s) =>
    s.replaceAll('\\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

/// Approximate Helvetica advance width of [s] at [size] pt (per-class char
/// widths in em; close enough for conservative word wrapping).
double approxTextWidth(String s, double size) {
  var em = 0.0;
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    if ('iljI.,;:!|\''.contains(ch)) {
      em += 0.28;
    } else if ('ftr()[]"-/ '.contains(ch)) {
      em += 0.36;
    } else if ('mwMW@'.contains(ch)) {
      em += 0.89;
    } else if (ch.toUpperCase() == ch && ch.toLowerCase() != ch) {
      em += 0.70; // capitals
    } else {
      em += 0.53;
    }
  }
  return em * size;
}

/// Greedy word wrap of sanitized [text] to [maxWidth] pt at [size] pt.
List<String> _wrap(String text, double size, double maxWidth) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var line = '';
  for (final w in words) {
    final candidate = line.isEmpty ? w : '$line $w';
    if (approxTextWidth(candidate, size) <= maxWidth || line.isEmpty) {
      line = candidate;
    } else {
      lines.add(line);
      line = w;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines.isEmpty ? <String>[''] : lines;
}

/// Clips [text] to [maxWidth] pt, appending an ellipsis when clipped.
String _clip(String text, double size, double maxWidth) {
  if (approxTextWidth(text, size) <= maxWidth) return text;
  var t = text;
  while (t.isNotEmpty && approxTextWidth('$t...', size) > maxWidth) {
    t = t.substring(0, t.length - 1);
  }
  return '$t...';
}

class _Page {
  final StringBuffer ops = StringBuffer();
}

/// Builds a complete PDF byte stream from [blocks].
///
/// [tableColumns] gives the fraction of the content width for each
/// [PdfTableRow] column (defaults to equal columns of the widest row).
Uint8List buildSimplePdf({
  required String title,
  required List<PdfBlock> blocks,
  List<double>? tableColumns,
}) {
  final pages = <_Page>[_Page()];
  var y = _pageH - _margin;

  void newPageIfNeeded(double needed) {
    if (y - needed < _margin) {
      pages.add(_Page());
      y = _pageH - _margin;
    }
  }

  void text(String s, double size,
      {bool bold = false, double x = _margin, bool gray = false}) {
    final page = pages.last;
    page.ops
      ..writeln(gray ? '0.35 0.42 0.50 rg' : '0.06 0.09 0.16 rg')
      ..writeln('BT /${bold ? 'F2' : 'F1'} $size Tf')
      ..writeln('1 0 0 1 ${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} Tm')
      ..writeln('(${_escape(s)}) Tj ET');
  }

  void rule() {
    final page = pages.last;
    page.ops
      ..writeln('0.78 0.82 0.88 RG 0.7 w')
      ..writeln('$_margin ${y.toStringAsFixed(1)} m '
          '${(_pageW - _margin).toStringAsFixed(1)} '
          '${y.toStringAsFixed(1)} l S');
  }

  // Determine table column fractions.
  var maxCols = 0;
  for (final b in blocks) {
    if (b is PdfTableRow && b.cells.length > maxCols) maxCols = b.cells.length;
  }
  final cols = tableColumns ??
      (maxCols == 0
          ? const <double>[1.0]
          : List<double>.filled(maxCols, 1.0 / maxCols));

  for (final block in blocks) {
    switch (block) {
      case PdfHeading(text: final headingText, :final level):
        final size = level == 1 ? 17.0 : 12.0;
        newPageIfNeeded(size + 14);
        y -= size + (level == 1 ? 4 : 8);
        text(_sanitize(headingText), size, bold: true);
        y -= 4;
      case PdfParagraph(text: final paragraphText, :final size, :final gray):
        for (final line in _wrap(_sanitize(paragraphText), size, _contentW)) {
          newPageIfNeeded(size + 4);
          y -= size + 3;
          text(line, size, gray: gray);
        }
        y -= 2;
      case PdfKeyValue(:final keyText, :final value):
        const size = 10.0;
        newPageIfNeeded(size + 4);
        y -= size + 3;
        final key = _sanitize(keyText);
        text('$key:', size, bold: true);
        text(_sanitize(value), size,
            x: _margin + approxTextWidth('$key:', size) + 6);
      case PdfTableRow(:final cells, :final bold):
        const size = 9.0;
        newPageIfNeeded(size + 5);
        y -= size + 4;
        var x = _margin;
        for (var i = 0; i < cells.length; i++) {
          final w = _contentW * (i < cols.length ? cols[i] : 1.0 / cells.length);
          text(_clip(_sanitize(cells[i]), size, w - 6), size,
              bold: bold, x: x);
          x += w;
        }
      case PdfDivider():
        newPageIfNeeded(10);
        y -= 7;
        rule();
        y -= 3;
      case PdfSpacer(:final height):
        y -= height;
    }
  }

  // Footer with page numbers.
  for (var i = 0; i < pages.length; i++) {
    pages[i].ops
      ..writeln('0.35 0.42 0.50 rg')
      ..writeln('BT /F1 8 Tf 1 0 0 1 $_margin 30 Tm '
          '(${_escape(_sanitize(title))} - page ${i + 1} of ${pages.length}) '
          'Tj ET');
  }

  return _assemble(pages);
}

/// Assembles page content streams into a complete PDF file with xref.
Uint8List _assemble(List<_Page> pages) {
  final objects = <String>[]; // 1-based object bodies (without "N 0 obj")
  // 1: catalog, 2: pages, 3: F1, 4: F2, then per page: page obj + stream obj.
  final pageObjNumbers = <int>[];
  var next = 5;
  final pageEntries = <String>[];
  for (final _ in pages) {
    pageObjNumbers.add(next);
    pageEntries.add('$next 0 R');
    next += 2; // page + its content stream
  }
  objects.add('<< /Type /Catalog /Pages 2 0 R >>'); // 1
  objects.add('<< /Type /Pages /Kids [${pageEntries.join(' ')}] '
      '/Count ${pages.length} >>'); // 2
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>'); // 3
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>'); // 4
  for (var i = 0; i < pages.length; i++) {
    final contentObj = pageObjNumbers[i] + 1;
    objects.add('<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_pageW.toInt()} ${_pageH.toInt()}] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents $contentObj 0 R >>');
    final stream = pages[i].ops.toString();
    objects.add('<< /Length ${stream.length} >>\nstream\n${stream}endstream');
  }

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer
      ..write('${i + 1} 0 obj\n')
      ..write(objects[i])
      ..write('\nendobj\n');
  }
  final xrefStart = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final off in offsets) {
    buffer.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefStart\n%%EOF');

  return Uint8List.fromList(buffer.toString().codeUnits);
}
