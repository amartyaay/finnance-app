// Guards against mojibake: UTF-8 text saved through a Windows-1252 round trip
// ("—" becoming "â€”", or "Ã¢â‚¬â€" when it happens twice). Commit bc9e353 put
// that on a card's utilisation ring and in Activity/Insights copy, and no test
// noticed. Every Dart source file the app ships is scanned.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no mojibake in lib/', () {
    // Plus any C1 control character: a stray U+009D after an em dash drew a
    // missing-glyph box in the card ring on the device.
    final bad = RegExp('[ÃÂ][\u0080-¿]|â€|Ã¢|[\u0080-\u009f]');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (bad.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
