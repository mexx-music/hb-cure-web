import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Load keystore properties (robust, with clear error messages) ----------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
println("HBDBG key.properties = ${keystorePropertiesFile.absolutePath} exists=${keystorePropertiesFile.exists()}")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    println("HBDBG loaded keys = ${keystoreProperties.keys}")
}
fun kp(name: String): String {
    val v = keystoreProperties.getProperty(name)
    if (v.isNullOrBlank()) error("Missing key.properties entry: $name (loaded keys=${keystoreProperties.keys})")
    return v
}

android {
    namespace = "com.catlabstudios.hbcure"
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
        applicationId = "com.catlabstudios.hbcure"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signing config for release builds (loaded from key.properties)
    signingConfigs {
        create("release") {
            keyAlias = kp("keyAlias")
            keyPassword = kp("keyPassword")
            storeFile = file(kp("storeFile"))
            storePassword = kp("storePassword")
        }
    }

    buildTypes {
        release {
            // Use the release signing config when available
            signingConfig = signingConfigs.getByName("release")
            // TODO: enable/provide minify/shrink settings as needed
            // isMinifyEnabled = false
            // isShrinkResources = false
        }
    }
}

dependencies {
    implementation("org.bouncycastle:bcprov-jdk15on:1.70")
}

flutter {
    source = "../.."
}
