plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutterrhythmquake"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutterrhythmquake"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Build the same Rust backend as Windows. Generated libraries live under
// build/, never in source-controlled jniLibs or in a hand-maintained APK step.
data class RustAndroidTarget(val abi: String, val rust: String, val clang: String)
val rustTargets = mapOf(
    "android-arm" to RustAndroidTarget("armeabi-v7a", "armv7-linux-androideabi", "armv7a-linux-androideabi"),
    "android-arm64" to RustAndroidTarget("arm64-v8a", "aarch64-linux-android", "aarch64-linux-android"),
    "android-x64" to RustAndroidTarget("x86_64", "x86_64-linux-android", "x86_64-linux-android"),
)
val selectedRustTargets = (findProperty("target-platform")?.toString()
    ?: "android-arm,android-arm64,android-x64").split(",").map { platform ->
    rustTargets[platform] ?: error("Unsupported Rust Android platform: $platform")
}
// Flutter's --split-per-abi supplies its own ABI split filters. Do not also
// set ndk.abiFilters in that mode, because Android Gradle rejects both sets
// together. The normal all-ABI APK keeps the existing fixed Rust filters.
val splitPerAbi = findProperty("split-per-abi")?.toString()?.toBoolean() == true
if (!splitPerAbi) {
    android.defaultConfig.ndk.abiFilters.addAll(selectedRustTargets.map { it.abi })
}
val rustRoot = rootProject.file("../native/station_core")
val rustBuild = rootProject.layout.buildDirectory.dir("rust-android")
val hostOs = System.getProperty("os.name").lowercase()
val ndkHost = when {
    hostOs.contains("windows") -> "windows-x86_64"
    hostOs.contains("mac") -> "darwin-x86_64"
    else -> "linux-x86_64"
}
val executableSuffix = if (hostOs.contains("windows")) ".exe" else ""
val ndkBin = android.sdkDirectory.resolve("ndk/${android.ndkVersion}/toolchains/llvm/prebuilt/$ndkHost/bin")
listOf("debug", "profile", "release").forEach { variant ->
    val cargoProfile = if (variant == "debug") "debug" else "release"
    val jniDir = rustBuild.map { it.dir("jniLibs/$variant") }
    android.sourceSets.maybeCreate(variant).jniLibs.srcDir(jniDir)
    val rustTasks = selectedRustTargets.map { target ->
        tasks.register<Exec>("buildRust${variant.replaceFirstChar { it.uppercase() }}${target.abi.replace("-", "_")}") {
            val targetDir = rustBuild.get().dir("cargo").asFile
            val library = targetDir.resolve("${target.rust}/$cargoProfile/librq_station_core.so")
            val packagedLibrary = jniDir.get().file("${target.abi}/librq_station_core.so").asFile
            inputs.files(fileTree(rustRoot) { include("src/**/*.rs", "Cargo.toml", "Cargo.lock") })
            inputs.files(fileTree(rootProject.file("../assets/regions")) { include("*.bin") })
            inputs.property("ndkVersion", android.ndkVersion)
            inputs.property("minSdk", android.defaultConfig.minSdk!!)
            outputs.file(library)
            outputs.file(packagedLibrary)
            workingDir(rustRoot)
            val envTarget = target.rust.replace("-", "_")
            val clang = ndkBin.resolve("clang$executableSuffix").absolutePath
            environment("CARGO_TARGET_${envTarget.uppercase()}_LINKER", clang)
            environment("CARGO_TARGET_${envTarget.uppercase()}_RUSTFLAGS",
                "-C link-arg=--target=${target.clang}${android.defaultConfig.minSdk} -C link-arg=-Wl,-z,max-page-size=16384")
            environment("CC_$envTarget", clang)
            environment("CFLAGS_$envTarget", "--target=${target.clang}${android.defaultConfig.minSdk}")
            environment("AR_$envTarget", ndkBin.resolve("llvm-ar$executableSuffix").absolutePath)
            commandLine(listOf("cargo", "build", "--locked", "--manifest-path",
                rustRoot.resolve("Cargo.toml").absolutePath, "--target", target.rust,
                "--target-dir", targetDir.absolutePath) + if (cargoProfile == "release") listOf("--release") else emptyList())
            doLast {
                check(library.isFile) { "Missing Rust library: $library" }
                packagedLibrary.parentFile.mkdirs()
                library.copyTo(packagedLibrary, overwrite = true)
            }
        }
    }
    tasks.matching { it.name == "merge${variant.replaceFirstChar { it.uppercase() }}JniLibFolders" }
        .configureEach { dependsOn(rustTasks) }
}
