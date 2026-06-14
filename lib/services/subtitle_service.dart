import 'dart:io';

import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import 'srt_writer.dart';

/// Idiomas suportados na v1 (origem e destino).
const Map<String, String> kSupportedLanguages = {
  'pt': 'Português',
  'en': 'Inglês',
  'es': 'Espanhol',
  'fr': 'Francês',
  'it': 'Italiano',
  'de': 'Alemão',
};

/// Resultado de um `.srt` gerado para um idioma.
class GeneratedSubtitle {
  final String langCode;
  final String langName;
  final String fileName;
  final String path;
  final int segments;

  const GeneratedSubtitle({
    required this.langCode,
    required this.langName,
    required this.fileName,
    required this.path,
    required this.segments,
  });
}

/// Reporta o andamento do pipeline para a UI.
typedef ProgressCallback = void Function(String message, double? fraction);

/// Pipeline 100% on-device:
/// vídeo → (ffmpeg) WAV 16kHz mono → (whisper.cpp) transcrição com timestamps →
/// (ML Kit, offline) tradução segmento a segmento → arquivos `.srt`.
///
/// Nenhum áudio ou texto sai do aparelho. A rede só é usada na 1ª vez para
/// baixar o modelo do Whisper e os pares de idioma do ML Kit.
class SubtitleService {
  final WhisperController _whisper = WhisperController();

  /// Garante que o modelo Whisper escolhido está no aparelho (baixa na 1ª vez).
  Future<void> ensureModel(WhisperModel model, ProgressCallback onProgress) async {
    final path = await _whisper.getPath(model);
    if (File(path).existsSync()) return;
    onProgress(
      'Baixando modelo Whisper "${model.modelName}" (só na 1ª vez)…',
      null,
    );
    await _whisper.downloadModel(model);
  }

  /// Transcreve [videoPath]. A conversão para WAV 16kHz acontece dentro do
  /// whisper_ggml_plus via o conversor FFmpeg registrado em [main].
  ///
  /// [lang] é um código ('pt','en',…) ou 'auto' para deixar o whisper detectar.
  Future<List<Subtitle>> transcribe({
    required String videoPath,
    required WhisperModel model,
    required String lang,
    required ProgressCallback onProgress,
  }) async {
    onProgress('Extraindo áudio e transcrevendo no aparelho…', null);
    final result = await _whisper.transcribe(
      model: model,
      audioPath: videoPath,
      lang: lang,
      withTimestamps: true,
      // convert: true (default) → usa o WhisperFFmpegConverter registrado.
    );

    final segments = result?.transcription.segments ?? const [];
    final subs = <Subtitle>[];
    for (final s in segments) {
      final text = s.text.trim();
      if (text.isEmpty) continue;
      subs.add(Subtitle(s.fromTs, s.toTs, text));
    }
    return subs;
  }

  /// Detecta o idioma de origem a partir do texto transcrito (offline).
  /// Retorna um código suportado ('pt','en',…) ou `null` se indeterminado.
  Future<String?> detectLanguage(List<Subtitle> subs) async {
    if (subs.isEmpty) return null;
    final sample = subs.map((s) => s.text).join(' ');
    final identifier = LanguageIdentifier(confidenceThreshold: 0.4);
    try {
      final code = await identifier.identifyLanguage(sample);
      if (kSupportedLanguages.containsKey(code)) return code;
      return null;
    } catch (_) {
      return null;
    } finally {
      await identifier.close();
    }
  }

  /// Traduz [subs] de [from] para [to] preservando os timestamps. Offline.
  /// Baixa o par de idiomas na 1ª vez.
  Future<List<Subtitle>> translate({
    required List<Subtitle> subs,
    required String from,
    required String to,
    required ProgressCallback onProgress,
  }) async {
    if (from == to) return subs;
    final src = _mlKitLang(from);
    final tgt = _mlKitLang(to);
    if (src == null || tgt == null) return subs;

    onProgress(
      'Preparando tradução ${kSupportedLanguages[from]} → '
      '${kSupportedLanguages[to]} (baixa o par na 1ª vez)…',
      null,
    );
    final manager = OnDeviceTranslatorModelManager();
    if (!await manager.isModelDownloaded(src.bcpCode)) {
      await manager.downloadModel(src.bcpCode, isWifiRequired: false);
    }
    if (!await manager.isModelDownloaded(tgt.bcpCode)) {
      await manager.downloadModel(tgt.bcpCode, isWifiRequired: false);
    }

    final translator =
        OnDeviceTranslator(sourceLanguage: src, targetLanguage: tgt);
    final out = <Subtitle>[];
    try {
      for (var i = 0; i < subs.length; i++) {
        final s = subs[i];
        final translated = await translator.translateText(s.text);
        out.add(s.copyWith(text: translated));
        onProgress(
          'Traduzindo para ${kSupportedLanguages[to]}… (${i + 1}/${subs.length})',
          (i + 1) / subs.length,
        );
      }
    } finally {
      await translator.close();
    }
    return out;
  }

  /// Escreve um `.srt` para [langCode] e devolve os metadados.
  Future<GeneratedSubtitle> writeSrt({
    required List<Subtitle> subs,
    required String baseName,
    required String langCode,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '$baseName.$langCode.srt';
    final path = '${dir.path}/$fileName';
    await File(path).writeAsString(SrtWriter.build(subs));
    return GeneratedSubtitle(
      langCode: langCode,
      langName: kSupportedLanguages[langCode] ?? langCode,
      fileName: fileName,
      path: path,
      segments: subs.length,
    );
  }

  /// Pipeline completo: transcreve uma vez e gera um `.srt` por idioma alvo.
  Future<List<GeneratedSubtitle>> generate({
    required String videoPath,
    required WhisperModel model,
    required String sourceLang, // 'auto' ou código
    required List<String> targetLangs,
    required ProgressCallback onProgress,
  }) async {
    await ensureModel(model, onProgress);

    final source = await transcribe(
      videoPath: videoPath,
      model: model,
      lang: sourceLang,
      onProgress: onProgress,
    );
    if (source.isEmpty) {
      throw Exception('Nenhuma fala detectada no vídeo.');
    }

    var detected = sourceLang;
    if (sourceLang == 'auto') {
      onProgress('Detectando idioma da fala…', null);
      detected = await detectLanguage(source) ?? 'en';
    }

    final base = _baseName(videoPath);
    final results = <GeneratedSubtitle>[];
    for (final target in targetLangs) {
      final subs = (target == detected)
          ? source
          : await translate(
              subs: source,
              from: detected,
              to: target,
              onProgress: onProgress,
            );
      onProgress('Gerando .srt (${kSupportedLanguages[target]})…', null);
      results.add(await writeSrt(
        subs: subs,
        baseName: base,
        langCode: target,
      ));
    }
    return results;
  }

  String _baseName(String path) {
    final file = path.split('/').last;
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  TranslateLanguage? _mlKitLang(String code) {
    switch (code) {
      case 'pt':
        return TranslateLanguage.portuguese;
      case 'en':
        return TranslateLanguage.english;
      case 'es':
        return TranslateLanguage.spanish;
      case 'fr':
        return TranslateLanguage.french;
      case 'it':
        return TranslateLanguage.italian;
      case 'de':
        return TranslateLanguage.german;
      default:
        return null;
    }
  }
}
