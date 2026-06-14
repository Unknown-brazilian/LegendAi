/// Monta o texto de um arquivo `.srt` a partir de uma lista de segmentos
/// legendados, no formato padrão SubRip:
///
/// ```
/// 1
/// 00:00:00,000 --> 00:00:02,500
/// Texto da legenda
///
/// 2
/// ...
/// ```
class SrtWriter {
  /// Gera o conteúdo `.srt` completo a partir dos [subs].
  static String build(List<Subtitle> subs) {
    final b = StringBuffer();
    for (var i = 0; i < subs.length; i++) {
      final s = subs[i];
      b.writeln('${i + 1}');
      b.writeln('${formatTimestamp(s.start)} --> ${formatTimestamp(s.end)}');
      b.writeln(s.text.trim());
      b.writeln();
    }
    return b.toString();
  }

  /// Converte uma [Duration] para o carimbo SRT `HH:MM:SS,mmm`.
  static String formatTimestamp(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }
}

/// Um segmento de legenda: intervalo de tempo + texto.
class Subtitle {
  final Duration start;
  final Duration end;
  final String text;

  const Subtitle(this.start, this.end, this.text);

  Subtitle copyWith({String? text}) =>
      Subtitle(start, end, text ?? this.text);
}
