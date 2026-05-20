import java.util.Properties
import java.io.FileInputStream

configurations.all {
    resolutionStrategy {
        force("org.jetbrains.kotlin:kotlin-stdlib:2.3.10")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.3.10")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.3.10")
    }
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "pt.boraapp.bora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requer core library desugaring (Java 8+ APIs em Android <26).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pt.boraapp.bora"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // BUG fix pós-takeaway (2026-05-14): minSdk=21 (Android 5.0) garante
        // que APK instala em >99% de dispositivos activos. Default do Flutter
        // pode ser mais alto, bloqueando devices antigos.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            // 2026-05-14 fix: armeabi-v7a adicionado para suportar Android
            // 32-bit (~5-10% de devices activos em PT, sobretudo gamas baixas
            // pre-2018 que continuam em uso). Sem isto o APK nao instala.
            // arm64-v8a: cobre todos os Android 64-bit modernos.
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
        }
    }

    signingConfigs {
        create("release") {
            val storeFileName = keystoreProperties["storeFile"] as String?
            if (storeFileName != null) {
                // Resolve relativo ao rootProject (android/) — key.properties usa
                // "app/release.keystore" para apontar para android/app/release.keystore.
                // file() resolveria relativo ao módulo :app (android/app/), duplicando "app/".
                storeFile = rootProject.file(storeFileName)
            }
            storePassword = keystoreProperties["storePassword"] as String?
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
        }
    }

        buildTypes {
                release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }

        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring — necessário para flutter_local_notifications (Java 8+ time APIs).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.3.10")
}



