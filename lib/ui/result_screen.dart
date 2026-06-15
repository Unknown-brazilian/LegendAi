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
  static const MethodChannel _pickChannel = MethodChannel('legendai/pick');
  final BurnService _burner = BurnService();

  String? _fontPath; // fonte .ttf/.otf importada
  String? _customFontName;

  static const Map<String, String> _fonts = {
    'sans': 'Padrão',
    'serif': 'Serifada',
    'mono': 'Monoespaçada',
    'condensed': 'Condensada',
    'casual': 'Manuscrita',
  };
  static final Map<double, String> _sizes = {
    0.035: 'Pequena',
    0.045: 'Média',
    0.058: 'Grande',
  };
  static const Map<int, String> _colors = {
    0xFFFFFFFF: 'Branco',
    0xFFFFEB3B: 'Amarelo',
    0xFF00E676: 'Verde',
    0xFF40C4FF: 'Azul',
  };

  String _font = 'sans';
  double _sizeScale = 0.045;
  int _color = 0xFFFFFFFF;

  final Map<String, String> _burned = {}; // langCode -> .mp4 legendado
  bool _busy = false;
  String? _busyLang;
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

  Future<void> _importFont() async {
    try {
      final res = await _pickChannel.invokeMethod<Map>('pickFont');
      if (res == null) return; // cancelado
      if (!mounted) return;
      setState(() {
        _fontPath = res['path'] as String?;
        _customFontName = res['name'] as String?;
        _font = 'custom';
      });
      _snack('Fonte importada: ${_customFontName ?? ''}');
    } on PlatformException catch (e) {
      if (mounted) _snack('Erro ao importar fonte: ${e.message}');
    }
  }

  Future<void> _exportVideo(GeneratedSubtitle sub) async {
    setState(() {
      _busy = true;
      _busyLang = sub.langCode;
      _progress = 0;
    });
    try {
      final out = await _burner.burn(
        videoPath: widget.videoPath,
        srtPath: sub.path,
        langCode: sub.langCode,
        style: SubtitleStyle(
          font: _font,
          sizeScale: _sizeScale,
          color: _color,
          fontPath: _font == 'custom' ? _fontPath : null,
        ),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
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
          _busy = false;
          _busyLang = null;
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
              'Salve/compartilhe o .srt ou exporte o vídeo já legendado.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _styleCard(),
            const SizedBox(height: 12),
            for (final r in widget.results) _languageCard(r),
          ],
        ),
      ),
    );
  }

  Widget _styleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Estilo da legenda no vídeo',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Aplica-se ao "Exportar vídeo legendado".',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _fontDropdown()),
                const SizedBox(width: 8),
                Expanded(
                  child: _dropdown<double>(
                    label: 'Tamanho',
                    value: _sizeScale,
                    items: _sizes,
                    onChanged: (v) => setState(() => _sizeScale = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _importFont,
                icon: const Icon(Icons.font_download_outlined, size: 18),
                label: Text(_fontPath != null
                    ? 'Trocar fonte importada'
                    : 'Importar fonte (.ttf/.otf)'),
              ),
            ),
            const SizedBox(height: 8),
            _dropdown<int>(
              label: 'Cor',
              value: _color,
              items: _colors,
              onChanged: (v) => setState(() => _color = v),
            ),
            const SizedBox(height: 12),
            // Prévia
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                'Exemplo de legenda',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(_color),
                  fontWeight: FontWeight.bold,
                  fontSize: 13 + (_sizeScale - 0.035) / 0.023 * 7,
                  fontFamily: _flutterFont(_font),
                  shadows: const [
                    Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Aproximação da fonte só para a prévia na tela.
  String? _flutterFont(String key) {
    switch (key) {
      case 'serif':
        return 'serif';
      case 'mono':
        return 'monospace';
      default:
        return null;
    }
  }

  Widget _fontDropdown() {
    final entries = <DropdownMenuItem<String>>[
      for (final e in _fonts.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
      if (_fontPath != null)
        DropdownMenuItem(
          value: 'custom',
          child: Text(
            _customFontName ?? 'Importada',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    return DropdownButtonFormField<String>(
      initialValue: _font,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Fonte',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: entries,
      onChanged: _busy ? null : (v) => setState(() => _font = v!),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: _busy ? null : (v) => onChanged(v as T),
    );
  }

  Widget _languageCard(GeneratedSubtitle r) {
    final mp4 = _burned[r.langCode];
    final busyThis = _busy && _busyLang == r.langCode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.langName} • ${r.segments} legendas',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            _fileRow(
              icon: Icons.description_outlined,
              name: r.fileName,
              path: r.path,
              mime: 'application/x-subrip',
              shareText: 'Legenda ${r.langName} — LegendAí',
            ),
            const SizedBox(height: 8),
            if (mp4 != null)
              _fileRow(
                icon: Icons.movie_outlined,
                name: mp4.split('/').last,
                path: mp4,
                mime: 'video/mp4',
                shareText: 'Vídeo legendado ${r.langName} — LegendAí',
              )
            else if (busyThis) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text('Gerando vídeo legendado… ${(_progress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _exportVideo(r),
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: const Text('Exportar vídeo legendado'),
                ),
              ),
          ],
        ),
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
