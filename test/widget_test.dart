import 'package:flutter_test/flutter_test.dart';

import 'package:legendai/services/srt_writer.dart';

void main() {
  test('formatTimestamp produz o formato SRT correto', () {
    expect(SrtWriter.formatTimestamp(Duration.zero), '00:00:00,000');
    expect(
      SrtWriter.formatTimestamp(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 456)),
      '01:02:03,456',
    );
  });

  test('build gera blocos SRT numerados', () {
    final srt = SrtWriter.build(const [
      Subtitle(Duration(seconds: 0), Duration(seconds: 2), 'Olá'),
      Subtitle(Duration(seconds: 2), Duration(seconds: 4), 'Mundo'),
    ]);
    expect(srt.contains('1\n00:00:00,000 --> 00:00:02,000\nOlá'), isTrue);
    expect(srt.contains('2\n00:00:02,000 --> 00:00:04,000\nMundo'), isTrue);
  });
}
