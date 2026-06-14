package app.legendai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val diagChannel = "legendai/diag"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal de diagnóstico: lê o logcat do PRÓPRIO processo (sem permissão,
        // sem cabo) para investigar erros de registro de plugin.
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
}
