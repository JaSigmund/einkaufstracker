import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung: Zugangsdaten stehen in android/key.properties (nicht im Git, siehe .gitignore).
// Vorlage: android/key.properties.example. Ohne diese Datei wird mit dem Debug-Schluessel signiert
// (nur zum lokalen Testen, nicht fuer die Verteilung).
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keyPropertiesFile.exists()
if (hasReleaseKey) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

android {
    namespace = "at.jakob.einkaufstracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Von flutter_local_notifications verlangt (java.time-Backport auf aelteren Android-Versionen).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Feste App-Kennung, in der Android Developer Console registriert. Nie aendern.
        applicationId = "at.jakob.einkaufstracker"
        // ML Kit und mobile_scanner verlangen mindestens API 23; wir setzen 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// Ohne key.properties signiert der Release-Build mit dem Debug-Schluessel (gewollt fuer lokale Tests, siehe README). Damit
// so eine APK nicht versehentlich verteilt wird, sagt der Build es jetzt laut (Codereview 2026-10-16).
if (!hasReleaseKey) {
    gradle.taskGraph.whenReady {
        if (allTasks.any { it.name.contains("Release") }) {
            logger.warn(
                """
                |
                |WARNUNG: android/key.properties fehlt, der Release-Build wird mit dem DEBUG-Schluessel signiert.
                |Diese APK nur zum lokalen Testen verwenden, nicht verteilen (README, "Signierter Release-Build").
                |
                """.trimMargin(),
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

dependencies {
    // Core library desugaring, von flutter_local_notifications verlangt.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
