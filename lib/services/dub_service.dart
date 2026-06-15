import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Gera um vídeo DUBLADO no idioma alvo: sintetiza a fala (TTS nativo) de cada
/// legenda, monta a trilha sincronizada e remuxa com o vídeo (canal
/// `legendai/dub`). 100% on-device.
class DubService {
  static const MethodChannel _channel = MethodChannel('legendai/dub');

  Future<String> dub({
    required String videoPath,
    required String srtPath,
    required String langCode,
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
    final out = '${dir.path}/$base.$langCode.dublado.mp4';
    try {
      final result = await _channel.invokeMethod<String>('dub', {
        'video': videoPath,
        'srt': srtPath,
        'lang': langCode,
        'output': out,
      });
      return result ?? out;
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
