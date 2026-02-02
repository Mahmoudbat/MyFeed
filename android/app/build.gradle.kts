plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.local_social_media"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.local_social_media"
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

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.annotation:annotation:1.7.0")
}

// Copy APK to where Flutter expects it (build/app/outputs/flutter-apk/)
afterEvaluate {
    val flutterBuildDir = rootProject.file("../build/app/outputs/flutter-apk")
    tasks.named("assembleDebug").configure {
        doLast {
            val apk = file("${layout.buildDirectory.get()}/outputs/apk/debug/app-debug.apk")
            if (apk.exists()) {
                flutterBuildDir.mkdirs()
                apk.copyTo(flutterBuildDir.resolve("app-debug.apk"), overwrite = true)
            }
        }
    }
    tasks.named("assembleRelease").configure {
        doLast {
            val apk = file("${layout.buildDirectory.get()}/outputs/apk/release/app-release.apk")
            if (apk.exists()) {
                flutterBuildDir.mkdirs()
                apk.copyTo(flutterBuildDir.resolve("app-release.apk"), overwrite = true)
            }
        }
    }
}
