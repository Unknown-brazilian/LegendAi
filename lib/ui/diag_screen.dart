import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show kBrandOrange, kBrandBlack;

/// Lê o logcat do próprio app (via canal nativo em MainActivity) e mostra as
/// linhas relevantes para diagnosticar erros de registro de plugin.
class DiagScreen extends StatefulWidget {
  const DiagScreen({super.key});

  @override
  State<DiagScreen> createState() => _DiagScreenState();
}

class _DiagScreenState extends State<DiagScreen> {
  static const _channel = MethodChannel('legendai/diag');

  // Palavras-chave que indicam o problema (erro de plugin/registro/stacktrace).
  static const _keywords = [
    'registering',
    'Exception',
    'file_selector',
    'FileSelector',
    'filepicker',
    'FilePicker',
    'NoClassDef',
    'ClassNotFound',
    'GeneratedPlugin',
    'AndroidRuntime',
    'mlkit',
    'MLKit',
    'flutter',
    'Flutter',
    '\tat ',
    ' at ',
    'E/',
    'E ',
  ];

  String _full = '';
  String _filtered = 'Carregando…';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _channel.invokeMethod<String>('logcat') ?? '';
      final lines = raw.split('\n');
      final hits = lines
          .where((l) => _keywords.any((k) => l.contains(k)))
          .toList();
      final tail = hits.length > 140
          ? hits.sublist(hits.length - 140)
          : hits;
      if (!mounted) return;
      setState(() {
        _full = raw;
        _filtered = tail.isEmpty
            ? '(nenhuma linha relevante encontrada — toque em "Copiar tudo")'
            : tail.join('\n');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _filtered = 'Erro ao ler o log: $e';
        _loading = false;
      });
    }
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _full.isEmpty ? _filtered : _full));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copiado. Cole aqui pro Claude.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: 'Copiar tudo',
            icon: const Icon(Icons.copy_all),
            onPressed: _copyAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: kBrandOrange))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: kBrandBlack,
                child: SelectableText(
                  _filtered,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
    );
  }
}
