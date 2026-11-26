package com.ikho.mistyforgelabs

import android.content.Context
import android.content.res.AssetManager
import android.os.Build
import android.os.StatFs
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Extracts on-device ML models delivered through the Google Play install-time AI pack
 * (`:ai_models`) from Android's split APK [AssetManager] into internal app storage.
 *
 * Native FFI runtimes (`sherpa_onnx` C++ and ONNX Runtime `OrtSession.fromFile`)
 * require direct filesystem paths and cannot read compressed or split APK assets
 * via Flutter's [rootBundle].
 */
class AiPackModelExtractor(private val context: Context) {

    companion object {
        const val CHANNEL_NAME = "com.ikho.mistyforgelabs/ai_models"
        private const val MODELS_ASSET_ROOT = "models"
        private const val STAMP_FILE_NAME = ".ai_pack_stamp"
        private const val BUFFER_SIZE = 64 * 1024
        private const val SAFETY_MARGIN_BYTES = 24L * 1024L * 1024L
        private const val EXPECTED_PACK_BYTES_FALLBACK = 860_000_000L

        private val OBSOLETE_RELATIVE_FILES = listOf(
            "tiny-encoder.int8.onnx",
            "tiny-decoder.int8.onnx",
            "tiny-tokens.txt",
        )
    }

    class ExtractionException(
        val code: String,
        override val message: String,
        cause: Throwable? = null,
    ) : Exception(message, cause)

    private val executor = Executors.newSingleThreadExecutor()

    fun extractModelsAsync(
        targetDirPath: String,
        overwrite: Boolean,
        onSuccess: (List<String>) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        executor.execute {
            try {
                val paths = extractModelsSync(targetDirPath, overwrite)
                onSuccess(paths)
            } catch (e: ExtractionException) {
                onError(e.code, e.message)
            } catch (e: Exception) {
                onError("IO_ERROR", e.message ?: "Unexpected native extraction error.")
            }
        }
    }

    fun getPackStatusAsync(
        targetDirPath: String,
        onSuccess: (Map<String, Any>) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        executor.execute {
            try {
                val targetDir = File(targetDirPath)
                val currentVersion = getAppVersionCode()
                val assets = resolvePackAssetManager()
                val assetFiles = mutableListOf<String>()
                collectAssetFiles(assets, MODELS_ASSET_ROOT, assetFiles)

                var extractedCount = 0
                if (targetDir.exists()) {
                    for (assetPath in assetFiles) {
                        val rel = assetPath.removePrefix("$MODELS_ASSET_ROOT/")
                        val f = File(targetDir, rel)
                        if (f.exists() && f.length() > 0) {
                            extractedCount++
                        }
                    }
                }

                onSuccess(
                    mapOf(
                        "packAvailable" to assetFiles.isNotEmpty(),
                        "assetCount" to assetFiles.size,
                        "extractedCount" to extractedCount,
                        "versionCode" to currentVersion,
                    ),
                )
            } catch (e: Exception) {
                onError("STATUS_ERROR", e.message ?: "Unable to inspect AI pack status.")
            }
        }
    }

