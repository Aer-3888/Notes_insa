import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aer.notes_insa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.aer.notes_insa"
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Support both 64-bit and 32-bit ARM architectures
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
            abiFilters.add("armeabi-v7a")
        }
    }

    val keystorePath = System.getenv("KEYSTORE_PATH")
    val isCI = System.getenv("CI") != null

    if (keystorePath != null) {
        signingConfigs {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("KEY_STORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    } else if (isCI) {
        throw GradleException("KEYSTORE_PATH must be set in CI for release builds")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (keystorePath != null)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")  // local dev only
        }
    }

    packaging {
        resources.pickFirsts += setOf("**/libc++_shared.so", "**/libjsc.so")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("lib/mobinsapi.aar"))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Native WorkManager — replaces the Flutter workmanager plugin
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    // EncryptedSharedPreferences — same version as flutter_secure_storage uses
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}

tasks.withType(KotlinJvmCompile::class.java).configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
