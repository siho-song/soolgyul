import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release builds are signed with the upload key described in android/key.properties
// (gitignored): storeFile, storePassword, keyAlias, keyPassword. Debug builds never use it.
// Flutter hands every --dart-define to Gradle as a comma-separated list of base64 "KEY=VALUE".
// The Kakao login redirect scheme in the manifest must match KAKAO_NATIVE_APP_KEY of the same build.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        ?.associate { it.substringBefore("=") to it.substringAfter("=", "") }
        ?: emptyMap()
val kakaoNativeAppScheme = dartDefines["KAKAO_NATIVE_APP_SCHEME"] ?: ""

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.fitkle.soolgyul"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fitkle.soolgyul"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["kakaoNativeAppScheme"] =
            kakaoNativeAppScheme.ifEmpty { "kakao-scheme-not-configured" }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else null
        }
    }
}

// Fail release packaging early instead of producing an unsigned or mis-configured build;
// debug builds are unaffected.
tasks.configureEach {
    if (name == "assembleRelease" || name == "bundleRelease") {
        doFirst {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "android/key.properties is missing: release builds must be signed with the upload key.",
                )
            }
            if (kakaoNativeAppScheme.isEmpty()) {
                throw GradleException(
                    "KAKAO_NATIVE_APP_SCHEME is missing: build with --dart-define-from-file=config/env/production.env.",
                )
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // On-device label text recognition for the taste-fit search. The Korean
    // model also reads Latin script; the Japanese one reads sake brands.
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}
