import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show kBrandOrange, kBrandBlack, kAppVersion;
import 'home_screen.dart';

/// Tela de carregamento: logo + nome + versão. Sem trabalho pesado no boot —
/// apenas um timer curto antes de ir para a Home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBrandBlack,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo: tile laranja com balão de legenda (mesma ideia do ícone).
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x22F7931A), Color(0x44F7931A)],
                ),
                border: Border.all(color: kBrandOrange, width: 2),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.subtitles,
                  size: 56, color: kBrandOrange),
            ),
            const SizedBox(height: 22),
            const Text(
              'LegendAí',
              style: TextStyle(
                color: kBrandOrange,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Legendas traduzidas 100% on-device',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(kBrandOrange),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'v$kAppVersion',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
