import org.gradle.api.GradleException
import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val requiredSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun resolveKeystoreFile(configuredStore: String?): File? {
    if (configuredStore.isNullOrBlank()) return null
    val asConfigured = File(configuredStore)
    if (asConfigured.isAbsolute) return asConfigured
    val fromRoot = rootProject.file(configuredStore)
    if (fromRoot.exists()) return fromRoot
    val fromModule = file(configuredStore)
    if (fromModule.exists()) return fromModule
    return fromRoot
}

val missingSigningKeys = requiredSigningKeys.filter {
    keystoreProperties.getProperty(it).isNullOrBlank()
}
val resolvedKeystoreFile = resolveKeystoreFile(keystoreProperties.getProperty("storeFile"))
val hasValidReleaseSigning = keystorePropertiesFile.exists() &&
    missingSigningKeys.isEmpty() &&
    resolvedKeystoreFile != null &&
    resolvedKeystoreFile.isFile

fun validateReleaseSigningOrThrow() {
    if (!keystorePropertiesFile.exists()) {
        throw GradleException(
            "RELEASE SIGNING ERROR: Missing ${keystorePropertiesFile.absolutePath}. " +
                "Release builds require an external upload/release keystore configured in android/key.properties " +
                "(storeFile, storePassword, keyAlias, keyPassword). Debug signing fallback is disabled for production."
        )
    }
    if (missingSigningKeys.isNotEmpty()) {
        throw GradleException(
            "RELEASE SIGNING ERROR: Missing or blank properties in ${keystorePropertiesFile.absolutePath}: " +
                "${missingSigningKeys.joinToString(", ")}."
        )
    }
    if (resolvedKeystoreFile == null || !resolvedKeystoreFile.isFile) {
        throw GradleException(
            "RELEASE SIGNING ERROR: Keystore file not found at '${resolvedKeystoreFile?.absolutePath ?: ""}' " +
                "(configured via storeFile in ${keystorePropertiesFile.absolutePath}). " +
                "Keep the keystore outside the repository and verify storeFile."
        )
    }
    val repoRoot = rootProject.projectDir.parentFile?.canonicalFile
    if (repoRoot != null && resolvedKeystoreFile.canonicalPath.startsWith(repoRoot.path + File.separator)) {
        logger.warn(
            "WARNING: Release keystore (${resolvedKeystoreFile.canonicalPath}) is inside the project directory. " +
                "Move it outside the repository; ensure it is never committed."
        )
    }
}

android {
    namespace = "com.ikho.mistyforgelabs"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ikho.mistyforgelabs"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasValidReleaseSigning) {
            create("release") {
                storeFile = resolvedKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            pickFirsts += "**/libonnxruntime.so"
            pickFirsts += "**/libc++_shared.so"
        }
    }

    assetPacks += ":ai_models"

    val isAppBundleBuild = gradle.startParameter.taskNames.any {
        it.contains("bundle", ignoreCase = true)
    }

    sourceSets {
        getByName("main") {
            if (!isAppBundleBuild) {
                assets.srcDir("../ai_models/src/main/assets")
            }
        }
    }

    androidResources {
        noCompress += listOf("onnx", "spm", "bin")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

gradle.taskGraph.whenReady {
    val runningReleaseTask = allTasks.any { task ->
        task.project == project &&
            task.name.contains("Release") &&
            !task.name.contains("UnitTest") &&
            !task.name.contains("AndroidTest")
    }
    if (runningReleaseTask) {
        validateReleaseSigningOrThrow()
    }
}
