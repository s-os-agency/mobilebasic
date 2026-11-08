// mobilebasic - app module build configuration
plugins {
    id("com.android.application")
}

android {
    namespace = "app.mobilebasic"
    compileSdk = 34

    defaultConfig {
        applicationId = "app.mobilebasic"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // The build runs on an aarch64 host where the Google build-tools are
    // x86_64 ELF binaries executed under qemu-user-static. Keeping the
    // packaging steps deterministic avoids the tool depending on aapt2
    // variants that may not exist for the emulated architecture.
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*"
            )
        }
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
