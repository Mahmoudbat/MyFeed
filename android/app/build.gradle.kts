import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: create android/key.properties (git-ignored) with
// storeFile, storePassword, keyAlias and keyPassword. See
// https://docs.flutter.dev/deployment/android#sign-the-app
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.imle.myfeed"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.imle.myfeed"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "MyFeed"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    // Which ID and key each build mode gets:
    //   flutter run / build --debug   -> com.imle.myfeed.debug, debug key (separate app, own data)
    //   flutter build apk --release   -> com.imle.myfeed,       your release key
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "MyFeed (debug)"
        }
        release {
            if (hasReleaseKey) signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Never produce a release APK signed with anything but the release key:
// an APK with a different key can't update the installed app, and getting
// past that means uninstalling, which erases the locked gallery.
tasks.matching { it.name.startsWith("assembleRelease") || it.name.startsWith("bundleRelease") }.configureEach {
    doFirst {
        if (!hasReleaseKey) {
            throw GradleException(
                "Release build refused: android/key.properties is missing. " +
                    "Create it (see README) so the APK is signed with your release key.",
            )
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
