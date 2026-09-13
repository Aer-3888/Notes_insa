import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}
val keystorePath = keystoreProperties.getProperty("storeFile") ?: System.getenv("KEYSTORE_PATH")
val isCI = System.getenv("CI") != null

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

    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = keystoreProperties.getProperty("storePassword") ?: System.getenv("KEY_STORE_PASSWORD")
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Use the real release signing config when present; otherwise fall
            // back to debug keys so local release builds still work. A missing
            // release config is a hard error only when a release artifact is
            // actually assembled in CI (enforced in the task graph below).
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Native WorkManager, replaces the Flutter workmanager plugin
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

tasks.withType(KotlinJvmCompile::class.java).configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// Refuse to assemble a CI release build signed with debug keys. Deferred to the
// task graph so debug and test tasks in CI are unaffected by a missing keystore.
if (isCI && keystorePath == null) {
    gradle.taskGraph.whenReady {
        val assemblingRelease = allTasks.any { task ->
            (task.name.startsWith("assemble") || task.name.startsWith("bundle")) &&
                task.name.contains("Release")
        }
        if (assemblingRelease) {
            throw GradleException(
                "Release signing config missing (no key.properties or " +
                    "KEYSTORE_PATH). Refusing to assemble a CI release build " +
                    "with debug keys.",
            )
        }
    }
}
