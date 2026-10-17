plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Share the existing artwork with iOS without requiring manual copies or
// committing a second set of large binary assets.
val sharedArtwork = layout.buildDirectory.dir("generated/nightjar-artwork")
val prepareSharedArtwork by tasks.registering(Sync::class) {
    from(rootProject.file("../ios/nightjar/Assets.xcassets/AppBackground.imageset/background.jpg")) {
        into("assets")
    }
    from(rootProject.file("../ios/nightjar/centipede.gif")) {
        into("assets")
    }
    from(rootProject.file("../ios/nightjar/Assets.xcassets/AppIcon.appiconset/IMG_1434.png")) {
        into("res/mipmap-xxxhdpi")
        rename { "ic_launcher.png" }
    }
    into(sharedArtwork)
}

android {
    namespace = "net.nosuchmachine.nightjarhack"
    compileSdk = 34

    defaultConfig {
        applicationId = "net.nosuchmachine.nightjarhack"
        minSdk = 26
        targetSdk = 34
        versionCode = 300
        versionName = "3.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
        debug {
            isMinifyEnabled = false
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
    sourceSets.getByName("main") {
        assets.srcDir(sharedArtwork.map { it.dir("assets") })
        res.srcDir(sharedArtwork.map { it.dir("res") })
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

tasks.named("preBuild") { dependsOn(prepareSharedArtwork) }

dependencies {
    testImplementation("junit:junit:4.13.2")
    val composeBom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("io.coil-kt:coil-gif:2.7.0")
    // Blink: QR codes (zxing) and the camera that reads them.
    implementation("com.google.zxing:core:3.5.3")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")
}
