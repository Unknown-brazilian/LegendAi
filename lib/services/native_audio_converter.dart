import 'dart:io';

import 'package:flutter/services.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Conversor de áudio do Whisper usando o MediaCodec NATIVO do Android
/// (canal `legendai/audio` em MainActivity). Substitui o ffmpeg-kit, cuja lib
/// nativa não carrega no Android 15. Gera WAV 16 kHz mono 16-bit a partir da
/// trilha de áudio do vídeo — só com APIs nativas do Android (sem libs frágeis).
class NativeAudioConverter implements WhisperAudioConverter {
  static const MethodChannel _channel = MethodChannel('legendai/audio');

  @override
  Future<File?> convert(File input) async {
    final output = '${input.path}.wav';
    try {
      final result = await _channel.invokeMethod<String>('toWav16kMono', {
        'input': input.path,
        'output': output,
      });
      if (result == null) return null;
      final f = File(result);
      return await f.exists() ? f : null;
    } on PlatformException {
      return null;
    }
  }
}
