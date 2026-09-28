plugins {
    id("com.android.application")
    id("kotlin-android")
    id("kotlin-kapt")
    id("com.google.dagger.hilt.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.cloudpix.cloudpix"
    compileSdk = 36
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
        applicationId = "com.cloudpix.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 34
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
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.work:work-runtime-ktx:2.10.1")

    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    kapt("androidx.room:room-compiler:2.6.1")

    implementation("com.google.dagger:hilt-android:2.52")
    kapt("com.google.dagger:hilt-android-compiler:2.52")
    implementation("androidx.hilt:hilt-work:1.2.0")
    kapt("androidx.hilt:hilt-compiler:1.2.0")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}

kapt {
    correctErrorTypes = true
}

flutter {
    source = "../.."
}

val syncFlutterDebugApk by tasks.registering {
    doLast {
        val workspaceRoot = rootDir.parentFile
        val flutterOutDir = workspaceRoot.resolve("build/app/outputs/flutter-apk")
        flutterOutDir.mkdirs()

        val apkFromFlutterPath = layout.buildDirectory.file("outputs/flutter-apk/app-debug.apk").get().asFile
        val apkFromApkPath = layout.buildDirectory.file("outputs/apk/debug/app-debug.apk").get().asFile
        val srcApk = when {
            apkFromFlutterPath.exists() -> apkFromFlutterPath
            apkFromApkPath.exists() -> apkFromApkPath
            else -> null
        }

        if (srcApk != null) {
            srcApk.copyTo(flutterOutDir.resolve("app-debug.apk"), overwrite = true)
        }
    }
}

tasks.matching { it.name == "assembleDebug" }.configureEach {
    finalizedBy(syncFlutterDebugApk)
}
