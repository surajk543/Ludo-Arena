import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // NOTE: the google-services plugin is intentionally NOT applied. Firebase
    // (Analytics only) is initialized from Dart options supplied through
    // --dart-define-from-file=config/firebase.json.
}

/**
 * Optional build-time values: a Gradle property (-PNAME=… or
 * ~/.gradle/gradle.properties) wins over an environment variable. Defaults are
 * EMPTY on purpose — never commit real Facebook ids/tokens here.
 */
fun configValue(name: String): String =
    (project.findProperty(name) as String?)?.trim().takeUnless { it.isNullOrEmpty() }
        ?: System.getenv(name)?.trim().orEmpty()

val facebookAppId = configValue("FACEBOOK_APP_ID")
val facebookClientToken = configValue("FACEBOOK_CLIENT_TOKEN")

/**
 * Play upload key, from android/key.properties (gitignored, never committed;
 * the upload keystore sits next to it in android/ and is gitignored too).
 * Keys: storeFile (relative to android/), storePassword, keyAlias, keyPassword.
 * Google Play App Signing holds the app signing key (docs/deployment.md).
 */
val uploadKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

/**
 * Release builds are always obfuscated (owner's rule, 22 Oct 2026): Dart with
 * `--obfuscate --split-debug-info=<dir>`, Java/Kotlin with R8 (the Flutter
 * Gradle plugin's default shrinking, never `-Pshrink=false`). Any other
 * release build stops here. Build with `tool/build_android_release.sh`, which
 * also collects the symbols for the release PR (docs/deployment.md).
 */
val releaseRequested = gradle.startParameter.taskNames.any {
    it.substringAfterLast(':').endsWith("Release")
}
if (releaseRequested) {
    val dartObfuscated = project.findProperty("dart-obfuscation")?.toString().toBoolean()
    val symbolsDir = project.findProperty("split-debug-info")?.toString().orEmpty()
    val shrink = project.findProperty("shrink")?.toString()?.toBoolean() ?: true
    if (!dartObfuscated || symbolsDir.isBlank() || !shrink) {
        throw GradleException(
            "Android release builds must be obfuscated. Use " +
                "tool/build_android_release.sh apk|appbundle [options], or pass " +
                "--obfuscate --split-debug-info=<dir> (and keep R8 shrinking on)."
        )
    }
}

android {
    namespace = "com.ludoarena.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Google Play package. The namespace (R class, MainActivity's Kotlin
        // package) stays com.ludoarena.app; the iOS bundle id is unchanged.
        applicationId = "com.sungamestudio.ludoarena"
        // Flutter's default (24) satisfies Firebase, Google Sign-In, Sign in
        // with Apple and flutter_secure_storage.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Facebook Login (shown in-app only when FACEBOOK_ENABLED=true).
        manifestPlaceholders["facebookAppId"] = facebookAppId
        manifestPlaceholders["facebookClientToken"] = facebookClientToken
        // Custom-tab callback scheme; a harmless placeholder when unconfigured.
        manifestPlaceholders["facebookScheme"] =
            if (facebookAppId.isEmpty()) "fbnotconfigured" else "fb$facebookAppId"
    }

    signingConfigs {
        if (!uploadKey.isEmpty()) {
            create("upload") {
                storeFile = rootProject.file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties, release builds fall back to the debug
            // key so `flutter run --release` keeps working locally. Such a
            // build cannot go to Play: tool/build_android_release.sh refuses
            // an app bundle without key.properties.
            signingConfig = if (uploadKey.isEmpty()) {
                logger.warn(
                    "android/key.properties not found: release builds are " +
                        "signed with the debug key (not for Play)."
                )
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("upload")
            }
            // R8: shrink, optimize and obfuscate Java/Kotlin (the Flutter
            // plugin adds its keep rules; mapping.txt goes with the release PR).
            isMinifyEnabled = true
            isShrinkResources = true
        }
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
