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

/// Reporta o andamento (mensagem + fração 0..1, ou null = indeterminado).
typedef ProgressCallback = void Function(String message, double? fraction);

/// Pipeline 100% on-device:
/// vídeo → (ffmpeg) WAV 16kHz mono → (whisper.cpp) transcrição com timestamps →
/// (ML Kit, offline) tradução segmento a segmento → arquivos `.srt`.
///
/// Nenhum áudio ou texto sai do aparelho. A rede só é usada na 1ª vez para
/// baixar o modelo do Whisper e os pares de idioma do ML Kit.
class SubtitleService {
  final WhisperController _whisper = WhisperController();

  // ───────────────────────── Modelos / downloads ─────────────────────────

  /// O modelo Whisper [model] já está no aparelho?
  Future<bool> isWhisperModelReady(WhisperModel model) async {
    final f = File(await _whisper.getPath(model));
    return f.existsSync() && await f.length() > 1024 * 1024; // > 1 MB = válido
  }

  /// Idiomas (ML Kit) que ainda faltam baixar dentre [langs] (ignora 'auto').
  Future<List<String>> missingTranslationModels(List<String> langs) async {
    final manager = OnDeviceTranslatorModelManager();
    final missing = <String>[];
    for (final code in langs.toSet()) {
      final ml = _mlKitLang(code);
      if (ml == null) continue;
      if (!await manager.isModelDownloaded(ml.bcpCode)) missing.add(code);
    }
    return missing;
  }

  /// Baixa o modelo Whisper [model] em streaming, reportando o % em [onProgress].
  /// Grava no caminho exato que o whisper.cpp espera. Idempotente.
  Future<void> downloadWhisperModel(
    WhisperModel model,
    ProgressCallback onProgress,
  ) async {
    if (await isWhisperModelReady(model)) return;

    final path = await _whisper.getPath(model);
    final file = File(path);
    final tmp = File('$path.part');
    final client = HttpClient();
    try {
      final request = await client.getUrl(model.modelUri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
            'Falha ao baixar modelo Whisper (HTTP ${response.statusCode}).');
      }
      final total = response.contentLength; // -1 se desconhecido
      final sink = tmp.openWrite();
      int received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        final mb = (received / (1024 * 1024)).toStringAsFixed(0);
        if (total > 0) {
          onProgress(
            'Baixando modelo "${model.modelName}"… $mb MB',
            received / total,
          );
        } else {
          onProgress('Baixando modelo "${model.modelName}"… $mb MB', null);
        }
      }
      await sink.flush();
      await sink.close();
      await tmp.rename(path);
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Baixa os modelos de idioma do ML Kit (offline) para [langs]. Sem % real
  /// (a API do ML Kit não expõe progresso), então reporta por idioma.
  Future<void> downloadTranslationModels(
    List<String> langs,
    ProgressCallback onProgress,
  ) async {
    final manager = OnDeviceTranslatorModelManager();
    for (final code in langs.toSet()) {
      final ml = _mlKitLang(code);
      if (ml == null) continue;
      if (await manager.isModelDownloaded(ml.bcpCode)) continue;
      onProgress('Baixando idioma ${kSupportedLanguages[code]}…', null);
      await manager.downloadModel(ml.bcpCode, isWifiRequired: false);
    }
  }

  /// Baixa tudo o que falta para [model], idioma de origem [sourceLang] e os
  /// [targetLangs]. Whisper com %, idiomas ML Kit por etapa.
  Future<void> downloadAllModels({
    required WhisperModel model,
    required String sourceLang,
    required List<String> targetLangs,
    required ProgressCallback onProgress,
  }) async {
    await downloadWhisperModel(model, onProgress);

    // Idiomas necessários para traduzir. Se a origem for "auto", baixamos
    // todos os suportados (o idioma detectado pode ser qualquer um).
    final langs = <String>{...targetLangs};
    if (sourceLang == 'auto') {
      langs.addAll(kSupportedLanguages.keys);
    } else {
      langs.add(sourceLang);
    }
    await downloadTranslationModels(langs.toList(), onProgress);
    onProgress('Modelos prontos.', 1.0);
  }

  /// Garante o modelo Whisper (usado pelo pipeline se o usuário não baixou antes).
  Future<void> ensureModel(WhisperModel model, ProgressCallback onProgress) =>
      downloadWhisperModel(model, onProgress);

  // ───────────────────────────── Pipeline ─────────────────────────────

  /// Transcreve [videoPath]. A conversão para WAV 16kHz acontece dentro do
  /// whisper_ggml_plus via o conversor FFmpeg registrado em [main].
  Future<List<Subtitle>> transcribe({
    required String videoPath,
    required WhisperModel model,
    required String lang, // 'auto' ou código
    required ProgressCallback onProgress,
  }) async {
    onProgress('Extraindo áudio e transcrevendo no aparelho…', null);
    final result = await _whisper.transcribe(
      model: model,
      audioPath: videoPath,
      lang: lang,
      withTimestamps: true,
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

  /// Detecta o idioma da fala a partir do texto transcrito (offline).
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

  /// Traduz [subs] de [from] para [to] preservando timestamps. Offline.
  /// Reporta progresso determinado (segmento a segmento).
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

    // Garante os modelos do par (caso o usuário não tenha baixado antes).
    await downloadTranslationModels([from, to], onProgress);

    final translator =
        OnDeviceTranslator(sourceLanguage: src, targetLanguage: tgt);
    final out = <Subtitle>[];
    try {
      final toName = kSupportedLanguages[to];
      for (var i = 0; i < subs.length; i++) {
        final s = subs[i];
        final translated = await translator.translateText(s.text);
        out.add(s.copyWith(text: translated));
        onProgress(
          'Traduzindo para $toName… (${i + 1}/${subs.length})',
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

  /// Pipeline completo: transcreve uma vez e gera um `.srt` **no idioma de cada
  /// alvo** (traduzido — nunca no idioma original, a menos que o alvo seja o
  /// próprio idioma da fala).
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
      // Legenda SEMPRE no idioma alvo: se o alvo == idioma da fala, usa a
      // transcrição; senão, traduz cada segmento para o alvo.
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
    onProgress('Concluído.', 1.0);
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
