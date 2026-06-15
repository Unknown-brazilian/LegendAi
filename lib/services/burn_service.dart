import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Estilo da legenda queimada no vídeo.
class SubtitleStyle {
  final String font; // sans | serif | mono | condensed | casual | custom
  final double sizeScale; // fração da altura (0.035 / 0.045 / 0.058)
  final int color; // ARGB
  final String? fontPath; // caminho de uma fonte .ttf/.otf importada

  const SubtitleStyle({
    this.font = 'sans',
    this.sizeScale = 0.045,
    this.color = 0xFFFFFFFF,
    this.fontPath,
  });
}

/// Queima a legenda (.srt) no vídeo e gera um .mp4 legendado, via o pipeline
/// nativo MediaCodec+OpenGL (canal `legendai/burn`). Sem ffmpeg.
class BurnService {
  static const MethodChannel _channel = MethodChannel('legendai/burn');

  Future<String> burn({
    required String videoPath,
    required String srtPath,
    required String langCode,
    required SubtitleStyle style,
    required void Function(double) onProgress,
  }) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final v = (call.arguments as num).toDouble();
        onProgress(v.clamp(0.0, 1.0));
      }
      return null;
    });
    final dir = await getApplicationDocumentsDirectory();
    final file = videoPath.split('/').last;
    final dot = file.lastIndexOf('.');
    final base = dot > 0 ? file.substring(0, dot) : file;
    final out = '${dir.path}/$base.$langCode.legendado.mp4';
    try {
      final result = await _channel.invokeMethod<String>('burn', {
        'video': videoPath,
        'srt': srtPath,
        'output': out,
        'font': style.font,
        'size': style.sizeScale,
        'color': style.color,
        'fontPath': style.fontPath,
      });
      return result ?? out;
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
