import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/subtitle_service.dart';

class ResultScreen extends StatelessWidget {
  final List<GeneratedSubtitle> results;

  const ResultScreen({super.key, required this.results});

  static const MethodChannel _saveChannel = MethodChannel('legendai/save');

  /// Salva o `.srt` numa pasta/local escolhido pelo usuário (SAF "Salvar como").
  Future<void> _save(BuildContext context, GeneratedSubtitle sub) async {
    try {
      final saved = await _saveChannel.invokeMethod<String>('saveToFolder', {
        'fileName': sub.fileName,
        'sourcePath': sub.path,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved != null ? 'Salvo: ${sub.fileName}' : 'Salvamento cancelado',
          ),
        ),
      );
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: ${e.message}')),
      );
    }
  }

  /// Compartilha o `.srt` (apps, e-mail, etc.).
  Future<void> _share(GeneratedSubtitle sub) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(sub.path, mimeType: 'application/x-subrip')],
        text: 'Legenda ${sub.langName} — LegendAí',
      ),
    );
  }

  Future<void> _shareAll() async {
    await SharePlus.instance.share(
      ShareParams(
        files: results
            .map((r) => XFile(r.path, mimeType: 'application/x-subrip'))
            .toList(),
        text: 'Legendas geradas pelo LegendAí',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legendas geradas'),
        actions: [
          if (results.length > 1)
            IconButton(
              tooltip: 'Compartilhar todas',
              icon: const Icon(Icons.ios_share),
              onPressed: _shareAll,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${results.length} arquivo(s) .srt gerado(s) no aparelho. '
            'Toque no disquete para salvar numa pasta, ou no compartilhar para '
            'enviar.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final r in results)
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(r.fileName),
                subtitle: Text('${r.langName} • ${r.segments} legendas'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Salvar numa pasta',
                      icon: const Icon(Icons.save),
                      onPressed: () => _save(context, r),
                    ),
                    IconButton(
                      tooltip: 'Compartilhar',
                      icon: const Icon(Icons.share),
                      onPressed: () => _share(r),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
