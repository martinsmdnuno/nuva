plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "pt.nunomartins.nuva"
    compileSdk = 35

    defaultConfig {
        applicationId = "pt.nunomartins.nuva"
        // Android 8.1: the first with the system's own FLAC decoder.
        minSdk = 27
        targetSdk = 35
        versionCode = 2
        versionName = "0.2"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.tv:tv-material:1.0.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Google's own player for Android; FLAC goes through the system's decoder.
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-session:1.4.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

// TERMS.md, from the repository's root, bundled as an asset (NuVa › Terms and Privacy on the Mac).
val copyTerms by tasks.registering(Copy::class) {
    from(rootProject.file("../TERMS.md"))
    into(layout.buildDirectory.dir("generated/terms"))
}
android.sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/terms"))
tasks.named("preBuild") { dependsOn(copyTerms) }
