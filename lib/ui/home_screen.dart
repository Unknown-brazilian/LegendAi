import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../services/subtitle_service.dart';
import 'about_screen.dart';
import 'diag_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Busy { idle, downloading, generating }

class _HomeScreenState extends State<HomeScreen> {
  final SubtitleService _service = SubtitleService();

  /// Modelos oferecidos (multilíngues). Maiores = mais precisos, porém mais
  /// lentos e pesados.
  static const Map<WhisperModel, String> _models = {
    WhisperModel.tiny: 'tiny (~75 MB, mais rápido)',
    WhisperModel.base: 'base (~142 MB, recomendado)',
    WhisperModel.small: 'small (~466 MB, mais preciso)',
    WhisperModel.medium: 'medium (~1.5 GB, lento)',
  };

  String? _videoPath;
  int _videoBytes = 0;
  String _sourceLang = 'auto';
  WhisperModel _model = WhisperModel.base;
  final Map<String, bool> _targets = {
    'pt': true,
    'en': true,
    'es': false,
    'fr': false,
    'it': false,
    'de': false,
  };

  _Busy _busy = _Busy.idle;
  String _status = '';
  double? _fraction;

  // Estado dos modelos. O Whisper é checado por arquivo (seguro no boot).
  // O ML Kit NÃO é consultado no boot (evita crash em aparelhos sem/limitado
  // Google Play Services); só após o usuário baixar.
  bool _whisperReady = false;
  bool _langsDownloaded = false;

  // Sem trabalho no boot: a tela só renderiza. O status do modelo é checado
  // sob demanda (ao baixar/gerar), nunca no initState — evita qualquer chamada
  // nativa/IO no arranque que pudesse derrubar o app.

  List<String> get _selectedTargets =>
      _targets.entries.where((e) => e.value).map((e) => e.key).toList();

  Future<void> _refreshWhisperStatus() async {
    try {
      final ready = await _service.isWhisperModelReady(_model);
      if (!mounted) return;
      setState(() => _whisperReady = ready);
    } catch (_) {
      // Sem acesso ao diretório ainda: mantém o estado atual.
    }
  }

  bool get _modelsReady => _whisperReady && _langsDownloaded;

