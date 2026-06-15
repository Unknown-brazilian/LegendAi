import 'package:flutter/material.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import 'services/native_audio_converter.dart';
import 'ui/splash_screen.dart';

/// Cores da marca (mesma linguagem visual do AnotAí).
const Color kBrandOrange = Color(0xFFF7931A);
const Color kBrandBlack = Color(0xFF0D0D0D);

/// Versão exibida na splash. Manter em sincronia com `version:` no pubspec.
const String kAppVersion = '1.3.1';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Mostra erros de build na tela (laranja sobre preto) em vez de tela cinza/
  // preta. Não usa runZonedGuarded (que pode causar tela preta por zona).
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: kBrandBlack,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: Text(
                'LegendAí — erro:\n\n${details.exceptionAsString()}',
                style: const TextStyle(color: kBrandOrange, fontSize: 13),
              ),
            ),
          ),
        ),
      );

  // Conversor de áudio nativo (MediaCodec) no motor do Whisper. Sem ffmpeg
  // (a lib nativa do ffmpeg-kit não carrega no Android 15).
  try {
    WhisperController.registerAudioConverter(NativeAudioConverter());
  } catch (e) {
    debugPrint('Falha ao registrar conversor de áudio: $e');
  }
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
      home: const SplashScreen(),
    );
  }
}
