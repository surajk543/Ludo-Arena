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

android {
    namespace = "com.ludoroyale.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ludoroyale.app"
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

    buildTypes {
        release {
            // TODO(release): add a real signing config. Debug keys keep
            // `flutter run --release` working locally.
            signingConfig = signingConfigs.getByName("debug")
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
