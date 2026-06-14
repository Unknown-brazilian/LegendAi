import 'package:flutter/material.dart';

import '../main.dart' show kBrandOrange;

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Icon(Icons.subtitles, size: 64, color: kBrandOrange),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'LegendAí',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: kBrandOrange,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Legendas traduzidas 100% on-device',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 24),
          Text(
            'O LegendAí escolhe um vídeo do aparelho, transcreve a fala no '
            'próprio dispositivo (whisper.cpp), traduz offline (Google ML Kit) '
            'e gera arquivos .srt por idioma.\n\n'
            'Nenhum áudio ou texto sai do aparelho. A internet só é usada na '
            '1ª vez, para baixar o modelo do Whisper e os pares de idioma.',
            style: body,
          ),
          const SizedBox(height: 16),
          Text('Idiomas: Português, Inglês, Espanhol, Francês, Italiano, '
              'Alemão.', style: body),
          const SizedBox(height: 16),
          const Text(
            'Tecnologias: Flutter, whisper_ggml_plus (whisper.cpp), '
            'Google ML Kit (tradução e identificação de idioma offline), '
            'FFmpeg.',
          ),
          const Divider(height: 40),
          Center(
            child: Text(
              'Feito por unknown_BTC_usr e Claude',
              style: body?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
