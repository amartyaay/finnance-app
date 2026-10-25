/// A word on a statement page with its position, in points from the page's
/// top-left corner. Produced by `readPdfWords` on the device, and by
/// [wordsFromText] in tests (monospaced text fixtures), so the table builder
/// is exercised without a PDF engine.
class PdfWord {
  const PdfWord({
    required this.page,
    required this.x0,
    required this.x1,
    required this.top,
    required this.bottom,
    required this.text,
  });

  final int page;
  final double x0;
  final double x1;
  final double top;
  final double bottom;
  final String text;

  double get height => (bottom - top).abs();

  @override
  String toString() => '$text@${x0.toStringAsFixed(0)}-${x1.toStringAsFixed(0)}';
}

/// Turns monospaced text (one statement line per text line) into positioned
/// words: each character is [charWidth] points wide and each line
/// [lineHeight] points tall. A form feed (`\f`) starts a new page.
///
/// Also the path for SBI's ".xls" download, which is really tab-separated text:
/// callers expand tabs to fixed columns first.
List<PdfWord> wordsFromText(
  String text, {
  double charWidth = 5,
  double lineHeight = 10,
}) {
  final words = <PdfWord>[];
  var page = 1;
  var line = 0;
  for (final raw in text.split('\n')) {
    var row = raw.replaceAll('\r', '');
    if (row.contains('\f')) {
      page++;
      line = 0;
      row = row.replaceAll('\f', '');
    }
    for (final match in RegExp(r'\S+').allMatches(row)) {
      words.add(PdfWord(
        page: page,
        x0: match.start * charWidth,
        x1: match.end * charWidth,
        top: line * lineHeight,
        bottom: line * lineHeight + lineHeight * 0.8,
        text: match.group(0)!,
      ));
    }
    line++;
  }
  return words;
}
