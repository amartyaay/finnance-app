// Gemini Nano's one-word answers map onto verdicts; anything else is "unsure".
import 'package:finnance_app/services/sms/gemini_nano.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one-word answers', () {
    expect(GeminiNano.parse('SPENT'), NanoVerdict.spent);
    expect(GeminiNano.parse(' received.\n'), NanoVerdict.received);
    expect(GeminiNano.parse('Nothing'), NanoVerdict.nothing);
    expect(GeminiNano.parse('I think this is a promotion'), NanoVerdict.unsure);
  });

  test('the prompt carries the sender and the message', () {
    final p = GeminiNano.prompt('JM-HDFCBN-P', 'Rs.500 benefits');
    expect(p, contains('Sender: JM-HDFCBN-P'));
    expect(p, contains('"""Rs.500 benefits"""'));
    expect(p, endsWith('Answer:'));
  });
}