  void _setProgress(String msg, double? frac) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _fraction = frac;
    });
  }

  Future<void> _pickVideo() async {
    try {
      // Seletor de documentos do Android (SAF): mostra os vídeos do
      // armazenamento LOCAL do aparelho. Nada de nuvem/YouTube.
      const typeGroup = XTypeGroup(
        label: 'Vídeos',
        mimeTypes: ['video/*'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return; // cancelado
      final path = file.path;
      setState(() {
        _videoPath = path;
        _videoBytes = File(path).existsSync() ? File(path).lengthSync() : 0;
      });
    } catch (e) {
      _snack('Erro ao abrir o seletor de vídeo: $e');
    }
  }

  Future<void> _downloadModels() async {
    final targets = _selectedTargets;
    if (targets.isEmpty) {
      _snack('Selecione pelo menos um idioma de saída.');
      return;
    }
    setState(() {
      _busy = _Busy.downloading;
      _status = 'Iniciando download…';
      _fraction = null;
    });
    try {
      await _service.downloadAllModels(
        model: _model,
        sourceLang: _sourceLang,
        targetLangs: targets,
        onProgress: _setProgress,
      );
      await _refreshWhisperStatus();
      if (mounted) {
        setState(() => _langsDownloaded = true);
        _snack('Modelos prontos. Já dá pra gerar offline.');
      }
    } catch (e) {
      if (mounted) _snack('Erro no download: $e');
    } finally {
      if (mounted) setState(() => _busy = _Busy.idle);
    }
  }

  Future<void> _generate() async {
    final path = _videoPath;
    if (path == null) return;
    final targets = _selectedTargets;
    if (targets.isEmpty) {
      _snack('Selecione pelo menos um idioma de saída.');
      return;
    }

    setState(() {
      _busy = _Busy.generating;
      _status = 'Iniciando…';
      _fraction = null;
    });

    try {
      final results = await _service.generate(
        videoPath: path,
        model: _model,
        sourceLang: _sourceLang,
        targetLangs: targets,
        onProgress: _setProgress,
      );
      await _refreshWhisperStatus();
      if (mounted) setState(() => _langsDownloaded = true);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultScreen(videoPath: path, results: results),
        ),
      );
    } catch (e) {
      if (mounted) _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = _Busy.idle);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 5)));

  @override
  Widget build(BuildContext context) {
    final fileName = _videoPath?.split('/').last;
    final sizeMb = (_videoBytes / (1024 * 1024)).toStringAsFixed(1);
    final busy = _busy != _Busy.idle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LegendAí'),
        actions: [
          IconButton(
            tooltip: 'Diagnóstico',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sobre',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----- Vídeo -----
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.video_file_outlined),
                      label: const Text('Escolher vídeo'),
                    ),
                    if (fileName != null) ...[
                      const SizedBox(height: 8),
                      Text(fileName,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Text('$sizeMb MB',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ----- Idioma de origem -----
            _label('Idioma da fala (origem)'),
            DropdownButtonFormField<String>(
              initialValue: _sourceLang,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                    value: 'auto', child: Text('Detectar automaticamente')),
                ...kSupportedLanguages.entries.map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) => setState(() {
                _sourceLang = v!;
                _langsDownloaded = false;
              }),
            ),
            const SizedBox(height: 16),

            // ----- Idiomas de saída -----
            _label('Traduzir para (idioma da legenda)'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: kSupportedLanguages.entries.map((e) {
                final on = _targets[e.key] ?? false;
                return FilterChip(
                  label: Text(e.value),
                  selected: on,
                  onSelected: (v) => setState(() {
                    _targets[e.key] = v;
                    _langsDownloaded = false;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ----- Modelo -----
            _label('Modelo Whisper'),
            DropdownButtonFormField<WhisperModel>(
              initialValue: _model,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _models.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                setState(() => _model = v!);
                _refreshWhisperStatus();
              },
            ),
            const SizedBox(height: 16),

            // ----- Download de modelos -----
            _modelsCard(),
            const SizedBox(height: 16),

            // ----- Ação principal -----
            FilledButton.icon(
              onPressed: (busy || _videoPath == null) ? null : _generate,
              icon: const Icon(Icons.subtitles_outlined),
              label: const Text('Gerar legendas'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Em compilação release a transcrição é ~5x mais rápida que em '
                'debug. Modelos maiores são mais precisos, porém mais lentos.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            // ----- Progresso (download ou geração) -----
            if (busy) ...[
              const SizedBox(height: 24),
              Text(
                _busy == _Busy.downloading
                    ? 'Baixando modelos'
                    : 'Gerando legendas',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: _fraction),
              const SizedBox(height: 8),
              Text(
                _fraction != null
                    ? '$_status  (${(_fraction! * 100).toStringAsFixed(0)}%)'
                    : _status,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modelsCard() {
    final ready = _modelsReady;
    return Card(
      color: ready ? Colors.green.withValues(alpha: 0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready ? Icons.check_circle : Icons.cloud_download_outlined,
                  color: ready ? Colors.green : null,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ready
                        ? 'Modelos prontos — funciona offline.'
                        : 'Baixe os modelos (transcrição + tradução) para gerar '
                            'offline.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Whisper "${_model.modelName}": '
              '${_whisperReady ? "✓ baixado" : "✗ falta"}\n'
              'Idiomas: ${_langsDownloaded ? "✓ baixados" : "toque em Baixar (re-baixar é rápido se já existir)"}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed:
                  (_busy != _Busy.idle || ready) ? null : _downloadModels,
              icon: const Icon(Icons.download),
              label: Text(ready
                  ? 'Modelos baixados'
                  : 'Baixar modelo de transcrição e tradução'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}
