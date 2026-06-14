package app.legendai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val diagChannel = "legendai/diag"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // O registrant automático do Flutter captura só Exception por plugin.
        // O ffmpeg-kit, no Android 15, lança java.lang.Error (Throwable, não
        // Exception) ao inicializar — isso escapa e ABORTA o registro de todos
        // os plugins seguintes (file_selector, path_provider, ML Kit), deixando
        // o seletor de vídeo "sem canal". Aqui re-registramos os essenciais
        // blindados contra Throwable. add() é idempotente por classe (seguro).
        safeAdd(flutterEngine, "path_provider") {
            io.flutter.plugins.pathprovider.PathProviderPlugin()
        }
        safeAdd(flutterEngine, "file_selector") {
            dev.flutter.packages.file_selector_android.FileSelectorAndroidPlugin()
        }
        safeAdd(flutterEngine, "mlkit_commons") {
            com.google_mlkit_commons.GoogleMlKitCommonsPlugin()
        }
        safeAdd(flutterEngine, "mlkit_language_id") {
            com.google_mlkit_language_id.GoogleMlKitLanguageIdPlugin()
        }
        safeAdd(flutterEngine, "mlkit_translation") {
            com.google_mlkit_translation.GoogleMlKitTranslationPlugin()
        }
        safeAdd(flutterEngine, "share_plus") {
            dev.fluttercommunity.plus.share.SharePlusPlugin()
        }
        // ffmpeg por último: é o que pode lançar Error; se falhar, os demais
        // já estão registrados e o seletor de vídeo funciona.
        safeAdd(flutterEngine, "ffmpeg") {
            com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diagChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "logcat" -> {
                        try {
                            val proc = Runtime.getRuntime().exec("logcat -d -v time")
                            val text = proc.inputStream.bufferedReader().use { it.readText() }
                            result.success(text)
                        } catch (e: Exception) {
                            result.error("LOGCAT_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun safeAdd(
        engine: FlutterEngine,
        name: String,
        create: () -> FlutterPlugin,
    ) {
        try {
            engine.plugins.add(create())
        } catch (t: Throwable) {
            android.util.Log.e("LegendAiReg", "Falha ao registrar $name: ${t.message}", t)
        }
    }
}
