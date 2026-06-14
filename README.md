# LegendAí

**Legendas traduzidas 100% on-device.** App Android (Flutter) que escolhe um
vídeo do aparelho, transcreve a fala **no próprio dispositivo**, traduz **offline**
e gera arquivos `.srt` (closed caption) em vários idiomas — para salvar ou
compartilhar.

> O nome vem do trocadilho com "anota aí" → **legenda aí**, na mesma família do AnotAí.

## 100% no aparelho

Nenhum áudio ou texto sai do dispositivo. A internet só é usada **uma vez**, para
baixar o modelo do Whisper e os pares de idioma do ML Kit. Depois, tudo funciona
offline.

- **Transcrição:** [`whisper_ggml_plus`](https://pub.dev/packages/whisper_ggml_plus)
  (whisper.cpp) — roda on-device, com timestamps por segmento.
- **Conversão de áudio:** `whisper_ggml_plus_ffmpeg` (vídeo → WAV 16 kHz mono).
- **Tradução offline:** `google_mlkit_translation` (par de idiomas baixado sob demanda).
- **Detecção de idioma:** `google_mlkit_language_id` (quando a origem é "automática").

## Idiomas suportados (v1)

Português, Inglês, Espanhol, Francês, Italiano e Alemão — origem e destino.

## Como usar

1. Toque em **Escolher vídeo**.
2. Selecione o idioma da fala (ou "detectar automaticamente").
3. Marque um ou mais **idiomas de saída**.
4. Escolha o **modelo Whisper** (`base` é o padrão recomendado).
5. **Gerar legendas** → ao final, **Salvar** (escolher pasta) ou **Compartilhar** cada `.srt`.

> Em compilação `--release` a transcrição é ~5x mais rápida que em debug. Modelos
> maiores são mais precisos, porém mais lentos e pesados.

## Instalar o APK

Baixe o `app-release.apk` na seção **Releases** deste repositório e instale no
Android (permita "instalar de fontes desconhecidas"). Requer Android 7.0
(API 24) ou superior.

## Compilar do código

```bash
flutter pub get
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

---

Feito por unknown_BTC_usr e Claude
