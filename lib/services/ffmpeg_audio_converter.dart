import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Conversor de áudio do Whisper usando o `ffmpeg_kit_flutter_new` (full-GPL).
/// Substitui o companion `_min` (cuja lib nativa antiga não carregava no
/// Android 15). Converte qualquer vídeo para WAV 16 kHz mono 16-bit.
class FfmpegAudioConverter implements WhisperAudioConverter {
  @override
  Future<File?> convert(File input) async {
    final output = '${input.path}.wav';
    final outFile = File(output);
    if (await outFile.exists()) {
      await outFile.delete();
    }
    final session = await FFmpegKit.execute(
      '-y -i "${input.path}" -ar 16000 -ac 1 -c:a pcm_s16le "$output"',
    );
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      return outFile;
    }
    return null;
  }
}
