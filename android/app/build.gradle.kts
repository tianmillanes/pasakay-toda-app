import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    // Add the dependency for the Google services Gradle plugin
    id("com.google.gms.google-services") version "4.4.4"
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.toda.transport.booking"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as? String
            keyPassword = keystoreProperties["keyPassword"] as? String
            storeFile = (keystoreProperties["storeFile"] as? String)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as? String
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.toda.transport.booking"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))
    implementation("com.google.firebase:firebase-analytics")
}

// Copy build artifacts to location where Flutter expects them
afterEvaluate {
    tasks.register<Copy>("copyArtifacts") {
        from("${layout.buildDirectory.get()}/outputs/flutter-apk") {
            include("*.apk")
            into("flutter-apk")
        }
        from("${layout.buildDirectory.get()}/outputs/bundle/release") {
            include("*.aab")
            into("bundle/release")
        }
        into("${rootProject.projectDir}/../build/app/outputs")
    }

    tasks.named("assembleDebug").configure {
        finalizedBy("copyArtifacts")
    }

    tasks.named("assembleRelease").configure {
        finalizedBy("copyArtifacts")
    }

    tasks.named("bundleRelease").configure {
        finalizedBy("copyArtifacts")
    }
}
