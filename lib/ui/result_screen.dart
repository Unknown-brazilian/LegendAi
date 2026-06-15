import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/burn_service.dart';
import '../services/dub_service.dart';
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
  final DubService _dubber = DubService();

  final Map<String, String> _burned = {}; // langCode -> .mp4 legendado
  final Map<String, String> _dubbed = {}; // langCode -> .mp4 dublado

  bool _busy = false;
  String? _busyLang;
  String? _busyKind; // 'legendado' | 'dublado'
  double _progress = 0;

  Future<void> _save(String path, String fileName, String mime) async {
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

  Future<void> _export(GeneratedSubtitle sub, String kind) async {
    setState(() {
      _busy = true;
      _busyLang = sub.langCode;
      _busyKind = kind;
      _progress = 0;
    });
    try {
      final out = kind == 'legendado'
          ? await _burner.burn(
              videoPath: widget.videoPath,
              srtPath: sub.path,
              langCode: sub.langCode,
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
            )
          : await _dubber.dub(
              videoPath: widget.videoPath,
              srtPath: sub.path,
              langCode: sub.langCode,
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
            );
      if (!mounted) return;
      setState(() {
        if (kind == 'legendado') {
          _burned[sub.langCode] = out;
        } else {
          _dubbed[sub.langCode] = out;
        }
      });
      _snack('Vídeo $kind (${sub.langName}) pronto.');
    } on PlatformException catch (e) {
      if (mounted) _snack('Erro ($kind): ${e.message}');
    } catch (e) {
      if (mounted) _snack('Erro ($kind): $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLang = null;
          _busyKind = null;
        });
      }
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 4)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resultado')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${widget.results.length} idioma(s) gerado(s) no aparelho. '
              'Salve/compartilhe o .srt, exporte o vídeo legendado, ou o vídeo '
              'dublado no idioma alvo.',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.langName} • ${r.segments} legendas',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),

            // .srt
            _fileRow(
              icon: Icons.description_outlined,
              name: r.fileName,
              path: r.path,
              mime: 'application/x-subrip',
              shareText: 'Legenda ${r.langName} — LegendAí',
            ),
            const SizedBox(height: 8),

            // vídeo legendado
            _exportSection(r, 'legendado', _burned[r.langCode],
                Icons.subtitles_outlined, 'Exportar vídeo legendado'),
            const SizedBox(height: 8),

            // vídeo dublado
            _exportSection(r, 'dublado', _dubbed[r.langCode],
                Icons.record_voice_over_outlined, 'Exportar vídeo dublado'),
          ],
        ),
      ),
    );
  }

  Widget _exportSection(
    GeneratedSubtitle r,
    String kind,
    String? donePath,
    IconData icon,
    String label,
  ) {
    final busyThis = _busy && _busyLang == r.langCode && _busyKind == kind;
    if (donePath != null) {
      return _fileRow(
        icon: Icons.movie_outlined,
        name: donePath.split('/').last,
        path: donePath,
        mime: 'video/mp4',
        shareText: 'Vídeo $kind ${r.langName} — LegendAí',
      );
    }
    if (busyThis) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4),
          Text(
            'Gerando vídeo $kind… ${(_progress * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : () => _export(r, kind),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _fileRow({
    required IconData icon,
    required String name,
    required String path,
    required String mime,
    required String shareText,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
        IconButton(
          tooltip: 'Salvar numa pasta',
          icon: const Icon(Icons.save),
          onPressed: _busy ? null : () => _save(path, name, mime),
        ),
        IconButton(
          tooltip: 'Compartilhar',
          icon: const Icon(Icons.share),
          onPressed: _busy ? null : () => _shareFile(path, mime, shareText),
        ),
      ],
    );
  }
}
