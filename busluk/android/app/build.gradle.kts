plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "tm.busluk"
    compileSdk = 35

    defaultConfig {
        applicationId = "tm.busluk"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        // Адрес сервера (только HTTPS)
        buildConfigField("String", "BASE", "\"https://busluk.tm\"")
        resourceConfigurations += listOf("ru", "tk")
    }
    buildFeatures { buildConfig = true }

    buildTypes {
        release {
            isMinifyEnabled = true      // R8: вырезает неиспользуемый код
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    // Отдельные APK под архитектуру не нужны: в приложении нет нативного кода.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    packaging { resources.excludes += listOf("META-INF/**", "kotlin/**", "DebugProbesKt.bin") }
}

// Никаких библиотек: только Android SDK и стандартная библиотека Kotlin.
dependencies { }
