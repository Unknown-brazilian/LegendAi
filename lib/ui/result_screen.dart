import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/subtitle_service.dart';

class ResultScreen extends StatelessWidget {
  final List<GeneratedSubtitle> results;

  const ResultScreen({super.key, required this.results});

  /// Compartilha/salva um `.srt`. A folha de compartilhamento do Android inclui
  /// "Salvar em Arquivos/Drive", então cobre salvar numa pasta e compartilhar.
  Future<void> _shareOne(GeneratedSubtitle sub) async {
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
            'Toque em Salvar/Compartilhar e escolha "Salvar em Arquivos" para '
            'guardar numa pasta, ou um app para compartilhar.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final r in results)
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(r.fileName),
                subtitle: Text('${r.langName} • ${r.segments} legendas'),
                trailing: IconButton(
                  tooltip: 'Salvar / Compartilhar',
                  icon: const Icon(Icons.share),
                  onPressed: () => _shareOne(r),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
