import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../services/subtitle_service.dart';
import 'about_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

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

  bool _running = false;
  String _status = '';
  double? _fraction;

  Future<void> _pickVideo() async {
    final r = await FilePicker.pickFiles(type: FileType.video);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() {
      _videoPath = path;
      _videoBytes = File(path).existsSync() ? File(path).lengthSync() : 0;
    });
  }

  List<String> get _selectedTargets =>
      _targets.entries.where((e) => e.value).map((e) => e.key).toList();

  Future<void> _generate() async {
    final path = _videoPath;
    if (path == null) return;
    final targets = _selectedTargets;
    if (targets.isEmpty) {
      _snack('Selecione pelo menos um idioma de saída.');
      return;
    }

    setState(() {
      _running = true;
      _status = 'Iniciando…';
      _fraction = null;
    });

    try {
      final results = await _service.generate(
        videoPath: path,
        model: _model,
        sourceLang: _sourceLang,
        targetLangs: targets,
        onProgress: (msg, frac) {
          if (!mounted) return;
          setState(() {
            _status = msg;
            _fraction = frac;
          });
        },
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultScreen(results: results),
        ),
      );
    } catch (e) {
      if (mounted) _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final fileName = _videoPath?.split('/').last;
    final sizeMb = (_videoBytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LegendAí'),
        actions: [
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
        absorbing: _running,
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
              onChanged: (v) => setState(() => _sourceLang = v!),
            ),
            const SizedBox(height: 16),

            // ----- Idiomas de saída -----
            _label('Traduzir para'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: kSupportedLanguages.entries.map((e) {
                final on = _targets[e.key] ?? false;
                return FilterChip(
                  label: Text(e.value),
                  selected: on,
                  onSelected: (v) => setState(() => _targets[e.key] = v),
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
              onChanged: (v) => setState(() => _model = v!),
            ),
            const SizedBox(height: 8),
            Text(
              'Modelos maiores são mais precisos, porém mais lentos e pesados. '
              'O modelo é baixado uma única vez. Em compilação release a '
              'transcrição é ~5x mais rápida que em debug.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),

            // ----- Ação principal -----
            FilledButton.icon(
              onPressed: (_running || _videoPath == null) ? null : _generate,
              icon: const Icon(Icons.subtitles_outlined),
              label: const Text('Gerar legendas'),
            ),

            // ----- Progresso -----
            if (_running) ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(value: _fraction),
              const SizedBox(height: 8),
              Text(_status, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}
