import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Signing config ────────────────────────────────────────────────────────────
// Reads from android/key.properties for local builds.
// In CI (GitHub Actions) the individual values are supplied as env vars:
//   KEYSTORE_BASE64, KEY_STORE_PASSWORD, KEY_PASSWORD, KEY_ALIAS
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties()
if (keyPropsFile.exists()) {
    keyPropsFile.inputStream().use { keyProps.load(it) }
}

android {
    namespace = "com.thesigmas.the_abyss_app"
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
        applicationId = "com.thesigmas.the_abyss_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // CI path: env vars injected by GitHub Actions
            val envKeystore = System.getenv("KEYSTORE_PATH")
            if (envKeystore != null) {
                storeFile     = file(envKeystore)
                storePassword = System.getenv("KEY_STORE_PASSWORD")
                keyAlias      = System.getenv("KEY_ALIAS")
                keyPassword   = System.getenv("KEY_PASSWORD")
            } else if (keyPropsFile.exists()) {
                // Local path: read from key.properties
                storeFile     = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
                keyAlias      = keyProps["keyAlias"] as String
                keyPassword   = keyProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig    = signingConfigs.getByName("release")
            // R8 minification crashes the JVM on this machine (see hs_err_pid*.log).
            // Keeping disabled until the root cause is resolved — APK is ~20 MB
            // larger but builds cleanly and installs on every device.
            isMinifyEnabled  = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
