import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/burn_service.dart';
import '../services/subtitle_service.dart';

class ResultScreen extends StatefulWidget {
  final String videoPath;
  final List<GeneratedSubtitle> results;

  const ResultScreen({
    super.key,
    required this.videoPath,
    required this.results,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static const MethodChannel _saveChannel = MethodChannel('legendai/save');
  final BurnService _burner = BurnService();

  // langCode -> caminho do .mp4 legendado já gerado
  final Map<String, String> _burned = {};
  bool _burning = false;
  String? _burningLang;
  double _burnProgress = 0;

  Future<void> _save(
    String path,
    String fileName,
    String mime,
  ) async {
    try {
      final saved = await _saveChannel.invokeMethod<String>('saveToFolder', {
        'fileName': fileName,
        'sourcePath': path,
        'mime': mime,
      });
      if (!mounted) return;
      _snack(saved != null ? 'Salvo: $fileName' : 'Salvamento cancelado');
    } on PlatformException catch (e) {
      if (mounted) _snack('Erro ao salvar: ${e.message}');
    }
  }

  Future<void> _shareFile(String path, String mime, String text) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path, mimeType: mime)], text: text),
    );
  }

  Future<void> _exportVideo(GeneratedSubtitle sub) async {
    setState(() {
      _burning = true;
      _burningLang = sub.langCode;
      _burnProgress = 0;
    });
    try {
      final out = await _burner.burn(
        videoPath: widget.videoPath,
        srtPath: sub.path,
        langCode: sub.langCode,
        onProgress: (p) {
          if (mounted) setState(() => _burnProgress = p);
        },
      );
      if (!mounted) return;
      setState(() => _burned[sub.langCode] = out);
      _snack('Vídeo legendado (${sub.langName}) pronto.');
    } on PlatformException catch (e) {
      if (mounted) _snack('Erro ao gerar vídeo: ${e.message}');
    } catch (e) {
      if (mounted) _snack('Erro ao gerar vídeo: $e');
    } finally {
      if (mounted) {
        setState(() {
          _burning = false;
          _burningLang = null;
        });
      }
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 4)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legendas geradas')),
      body: AbsorbPointer(
        absorbing: _burning,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${widget.results.length} idioma(s) gerado(s) no aparelho. '
              'Salve/compartilhe o .srt, ou exporte o vídeo já legendado.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final r in widget.results) _languageCard(r),
          ],
        ),
      ),
    );
  }

  Widget _languageCard(GeneratedSubtitle r) {
    final mp4 = _burned[r.langCode];
    final burningThis = _burning && _burningLang == r.langCode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.langName} • ${r.segments} legendas',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),

            // ----- .srt -----
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(r.fileName, overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: 'Salvar .srt numa pasta',
                  icon: const Icon(Icons.save),
                  onPressed: _burning
                      ? null
                      : () => _save(r.path, r.fileName, 'application/x-subrip'),
                ),
                IconButton(
                  tooltip: 'Compartilhar .srt',
                  icon: const Icon(Icons.share),
                  onPressed: _burning
                      ? null
                      : () => _shareFile(r.path, 'application/x-subrip',
                          'Legenda ${r.langName} — LegendAí'),
                ),
              ],
            ),

            // ----- vídeo legendado -----
            if (mp4 != null)
              Row(
                children: [
                  const Icon(Icons.movie_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(mp4.split('/').last,
                          overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Salvar vídeo numa pasta',
                    icon: const Icon(Icons.save),
                    onPressed: _burning
                        ? null
                        : () => _save(
                            mp4, mp4.split('/').last, 'video/mp4'),
                  ),
                  IconButton(
                    tooltip: 'Compartilhar vídeo',
                    icon: const Icon(Icons.share),
                    onPressed: _burning
                        ? null
                        : () => _shareFile(mp4, 'video/mp4',
                            'Vídeo legendado ${r.langName} — LegendAí'),
                  ),
                ],
              )
            else if (burningThis) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _burnProgress),
              const SizedBox(height: 4),
              Text(
                'Gerando vídeo legendado… ${(_burnProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: _burning ? null : () => _exportVideo(r),
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: const Text('Exportar vídeo legendado'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
