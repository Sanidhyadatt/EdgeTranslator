allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    if (project.name != "app" && project.name != "ai_models") {
        val configureAndroid = {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    val compileSdkVersionMethod = android.javaClass.methods.firstOrNull {
                        it.name == "compileSdkVersion" && it.parameterTypes.size == 1 &&
                            (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == java.lang.Integer::class.java)
                    }
                    compileSdkVersionMethod?.invoke(android, 35)

                    val setCompileSdkMethod = android.javaClass.methods.firstOrNull {
                        it.name == "setCompileSdk" && it.parameterTypes.size == 1
                    }
                    setCompileSdkMethod?.invoke(android, 35)

                    // Exclude the older ORT 1.15.1 libonnxruntime.so from :onnxruntime so
                    // sherpa_onnx_android_*'s newer backward-compatible libonnxruntime.so is bundled.
                    if (project.name == "onnxruntime") {
                        val getPackaging = android.javaClass.methods.firstOrNull {
                            it.name == "getPackaging" && it.parameterTypes.isEmpty()
                        } ?: android.javaClass.methods.firstOrNull {
                            it.name == "getPackagingOptions" && it.parameterTypes.isEmpty()
                        }
                        val packaging = getPackaging?.invoke(android)
                        val getJniLibs = packaging?.javaClass?.methods?.firstOrNull {
                            it.name == "getJniLibs" && it.parameterTypes.isEmpty()
                        }
                        val jniLibs = getJniLibs?.invoke(packaging)
                        val getExcludes = jniLibs?.javaClass?.methods?.firstOrNull {
                            it.name == "getExcludes" && it.parameterTypes.isEmpty()
                        }
                        @Suppress("UNCHECKED_CAST")
                        val excludes = getExcludes?.invoke(jniLibs) as? MutableCollection<String>
                        excludes?.add("**/libonnxruntime.so")

                        val getSourceSets = android.javaClass.methods.firstOrNull {
                            it.name == "getSourceSets" && it.parameterTypes.isEmpty()
                        }
                        val sourceSets = getSourceSets?.invoke(android)
                        val getByName = sourceSets?.javaClass?.methods?.firstOrNull {
                            it.name == "getByName" && it.parameterTypes.size == 1 && it.parameterTypes[0] == String::class.java
                        }
                        val mainSourceSet = getByName?.invoke(sourceSets, "main")
                        val getSsJniLibs = mainSourceSet?.javaClass?.methods?.firstOrNull {
                            it.name == "getJniLibs" && it.parameterTypes.isEmpty()
                        }
                        val ssJniLibs = getSsJniLibs?.invoke(mainSourceSet)
                        val setSrcDirs = ssJniLibs?.javaClass?.methods?.firstOrNull {
                            it.name == "setSrcDirs" && it.parameterTypes.size == 1
                        }
                        setSrcDirs?.invoke(ssJniLibs, emptyList<String>())
                    }
                } catch (_: Exception) {
                }
            }
        }
        if (project.name == "onnxruntime") {
            project.plugins.withId("com.android.library") {
                configureAndroid()
            }
        }
        if (project.state.executed) {
            configureAndroid()
        } else {
            project.afterEvaluate { configureAndroid() }
        }
    }
}

subprojects {
    if (project.name != "ai_models") {
        project.evaluationDependsOn(":app")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
