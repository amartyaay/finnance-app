// Every TextStyle literal names the bundled family. A ButtonStyle.textStyle
// *replaces* the theme's style, so one without a family silently falls back
// to the platform font — every button in the app shipped that way once.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every TextStyle literal in lib/ sets fontFamily', () {
    final offenders = <String>[];
    final literal = RegExp(r'(?<![A-Za-z_.])TextStyle\(');
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      for (final m in literal.allMatches(text)) {
        final window = text.substring(m.end, (m.end + 120).clamp(0, text.length));
        if (!window.contains('fontFamily')) {
          final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
