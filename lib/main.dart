import 'package:flutter/material.dart';
import 'package:whisper_ggml_plus_ffmpeg/whisper_ggml_plus_ffmpeg.dart';

import 'ui/home_screen.dart';

/// Cores da marca (mesma linguagem visual do AnotAí).
const Color kBrandOrange = Color(0xFFF7931A);
const Color kBrandBlack = Color(0xFF0D0D0D);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Registra o conversor FFmpeg no motor do whisper_ggml_plus. A partir daqui,
  // transcrever um vídeo converte o áudio para WAV 16kHz mono automaticamente.
  WhisperFFmpegConverter.register();
  runApp(const LegendAiApp());
}

class LegendAiApp extends StatelessWidget {
  const LegendAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kBrandOrange,
      brightness: Brightness.dark,
    ).copyWith(
      primary: kBrandOrange,
      surface: kBrandBlack,
    );

    return MaterialApp(
      title: 'LegendAí',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBrandBlack,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBrandBlack,
          foregroundColor: kBrandOrange,
          centerTitle: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kBrandOrange,
            foregroundColor: kBrandBlack,
            minimumSize: const Size.fromHeight(52),
            textStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
