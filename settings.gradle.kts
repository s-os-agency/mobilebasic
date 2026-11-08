// mobilebasic - settings
//
// Minimal, dependency-light Android scaffold.
// Kept on AGP 8.5.x / Gradle 8.7 which is verified to work on this host
// (aarch64 + qemu-emulated x86_64 build-tools).
pluginManagement {
    plugins {
        id("com.android.application") version "8.5.0"
        id("com.android.library") version "8.5.0"
    }
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "mobilebasic"
include(":app")
