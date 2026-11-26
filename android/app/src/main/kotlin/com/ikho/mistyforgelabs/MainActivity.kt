package com.ikho.mistyforgelabs

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var modelExtractor: AiPackModelExtractor
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        modelExtractor = AiPackModelExtractor(applicationContext)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AiPackModelExtractor.CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractModels" -> {
                    val targetDir = call.argument<String>("targetDir")
                    val overwrite = call.argument<Boolean>("overwrite") ?: false
                    if (targetDir.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "targetDir must be non-empty", null)
                        return@setMethodCallHandler
                    }
                    modelExtractor.extractModelsAsync(
                        targetDirPath = targetDir,
                        overwrite = overwrite,
                        onSuccess = { paths ->
                            mainHandler.post { result.success(paths) }
                        },
                        onError = { code, message ->
                            mainHandler.post { result.error(code, message, null) }
                        },
                    )
                }

                "getPackStatus" -> {
                    val targetDir = call.argument<String>("targetDir") ?: ""
                    modelExtractor.getPackStatusAsync(
                        targetDirPath = targetDir,
                        onSuccess = { status ->
                            mainHandler.post { result.success(status) }
                        },
                        onError = { code, message ->
                            mainHandler.post { result.error(code, message, null) }
                        },
                    )
                }

                else -> result.notImplemented()
            }
        }
    }
}
