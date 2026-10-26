/// Opens a (possibly password-protected) statement PDF on the device and
/// returns every word with its position, which is what the table builder needs:
/// SBI's statement layouts cannot be recovered from plain text (amounts drift
/// lines away from their narration), but they can from x/y coordinates.
///
/// PDFium (via pdfrx) runs fully offline; the password lives only in this call
/// and is never stored, logged or put in an exception message.
library;

import 'package:pdfrx/pdfrx.dart';

import 'statement_words.dart';

sealed class PdfOpenError implements Exception {
  const PdfOpenError();
}

/// The file is encrypted and no password was given.
class PdfNeedsPassword extends PdfOpenError {
  const PdfNeedsPassword();
}

/// A password was given and it did not open the file.
class PdfWrongPassword extends PdfOpenError {
  const PdfWrongPassword();
}

/// Not a readable PDF (corrupt, or not a PDF at all).
class PdfUnreadable extends PdfOpenError {
  const PdfUnreadable();
}

/// [initialize] defaults to the Flutter initializer (app cache dir via
/// path_provider); host tests pass `pdfrxInitialize` from pdfrx_engine.
Future<List<PdfWord>> readPdfWords(
  String path, {
  String? password,
  Future<void> Function()? initialize,
}) async {
  await (initialize ?? pdfrxFlutterInitialize)();
  final PdfDocument doc;
  try {
    // pdfrx tries an empty password first, then [password] once.
    doc = await PdfDocument.openFile(
      path,
      passwordProvider: createSimplePasswordProvider(
        password == null || password.isEmpty ? null : password,
      ),
    );
  } on PdfPasswordException {
    throw (password == null || password.isEmpty)
        ? const PdfNeedsPassword()
        : const PdfWrongPassword();
  } on PdfException {
    throw const PdfUnreadable();
  }

  try {
    final words = <PdfWord>[];
    for (final page in doc.pages) {
      final raw = await page.loadText();
      if (raw == null) continue;
      final height = page.height;
      var buffer = StringBuffer();
      PdfRect? box;
      void flush() {
        final b = box;
        if (b != null && buffer.isNotEmpty) {
          // PDF y grows upwards; the table builder wants "points from the top".
          words.add(PdfWord(
            page: page.pageNumber,
            x0: b.left,
            x1: b.right,
            top: height - b.top,
            bottom: height - b.bottom,
            text: buffer.toString(),
          ));
        }
        buffer = StringBuffer();
        box = null;
      }

      final count = raw.fullText.length < raw.charRects.length
          ? raw.fullText.length
          : raw.charRects.length;
      // PDFium's boxes are tight glyph boxes (a "." is ~1 pt tall), so gaps
      // are measured against the page's median glyph height, not the
      // current glyph's — otherwise "0.00" falls apart into "0", ".", "00".
      final heights = <double>[
        for (var i = 0; i < count; i++)
          if (raw.fullText[i].trim().isNotEmpty && raw.charRects[i].isNotEmpty)
            raw.charRects[i].top - raw.charRects[i].bottom,
      ]..sort();
      final unit = heights.isEmpty ? 5.0 : heights[heights.length ~/ 2];
      for (var i = 0; i < count; i++) {
        final char = raw.fullText[i];
        final rect = raw.charRects[i];
        if (char.trim().isEmpty || rect.isEmpty) {
          flush();
          continue;
        }
        final current = box;
        if (current != null) {
          // A real space ends a word above; this catches cells laid out by
          // position with no space character between them.
          final gap = rect.left - current.right;
          final otherLine = (rect.bottom - current.bottom).abs() > unit * 0.6;
          if (gap > unit || gap < -unit || otherLine) flush();
        }
        box = box == null ? rect : box!.merge(rect);
        buffer.write(char);
      }
      flush();
    }
    return words;
  } finally {
    await doc.dispose();
  }
}