    private fun extractModelsSync(targetDirPath: String, overwrite: Boolean): List<String> {
        val baseDir = File(targetDirPath)
        if (!baseDir.exists() && !baseDir.mkdirs()) {
            throw ExtractionException(
                "IO_ERROR",
                "Failed creating models directory at ${baseDir.absolutePath}",
            )
        }

        val currentVersion = getAppVersionCode()
        val stampFile = File(baseDir, STAMP_FILE_NAME)

        if (!overwrite) {
            val cachedPaths = tryValidateStamp(baseDir, stampFile, currentVersion)
            if (cachedPaths != null) {
                return cachedPaths
            }
        }

        val assets = resolvePackAssetManager()
        val assetPaths = mutableListOf<String>()
        collectAssetFiles(assets, MODELS_ASSET_ROOT, assetPaths)
        assetPaths.sort()

        if (assetPaths.isEmpty()) {
            throw ExtractionException(
                "AI_PACK_MISSING",
                "Install-time AI pack assets ('models/') were not found in Android AssetManager. " +
                    "Install the app from Google Play or via bundletool from an .aab containing :ai_models.",
            )
        }

        cleanupObsoleteModels(baseDir)

        val stampedSizes = if (!overwrite) readStampSizes(stampFile, currentVersion) else emptyMap()
        var reusableBytes = 0L
        var missingFilesCount = 0
        val canonicalBase = baseDir.canonicalPath

        for (assetPath in assetPaths) {
            val relPath = assetPath.removePrefix("$MODELS_ASSET_ROOT/")
            val targetFile = File(baseDir, relPath)
            val expectedSize = stampedSizes[relPath]
            val canReuse = !overwrite &&
                targetFile.exists() &&
                targetFile.length() > 0 &&
                (expectedSize == null || targetFile.length() == expectedSize)
            if (canReuse) {
                reusableBytes += targetFile.length()
            } else {
                missingFilesCount++
            }
        }

        if (missingFilesCount > 0) {
            ensureSufficientDiskSpace(baseDir, reusableBytes, missingFilesCount == assetPaths.size)
        }

        val extractedRecords = ArrayList<Pair<String, Long>>(assetPaths.size)
        val extractedAbsolutePaths = ArrayList<String>(assetPaths.size)
        val copyBuffer = ByteArray(BUFFER_SIZE)

        for (assetPath in assetPaths) {
            val relPath = assetPath.removePrefix("$MODELS_ASSET_ROOT/")
            val targetFile = File(baseDir, relPath)
            val canonicalTarget = targetFile.canonicalPath
            if (!canonicalTarget.startsWith(canonicalBase + File.separator) && canonicalTarget != canonicalBase) {
                throw ExtractionException("IO_ERROR", "Unsafe model asset path: $relPath")
            }

            val expectedSize = stampedSizes[relPath]
            val alreadyValid = !overwrite &&
                targetFile.exists() &&
                targetFile.length() > 0 &&
                (expectedSize == null || targetFile.length() == expectedSize)

            if (!alreadyValid) {
                copySingleAsset(assets, assetPath, targetFile, copyBuffer)
            }

            if (!targetFile.exists() || targetFile.length() <= 0L) {
                throw ExtractionException(
                    "IO_ERROR",
                    "CRITICAL FFI ERROR: Missing or empty extracted file at ${targetFile.absolutePath}",
                )
            }

            extractedRecords.add(relPath to targetFile.length())
            extractedAbsolutePaths.add(targetFile.absolutePath)
        }

        writeStamp(stampFile, currentVersion, extractedRecords)
        return extractedAbsolutePaths
    }

    private fun resolvePackAssetManager(): AssetManager {
        try {
            val pkgContext = context.applicationContext.createPackageContext(
                context.packageName,
                0,
            )
            val pkgAssets = pkgContext.assets
            val entries = pkgAssets.list(MODELS_ASSET_ROOT)
            if (!entries.isNullOrEmpty()) {
                return pkgAssets
            }
        } catch (_: Exception) {
            // Fall back to current application context AssetManager.
        }
        return context.applicationContext.assets
    }

    private fun collectAssetFiles(
        assets: AssetManager,
        assetDir: String,
        out: MutableList<String>,
    ) {
        val children = assets.list(assetDir) ?: return
        for (name in children) {
            val childPath = if (assetDir.isEmpty()) name else "$assetDir/$name"
            val nested = assets.list(childPath)
            if (nested != null && nested.isNotEmpty()) {
                collectAssetFiles(assets, childPath, out)
            } else {
                try {
                    assets.open(childPath).use { }
                    out.add(childPath)
                } catch (_: IOException) {
                    // Skip directory placeholders or unreadable entries.
                }
            }
        }
    }

    private fun copySingleAsset(
        assets: AssetManager,
        assetPath: String,
        targetFile: File,
        buffer: ByteArray,
    ) {
        val parent = targetFile.parentFile
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw ExtractionException(
                "IO_ERROR",
                "Unable to create parent directory: ${parent.absolutePath}",
            )
        }

        val tempFile = File("${targetFile.absolutePath}.tmp")
        try {
            assets.open(assetPath).use { input ->
                FileOutputStream(tempFile).use { output ->
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        if (read > 0) {
                            output.write(buffer, 0, read)
                        }
                    }
                    output.flush()
                    output.fd.sync()
                }
            }

            if (targetFile.exists() && !targetFile.delete()) {
                throw ExtractionException(
                    "IO_ERROR",
                    "Unable to replace existing model file: ${targetFile.absolutePath}",
                )
            }
            if (!tempFile.renameTo(targetFile)) {
                tempFile.copyTo(targetFile, overwrite = true)
                tempFile.delete()
            }
        } catch (e: ExtractionException) {
            tempFile.delete()
            throw e
        } catch (e: IOException) {
            tempFile.delete()
            val msg = e.message ?: "Failed extracting asset $assetPath"
            if (msg.contains("No space left", ignoreCase = true) ||
                msg.contains("ENOSPC", ignoreCase = true)
            ) {
                throw ExtractionException(
                    "INSUFFICIENT_STORAGE",
                    "Insufficient internal storage space to extract offline AI models: $msg",
                    e,
                )
            }
            throw ExtractionException("IO_ERROR", "Failed extracting $assetPath: $msg", e)
        }
    }

    private fun ensureSufficientDiskSpace(
        baseDir: File,
        reusableBytes: Long,
        isFullInstall: Boolean,
    ) {
        try {
            val stat = StatFs(baseDir.absolutePath)
            val availableBytes = stat.availableBytes
            val requiredBytes = if (isFullInstall) {
                EXPECTED_PACK_BYTES_FALLBACK + SAFETY_MARGIN_BYTES
            } else {
                val estimatedRemaining = (EXPECTED_PACK_BYTES_FALLBACK - reusableBytes).coerceAtLeast(0L)
                estimatedRemaining + SAFETY_MARGIN_BYTES
            }
            if (availableBytes < requiredBytes) {
                val needMb = (requiredBytes + (1024 * 1024 - 1)) / (1024 * 1024)
                val freeMb = availableBytes / (1024 * 1024)
                throw ExtractionException(
                    "INSUFFICIENT_STORAGE",
                    "Need approximately ${needMb} MB of free storage to prepare offline models (${freeMb} MB available).",
                )
            }
        } catch (e: ExtractionException) {
            throw e
        } catch (_: Exception) {
            // If StatFs cannot query free space, let write loop handle ENOSPC cleanly.
        }
    }

    private fun cleanupObsoleteModels(baseDir: File) {
        val legacyEnJaDir = File(baseDir, "nmt_en_ja")
        if (legacyEnJaDir.exists() && legacyEnJaDir.isDirectory) {
            legacyEnJaDir.listFiles()?.forEach { child ->
                if (child.isFile && child.name.contains("(1)")) {
                    child.delete()
                }
            }
        }
        for (rel in OBSOLETE_RELATIVE_FILES) {
            val f = File(baseDir, rel)
            if (f.exists()) {
                f.delete()
            }
        }
    }

    private fun tryValidateStamp(
        baseDir: File,
        stampFile: File,
        currentVersion: Long,
    ): List<String>? {
        val stampedSizes = readStampSizes(stampFile, currentVersion)
        if (stampedSizes.isEmpty()) return null

        val paths = ArrayList<String>(stampedSizes.size)
        for ((relPath, expectedSize) in stampedSizes) {
            val f = File(baseDir, relPath)
            if (!f.exists() || !f.isFile || f.length() != expectedSize || expectedSize <= 0L) {
                return null
            }
            paths.add(f.absolutePath)
        }
        paths.sort()
        return paths
    }

    private fun readStampSizes(stampFile: File, expectedVersion: Long): Map<String, Long> {
        if (!stampFile.exists() || !stampFile.isFile) return emptyMap()
        return try {
            val lines = stampFile.readLines(Charsets.UTF_8)
            var versionMatch = false
            val sizes = LinkedHashMap<String, Long>()
            for (line in lines) {
                if (line.startsWith("versionCode=")) {
                    val v = line.substringAfter("versionCode=").toLongOrNull()
                    if (v != expectedVersion) return emptyMap()
                    versionMatch = true
                } else if (line.startsWith("file|")) {
                    val parts = line.split('|')
                    if (parts.size == 3) {
                        val size = parts[2].toLongOrNull() ?: return emptyMap()
                        sizes[parts[1]] = size
                    }
                }
            }
            if (versionMatch) sizes else emptyMap()
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun writeStamp(
        stampFile: File,
        versionCode: Long,
        records: List<Pair<String, Long>>,
    ) {
        val tmpStamp = File("${stampFile.absolutePath}.tmp")
        try {
            val content = buildString {
                append("versionCode=").append(versionCode).append('\n')
                for ((rel, size) in records) {
                    append("file|").append(rel).append('|').append(size).append('\n')
                }
            }
            tmpStamp.writeText(content, Charsets.UTF_8)
            if (stampFile.exists()) {
                stampFile.delete()
            }
            if (!tmpStamp.renameTo(stampFile)) {
                tmpStamp.copyTo(stampFile, overwrite = true)
                tmpStamp.delete()
            }
        } catch (_: Exception) {
            tmpStamp.delete()
        }
    }

    private fun getAppVersionCode(): Long {
        val pm = context.packageManager
        val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(
                context.packageName,
                android.content.pm.PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(context.packageName, 0)
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pkgInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            pkgInfo.versionCode.toLong()
        }
    }
}
